# 性能基线（core-mobile，release）

测量环境：沙箱 2 核 aarch64、2 GB 内存。手机需另测（iOS NE 内存上限待真机验证）。

| 项目 | 数值 | 说明 |
|---|---|---|
| 1310 万节点建库 | **10.4 s**（原 31.6 s） | 峰值 RSS 0.8 GB；文件 672.7 MB（51.3 B/节点） |
| 冷开节点库 | 1.9 ms，RSS ≈ 9 MB | mmap，按需换页 |
| 查询 | 0.1–1.7 ms | 16 条 fixtures 查询的计数、分区、首屏行与原型逐条一致（tests/full_scale.rs） |
| 分页 60 行 | ≤ 0.15 ms | |
| 1010 万规则编译 | 1.4 s，文件 160 MB | 域名后缀 + 10 万 CIDR |
| 规则匹配 | ≤ 0.3 ms | 7 层逐层 |

## 建库提速记录（2026-11-06）
- 倒排索引：BTreeMap 逐节点查找 → 稠密数组；roaring 逐个 `push` 约 150 ns，改为攒 4096 个再 `append`（快 15 倍以上）。
- 名称词元：原始片段 → 词元 id 缓存，命中后零分配。
- 指纹：栈缓冲，零分配；哈希表换 FxHash。
- 2.6M 节点：write 4.86 s → 1.05 s；push 0.84 s → 0.56 s。

## 复现
```
source /workspace/env/activate.sh && cd $ZM/core-mobile
cargo run --release --example scale 1.0          # 全量基准
ZM_PROFILE=1 cargo run --release --example prof 0.2   # 分段耗时
cargo test --release --test full_scale -- --ignored   # 全量对照原型
```
