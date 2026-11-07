package main

/*
#include <stdint.h>
*/
import "C"

import (
	"encoding/json"
	"sync"
	"time"

	"github.com/metacubex/mihomo/log"
)

// 日志环形缓冲（契约 §8 logs）：mihomo 的 /logs 是长连接流，移动端（尤其 iOS 跨进程 provider message）
// 不便直连，所以在嵌入进程内订阅日志事件、保留最近 logRingCap 条，平台按序号增量拉取。

const logRingCap = 500

type logLine struct {
	Seq   uint64 `json:"seq"`
	Level string `json:"level"`
	Msg   string `json:"msg"`
	At    int64  `json:"at"` // 毫秒
}

var logs struct {
	sync.Mutex
	once sync.Once
	ring []logLine
	seq  uint64
}

func levelRank(s string) int {
	switch s {
	case "debug":
		return 0
	case "info":
		return 1
	case "warning":
		return 2
	case "error":
		return 3
	default:
		return 4
	}
}

func startLogCollector() {
	logs.once.Do(func() {
		sub := log.Subscribe()
		go func() {
			for ev := range sub {
				appendLog(ev.LogLevel.String(), ev.Payload, time.Now().UnixMilli())
			}
		}()
	})
}

func appendLog(level, msg string, at int64) {
	logs.Lock()
	defer logs.Unlock()
	logs.seq++
	if len(logs.ring) >= logRingCap {
		copy(logs.ring, logs.ring[1:])
		logs.ring = logs.ring[:logRingCap-1]
	}
	logs.ring = append(logs.ring, logLine{Seq: logs.seq, Level: level, Msg: msg, At: at})
}

// 序号 > since 且级别 ≥ minLevel 的行，最多 limit 条（取最新的）。
func logsSince(since uint64, minLevel string, limit int) (uint64, []logLine) {
	logs.Lock()
	defer logs.Unlock()
	min := levelRank(minLevel)
	out := []logLine{}
	for _, l := range logs.ring {
		if l.Seq > since && levelRank(l.Level) >= min {
			out = append(out, l)
		}
	}
	if limit > 0 && len(out) > limit {
		out = out[len(out)-limit:]
	}
	return logs.seq, out
}

// char* zm_logs(int64_t since, const char* min_level, int limit) → {"seq":最新序号,"lines":[{seq,level,msg,at}]}；调用方 zm_free。
//
//export zm_logs
func zm_logs(since C.int64_t, minLevel *C.char, limit C.int) *C.char {
	startLogCollector()
	seq, lines := logsSince(uint64(since), C.GoString(minLevel), int(limit))
	b, _ := json.Marshal(map[string]any{"seq": seq, "lines": lines})
	return C.CString(string(b))
}
