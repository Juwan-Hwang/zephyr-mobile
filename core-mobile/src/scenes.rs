//! 场景（contract §3）与 Zephyr 覆写层（§13 overrideHost）。桌面端没有对应实现，移动端自写。
//!
//! 场景 = 按用途分的出口：AI / 视频 / 其他（+ 自定义）。每个场景在 mihomo 里是一个 select 组，
//! 组内放当前节点 + 若干热备候选，切换候选时只需 MihomoClient.selectInGroup（不重载）；
//! 换到组外节点才需要重新生成配置并 zm_reload。
//!
//! 规则顺序（生成配置时前插到订阅规则之前）：
//!   1. Zephyr 覆写（host → 直连/场景），持久的写盘，"仅本次"的只在内存
//!   2. 场景例外（"Claude：US-Fixed-01"）→ 独立 select 组
//!   3. 场景应用域名（AI：openai/claude/gemini…；视频：netflix/youtube…）→ 场景组
//!   4. 订阅自带规则；"其他"场景选了节点时接管 MATCH

use crate::error::MobileError;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum SceneKind {
    Ai,
    Video,
    Other,
    Custom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum SceneSource {
    Auto,
    Manual,
    SubscriptionGroup,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum TraceTarget {
    Unchanged,
    Direct,
    Scene,
}

pub struct App {
    pub id: &'static str,
    pub name: &'static str,
    pub kind: SceneKind,
    pub domains: &'static [&'static str],
}

/// 内置应用目录：场景路由与"影响哪些应用"的文案都来自这里。
pub const APPS: &[App] = &[
    App { id: "chatgpt", name: "ChatGPT", kind: SceneKind::Ai, domains: &["openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "sora.com"] },
    App { id: "claude", name: "Claude", kind: SceneKind::Ai, domains: &["claude.ai", "anthropic.com", "claudeusercontent.com"] },
    App { id: "gemini", name: "Gemini", kind: SceneKind::Ai, domains: &["gemini.google.com", "generativelanguage.googleapis.com", "aistudio.google.com", "makersuite.google.com"] },
    App { id: "perplexity", name: "Perplexity", kind: SceneKind::Ai, domains: &["perplexity.ai"] },
    App { id: "grok", name: "Grok", kind: SceneKind::Ai, domains: &["grok.com", "x.ai"] },
    App { id: "netflix", name: "Netflix", kind: SceneKind::Video, domains: &["netflix.com", "netflix.net", "nflxvideo.net", "nflximg.net", "nflxext.com", "nflxso.net"] },
    App { id: "youtube", name: "YouTube", kind: SceneKind::Video, domains: &["youtube.com", "googlevideo.com", "ytimg.com", "youtu.be", "youtube-nocookie.com"] },
    App { id: "disney", name: "Disney+", kind: SceneKind::Video, domains: &["disneyplus.com", "disney-plus.net", "dssott.com", "bamgrid.com"] },
    App { id: "max", name: "Max", kind: SceneKind::Video, domains: &["max.com", "hbomax.com", "hbomaxcdn.com"] },
    App { id: "primevideo", name: "Prime Video", kind: SceneKind::Video, domains: &["primevideo.com", "aiv-cdn.net", "aiv-delivery.net"] },
];

pub fn app(id: &str) -> Option<&'static App> {
    APPS.iter().find(|a| a.id == id)
}

/// host 属于哪个内置应用（后缀匹配）。
pub fn app_of_host(host: &str) -> Option<&'static App> {
    let h = host.trim_end_matches('.').to_ascii_lowercase();
    APPS.iter().find(|a| a.domains.iter().any(|d| h == *d || h.ends_with(&format!(".{d}"))))
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SceneRec {
    pub id: String,
    pub kind: SceneKind,
    pub name: String,
    pub note: Option<String>,
    pub source: SceneSource,
    /// 当前节点（NodeId = 指纹）
    pub selected: Option<u64>,
    /// 热备候选（组内成员，切换不重载）
    pub standby: Vec<u64>,
    /// (应用 id, 节点)
    pub exceptions: Vec<(String, u64)>,
    pub exit_ip: Option<String>,
    pub exit_region: Option<String>,
    pub tested_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct HostOverride {
    pub host: String,
    pub target: TraceTarget,
    pub scene_id: Option<String>,
    pub persistent: bool,
}

#[derive(Default, Serialize, Deserialize)]
struct Disk {
    scenes: Vec<SceneRec>,
    overrides: Vec<HostOverride>,
}

pub(crate) struct SceneStore {
    path: PathBuf,
    pub scenes: Vec<SceneRec>,
    /// 持久 + 仅本次（persistent=false 的不写盘）
    pub overrides: Vec<HostOverride>,
}

fn defaults() -> Vec<SceneRec> {
    let mk = |id: &str, kind, name: &str, note: Option<&str>| SceneRec {
        id: id.into(),
        kind,
        name: name.into(),
        note: note.map(String::from),
        source: SceneSource::Auto,
        selected: None,
        standby: vec![],
        exceptions: vec![],
        exit_ip: None,
        exit_region: None,
        tested_at: None,
    };
    vec![mk("ai", SceneKind::Ai, "AI", None), mk("video", SceneKind::Video, "视频", None), mk("other", SceneKind::Other, "其他", None)]
}

/// mihomo 组名：场景组 `Zephyr·AI`；例外组 `Zephyr·AI·Claude`。前缀避免与订阅自带组重名。
pub fn group_name(scene: &SceneRec) -> String {
    format!("Zephyr·{}", scene.name)
}
pub fn exception_group_name(scene: &SceneRec, app_id: &str) -> String {
    format!("Zephyr·{}·{}", scene.name, app(app_id).map_or(app_id, |a| a.name))
}

impl SceneStore {
    pub fn open(dir: &Path) -> Result<Self, MobileError> {
        let path = dir.join("scenes.json");
        let d: Disk = match std::fs::read(&path) {
            Ok(b) => serde_json::from_slice(&b).map_err(|e| MobileError::Corrupt(format!("scenes.json: {e}")))?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Disk { scenes: defaults(), overrides: vec![] },
            Err(e) => return Err(e.into()),
        };
        Ok(Self { path, scenes: d.scenes, overrides: d.overrides })
    }

    pub fn save(&self) -> Result<(), MobileError> {
        let d = Disk { scenes: self.scenes.clone(), overrides: self.overrides.iter().filter(|o| o.persistent).cloned().collect() };
        let tmp = self.path.with_extension("tmp");
        std::fs::write(&tmp, serde_json::to_vec_pretty(&d).map_err(|e| MobileError::Io(e.to_string()))?)?;
        std::fs::rename(tmp, &self.path)?;
        Ok(())
    }

    pub fn get(&self, id: &str) -> Result<&SceneRec, MobileError> {
        self.scenes.iter().find(|s| s.id == id).ok_or_else(|| MobileError::SceneNotFound(id.into()))
    }
    pub fn get_mut(&mut self, id: &str) -> Result<&mut SceneRec, MobileError> {
        self.scenes.iter_mut().find(|s| s.id == id).ok_or_else(|| MobileError::SceneNotFound(id.into()))
    }

    pub fn set_override(&mut self, o: HostOverride) -> Result<(), MobileError> {
        let host = crate::rules::normalize_domain(&o.host)?;
        if o.target == TraceTarget::Scene {
            self.get(o.scene_id.as_deref().unwrap_or(""))?;
        }
        self.overrides.retain(|x| x.host != host);
        if o.target != TraceTarget::Unchanged {
            self.overrides.push(HostOverride { host, ..o });
        }
        self.save()
    }

    pub fn override_for(&self, host: &str) -> Option<&HostOverride> {
        let h = host.to_ascii_lowercase();
        self.overrides.iter().find(|o| h == o.host || h.ends_with(&format!(".{}", o.host)))
    }

    /// 应用名单：该场景影响的应用（去掉例外）与保持不变的应用（例外）。
    pub fn apps_split(&self, s: &SceneRec) -> (Vec<String>, Vec<String>) {
        let ex: Vec<&str> = s.exceptions.iter().map(|e| e.0.as_str()).collect();
        let affected = APPS.iter().filter(|a| a.kind == s.kind && !ex.contains(&a.id)).map(|a| a.name.to_string()).collect();
        let unchanged = ex.iter().filter_map(|id| app(id)).map(|a| a.name.to_string()).collect();
        (affected, unchanged)
    }

    /// 生成配置时用：需要放进 mihomo 的全部节点。
    pub fn referenced_nodes(&self) -> Vec<u64> {
        let mut v: Vec<u64> = self.scenes.iter().flat_map(|s| s.selected.iter().chain(s.standby.iter()).copied().chain(s.exceptions.iter().map(|e| e.1))).collect();
        v.sort_unstable();
        v.dedup();
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_overrides_persist() {
        let d = tempfile::tempdir().unwrap();
        let mut s = SceneStore::open(d.path()).unwrap();
        assert_eq!(s.scenes.iter().map(|x| x.id.as_str()).collect::<Vec<_>>(), vec!["ai", "video", "other"]);
        s.set_override(HostOverride { host: "https://Claude.ai/chat".into(), target: TraceTarget::Direct, scene_id: None, persistent: true }).unwrap();
        s.set_override(HostOverride { host: "example.com".into(), target: TraceTarget::Scene, scene_id: Some("video".into()), persistent: false }).unwrap();
        assert!(s.set_override(HostOverride { host: "x.com".into(), target: TraceTarget::Scene, scene_id: Some("nope".into()), persistent: true }).is_err());
        assert_eq!(s.override_for("api.claude.ai").unwrap().target, TraceTarget::Direct);
        s.get_mut("ai").unwrap().exceptions.push(("claude".into(), 7));
        s.save().unwrap();
        let s2 = SceneStore::open(d.path()).unwrap();
        assert_eq!(s2.overrides.len(), 1, "仅本次的覆写不落盘");
        let (aff, unch) = s2.apps_split(s2.get("ai").unwrap());
        assert!(aff.contains(&"ChatGPT".to_string()) && !aff.contains(&"Claude".to_string()));
        assert_eq!(unch, vec!["Claude"]);
        assert_eq!(s2.referenced_nodes(), vec![7]);
        let mut s3 = s2;
        s3.set_override(HostOverride { host: "claude.ai".into(), target: TraceTarget::Unchanged, scene_id: None, persistent: true }).unwrap();
        assert!(s3.override_for("claude.ai").is_none(), "选“不变”即清除覆写");
    }

    #[test]
    fn app_lookup() {
        assert_eq!(app_of_host("rr3---sn-abc.googlevideo.com").unwrap().id, "youtube");
        assert_eq!(app_of_host("api.openai.com").unwrap().kind, SceneKind::Ai);
        assert!(app_of_host("notopenai.com").is_none());
    }
}
