# MockEngine 数据规格 v0

> 唯一真相：`design/prototype/pages.js`。本文是它的移植说明；校验样本 `contract/fixtures/mock-v0.json` 由 `node tools/gen-mock-fixtures.js` 直接对原型求值生成。**Swift / Kotlin 的 MockEngine 单测必须逐项与 fixtures 一致**（节点名、tag、协议、运营商、缓存延迟、查询计数与前 12 行）。

## 1. 地区表 RG
15 个地区，顺序固定（index 0..14）：`[code, name, count, cities[], baseLatency, carriers[]]`，原样见 fixtures `regions`。总数 **13,109,802**。

## 2. 节点生成（全部 32 位无符号整数运算）
```
hsh(r, j):
  h = (j * 2654435761 + r * 97) mod 2^32        // 注意：JS 里先做 double 乘法再 >>>0；j ≤ 3,118,401 时乘积 < 2^53，精确
  h ^= h >>> 15
  h = imul(h, 2246822519) mod 2^32             // imul = 32 位有符号乘法取低 32 位，再当无符号
  h ^= h >>> 13
tagOf(r,j)  = (j*7 + r) % 5                    → TAGS = [IPLC, IEPL, BGP, 家宽, 原生]
protOf(r,j) = hsh(r+7, j) % 5                  → PROT = [VLESS, Hy2, TUIC, SS, Trojan]
carOf(r,j)  = floor(j/5) % carriers.count
city(r,j)   = cities[j % cities.count]
MULT[hsh(r+3,j) % 10]: index 4 → " ×1.5", 7 → " ×0.5", 9 → " ×2"，其余 ""
n           = (floor(j / lcm(cities.count, 5*carriers.count)) % 64) + 1
name        = "{city} {carrier} {tag} {n 两位补零}{mult}"
id          = r * 100_000_000 + j
cachedLatency(r,j): h = hsh(r,j); 若 h % 11 < 3 则 baseLatency + h % 37，否则 null
```
⚠️ Kotlin/Swift 里 `j * 2654435761` 用 64 位算再 `and 0xFFFFFFFF`；`imul` 用 `(Int32(h) &* Int32(bitPattern: 2246822519))` 后转 UInt32。

## 3. 查询（queryNodes）——按原型 `buildModel` 移植，**不扫全表**
1. 输入小写、按空白切词。逐词依次尝试（命中即进入下一个词）：
   a. 地区：`code` 全等，或 `name` 包含该词，或该词包含 `name` → 地区集合取交集，词加入 highlights。
   b. 城市：城市名包含该词或该词包含城市名 → 记录该地区的城市序号，城市名加入 highlights。
   c. 运营商：小写全等 / 去空格全等 / 按空格切分后含该词 / 词长 ≥2 且前缀 → 记录运营商序号。
   d. 标签：小写全等或（词长 ≥2 且前缀）→ 记录 tag。
   e. 都不中：若是最后一个词且匹配 `^[a-z0-9+-]{1,3}$`，忽略（打字中）；否则整体无结果... **注意原型实际行为**：`ok=false` 时 G 为空，但 fixtures 中 "zzz" 返回全量——因为 "zzz" 是最后一个词且满足正则被忽略。以 fixtures 为准。
2. 每个地区计算周期 `P = (有城市? L:1) * ((有tag或运营商)? 5:1) * (有运营商? C:1)`，在 `[0,P)` 内筛出满足条件的余数集合 S，命中数 `Σ_{s∈S, s<count} floor((count-1-s)/P)+1`。
3. 结果第 k 个节点（分区内）：`j = floor(k/|S|)*P + S[k % |S|]`。
4. 分区顺序 = RG 顺序；每分区一行头。fixtures `queries[].firstRows` 给出前 12 行（含头行）。

## 4. 规则
7 层见 fixtures `rules.layers`（总 103,606,731 条，"已编译 · 磁盘占用 1.9 GB"）。`testRule` 按原型 `matchRule` 的 7 条正则顺序匹配，域名不进第 7 层（IP 层），IP 只进第 7 层；不中 → MATCH，场景 "其他"。policy 映射：`AI`→场景 ai，`V`→场景 video，`O`→场景 other，`DIRECT`/`REJECT` 原样。`ruleNo` 为原型第 4 列。fixtures `rules.tests` 为校验样本。耗时 mock：`10 + len(input)` 微秒。

## 5. 场景（固定初始值，取自原型首页）
| id | name | available | selected | exitIp | source | note / exceptions |
|---|---|---|---|---|---|---|
| ai | AI | 9 | SG 新加坡 02 | 198.51.100.7 | auto | 例外：Claude → US-Fixed-01 |
| video | 视频 | 22 | HK 香港 HKT | 203.0.113.24 | auto | Netflix 完整片库 |
| other | 其他 | — | TW TW-Fixed-01 | 198.51.100.41 | subscription_group | |
- testedAt = now − 2h。AI 场景切 JP 东京 03 时出口 `203.0.113.61`，affectedApps ["GPT","Gemini"]，unchangedApps ["Claude"]。
- 全局模式出口：东京 03（JP 203.0.113.61）。

## 6. 其余固定值
- 连接：初始 disconnected、mode rule；connect 后 600ms 进入 connected。连接时长样例 2:14:07。
- 流量：1 Hz，down 在 2.4–3.4 MB/s、up 150–260 KB/s 之间按 `sin` + hsh 抖动（确定性：第 t 秒用 `hsh(1, t)`）。
- 今日：1.8 GB，4 个地区，6 小时在线，最快 38 ms；hourly 24 项总和 = 1.8 GB（1.8×10^9 字节，按 hsh(2,h) 权重分配）。
- 订阅：Nebula Cloud（8,204 节点，剩 86.4 GB，26 天后到期，2 小时前更新，diff +1,204 / −318 / 0 规则变更，覆写已保留，场景池已重测）；Orbit（3,118 节点，剩 12.0 GB，11月9日到期）；其余 212 个合计 13,098,480 节点；共 214 个，每 12 小时更新。
- 存储：节点 0.6 GB，规则 1.9 GB，可用 3.1 GB。
- 设置默认：受信任 Wi‑Fi "家"、本地代理 127.0.0.1:7890 需要密码 关、仅 Wi‑Fi 测速 开、结果保留 24 小时、自动更新 12 小时、仅 Wi‑Fi 更新 开、更新前显示更改 开、强调色 blue、外观 system。
- 测速：`testLatency` 对每个 id 延迟 80–400ms 后推送 `cachedLatency` 或 `baseLatency + hsh(r,j)%37`；`hsh(r,j)%23==0` 记超时 -1。
