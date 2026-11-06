//! UniFFI 导出的 `MobileCore`：CoreEngine（Swift/Kotlin）只包这一层。
//! 线程安全：内部 RwLock；节点库/规则替换为原子换指针，查询不阻塞写入。

use crate::diff::{diff_sorted, NodeDiff};
use crate::error::MobileError;
use crate::nodes::{NodeQueryResult, NodeRow, NodeStore, NodeStoreBuilder, RegionSection};
use crate::rules::{Layer, LayerBuilder, LayerKind, RuleLayerInfo, RuleSet, RuleTrace};
use parking_lot::{Mutex, RwLock};
use roaring::RoaringBitmap;
use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::Arc;

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NodeIndex {
    pub total: u64,
    pub sections: Vec<RegionSection>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NodePage {
    pub rows: Vec<NodeRow>,
    pub offset: u64,
    pub total: u64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SubscriptionSource {
    pub id: u16,
    /// Clash/mihomo YAML 全文
    pub yaml: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct BuildReport {
    pub total: u64,
    pub skipped: u64,
    pub diff: NodeDiff,
    pub took_millis: u64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RuleStats {
    pub total: u64,
    pub layers: Vec<RuleLayerInfo>,
    pub disk_bytes: u64,
}

const QUERY_CACHE: usize = 8;

#[derive(uniffi::Object)]
pub struct MobileCore {
    dir: PathBuf,
    store: RwLock<Option<Arc<NodeStore>>>,
    rules: RwLock<Arc<RuleSet>>,
    queries: Mutex<VecDeque<(u64, Arc<RoaringBitmap>)>>,
    next_token: Mutex<u64>,
    generation: Mutex<u64>,
}

impl MobileCore {
    fn store(&self) -> Result<Arc<NodeStore>, MobileError> {
        self.store.read().clone().ok_or_else(|| MobileError::NotFound("节点库未建立".into()))
    }
    fn swap_store(&self, builder: NodeStoreBuilder, skipped: u64, t0: std::time::Instant) -> Result<BuildReport, MobileError> {
        let gen = {
            let mut g = self.generation.lock();
            *g += 1;
            *g
        };
        let path = self.dir.join(format!("nodes.{gen}.zn"));
        builder.write(&path)?;
        let new = Arc::new(NodeStore::open(&path)?);
        let old = self.store.read().clone();
        let diff = match &old {
            Some(o) => diff_sorted(&o.fingerprints_sorted(), &new.fingerprints_sorted()),
            None => NodeDiff { added: new.total(), removed: 0, kept: 0 },
        };
        *self.store.write() = Some(new.clone());
        self.queries.lock().clear();
        // 旧文件：Arc 释放后删除（mmap 在 unix 上删除后仍有效）
        for e in std::fs::read_dir(&self.dir)?.flatten() {
            let n = e.file_name().to_string_lossy().to_string();
            if n.starts_with("nodes.") && n.ends_with(".zn") && n != format!("nodes.{gen}.zn") {
                let _ = std::fs::remove_file(e.path());
            }
        }
        let _ = std::fs::write(self.dir.join("nodes.current"), gen.to_string());
        Ok(BuildReport { total: new.total(), skipped, diff, took_millis: t0.elapsed().as_millis() as u64 })
    }
}

#[uniffi::export]
impl MobileCore {
    /// data_dir：App Group 容器下的目录（iOS 扩展与 App 共享）/ Android filesDir。
    #[uniffi::constructor]
    pub fn new(data_dir: String) -> Result<Arc<Self>, MobileError> {
        let dir = PathBuf::from(data_dir);
        std::fs::create_dir_all(dir.join("rules"))?;
        let gen: u64 = std::fs::read_to_string(dir.join("nodes.current")).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0);
        let store = if gen > 0 { NodeStore::open(&dir.join(format!("nodes.{gen}.zn"))).ok().map(Arc::new) } else { None };
        Ok(Arc::new(Self {
            dir,
            store: RwLock::new(store),
            rules: RwLock::new(Arc::new(RuleSet { layers: vec![], final_policy: "other".into() })),
            queries: Mutex::new(VecDeque::new()),
            next_token: Mutex::new(1),
            generation: Mutex::new(gen),
        }))
    }

    /// 由全部订阅重建节点库，返回与旧库的差异（"+1,204 节点 −318 节点"）。
    pub fn rebuild_nodes(&self, sources: Vec<SubscriptionSource>) -> Result<BuildReport, MobileError> {
        let t0 = std::time::Instant::now();
        let mut b = NodeStoreBuilder::new();
        let mut skipped = 0;
        for s in sources {
            let (nodes, sk) = crate::subscription::parse_proxies_yaml(&s.yaml, s.id)?;
            skipped += sk;
            for n in nodes {
                b.push(n);
            }
        }
        self.swap_store(b, skipped, t0)
    }

    /// 开发/演示：用原型生成器建库。scale=1.0 即 13,109,802 个节点。
    pub fn rebuild_mock_nodes(&self, scale: f64) -> Result<BuildReport, MobileError> {
        let t0 = std::time::Instant::now();
        let scale = scale.clamp(0.000_01, 1.0);
        let mut b = NodeStoreBuilder::with_capacity((crate::mock::total() as f64 * scale) as usize);
        for n in crate::mock::nodes(scale) {
            b.push(n);
        }
        self.swap_store(b, 0, t0)
    }

    pub fn node_index(&self) -> Result<NodeIndex, MobileError> {
        let s = self.store()?;
        let mut row = 0;
        let sections = s
            .region_codes()
            .into_iter()
            .map(|(region, count)| {
                let sec = RegionSection { region, count, row_offset: row };
                row += 1 + count;
                sec
            })
            .collect();
        Ok(NodeIndex { total: s.total(), sections })
    }

    pub fn query_nodes(&self, query: String) -> Result<NodeQueryResult, MobileError> {
        let s = self.store()?;
        let (bm, mut res) = s.timed_query(&query);
        let token = {
            let mut t = self.next_token.lock();
            *t += 1;
            *t
        };
        res.token = token;
        let mut q = self.queries.lock();
        q.push_back((token, Arc::new(bm)));
        while q.len() > QUERY_CACHE {
            q.pop_front();
        }
        Ok(res)
    }

    /// offset：结果集内节点序号（不含分区头行）。
    pub fn node_rows(&self, token: u64, offset: u64, limit: u32) -> Result<NodePage, MobileError> {
        let s = self.store()?;
        let bm = self.queries.lock().iter().find(|(t, _)| *t == token).map(|(_, b)| b.clone());
        let bm = bm.ok_or_else(|| MobileError::NotFound(format!("查询句柄 {token} 已过期")))?;
        Ok(NodePage { rows: s.page(&bm, offset, limit), offset, total: bm.len() })
    }

    /// 编译一层规则（文本为 Clash 规则行或规则集 payload）。index 决定匹配顺序。
    pub fn compile_rule_layer(&self, index: u32, name: String, kind: LayerKind, note: String, default_policy: String, text: String) -> Result<RuleLayerInfo, MobileError> {
        let mut b = LayerBuilder::new(&name, kind, &note, &default_policy);
        b.add_text(&text);
        let path = self.dir.join("rules").join(format!("{index:03}.zr"));
        let tmp = path.with_extension("tmp");
        b.write(&tmp)?;
        std::fs::rename(&tmp, &path)?;
        Ok(Layer::open(&path)?.info(index))
    }

    /// 重新加载 rules/ 下全部层（按文件名序），final_policy 为 MATCH 的去向（通常是场景 "other"）。
    pub fn load_rules(&self, final_policy: String) -> Result<RuleStats, MobileError> {
        let mut files: Vec<PathBuf> = std::fs::read_dir(self.dir.join("rules"))?.flatten().map(|e| e.path()).filter(|p| p.extension().map(|e| e == "zr").unwrap_or(false)).collect();
        files.sort();
        let mut layers = Vec::with_capacity(files.len());
        for f in files {
            layers.push(Layer::open(&f)?);
        }
        *self.rules.write() = Arc::new(RuleSet { layers, final_policy });
        Ok(self.rule_stats())
    }

    pub fn rule_stats(&self) -> RuleStats {
        let r = self.rules.read().clone();
        RuleStats { total: r.total(), layers: r.layers.iter().enumerate().map(|(i, l)| l.info(i as u32)).collect(), disk_bytes: r.disk_bytes() }
    }

    pub fn test_rule(&self, input: String) -> Result<RuleTrace, MobileError> {
        let r = self.rules.read().clone();
        r.test(&input)
    }
}

/// zephyr-core（桌面共用核心）版本探针，确认链接正常。
#[uniffi::export]
pub fn core_greeting() -> String {
    zephyr_core::greet("mobile".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn end_to_end_mock_store() {
        let d = tempfile::tempdir().unwrap();
        let core = MobileCore::new(d.path().to_string_lossy().into()).unwrap();
        let rep = core.rebuild_mock_nodes(0.001).unwrap();
        assert!(rep.total > 13_000 && rep.total < 13_200, "{}", rep.total);
        let idx = core.node_index().unwrap();
        assert_eq!(idx.sections[0].region, "US");
        let q = core.query_nodes("东京 iplc".into()).unwrap();
        assert_eq!(q.sections.len(), 1);
        assert_eq!(q.sections[0].region, "JP");
        let page = core.node_rows(q.token, 0, 5).unwrap();
        assert_eq!(page.rows.len(), 5);
        assert!(page.rows.iter().all(|r| r.name.starts_with("东京") && r.tag.as_deref() == Some("IPLC")));
        // 重建：再次建库差异为 0 新增
        let rep2 = core.rebuild_mock_nodes(0.001).unwrap();
        assert_eq!(rep2.diff.added, 0);
        assert_eq!(rep2.diff.removed, 0);
        // 重开（持久化）
        drop(core);
        let core = MobileCore::new(d.path().to_string_lossy().into()).unwrap();
        assert_eq!(core.node_index().unwrap().total, rep.total);
        // 规则
        core.compile_rule_layer(0, "覆写".into(), LayerKind::Override, "在订阅之上".into(), "DIRECT".into(), "DOMAIN-SUFFIX,github.com,DIRECT".into()).unwrap();
        core.compile_rule_layer(1, "OpenAI".into(), LayerKind::Domain, "规则集".into(), "ai".into(), "+.openai.com\n+.chatgpt.com".into()).unwrap();
        let st = core.load_rules("other".into()).unwrap();
        assert_eq!(st.total, 3);
        assert_eq!(core.test_rule("chat.openai.com".into()).unwrap().policy, "ai");
        assert_eq!(core.test_rule("example.org".into()).unwrap().rule, "MATCH");
    }
}
