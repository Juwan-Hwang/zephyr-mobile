package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter"
)

// 批量延迟测试（契约 §5 testLatency）：节点库有上千万条，不可能都放进运行配置，
// 所以由核心按需给出一批代理定义（name = 节点 id 的十六进制），这里临时构造出站并测 URL 延迟。
// 不依赖 zm_start：VPN 未连接时 App 可直接调用；连接时由扩展/VPN 进程调用，出站不进 TUN。

type urlTestResult struct {
	Name string `json:"name"`
	Ms   int    `json:"ms"` // -1 = 超时/失败
}

const maxURLTestBatch = 512

func urlTest(proxiesJSON string, url string, timeout time.Duration, concurrency int) ([]urlTestResult, error) {
	var defs []map[string]any
	if err := json.Unmarshal([]byte(proxiesJSON), &defs); err != nil {
		return nil, err
	}
	if len(defs) > maxURLTestBatch {
		return nil, errors.New("batch too large")
	}
	if url == "" {
		url = "https://www.gstatic.com/generate_204"
	}
	if concurrency <= 0 {
		concurrency = 16
	}
	if timeout <= 0 {
		timeout = 5 * time.Second
	}
	out := make([]urlTestResult, len(defs))
	sem := make(chan struct{}, concurrency)
	var wg sync.WaitGroup
	for i, d := range defs {
		name, _ := d["name"].(string)
		out[i] = urlTestResult{Name: name, Ms: -1}
		p, err := adapter.ParseProxy(d)
		if err != nil {
			continue
		}
		wg.Add(1)
		sem <- struct{}{}
		go func(i int) {
			defer wg.Done()
			defer func() { <-sem }()
			defer p.Close()
			ctx, cancel := context.WithTimeout(context.Background(), timeout)
			defer cancel()
			if ms, err := p.URLTest(ctx, url, nil); err == nil && ms > 0 {
				out[i].Ms = int(ms)
			}
		}(i)
	}
	wg.Wait()
	return out, nil
}

// char* zm_url_test(const char* proxies_json, const char* url, int timeout_ms, int concurrency)
// 返回 JSON：成功 {"results":[{"name","ms"}]}，失败 {"error":"..."}；调用方 zm_free。
//
//export zm_url_test
func zm_url_test(proxiesJSON *C.char, url *C.char, timeoutMs C.int, concurrency C.int) *C.char {
	res, err := urlTest(C.GoString(proxiesJSON), C.GoString(url), time.Duration(timeoutMs)*time.Millisecond, int(concurrency))
	var b []byte
	if err != nil {
		b, _ = json.Marshal(map[string]string{"error": err.Error()})
	} else {
		b, _ = json.Marshal(map[string]any{"results": res})
	}
	return C.CString(string(b))
}
