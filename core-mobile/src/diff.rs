//! 订阅更新差异：新旧指纹集合的有序归并，O(n)。

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct NodeDiff {
    pub added: u64,
    pub removed: u64,
    pub kept: u64,
}

/// 两个已排序（可含重复）的指纹数组求差异。
pub fn diff_sorted(old: &[u64], new: &[u64]) -> NodeDiff {
    let (mut i, mut j) = (0, 0);
    let (mut added, mut removed, mut kept) = (0u64, 0u64, 0u64);
    while i < old.len() || j < new.len() {
        // 跳过重复
        if i > 0 && i < old.len() && old[i] == old[i - 1] { i += 1; continue; }
        if j > 0 && j < new.len() && new[j] == new[j - 1] { j += 1; continue; }
        match (old.get(i), new.get(j)) {
            (Some(a), Some(b)) if a == b => { kept += 1; i += 1; j += 1; }
            (Some(a), Some(b)) if a < b => { removed += 1; i += 1; }
            (Some(_), Some(_)) => { added += 1; j += 1; }
            (Some(_), None) => { removed += 1; i += 1; }
            (None, Some(_)) => { added += 1; j += 1; }
            (None, None) => break,
        }
    }
    NodeDiff { added, removed, kept }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn diff() {
        assert_eq!(diff_sorted(&[1, 2, 3, 5], &[2, 3, 4, 4, 6]), NodeDiff { added: 2, removed: 2, kept: 2 });
        assert_eq!(diff_sorted(&[], &[1]), NodeDiff { added: 1, removed: 0, kept: 0 });
        assert_eq!(diff_sorted(&[7, 7], &[]), NodeDiff { added: 0, removed: 1, kept: 0 });
    }
}
