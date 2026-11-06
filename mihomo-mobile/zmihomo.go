// Package main 把 mihomo 以库的形式嵌入移动端（iOS NetworkExtension / Android VpnService 进程内），禁止起子进程。
//
// C ABI（cgo，iOS 用 c-archive、Android 用 c-shared）：
//
//	char*   zm_start(const char* home_dir, const char* config_yaml, const char* controller_unix)  // NULL=成功，否则错误串（调用方 zm_free）
//	char*   zm_reload(const char* config_yaml)
//	void    zm_stop(void)
//	int     zm_running(void)
//	void    zm_traffic(int64_t* up_bps, int64_t* down_bps, int64_t* up_total, int64_t* down_total)
//	int64_t zm_memory(void)                         // mihomo 自报内存（字节）
//	void    zm_set_memory_limit(int64_t bytes)      // Go 软上限；iOS NE 约 50 MB 预算，建议 30 MB
//	void    zm_free_os_memory(void)                 // 内存告警时调用
//	char*   zm_version(void)
//	void    zm_free(char*)
//
// 策略组、延迟测试、连接、日志：走 mihomo 自带 REST（external-controller-unix，App Group/私有目录下的 unix socket），
// 不在此重复实现；CoreEngine 把 REST 映射到 contract/zephyr-engine.md 的接口。
// tun：平台层建好 tun 后，用 zephyr-core 的 inject_tun_fd 把 fd 写进配置再 zm_start / zm_reload。
package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"runtime/debug"
	"sync"
	"unsafe"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var (
	mu      sync.Mutex
	running bool
)

func cerr(err error) *C.char {
	if err == nil {
		return nil
	}
	return C.CString(err.Error())
}

func start(homeDir, cfg, unix string) error {
	mu.Lock()
	defer mu.Unlock()
	if running {
		executor.Shutdown()
		running = false
	}
	if homeDir != "" {
		constant.SetHomeDir(homeDir)
	}
	var opts []hub.Option
	if unix != "" {
		opts = append(opts, hub.WithExternalControllerUnix(unix))
	}
	if err := hub.Parse([]byte(cfg), opts...); err != nil {
		return err
	}
	running = true
	return nil
}

func reload(cfg string) error {
	mu.Lock()
	defer mu.Unlock()
	c, err := executor.ParseWithBytes([]byte(cfg))
	if err != nil {
		return err
	}
	hub.ApplyConfig(c)
	running = true
	return nil
}

func stop() {
	mu.Lock()
	defer mu.Unlock()
	if running {
		executor.Shutdown()
		running = false
	}
}

//export zm_start
func zm_start(homeDir, cfg, ctlSock *C.char) *C.char {
	return cerr(start(C.GoString(homeDir), C.GoString(cfg), C.GoString(ctlSock)))
}

//export zm_reload
func zm_reload(cfg *C.char) *C.char { return cerr(reload(C.GoString(cfg))) }

//export zm_stop
func zm_stop() { stop() }

//export zm_running
func zm_running() C.int {
	mu.Lock()
	defer mu.Unlock()
	if running {
		return 1
	}
	return 0
}

//export zm_traffic
func zm_traffic(upBps, downBps, upTotal, downTotal *C.int64_t) {
	u, d := statistic.DefaultManager.Now()
	tu, td := statistic.DefaultManager.Total()
	if upBps != nil {
		*upBps = C.int64_t(u)
	}
	if downBps != nil {
		*downBps = C.int64_t(d)
	}
	if upTotal != nil {
		*upTotal = C.int64_t(tu)
	}
	if downTotal != nil {
		*downTotal = C.int64_t(td)
	}
}

//export zm_memory
func zm_memory() C.int64_t { return C.int64_t(statistic.DefaultManager.Memory()) }

//export zm_set_memory_limit
func zm_set_memory_limit(bytes C.int64_t) {
	debug.SetMemoryLimit(int64(bytes))
	debug.SetGCPercent(50)
}

//export zm_free_os_memory
func zm_free_os_memory() { debug.FreeOSMemory() }

//export zm_version
func zm_version() *C.char { return C.CString("mihomo " + constant.Version) }

//export zm_free
func zm_free(p *C.char) { C.free(unsafe.Pointer(p)) }

func main() {}
