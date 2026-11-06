//! UniFFI 导出的 `MobileCore`：CoreEngine（Swift/Kotlin）只包这一层。
//! 线程安全：内部 RwLock；节点库/规则替换为原子换指针，查询不阻塞写入。

use crate::diff::{diff_sorted, NodeDiff};
use crate::error::MobileError;
use crate::subs::{FetchedSubscription, SubStore, Subscription, SubscriptionDiff, SubscriptionsSummary};
use crate::nodes::{BuildPhase, NodeQueryResult, NodeRow, NodeStore, NodeStoreBuilder, RegionSection};
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
    subs: Mutex<SubStore>,
}

impl MobileCore {
    fn store(&self) -> Result<Arc<NodeStore>, MobileError> {
        self.store.read().clone().ok_or_else(|| MobileError::NotFound("节点库未建立".into()))
    }
    fn swap_store(&self, builder: NodeStoreBuilder, skipped: u64, t0: std::time::Instant) -> Result<BuildReport, MobileError> {
        self.swap_store_p(builder, skipped, t0, &|_, _, _| true)
    }
    fn swap_store_p(&self, builder: NodeStoreBuilder, skipped: u64, t0: std::time::Instant, progress: &dyn Fn(BuildPhase, u64, u64) -> bool) -> Result<BuildReport, MobileError> {
        let gen = {
            let mut g = self.generation.lock();
            *g += 1;
            *g
        };
        let path = self.dir.join(format!("nodes.{gen}.zn"));
        if let Err(e) = builder.write_with_progress(&path, progress) {
            let _ = std::fs::remove_file(&path);
            return Err(e);
        }
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

/// 建库进度回调（平台实现）。返回 false = 取消。会在后台线程调用。
#[uniffi::export(callback_interface)]
pub trait BuildProgress: Send + Sync {
    fn on_progress(&self, phase: BuildPhase, done: u64, total: u64) -> bool;
}

#[uniffi::export]
impl MobileCore {
    /// data_dir：App Group 容器下的目录（iOS 扩展与 App 共享）/ Android filesDir。
    #[uniffi::constructor]
    pub fn new(data_dir: String) -> Result<Arc<Self>, MobileError> {
        let dir = PathBuf::from(data_dir);
        std::fs::create_dir_all(dir.join("rules"))?;
        let dir_for_subs = dir.clone();
        let gen: u64 = std::fs::read_to_string(dir.join("nodes.current")).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0);
        let store = if gen > 0 { NodeStore::open(&dir.join(format!("nodes.{gen}.zn"))).ok().map(Arc::new) } else { None };
        Ok(Arc::new(Self {
            dir,
            store: RwLock::new(store),
            rules: RwLock::new(Arc::new(RuleSet { layers: vec![], final_policy: "other".into() })),
            queries: Mutex::new(VecDeque::new()),
            next_token: Mutex::new(1),
            generation: Mutex::new(gen),
            subs: Mutex::new(SubStore::open(&dir_for_subs)?),
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

    /// 同 rebuild_nodes，带进度与取消（UI 显示"正在建立索引 62%"；回调返回 false 取消，旧库保持不变）。
    pub fn rebuild_nodes_with_progress(&self, sources: Vec<SubscriptionSource>, progress: Box<dyn BuildProgress>) -> Result<BuildReport, MobileError> {
        let t0 = std::time::Instant::now();
        let mut b = NodeStoreBuilder::new();
        let mut skipped = 0;
        let n = sources.len() as u64;
        for (k, s) in sources.into_iter().enumerate() {
            if !progress.on_progress(BuildPhase::Parse, k as u64, n) {
                return Err(MobileError::Cancelled);
            }
            let (nodes, sk) = crate::subscription::parse_proxies_yaml(&s.yaml, s.id)?;
            skipped += sk;
            for x in nodes {
                b.push(x);
            }
        }
        self.swap_store_p(b, skipped, t0, &|ph, d, t| progress.on_progress(ph, d, t))
    }

    pub fn rebuild_mock_nodes_with_progress(&self, scale: f64, progress: Box<dyn BuildProgress>) -> Result<BuildReport, MobileError> {
        let t0 = std::time::Instant::now();
        let scale = scale.clamp(0.000_01, 1.0);
        let total = (crate::mock::total() as f64 * scale) as u64;
        let mut b = NodeStoreBuilder::with_capacity(total as usize);
        for (k, x) in crate::mock::nodes(scale).enumerate() {
            if k & 0xFFFF == 0 && !progress.on_progress(BuildPhase::Parse, k as u64, total) {
                return Err(MobileError::Cancelled);
            }
            b.push(x);
        }
        self.swap_store_p(b, 0, t0, &|ph, d, t| progress.on_progress(ph, d, t))
    }

    // ---------- 订阅（contract §7）：平台拉取正文，核心存储/差异/重建 ----------

    pub fn subscriptions(&self) -> Vec<Subscription> {
        self.subs.lock().list()
    }

    pub fn subscriptions_summary(&self) -> SubscriptionsSummary {
        self.subs.lock().summary()
    }

    /// 平台拉取用的完整 URL（不出现在 Subscription.url 里）。
    pub fn subscription_fetch_url(&self, id: String) -> Result<Option<String>, MobileError> {
        self.subs.lock().full_url(&id)
    }

    /// 到了自动更新时间的订阅 id（后台任务：逐个拉取后 update_subscription）。
    pub fn due_subscriptions(&self, now_millis: i64) -> Vec<String> {
        self.subs.lock().due(now_millis)
    }

    /// 导入并重建节点库。url 可空（剪贴板/文件导入）。
    pub fn import_subscription(&self, name: String, url: Option<String>, fetched: FetchedSubscription, auto_update_hours: i32, progress: Option<Box<dyn BuildProgress>>) -> Result<Subscription, MobileError> {
        let sub = self.subs.lock().import(name, url, &fetched, auto_update_hours)?;
        if let Err(e) = self.rebuild_from_subscriptions(progress) {
            let _ = self.subs.lock().delete(&sub.id);
            return Err(e);
        }
        Ok(sub)
    }

    /// "更新前显示更改"：不落盘。
    pub fn preview_subscription_update(&self, id: String, fetched: FetchedSubscription) -> Result<SubscriptionDiff, MobileError> {
        self.subs.lock().preview(&id, &fetched)
    }

    pub fn update_subscription(&self, id: String, fetched: FetchedSubscription, progress: Option<Box<dyn BuildProgress>>) -> Result<SubscriptionDiff, MobileError> {
        let d = self.subs.lock().update(&id, &fetched)?;
        self.rebuild_from_subscriptions(progress)?;
        Ok(d)
    }

    pub fn delete_subscription(&self, id: String) -> Result<(), MobileError> {
        self.subs.lock().delete(&id)?;
        self.rebuild_from_subscriptions(None).map(|_| ())
    }

    /// 由已保存的全部订阅正文重建节点库（启动修复、批量更新后调用一次即可）。
    pub fn rebuild_from_subscriptions(&self, progress: Option<Box<dyn BuildProgress>>) -> Result<BuildReport, MobileError> {
        let sources: Vec<SubscriptionSource> = {
            let s = self.subs.lock();
            s.entries.iter().filter_map(|e| s.body(e.slot).map(|yaml| SubscriptionSource { id: e.slot, yaml })).collect()
        };
        match progress {
            Some(p) => self.rebuild_nodes_with_progress(sources, p),
            None => self.rebuild_nodes(sources),
        }
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
        let bm = bm.ok_or_else(|| MobileError::StaleToken(format!("查询句柄 {token} 已过期")))?;
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
    use std::sync::atomic::{AtomicU64, Ordering};

    struct P {
        calls: Arc<AtomicU64>,
        cancel_at_index: bool,
    }
    impl BuildProgress for P {
        fn on_progress(&self, phase: BuildPhase, done: u64, total: u64) -> bool {
            self.calls.fetch_add(1, Ordering::Relaxed);
            assert!(total == 0 || done <= total);
            !(self.cancel_at_index && phase == BuildPhase::Index)
        }
    }

    #[test]
    fn subscriptions_drive_node_store() {
        let d = tempfile::tempdir().unwrap();
        let core = MobileCore::new(d.path().to_string_lossy().into()).unwrap();
        let body = |n: usize| {
            let mut s = String::from("proxies:\n");
            for i in 0..n {
                s += &format!("  - {{name: \"香港 {i:02}\", server: h{i}.example, port: 443, type: trojan}}\n");
            }
            s
        };
        let f = |b: String| FetchedSubscription { body: b, userinfo: None, now_millis: 1 };
        let a = core.import_subscription("A".into(), None, f(body(30)), 24, None).unwrap();
        assert_eq!(core.node_index().unwrap().total, 30);
        let p = core.preview_subscription_update(a.id.clone(), f(body(40))).unwrap();
        assert_eq!((p.added_nodes, p.removed_nodes), (10, 0));
        core.update_subscription(a.id.clone(), f(body(40)), None).unwrap();
        assert_eq!(core.node_index().unwrap().total, 40);
        assert_eq!(core.query_nodes("香港".into()).unwrap().total, 40);
        // 重开：订阅与节点库都持久
        drop(core);
        let core = MobileCore::new(d.path().to_string_lossy().into()).unwrap();
        assert_eq!(core.subscriptions_summary().total_nodes, 40);
        assert_eq!(core.node_index().unwrap().total, 40);
        core.delete_subscription(a.id).unwrap();
        assert_eq!(core.node_index().unwrap().total, 0);
        assert!(core.import_subscription("bad".into(), None, f("proxies: []".into()), 0, None).is_err());
        assert_eq!(core.subscriptions().len(), 0);
    }

    #[test]
    fn progress_and_cancel_keep_old_store() {
        let d = tempfile::tempdir().unwrap();
        let core = MobileCore::new(d.path().to_string_lossy().into()).unwrap();
        let calls = Arc::new(AtomicU64::new(0));
        let r = core.rebuild_mock_nodes_with_progress(0.01, Box::new(P { calls: calls.clone(), cancel_at_index: false })).unwrap();
        assert!(calls.load(Ordering::Relaxed) >= 4);
        let before = core.node_index().unwrap().total;
        assert_eq!(before, r.total);
        let e = core.rebuild_mock_nodes_with_progress(0.02, Box::new(P { calls: calls.clone(), cancel_at_index: true })).unwrap_err();
        assert!(matches!(e, MobileError::Cancelled));
        assert_eq!(core.node_index().unwrap().total, before, "取消后旧库不变");
        let zn = std::fs::read_dir(d.path()).unwrap().flatten().filter(|e| e.file_name().to_string_lossy().ends_with(".zn")).count();
        assert_eq!(zn, 1, "取消不留半成品文件");
        // 句柄过期 → StaleToken
        assert!(matches!(core.node_rows(987654, 0, 10).unwrap_err(), MobileError::StaleToken(_)));
    }

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
