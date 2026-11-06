//! 延迟缓存：按节点指纹（= NodeId，跨订阅更新稳定）记录最近一次测速。
//!
//! 千万级节点里真正测过的通常只有几千到几十万个，所以缓存是稀疏表，不随节点库膨胀。
//! 上限 MAX_ENTRIES，超出按测速时间淘汰最旧。磁盘格式：magic + N × (fp u64, ms i32, at i64)，原子写。
//!
//! 用途：节点行显示延迟（contract：null = 未测/过期，-1 = 超时）、场景候选按延迟排序、命令"最快节点"。

use crate::error::MobileError;
use rustc_hash::FxHashMap;
use std::path::{Path, PathBuf};

const MAGIC: &[u8; 8] = b"ZLAT\x00\x00\x00\x01";
pub const MAX_ENTRIES: usize = 262_144;

#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct LatencySample {
    pub id: u64,
    /// 毫秒；-1 = 超时
    pub ms: i32,
    /// 毫秒时间戳
    pub at: i64,
}

pub(crate) struct LatencyCache {
    path: PathBuf,
    pub map: FxHashMap<u64, (i32, i64)>,
    dirty: bool,
}

impl LatencyCache {
    pub fn open(dir: &Path) -> Self {
        let path = dir.join("latency.bin");
        let mut map = FxHashMap::default();
        if let Ok(b) = std::fs::read(&path) {
            if b.len() >= 8 && &b[..8] == MAGIC {
                for c in b[8..].chunks_exact(20) {
                    let fp = u64::from_le_bytes(c[0..8].try_into().unwrap());
                    let ms = i32::from_le_bytes(c[8..12].try_into().unwrap());
                    let at = i64::from_le_bytes(c[12..20].try_into().unwrap());
                    map.insert(fp, (ms, at));
                }
            }
        }
        Self { path, map, dirty: false }
    }

    pub fn record(&mut self, samples: &[LatencySample]) {
        for s in samples {
            let e = self.map.entry(s.id).or_insert((s.ms, s.at));
            if s.at >= e.1 {
                *e = (s.ms, s.at);
            }
        }
        if self.map.len() > MAX_ENTRIES {
            let mut ats: Vec<i64> = self.map.values().map(|v| v.1).collect();
            let cut = self.map.len() - MAX_ENTRIES;
            let (_, &mut nth, _) = ats.select_nth_unstable(cut);
            self.map.retain(|_, v| v.1 > nth);
        }
        self.dirty = true;
    }

    /// 有效值：未过期才返回。max_age_millis <= 0 表示不过期。
    pub fn get(&self, id: u64, now: i64, max_age_millis: i64) -> Option<(i32, i64)> {
        self.map.get(&id).copied().filter(|&(_, at)| max_age_millis <= 0 || now - at <= max_age_millis)
    }

    pub fn flush(&mut self) -> Result<(), MobileError> {
        if !self.dirty {
            return Ok(());
        }
        let mut buf = Vec::with_capacity(8 + self.map.len() * 20);
        buf.extend_from_slice(MAGIC);
        for (fp, (ms, at)) in &self.map {
            buf.extend_from_slice(&fp.to_le_bytes());
            buf.extend_from_slice(&ms.to_le_bytes());
            buf.extend_from_slice(&at.to_le_bytes());
        }
        let tmp = self.path.with_extension("tmp");
        std::fs::write(&tmp, buf)?;
        std::fs::rename(&tmp, &self.path)?;
        self.dirty = false;
        Ok(())
    }

    /// 排序键：超时排最后，其余按毫秒升序。
    pub fn rank_key(ms: i32) -> i64 {
        if ms < 0 {
            i64::MAX
        } else {
            ms as i64
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn record_newer_wins_persist_and_evict() {
        let d = tempfile::tempdir().unwrap();
        let mut c = LatencyCache::open(d.path());
        c.record(&[LatencySample { id: 1, ms: 50, at: 10 }, LatencySample { id: 1, ms: 99, at: 5 }, LatencySample { id: 2, ms: -1, at: 10 }]);
        assert_eq!(c.get(1, 10, 0), Some((50, 10)), "旧样本不覆盖新样本");
        assert_eq!(c.get(1, 1000, 100), None, "过期");
        c.flush().unwrap();
        let c2 = LatencyCache::open(d.path());
        assert_eq!(c2.get(2, 10, 0), Some((-1, 10)));
        let mut c3 = c2;
        let many: Vec<_> = (0..MAX_ENTRIES as u64 + 10).map(|i| LatencySample { id: 100 + i, ms: 1, at: 100 + i as i64 }).collect();
        c3.record(&many);
        assert!(c3.map.len() <= MAX_ENTRIES);
        assert!(c3.get(1, 10, 0).is_none(), "最旧的被淘汰");
        assert!(LatencyCache::rank_key(-1) > LatencyCache::rank_key(5000));
    }
}
