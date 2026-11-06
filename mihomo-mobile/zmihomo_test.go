package main

import (
	"context"
	"io"
	"net"
	"net/http"
	"strings"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// 冒烟：嵌入式启动 mihomo（混合端口 + unix 控制器），能连上端口与控制器，再干净停止。
func TestStartStop(t *testing.T) {
	dir := t.TempDir()
	sock := filepath.Join(dir, "ctl.sock")
	cfg := "mixed-port: 17890\nmode: rule\nlog-level: warning\nrules:\n  - MATCH,DIRECT\n"
	if err := start(dir, cfg, sock); err != nil {
		t.Fatal(err)
	}
	defer stop()
	deadline := time.Now().Add(5 * time.Second)
	for {
		c, err := net.Dial("tcp", "127.0.0.1:17890")
		if err == nil {
			c.Close()
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("mixed port not listening: %v", err)
		}
		time.Sleep(50 * time.Millisecond)
	}
	for {
		if _, err := os.Stat(sock); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("controller socket missing")
		}
		time.Sleep(50 * time.Millisecond)
	}
	// REST over unix socket：core-mobile 的 MihomoClient 走的就是这条路
	cl := &http.Client{Transport: &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return net.Dial("unix", sock)
	}}}
	for _, path := range []string{"/version", "/proxies", "/connections"} {
		resp, err := cl.Get("http://mihomo" + path)
		if err != nil {
			t.Fatalf("%s: %v", path, err)
		}
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 || !strings.HasPrefix(strings.TrimSpace(string(b)), "{") {
			t.Fatalf("%s: %d %s", path, resp.StatusCode, b)
		}
	}
	if err := reload(cfg); err != nil {
		t.Fatal(err)
	}
	stop()
	if running {
		t.Fatal("still running")
	}
}
