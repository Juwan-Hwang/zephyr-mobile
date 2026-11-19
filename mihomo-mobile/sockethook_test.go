package main

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
)

// 钩子拒绝时出站拨号必须失败（fail-closed），放行时拿到有效 fd 且连接成功；卸载后恢复默认。
func TestSocketHook(t *testing.T) {
	ln, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			c.Close()
		}
	}()
	addr := ln.Addr().String()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	defer setSocketHook(nil)

	setSocketHook(func(fd int, network string) error { return errors.New("deny") })
	if c, err := dialer.DialContext(ctx, "tcp4", addr); err == nil {
		c.Close()
		t.Fatal("dial succeeded while hook rejects")
	}

	var calls atomic.Int32
	var gotNet atomic.Value
	setSocketHook(func(fd int, network string) error {
		if fd <= 0 {
			return errors.New("bad fd")
		}
		calls.Add(1)
		gotNet.Store(network)
		return nil
	})
	c, err := dialer.DialContext(ctx, "tcp4", addr)
	if err != nil {
		t.Fatalf("dial with accepting hook: %v", err)
	}
	c.Close()
	if calls.Load() == 0 || gotNet.Load() != "tcp4" {
		t.Fatalf("hook calls=%d network=%v", calls.Load(), gotNet.Load())
	}

	pc, err := dialer.ListenPacket(ctx, "udp4", "", netip.AddrPortFrom(netip.MustParseAddr("127.0.0.1"), 9))
	if err != nil {
		t.Fatalf("listen packet: %v", err)
	}
	pc.Close()
	if calls.Load() < 2 {
		t.Fatalf("udp listen did not go through hook, calls=%d", calls.Load())
	}

	// 卸载后放行：先装一个拒绝钩子再卸载，拨号必须成功且不再回调。
	setSocketHook(func(fd int, network string) error { return errors.New("deny") })
	setSocketHook(nil)
	if curHook.Load() != nil {
		t.Fatal("hook not cleared")
	}
	c, err = dialer.DialContext(ctx, "tcp4", addr)
	if err != nil {
		t.Fatalf("dial after uninstall: %v", err)
	}
	c.Close()
}

// 装卸与拨号并发时不得有数据竞争（-race 下跑）。
func TestSocketHookConcurrent(t *testing.T) {
	ln, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			c.Close()
		}
	}()
	defer setSocketHook(nil)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 200; i++ {
			if i%2 == 0 {
				setSocketHook(func(int, string) error { return nil })
			} else {
				setSocketHook(nil)
			}
		}
	}()
	for i := 0; i < 50; i++ {
		if c, err := dialer.DialContext(ctx, "tcp4", ln.Addr().String()); err == nil {
			c.Close()
		}
	}
	<-done
}
