//! 场景自动切换。策略结构与校验复用桌面 zephyr-core（failover.rs），
//! 连续失败计数与冷却复用 clash-prism-core 的 FailoverTracker（桌面端同一实现）。
//! 移动端自写的只有"切到哪"：场景的热备成员里分数最高、且不是失败节点的那个。

use crate::engine::MobileCore;
use crate::error::MobileError;
use crate::nodes::NodeRow;
use crate::scene_api::SceneApply;
use clash_prism_core::failover::{FailoverTracker, NodeFailPolicy};
use rustc_hash::FxHashMap;
use std::path::{Path, PathBuf};
use zephyr_core::failover::{validate_failover_policy, FailoverPolicyConfig};

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FailoverPolicy {
    pub enabled: bool,
    /// 连续失败多少次切换（默认 3）
    pub threshold: u32,
    /// 冷却秒数（默认 30）
    pub cooldown_secs: u64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SceneFailover {
    pub failed: NodeRow,
    pub failure_count: u32,
    /// 已写入场景；needs_reload 恒 false（只在热备里选），平台直接 selectInGroup
    pub apply: SceneApply,
}

pub(crate) struct FailoverState {
    path: PathBuf,
    policy: FailoverPolicyConfig,
    trackers: FxHashMap<String, FailoverTracker>,
}

fn to_prism(p: &FailoverPolicyConfig) -> NodeFailPolicy {
    let mut n = NodeFailPolicy::new().with_threshold(p.threshold).with_cooldown(p.cooldown_secs);
    n.enabled = p.enabled;
    n
}

impl FailoverState {
    pub fn open(dir: &Path) -> Self {
        let path = dir.join("failover.json");
        let policy = std::fs::read(&path).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        Self { path, policy, trackers: FxHashMap::default() }
    }
    fn tracker(&mut self, scene: &str) -> &mut FailoverTracker {
        let p = to_prism(&self.policy);
        self.trackers.entry(scene.to_string()).or_insert_with(|| FailoverTracker::new(p))
    }
}

#[uniffi::export]
impl MobileCore {
    pub fn failover_policy(&self) -> FailoverPolicy {
        let p = &self.failover.lock().policy;
        FailoverPolicy { enabled: p.enabled, threshold: p.threshold, cooldown_secs: p.cooldown_secs }
    }

    pub fn set_failover_policy(&self, policy: FailoverPolicy) -> Result<(), MobileError> {
        let cfg = FailoverPolicyConfig { enabled: policy.enabled, threshold: policy.threshold, cooldown_secs: policy.cooldown_secs, fallback_group: "next".into() };
        let errs = validate_failover_policy(cfg.clone());
        if !errs.is_empty() {
            return Err(MobileError::Invalid(errs.join("; ")));
        }
        let mut f = self.failover.lock();
        std::fs::write(&f.path, serde_json::to_vec(&cfg).map_err(|e| MobileError::Io(e.to_string()))?)?;
        f.policy = cfg;
        f.trackers.clear();
        Ok(())
    }

    /// 平台对场景当前出口做健康探测（或连接失败）后上报。达到阈值且不在冷却期时，
    /// 自动换到热备里最优的节点并返回动作；否则 None。
    pub fn report_scene_probe(&self, scene_id: String, success: bool, now_millis: i64) -> Result<Option<SceneFailover>, MobileError> {
        let (selected, standby) = {
            let sc = self.scenes.lock();
            let s = sc.get(&scene_id)?;
            match s.selected {
                Some(id) => (id, s.standby.clone()),
                None => return Ok(None),
            }
        };
        let key = format!("{selected:016x}");
        let Some(action) = self.failover.lock().tracker(&scene_id).report(&key, success) else { return Ok(None) };
        // 热备按 smart 分数挑：没测过的排最后
        let failed = self.rows_by_id_pub(&[selected])?.remove(&selected).ok_or_else(|| MobileError::NotFound("node".into()))?;
        let lat = self.latency.lock();
        let mut cands: Vec<(i64, u64)> = standby
            .iter()
            .filter(|&&id| id != selected)
            .map(|&id| (lat.get(id, now_millis, 0).map_or(i64::MAX, |(ms, _)| crate::latency::LatencyCache::rank_key(ms)), id))
            .collect();
        drop(lat);
        cands.sort_unstable();
        let Some(&(_, next)) = cands.first() else { return Ok(None) };
        let apply = self.apply_scene_change(scene_id, next, now_millis)?;
        debug_assert!(!apply.needs_reload);
        Ok(Some(SceneFailover { failed, failure_count: action.failure_count, apply }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failover_switches_after_threshold_then_cools_down() {
        let (_d, core, _sub, rows) = crate::scene_api::tests::setup();
        assert!(core.set_failover_policy(FailoverPolicy { enabled: true, threshold: 0, cooldown_secs: 30 }).is_err(), "桌面端校验生效");
        core.set_failover_policy(FailoverPolicy { enabled: true, threshold: 2, cooldown_secs: 30 }).unwrap();
        assert_eq!(core.failover_policy().threshold, 2);
        core.apply_scene_change("ai".into(), rows[0].id, 1000).unwrap();
        assert!(core.report_scene_probe("ai".into(), false, 1000).unwrap().is_none());
        let f = core.report_scene_probe("ai".into(), false, 1000).unwrap().expect("第 2 次失败切换");
        assert_eq!(f.failed.id, rows[0].id);
        assert!(!f.apply.needs_reload);
        assert_eq!(f.apply.previous, Some(rows[0].id));
        let now = core.scenes(1000).unwrap()[0].selected.clone().unwrap();
        assert_ne!(now.id, rows[0].id);
        // 冷却期内新节点连续失败不再切
        core.report_scene_probe("ai".into(), false, 1000).unwrap();
        assert!(core.report_scene_probe("ai".into(), false, 1000).unwrap().is_none());
        // 未选节点的场景不处理
        assert!(core.report_scene_probe("video".into(), false, 1000).unwrap().is_none());
    }
}
