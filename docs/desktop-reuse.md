# 桌面 zephyr-core 复用记录

原则（用户 2026-11-06 决定）：与桌面端重叠的一律复用，桌面端没有的才自写。vendor/zephyr 只读。

| 功能 | 状态 | 说明 |
|---|---|---|
| 订阅正文规整 | 复用 | try_decode_base64_content → quote_short_id_values → remove_control_plane_keys |
| 订阅 URL / 名称校验 | 复用 | validate_subscription_url_basic、validate_subscription_name |
| URL 脱敏 | 复用 | merge::mask_url |
| 节点优选打分 | 复用 | smart_selector::compute_smart_rank |
| 配置合并与控制面钉死 | 复用 | merge_yaml、restore_security_settings |
| TUN dns-hijack | 复用 | tun::ensure_dns_hijack_entries（UDP + TCP 53） |
| TUN fd 注入 | **不复用** | 桌面 inject_tun_fd 写的是 `tun.fd`，mihomo v1.19.33 只认 `file-descriptor`（config/config.go:319），且它打开 auto-route；移动端路由由 VpnService / NEPacketTunnelProvider 设置，auto-route 必须关 |
| SSRF / DNS 校验、拉取 | 平台层 | validate_public_host_addrs*、fetch_util 依赖桌面网络栈；iOS/Android 在 Swift/Kotlin 拉取前做 |
| updater、process | 不适用 | 桌面二进制下载、子进程（iOS 禁止） |
| 节点库、规则引擎、延迟缓存、场景、覆写、MihomoClient、订阅存储与差异 | 自写 | 桌面端没有千万级或移动端对应实现 |
