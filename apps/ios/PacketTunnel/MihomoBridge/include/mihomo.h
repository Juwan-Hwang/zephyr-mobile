// mihomo.h —— libmihomo（mihomo/Clash Meta 以 c-archive 嵌入）的 C ABI。
//
// 由 A 的 core-mobile 构建脚本产出：Mihomo.xcframework（静态库 libmihomo.a + 本头文件），
// `go build -buildmode=c-archive`，GOOS=ios，arm64 真机 + arm64/x86_64 模拟器两个切片。
// PacketTunnel 只通过 MihomoBridge.swift 调用这些函数；未链接时（未定义 MIHOMO_LINKED）用 Swift 桩实现。
//
// 约定：
//   - 所有函数线程安全，可在任意线程调用；不回调 Swift。
//   - 字符串参数为 UTF-8，以 NUL 结尾，调用期间有效；库内部自行拷贝。
//   - 返回的 const char* 由库持有（线程局部缓冲），调用方不得 free，下一次调用前有效。
//   - 内存：NE 进程上限约 50 MB。mihomo 端必须用 mmap 读取编译后的规则/GeoIP，避免整份载入 Go 堆。

#ifndef ZEPHYR_MIHOMO_H
#define ZEPHYR_MIHOMO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 累计/实时流量。速率单位 字节/秒，累计单位 字节。
typedef struct {
    int64_t up;          ///< 上行速率
    int64_t down;        ///< 下行速率
    int64_t up_total;    ///< 本次启动以来上行总量
    int64_t down_total;  ///< 本次启动以来下行总量
} mihomo_traffic_t;

/// 启动核心。config_path：mihomo YAML 配置的绝对路径，其所在目录即 home dir（缓存、规则集）。
/// tun_fd：NEPacketTunnelFlow 底层 utun 的文件描述符；核心接管读写，不关闭。
/// 返回 0 成功；非 0 为错误码，详情见 mihomo_last_error()。
int32_t mihomo_start(const char *config_path, int32_t tun_fd);

/// 停止核心并释放资源。未启动时为空操作。
void mihomo_stop(void);

/// 当前流量。未启动时全 0。
mihomo_traffic_t mihomo_traffic(void);

/// 热重载配置（订阅更新后）。返回 0 成功。
int32_t mihomo_reload(const char *config_path);

/// 切换模式："rule" | "global" | "direct"。返回 0 成功。
int32_t mihomo_set_mode(const char *mode);

/// Go 运行时软内存上限（debug.SetMemoryLimit），字节。NE 内存预算见 ZephyrPacketTunnelProvider。
void mihomo_set_memory_limit(int64_t bytes);

/// 立即归还空闲内存给系统（debug.FreeOSMemory）。收到内存压力时调用。
void mihomo_free_os_memory(void);

/// 最近一次错误的描述（UTF-8），无错误时返回空字符串。
const char *mihomo_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* ZEPHYR_MIHOMO_H */
