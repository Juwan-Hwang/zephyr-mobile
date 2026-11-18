# 第三方许可声明（Third-Party Notices）

> 本文件由 `tools/gen-third-party.sh` 生成，请勿手改；依赖升级后重新生成（`--check` 校验是否最新）。
> 各依赖的许可原文见 [THIRD_PARTY_LICENSES.txt](THIRD_PARTY_LICENSES.txt)。

## 许可口径

- **本仓库自有源码**：MIT（见 [LICENSE](LICENSE)）。
- **移动端安装包**（iOS / Android）静态链接了 [mihomo](https://github.com/MetaCubeX/mihomo) `v1.19.33`（GPL-3.0，见 [mihomo-mobile/LICENSE](mihomo-mobile/LICENSE)），因此**安装包整体按 GPL-3.0 分发**。每个发布版本的对应源码即本仓库对应的 tag（如 `mobile-v1.0`），其中 `vendor/zephyr` 子模块 commit、`core-mobile/Cargo.lock` 与 `mihomo-mobile/go.sum` 锁定了全部依赖版本。
- 除下方 ⚠️ 标出的项外，下列依赖的许可均与 GPL-3.0 兼容（MIT / Apache-2.0 / BSD / ISC / Zlib / BSL-1.0 / Unicode-3.0 / MPL-2.0 / LGPL-3.0 / GPL-3.0(-or-later) 等）。
- **MPL-2.0**（`uniffi*` 等）：文件级 copyleft。分发二进制时须告知其源码获取方式并附 MPL-2.0 全文：源码见 crates.io 对应版本（https://crates.io/crates/<名称>/<版本>）及本仓库 tag；许可全文见 THIRD_PARTY_LICENSES.txt。本项目未修改任何 MPL-2.0 文件。
- Go 标准库与运行时（go1.27.4）：BSD-3-Clause。
- ⚠️ `github.com/rasky/go-lzo` v0.0.0-20200203143853-96a758eda86e：README 称沿用原 LZO 的 GPLv2（原 LZO 库为 GPL-2.0-or-later）；若为 GPL-2.0-only 则与 GPL-3.0 不兼容，由上游 mihomo 引入，需跟进。

## Rust 运行时依赖（core-mobile，151 个）

目标：`aarch64-apple-ios`、`aarch64-apple-ios-sim`、`aarch64-linux-android`、`x86_64-linux-android`；不含 dev / build 依赖与 proc-macro。

许可分布：MIT OR Apache-2.0 ×81，MIT ×18，Unicode-3.0 ×15，Apache-2.0 OR MIT ×12，MPL-2.0 ×6，MIT/Apache-2.0 ×5，Unlicense OR MIT ×3，Apache-2.0 ×2，Zlib ×2，Zlib OR Apache-2.0 OR MIT ×2，(MIT OR Apache-2.0) AND Unicode-3.0 ×1，Apache-2.0 OR BSL-1.0 ×1，BSD-2-Clause OR Apache-2.0 OR MIT ×1，BSD-3-Clause ×1，BSL-1.0 ×1

| crate | 版本 | 许可（Cargo.toml） | 来源 |
|---|---|---|---|
| aead | 0.5.2 | MIT OR Apache-2.0 | crates.io |
| aes | 0.8.4 | MIT OR Apache-2.0 | crates.io |
| aes-gcm | 0.10.3 | Apache-2.0 OR MIT | crates.io |
| aho-corasick | 1.1.5 | Unlicense OR MIT | crates.io |
| allocator-api2 | 0.2.21 | MIT OR Apache-2.0 | crates.io |
| android_system_properties | 0.1.6 | MIT OR Apache-2.0 | crates.io |
| anstream | 1.0.0 | MIT OR Apache-2.0 | crates.io |
| anstyle | 1.0.14 | MIT OR Apache-2.0 | crates.io |
| anstyle-parse | 1.0.0 | MIT OR Apache-2.0 | crates.io |
| anstyle-query | 1.1.5 | MIT OR Apache-2.0 | crates.io |
| anyhow | 1.0.104 | MIT OR Apache-2.0 | crates.io |
| askama | 0.12.1 | MIT OR Apache-2.0 | crates.io |
| askama_escape | 0.10.3 | MIT OR Apache-2.0 | crates.io |
| base64 | 0.22.1 | MIT OR Apache-2.0 | crates.io |
| block-buffer | 0.10.4 | MIT OR Apache-2.0 | crates.io |
| bytemuck | 1.25.2 | Zlib OR Apache-2.0 OR MIT | crates.io |
| byteorder | 1.5.0 | Unlicense OR MIT | crates.io |
| bytes | 1.12.1 | MIT | crates.io |
| camino | 1.2.6 | MIT OR Apache-2.0 | crates.io |
| cargo-platform | 0.1.9 | MIT OR Apache-2.0 | crates.io |
| cargo_metadata | 0.15.4 | MIT | crates.io |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 | crates.io |
| chrono | 0.4.45 | MIT OR Apache-2.0 | crates.io |
| cipher | 0.4.4 | MIT OR Apache-2.0 | crates.io |
| clap | 4.6.7 | MIT OR Apache-2.0 | crates.io |
| clap_builder | 4.6.7 | MIT OR Apache-2.0 | crates.io |
| clap_lex | 1.1.1 | MIT OR Apache-2.0 | crates.io |
| clash-prism-core | 0.1.5 | Apache-2.0 | crates.io |
| clash-prism-smart | 0.1.1 | Apache-2.0 | crates.io |
| colorchoice | 1.0.5 | MIT OR Apache-2.0 | crates.io |
| core-foundation-sys | 0.8.7 | MIT OR Apache-2.0 | crates.io |
| cpufeatures | 0.2.17 | MIT OR Apache-2.0 | crates.io |
| crossbeam-utils | 0.8.23 | MIT OR Apache-2.0 | crates.io |
| crypto-common | 0.1.7 | MIT OR Apache-2.0 | crates.io |
| ctr | 0.9.2 | MIT OR Apache-2.0 | crates.io |
| dashmap | 6.2.1 | MIT | crates.io |
| digest | 0.10.7 | MIT OR Apache-2.0 | crates.io |
| equivalent | 1.0.3 | Apache-2.0 OR MIT | crates.io |
| foldhash | 0.1.5 | Zlib | crates.io |
| foldhash | 0.2.0 | Zlib | crates.io |
| form_urlencoded | 1.2.2 | MIT OR Apache-2.0 | crates.io |
| fs-err | 2.11.0 | MIT/Apache-2.0 | crates.io |
| generic-array | 0.14.7 | MIT | crates.io |
| getrandom | 0.2.17 | MIT OR Apache-2.0 | crates.io |
| getrandom | 0.3.4 | MIT OR Apache-2.0 | crates.io |
| getrandom | 0.4.3 | MIT OR Apache-2.0 | crates.io |
| ghash | 0.5.1 | Apache-2.0 OR MIT | crates.io |
| glob | 0.3.4 | MIT OR Apache-2.0 | crates.io |
| goblin | 0.8.2 | MIT | crates.io |
| hashbrown | 0.14.5 | MIT OR Apache-2.0 | crates.io |
| hashbrown | 0.15.5 | MIT OR Apache-2.0 | crates.io |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 | crates.io |
| heck | 0.5.0 | MIT OR Apache-2.0 | crates.io |
| iana-time-zone | 0.1.65 | MIT OR Apache-2.0 | crates.io |
| icu_collections | 2.4.0 | Unicode-3.0 | crates.io |
| icu_locale_core | 2.4.0 | Unicode-3.0 | crates.io |
| icu_normalizer | 2.4.0 | Unicode-3.0 | crates.io |
| icu_normalizer_data | 2.4.0 | Unicode-3.0 | crates.io |
| icu_properties | 2.4.0 | Unicode-3.0 | crates.io |
| icu_properties_data | 2.4.0 | Unicode-3.0 | crates.io |
| icu_provider | 2.4.0 | Unicode-3.0 | crates.io |
| idna | 1.1.0 | MIT OR Apache-2.0 | crates.io |
| idna_adapter | 1.2.2 | Apache-2.0 OR MIT | crates.io |
| indexmap | 2.14.2 | Apache-2.0 OR MIT | crates.io |
| inout | 0.1.4 | MIT OR Apache-2.0 | crates.io |
| is_terminal_polyfill | 1.70.2 | MIT OR Apache-2.0 | crates.io |
| itoa | 1.0.18 | MIT OR Apache-2.0 | crates.io |
| libc | 0.2.191 | MIT OR Apache-2.0 | crates.io |
| litemap | 0.8.3 | Unicode-3.0 | crates.io |
| lock_api | 0.4.14 | MIT OR Apache-2.0 | crates.io |
| log | 0.4.35 | MIT OR Apache-2.0 | crates.io |
| memchr | 2.8.3 | Unlicense OR MIT | crates.io |
| memmap2 | 0.9.12 | MIT OR Apache-2.0 | crates.io |
| minimal-lexical | 0.2.1 | MIT/Apache-2.0 | crates.io |
| nom | 7.1.3 | MIT | crates.io |
| num-traits | 0.2.19 | MIT OR Apache-2.0 | crates.io |
| once_cell | 1.21.4 | MIT OR Apache-2.0 | crates.io |
| opaque-debug | 0.3.1 | MIT OR Apache-2.0 | crates.io |
| parking_lot | 0.12.5 | MIT OR Apache-2.0 | crates.io |
| parking_lot_core | 0.9.12 | MIT OR Apache-2.0 | crates.io |
| percent-encoding | 2.3.2 | MIT OR Apache-2.0 | crates.io |
| pin-project-lite | 0.2.17 | Apache-2.0 OR MIT | crates.io |
| plain | 0.2.3 | MIT/Apache-2.0 | crates.io |
| polyval | 0.6.2 | Apache-2.0 OR MIT | crates.io |
| potential_utf | 0.1.6 | Unicode-3.0 | crates.io |
| ppv-lite86 | 0.2.21 | MIT OR Apache-2.0 | crates.io |
| rand | 0.9.5 | MIT OR Apache-2.0 | crates.io |
| rand_chacha | 0.9.0 | MIT OR Apache-2.0 | crates.io |
| rand_core | 0.6.4 | MIT OR Apache-2.0 | crates.io |
| rand_core | 0.9.5 | MIT OR Apache-2.0 | crates.io |
| regex | 1.13.1 | MIT OR Apache-2.0 | crates.io |
| regex-automata | 0.4.18 | MIT OR Apache-2.0 | crates.io |
| regex-syntax | 0.8.11 | MIT OR Apache-2.0 | crates.io |
| roaring | 0.10.12 | MIT OR Apache-2.0 | crates.io |
| rustc-hash | 2.1.3 | Apache-2.0 OR MIT | crates.io |
| ryu | 1.0.23 | Apache-2.0 OR BSL-1.0 | crates.io |
| scopeguard | 1.2.0 | MIT OR Apache-2.0 | crates.io |
| scroll | 0.12.0 | MIT | crates.io |
| semver | 1.0.28 | MIT OR Apache-2.0 | crates.io |
| serde | 1.0.229 | MIT OR Apache-2.0 | crates.io |
| serde_core | 1.0.229 | MIT OR Apache-2.0 | crates.io |
| serde_json | 1.0.154 | MIT OR Apache-2.0 | crates.io |
| serde_spanned | 0.6.9 | MIT OR Apache-2.0 | crates.io |
| serde_yaml_ng | 0.10.0 | MIT | crates.io |
| sha2 | 0.10.9 | MIT OR Apache-2.0 | crates.io |
| siphasher | 0.3.11 | MIT/Apache-2.0 | crates.io |
| smallvec | 1.16.4 | MIT OR Apache-2.0 | crates.io |
| smawk | 0.3.3 | MIT | crates.io |
| stable_deref_trait | 1.2.1 | MIT OR Apache-2.0 | crates.io |
| static_assertions | 1.1.0 | MIT OR Apache-2.0 | crates.io |
| strsim | 0.11.1 | MIT | crates.io |
| subtle | 2.6.1 | BSD-3-Clause | crates.io |
| textwrap | 0.16.4 | MIT | crates.io |
| thiserror | 1.0.69 | MIT OR Apache-2.0 | crates.io |
| thiserror | 2.0.21 | MIT OR Apache-2.0 | crates.io |
| tinystr | 0.8.5 | Unicode-3.0 | crates.io |
| tinyvec | 1.13.3 | Zlib OR Apache-2.0 OR MIT | crates.io |
| toml | 0.5.11 | MIT/Apache-2.0 | crates.io |
| toml | 0.8.23 | MIT OR Apache-2.0 | crates.io |
| toml_datetime | 0.6.11 | MIT OR Apache-2.0 | crates.io |
| toml_edit | 0.22.27 | MIT OR Apache-2.0 | crates.io |
| toml_write | 0.1.2 | MIT OR Apache-2.0 | crates.io |
| tracing | 0.1.44 | MIT | crates.io |
| tracing-core | 0.1.36 | MIT | crates.io |
| typenum | 1.20.1 | MIT OR Apache-2.0 | crates.io |
| unicode-normalization | 0.1.26 | (MIT OR Apache-2.0) AND Unicode-3.0 | crates.io |
| unicode-width | 0.2.3 | MIT OR Apache-2.0 | crates.io |
| uniffi | 0.28.3 | MPL-2.0 | crates.io |
| uniffi_bindgen | 0.28.3 | MPL-2.0 | crates.io |
| uniffi_core | 0.28.3 | MPL-2.0 | crates.io |
| uniffi_meta | 0.28.3 | MPL-2.0 | crates.io |
| uniffi_testing | 0.28.3 | MPL-2.0 | crates.io |
| uniffi_udl | 0.28.3 | MPL-2.0 | crates.io |
| universal-hash | 0.5.1 | MIT OR Apache-2.0 | crates.io |
| unsafe-libyaml | 0.2.11 | MIT | crates.io |
| url | 2.5.8 | MIT OR Apache-2.0 | crates.io |
| utf8_iter | 1.1.0 | Apache-2.0 OR MIT | crates.io |
| utf8parse | 0.2.2 | Apache-2.0 OR MIT | crates.io |
| utf_types | 1.0.0 | Apache-2.0 OR MIT | crates.io |
| uuid | 1.29.0 | Apache-2.0 OR MIT | crates.io |
| weedle2 | 5.0.0 | MIT | crates.io |
| winnow | 0.7.15 | MIT | crates.io |
| writeable | 0.6.4 | Unicode-3.0 | crates.io |
| xxhash-rust | 0.8.19 | BSL-1.0 | crates.io |
| yoke | 0.8.4 | Unicode-3.0 | crates.io |
| zephyr-core | 0.1.0 | MIT | vendor/zephyr（子模块） |
| zerocopy | 0.8.63 | BSD-2-Clause OR Apache-2.0 OR MIT | crates.io |
| zerofrom | 0.1.8 | Unicode-3.0 | crates.io |
| zerotrie | 0.2.5 | Unicode-3.0 | crates.io |
| zerovec | 0.11.9 | Unicode-3.0 | crates.io |
| zmij | 1.0.23 | MIT | crates.io |

## Go 运行时依赖（mihomo-mobile，122 个模块）

目标：android/arm64、android/amd64、ios/arm64、ios/amd64，build tags `with_gvisor`；许可按模块根目录的许可文件识别。

许可分布：BSD-3-Clause ×44，MIT ×36，Apache-2.0 ×14，GPL-3.0-or-later ×8，GPL-3.0 ×6，BSD-2-Clause ×5，MPL-2.0 ×3，CC0-1.0 ×1，GPL-2.0 ×1，ISC ×1，LGPL-3.0 ×1，MIT（模块包未附许可文件；仓库 LICENSE 为 MIT，GitHub API 2026-11-18 核对） ×1，MPL-2.0 AND BSD-3-Clause ×1

| 模块 | 版本 | 许可 |
|---|---|---|
| github.com/RyuaNerin/go-krypto | v1.3.0 | MIT |
| github.com/Yawning/aez | v0.0.0-20211027044916-e49e68abd344 | CC0-1.0 |
| github.com/ajg/form | v1.7.1 | BSD-3-Clause |
| github.com/andybalholm/brotli | v1.1.1 | MIT |
| github.com/bahlo/generic-list-go | v0.2.0 | BSD-3-Clause |
| github.com/bodgit/plumbing | v1.3.0 | BSD-3-Clause |
| github.com/bodgit/windows | v1.0.1 | BSD-3-Clause |
| github.com/coreos/go-iptables | v0.8.0 | Apache-2.0 |
| github.com/dlclark/regexp2 | v1.12.0 | MIT |
| github.com/dunglas/httpsfv | v1.0.2 | BSD-3-Clause |
| github.com/easytier/easytier/easytier-go | v0.0.0-20260910071355-3d0c9c3ca5e2 | LGPL-3.0 |
| github.com/enfein/mieru/v3 | v3.38.1 | GPL-3.0 |
| github.com/ericlagergren/aegis | v0.0.0-20250325060835-cd0defd64358 | BSD-2-Clause |
| github.com/ericlagergren/polyval | v0.0.0-20220411101811-e25bc10ba391 | BSD-2-Clause |
| github.com/ericlagergren/siv | v0.0.0-20220507050439-0b757b3aa5f1 | BSD-3-Clause |
| github.com/ericlagergren/subtle | v0.0.0-20220507045147-890d697da010 | BSD-3-Clause |
| github.com/fsnotify/fsnotify | v1.9.0 | BSD-3-Clause |
| github.com/fxamacker/cbor/v2 | v2.9.0 | MIT |
| github.com/gaukas/godicttls | v0.0.4 | BSD-3-Clause |
| github.com/gobwas/httphead | v0.1.0 | MIT |
| github.com/gobwas/pool | v0.2.1 | MIT |
| github.com/gobwas/ws | v1.4.0 | MIT |
| github.com/gofrs/uuid/v5 | v5.4.0 | MIT |
| github.com/golang/groupcache | v0.0.0-20241129210726-2c02b8208cf8 | Apache-2.0 |
| github.com/golang/snappy | v1.0.0 | BSD-3-Clause |
| github.com/google/btree | v1.1.3 | Apache-2.0 |
| github.com/google/pprof | v0.0.0-20240727154555-813a5fbdbec8 | Apache-2.0 |
| github.com/hashicorp/golang-lru/v2 | v2.0.7 | MPL-2.0 |
| github.com/insomniacslk/dhcp | v0.0.0-20250109001534-8abf58130905 | BSD-3-Clause |
| github.com/josharian/native | v1.1.0 | MIT |
| github.com/klauspost/compress | v1.17.9 | Apache-2.0 |
| github.com/klauspost/cpuid/v2 | v2.2.6 | MIT |
| github.com/klauspost/reedsolomon | v1.12.3 | MIT |
| github.com/mdlayher/netlink | v1.7.2 | MIT |
| github.com/mdlayher/socket | v0.5.1 | MIT |
| github.com/metacubex/age | v0.0.0-20260603010618-28d156b4ea78 | BSD-3-Clause |
| github.com/metacubex/amneziawg-go | v0.0.0-20260908071407-0c1c6f40ecd7 | MIT |
| github.com/metacubex/ascon | v0.1.0 | BSD-3-Clause |
| github.com/metacubex/bart | v0.29.0 | MIT |
| github.com/metacubex/bbolt | v0.0.0-20260706163408-d4ec34ad7c48 | MIT |
| github.com/metacubex/blake3 | v0.1.0 | MIT |
| github.com/metacubex/chacha | v0.1.5 | MIT（模块包未附许可文件；仓库 LICENSE 为 MIT，GitHub API 2026-11-18 核对） |
| github.com/metacubex/chi | v0.1.1 | MIT |
| github.com/metacubex/connect-ip-go | v0.0.0-20260727083417-67ccdb0cf771 | MIT |
| github.com/metacubex/cpu | v0.1.2 | BSD-3-Clause |
| github.com/metacubex/edwards25519 | v1.2.0 | BSD-3-Clause |
| github.com/metacubex/fswatch | v0.1.1 | GPL-3.0-or-later |
| github.com/metacubex/gopacket | v1.1.20-0.20230608035415-7e2f98a3e759 | BSD-3-Clause |
| github.com/metacubex/gvisor | v0.0.0-20260922041103-e2cbcd6e7400 | Apache-2.0 |
| github.com/metacubex/hkdf | v0.1.0 | BSD-3-Clause |
| github.com/metacubex/hpke | v0.1.0 | BSD-3-Clause |
| github.com/metacubex/http | v0.1.8 | BSD-3-Clause |
| github.com/metacubex/jls-quic-go | v0.0.0-20260727080412-732f2fc9a34d | MIT |
| github.com/metacubex/jls-tls | v0.0.0-20260723084315-67adc0e2f796 | BSD-3-Clause |
| github.com/metacubex/jsonv2 | v0.0.0-20260721082349-16b4998c8f89 | BSD-3-Clause |
| github.com/metacubex/kcp-go | v0.0.0-20260105040817-550693377604 | MIT |
| github.com/metacubex/mhurl | v0.1.0 | BSD-3-Clause |
| github.com/metacubex/mihomo | v1.19.33 | GPL-3.0 |
| github.com/metacubex/mipstack | v0.0.0-20261019124225-9a80a07eaeb9 | MPL-2.0 |
| github.com/metacubex/mlkem | v0.1.0 | BSD-3-Clause |
| github.com/metacubex/nftables | v0.0.0-20260426003805-208c2c1ba2cb | Apache-2.0 |
| github.com/metacubex/qpack | v0.6.0 | MIT |
| github.com/metacubex/quic-go | v0.61.1-0.20260727080200-2548683b76f4 | MIT |
| github.com/metacubex/randv2 | v0.2.0 | GPL-3.0 |
| github.com/metacubex/restls-client-go | v0.1.9 | BSD-3-Clause |
| github.com/metacubex/sevenzip | v1.6.4 | BSD-3-Clause |
| github.com/metacubex/sing | v0.5.8 | GPL-3.0-or-later |
| github.com/metacubex/sing-mux | v0.3.12 | GPL-3.0-or-later |
| github.com/metacubex/sing-quic | v0.0.0-20260904234848-1c242664697a | GPL-3.0-or-later |
| github.com/metacubex/sing-shadowsocks | v0.2.13 | GPL-3.0-or-later |
| github.com/metacubex/sing-shadowsocks2 | v0.2.8 | GPL-3.0-or-later |
| github.com/metacubex/sing-tun | v0.4.28 | GPL-3.0-or-later |
| github.com/metacubex/sing-vmess | v0.2.5 | GPL-3.0-or-later |
| github.com/metacubex/sing-wireguard | v0.0.0-20261002050126-e5fa1a607406 | GPL-3.0 |
| github.com/metacubex/smux | v0.0.0-20260105030934-d0c8756d3141 | MIT |
| github.com/metacubex/ssh | v0.1.0 | BSD-3-Clause |
| github.com/metacubex/tailscale | v0.0.0-20260821153257-ff0ecd818181 | BSD-3-Clause |
| github.com/metacubex/tailscale-wireguard-go | v0.0.0-20260725073821-e61ab99cede2 | MIT |
| github.com/metacubex/tfo-go | v0.0.0-20260623020846-376a77860b8c | MIT |
| github.com/metacubex/tls | v0.1.9 | BSD-3-Clause |
| github.com/metacubex/utls | v1.8.8 | BSD-3-Clause |
| github.com/metacubex/wazero | v0.0.0-20260628025728-9ae6bdcf2a7d | Apache-2.0 |
| github.com/metacubex/wireguard-go | v0.0.0-20250820062549-a6cecdd7f57f | MIT |
| github.com/metacubex/yamux | v0.0.0-20250918083631-dd5f17c0be49 | MPL-2.0 AND BSD-3-Clause |
| github.com/metacubex/zerotier-go | v0.0.0-20260813124750-13fa6f45da5f | MPL-2.0 |
| github.com/miekg/dns | v1.1.63 | BSD-3-Clause |
| github.com/mroth/weightedrand/v2 | v2.1.0 | MIT |
| github.com/oasisprotocol/deoxysii | v0.0.0-20220228165953-2091330c22b7 | MIT |
| github.com/openacid/low | v0.1.21 | MIT |
| github.com/oschwald/maxminddb-golang | v1.12.0 | ISC |
| github.com/pierrec/lz4/v4 | v4.1.27 | BSD-3-Clause |
| github.com/pires/go-proxyproto | v0.8.0 | Apache-2.0 |
| github.com/rasky/go-lzo | v0.0.0-20200203143853-96a758eda86e | GPL-2.0 |
| github.com/sagernet/netlink | v0.0.0-20240612041022-b9a21c07ac6a | Apache-2.0 |
| github.com/samber/lo | v1.53.0 | MIT |
| github.com/sina-ghaderi/poly1305 | v0.0.0-20220724002748-c5926b03988b | GPL-3.0 |
| github.com/sina-ghaderi/rabaead | v0.0.0-20220730151906-ab6e06b96e8c | GPL-3.0 |
| github.com/sina-ghaderi/rabbitio | v0.0.0-20220730151941-9ce26f4f872e | Apache-2.0 |
| github.com/sirupsen/logrus | v1.9.4 | MIT |
| github.com/stangelandcl/ppmd | v0.1.1 | MIT |
| github.com/tailscale/peercred | v0.0.0-20250107143737-35a0c7bd7edc | BSD-3-Clause |
| github.com/u-root/uio | v0.0.0-20230220225925-ffce2a382923 | BSD-3-Clause |
| github.com/ulikunitz/xz | v0.5.15 | BSD-2-Clause |
| github.com/vishvananda/netns | v0.0.5 | Apache-2.0 |
| github.com/vmihailenco/msgpack/v5 | v5.4.1 | BSD-2-Clause |
| github.com/vmihailenco/tagparser/v2 | v2.0.0 | BSD-2-Clause |
| github.com/x448/float16 | v0.8.4 | MIT |
| github.com/yosida95/uritemplate/v3 | v3.0.2 | BSD-3-Clause |
| gitlab.com/go-extension/aes-ccm | v0.0.0-20230221065045-e58665ef23c7 | MIT |
| gitlab.com/yawning/bsaes.git | v0.0.0-20190805113838-0a714cd429ec | MIT |
| go.yaml.in/yaml/v3 | v3.0.5 | Apache-2.0 |
| go4.org/mem | v0.0.0-20240501181205-ae6ca9944745 | Apache-2.0 |
| go4.org/netipx | v0.0.0-20260823151212-3075585bcbeb | BSD-3-Clause |
| golang.org/x/crypto | v0.33.0 | BSD-3-Clause |
| golang.org/x/exp | v0.0.0-20240904232852-e7e105dedf7e | BSD-3-Clause |
| golang.org/x/net | v0.35.0 | BSD-3-Clause |
| golang.org/x/sync | v0.11.0 | BSD-3-Clause |
| golang.org/x/sys | v0.30.0 | BSD-3-Clause |
| golang.org/x/term | v0.29.0 | BSD-3-Clause |
| golang.org/x/text | v0.22.0 | BSD-3-Clause |
| golang.org/x/time | v0.10.0 | BSD-3-Clause |
| google.golang.org/protobuf | v1.34.2 | BSD-3-Clause |
