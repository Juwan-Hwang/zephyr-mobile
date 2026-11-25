# 内核地理数据（geoip.metadb / GeoSite.dat）

> 归属：A。契约见 `contract/zephyr-engine.md` §20。

## 为什么要管
mihomo 解析带 `GEOIP` / `GEOSITE` 的配置时读内核目录（`zm_start` 的 `home_dir`）里的地理数据，没有就去 `geox-url` 下载（mihomo 内部超时 90 秒）。大陆网络在 VPN 起来前多半连不上 GitHub，表现为点「连接」后约 90 秒失败：`rules[…] [GEOIP,cn,…] error: can't download MMDB … context deadline exceeded`。

现在 mihomo-mobile 在解析前先检查，缺了只在 15 秒内（`zm_set_geodata_timeout` 可改）尝试下载，失败立即返回以 `geodata missing:` 开头的清楚错误；`runtimeConfig` 也把默认下载地址换成了国内可达的 jsDelivr 镜像。但**最稳的是随安装包带上**，启动完全不依赖网络。

## 拉取固定快照
```sh
tools/fetch-geodata.sh [输出目录]   # 默认 build/geodata/
```
得到 `geoip.metadb`（约 8.4 MB）与 `GeoSite.dat`（约 4.4 MB），按 `tools/geodata.lock` 的 sha256 校验。快照转存在本仓库 Release `geodata-20261124`（来源 MetaCubeX/meta-rules-dat，GPL-3.0；geoip 数据含 GeoLite2 等来源，见上游说明），地址不会因上游每日更新而失效。CI（`core` 任务）每次都会拉一遍并用它跑「真实数据 + 下载源不可达」的启动测试，同时上传为 artifact `geodata`。

更新快照：`tools/fetch-geodata.sh --update` 打印上游最新哈希 → 下载文件传到新的 `geodata-YYYYMMDD` Release → 改 `tools/geodata.lock`。

## 平台接入（各端负责人做，A 只提供文件与接口）
| 端 | 打包 | 首次启动 / 升级后 | 每次 zm_start 前 |
|---|---|---|---|
| Android（C） | 构建前跑 `tools/fetch-geodata.sh app/src/main/assets/geodata`（或 Gradle 任务调用；目录不入库） | `filesDir/mihomo/` 里没有同名文件就从 `assets/geodata/` 拷入（先写临时名再改名） | `core.seedKernelGeodata(filesDir/mihomo)` |
| iOS（B） | 同上拉到 bundle 资源 | 拷进扩展用的内核目录（App Group 下 `zm_start` 的 home） | 同左 |
| 鸿蒙（D） | 拉到 `resources/rawfile/geodata` | 拷进内核目录 | 同左 |

- 只想要更小的包：可以只带 `GeoSite.dat`，`geoip.metadb` 留给首次启动有界下载（镜像可达时几秒）；或订阅设 `geodata-mode: true` 改用核心已有的 `geoip.dat`（由 `seedKernelGeodata` 拷入）。
- 拷文件不要覆盖内核目录里已有的（mihomo 的 `geo-auto-update` 可能已经更新过）。
- `zm_start` 返回 `geodata missing:` 时把错误原文写进日志、首页显示错误详情，不要立刻自动重连（同一配置会再失败一次）。
- iOS NE 内存：默认模式的 `geoip.metadb` 是 mmap，不进 Go 堆；`GeoSite.dat` 只按用到的分类加载。

## 自测
```sh
cd mihomo-mobile
go test -tags with_gvisor -run Geodata -v .                          # 合成数据：有文件不联网秒启；缺文件 2 s 内报错；时限 0 立即报错
ZM_GEODATA_DIR=../build/geodata go test -tags with_gvisor -run GeodataRealSnapshot -v .   # 真实快照 + 黑洞 geox-url
```
