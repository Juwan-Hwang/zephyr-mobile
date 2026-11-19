package main

/*
#include <stdint.h>
#include <stdlib.h>

// 出站 socket 钩子：返回 0 放行，非 0 拒绝（fail-closed：该连接以错误结束，不会走默认路由）。
// fd 只在回调期间有效，回调方不得 close；network 为 "tcp4"/"tcp6"/"udp4"/"udp6" 等，回调结束后失效。
typedef int (*zm_socket_hook_fn)(void* ctx, int fd, const char* network);

static inline int zm_call_socket_hook(uintptr_t fn, uintptr_t ctx, int fd, const char* network) {
	return ((zm_socket_hook_fn)fn)((void*)ctx, fd, network);
}
*/
import "C"

import (
	"fmt"
	"sync"
	"sync/atomic"
	"syscall"
	"unsafe"

	"github.com/metacubex/mihomo/component/dialer"
)

// socketHook 是 Go 侧的钩子形态；C ABI 只是它的一层包装，便于单测。
type socketHook func(fd int, network string) error

var (
	hookMu        sync.Mutex
	hookInstalled bool
	curHook       atomic.Pointer[socketHook]
)

// setSocketHook 安装 / 卸载（nil）出站 socket 钩子。
// 装上后 mihomo 的所有出站拨号与出站 UDP（含 DNS、URL 测试、订阅经内核的请求）都会先回调，
// 且 mihomo 会忽略 interface-name / routing-mark（由钩子负责绑定物理网络，防止回环进 tun）。
//
// dialer.DefaultSocketHook 是 mihomo 拨号时无锁读取的包级变量，运行中改写它会与拨号竞争。
// 所以只在首次安装时写一次（之后不再改写），真正的钩子放在 atomic 指针里，装卸只换指针；
// 卸载后包装层直接放行。代价：进程内一旦装过，interface-name / routing-mark 就一直被忽略
// （只有鸿蒙会调用本接口，iOS / Android 不受影响）。
func setSocketHook(h socketHook) {
	if h == nil {
		curHook.Store(nil)
		return
	}
	curHook.Store(&h)
	hookMu.Lock()
	defer hookMu.Unlock()
	if hookInstalled {
		return
	}
	hookInstalled = true
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		hp := curHook.Load()
		if hp == nil {
			return nil
		}
		hook := *hp
		var herr error
		if err := conn.Control(func(fd uintptr) { herr = hook(int(fd), network) }); err != nil {
			return fmt.Errorf("socket hook: %w", err)
		}
		if herr != nil {
			return fmt.Errorf("socket hook rejected %s %s: %w", network, address, herr)
		}
		return nil
	}
}

//export zm_set_socket_hook
func zm_set_socket_hook(fn C.zm_socket_hook_fn, ctx unsafe.Pointer) {
	if fn == nil {
		setSocketHook(nil)
		return
	}
	f, c := uintptr(unsafe.Pointer(fn)), uintptr(ctx)
	setSocketHook(func(fd int, network string) error {
		cn := C.CString(network)
		defer C.free(unsafe.Pointer(cn))
		if rc := C.zm_call_socket_hook(C.uintptr_t(f), C.uintptr_t(c), C.int(fd), cn); rc != 0 {
			return fmt.Errorf("rc=%d", int(rc))
		}
		return nil
	})
}
