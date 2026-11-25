package main

// 地理数据（GEOIP / GEOSITE / IP-ASN 规则要用的 geoip.metadb、GeoIP.dat、GeoSite.dat、ASN.mmdb）预检。
//
// mihomo 在解析规则时发现 home 目录里没有对应文件，会从 geox-url 现场下载，超时写死 90 秒
// （component/geodata/init.go downloadToPath）。在中国大陆 VPN 起来之前 GitHub 往往连不上，
// zm_start 就会卡 90 秒后报 "can't download MMDB ... context deadline exceeded"。
//
// 这里在 hub.Parse / ParseWithBytes 之前先算出配置真正要用到哪些文件：
//   - 文件在且有效 → 什么都不做，mihomo 直接读本地文件，不联网；
//   - 缺失或损坏 → 用有界超时（默认 15 秒，zm_set_geodata_timeout 可改；0 = 只用本地文件、不下载）
//     从配置里的 geox-url 下载到临时文件、校验后再改名；
//   - 仍然拿不到 → 立刻返回清楚的错误（哪个文件、哪类规则要用、home 目录、下载地址、原因），
//     不再进入 mihomo 的 90 秒下载。
//
// 平台层的推荐做法：把 tools/fetch-geodata.sh 产出的 geoip.metadb / GeoSite.dat 打进安装包，
// 首次启动时拷进 zm_start 的 home_dir（见 docs/geodata.md）。

/*
#include <stdint.h>
*/
import "C"

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
)

const defaultGeodataTimeout = 15 * time.Second

var geodataTimeoutNs atomic.Int64

func init() { geodataTimeoutNs.Store(int64(defaultGeodataTimeout)) }

func geodataTimeout() time.Duration { return time.Duration(geodataTimeoutNs.Load()) }

// zm_set_geodata_timeout：缺地理数据时，启动前下载的总超时（毫秒）。<0 恢复默认 15000；0 = 不下载，缺了直接报错。
//
//export zm_set_geodata_timeout
func zm_set_geodata_timeout(ms C.int64_t) {
	if ms < 0 {
		geodataTimeoutNs.Store(int64(defaultGeodataTimeout))
		return
	}
	geodataTimeoutNs.Store(int64(time.Duration(ms) * time.Millisecond))
}

type geoFile struct {
	name   string // 文件名（mihomo 约定）
	path   string // home 下的实际路径
	url    string // 下载地址（geox-url）
	usedBy string // 哪类规则要它（错误信息用）
	valid  func() error
}

var (
	reGeoIP   = regexp.MustCompile(`(?i)(?:^|\()\s*(?:SRC-)?GEOIP\s*,\s*([^,)\s]+)`)
	reGeoSite = regexp.MustCompile(`(?i)(?:^|\()\s*GEOSITE\s*,`)
	reASN     = regexp.MustCompile(`(?i)(?:^|\()\s*(?:SRC-)?IP-ASN\s*,`)
)

// geodataNeeds：配置在解析阶段会触发哪些地理数据加载（与 mihomo rules/common NewGEOIP / NewGEOSITE / NewIPASN 的调用点对应）。
// rule-provider 里的规则是解析后异步加载的，不会阻塞启动，这里不管。
func geodataNeeds(raw *config.RawConfig) (geoip, geosite, asn bool) {
	scan := func(rule string) {
		for _, m := range reGeoIP.FindAllStringSubmatch(rule, -1) {
			if !strings.EqualFold(m[1], "lan") { // GEOIP,LAN 是伪规则，不读文件
				geoip = true
			}
		}
		if reGeoSite.MatchString(rule) {
			geosite = true
		}
		if reASN.MatchString(rule) {
			asn = true
		}
	}
	for _, r := range raw.Rule {
		scan(r)
	}
	for _, rs := range raw.SubRules {
		for _, r := range rs {
			scan(r)
		}
	}
	d := raw.DNS
	if d.Enable {
		if d.NameServerPolicy != nil {
			for pair := d.NameServerPolicy.Oldest(); pair != nil; pair = pair.Next() {
				for _, k := range strings.Split(pair.Key, ",") {
					if strings.HasPrefix(strings.TrimSpace(k), "geosite:") {
						geosite = true
					}
				}
			}
		}
		if d.ProxyServerNameserverPolicy != nil {
			for pair := d.ProxyServerNameserverPolicy.Oldest(); pair != nil; pair = pair.Next() {
				for _, k := range strings.Split(pair.Key, ",") {
					if strings.HasPrefix(strings.TrimSpace(k), "geosite:") {
						geosite = true
					}
				}
			}
		}
		if len(d.Fallback) > 0 {
			if d.FallbackFilter.GeoIP && !strings.EqualFold(d.FallbackFilter.GeoIPCode, "lan") {
				geoip = true
			}
			if len(d.FallbackFilter.GeoSite) > 0 {
				geosite = true
			}
		}
	}
	return
}

func requiredGeodata(raw *config.RawConfig) []geoFile {
	geoip, geosite, asn := geodataNeeds(raw)
	var out []geoFile
	if geoip {
		if raw.GeodataMode {
			out = append(out, geoFile{name: constant.GeoipName, path: constant.Path.GeoIP(), url: raw.GeoXUrl.GeoIp, usedBy: "GEOIP（geodata-mode）",
				valid: func() error { return datValid(constant.GeoipName, geodata.ClearGeoIPCache) }})
		} else {
			out = append(out, geoFile{name: "geoip.metadb", path: constant.Path.MMDB(), url: raw.GeoXUrl.Mmdb, usedBy: "GEOIP",
				valid: func() error { return mmdbValid(constant.Path.MMDB()) }})
		}
	}
	if geosite {
		out = append(out, geoFile{name: constant.GeositeName, path: constant.Path.GeoSite(), url: raw.GeoXUrl.GeoSite, usedBy: "GEOSITE",
			valid: func() error { return datValid(constant.GeositeName, geodata.ClearGeoSiteCache) }})
	}
	if asn {
		out = append(out, geoFile{name: "ASN.mmdb", path: constant.Path.ASN(), url: raw.GeoXUrl.ASN, usedBy: "IP-ASN",
			valid: func() error { return mmdbValid(constant.Path.ASN()) }})
	}
	return out
}

// datValid：mihomo 的 matcher 加载结果（含错误）会被 singleflight 缓存；失败时清掉，免得换了文件还拿旧错误。
func datValid(name string, clear func()) error {
	err := geodata.Verify(name)
	if err != nil {
		clear()
	}
	return err
}

func mmdbValid(path string) error {
	if !mmdb.Verify(path) {
		return errors.New("not a valid MMDB")
	}
	return nil
}

// ensureGeodata：在 mihomo 解析之前保证配置要用的地理数据都在 home 目录里；做不到就在有界时间内报错。
func ensureGeodata(cfg []byte) error {
	raw, err := config.UnmarshalRawConfig(cfg)
	if err != nil {
		return nil // 配置本身有问题，交给 mihomo 报它自己的错
	}
	need := requiredGeodata(raw)
	if len(need) == 0 {
		return nil
	}
	if raw.GeodataLoader != "" {
		geodata.SetLoader(raw.GeodataLoader)
	}
	deadline := time.Now().Add(geodataTimeout())
	var errs []string
	for _, f := range need {
		if _, err := os.Stat(f.path); err == nil {
			if verr := f.valid(); verr == nil {
				continue
			} else {
				_ = os.Remove(f.path) // 损坏：mihomo 也会删掉重下，这里换成有界的下载
				if derr := fetchGeodata(f, deadline); derr != nil {
					errs = append(errs, fmt.Sprintf("%s（%s 规则要用）已损坏（%v），重新下载 %s 失败：%v", f.name, f.usedBy, verr, f.url, derr))
				}
				continue
			}
		}
		if derr := fetchGeodata(f, deadline); derr != nil {
			errs = append(errs, fmt.Sprintf("%s（%s 规则要用）不在 %s，下载 %s 失败：%v", f.name, f.usedBy, filepath.Dir(f.path), f.url, derr))
		}
	}
	if len(errs) > 0 {
		return fmt.Errorf("geodata missing: %s；请把地理数据随安装包拷进内核目录，或换可访问的 geox-url（docs/geodata.md）", strings.Join(errs, "；"))
	}
	return nil
}

func fetchGeodata(f geoFile, deadline time.Time) error {
	if geodataTimeout() <= 0 {
		return errors.New("已关闭启动时下载（zm_set_geodata_timeout=0）")
	}
	if f.url == "" {
		return errors.New("geox-url 为空")
	}
	if time.Now().After(deadline) {
		return fmt.Errorf("超过 %v 时限", geodataTimeout())
	}
	ctx, cancel := context.WithDeadline(context.Background(), deadline)
	defer cancel()
	nd := &net.Dialer{Control: func(network, address string, c syscall.RawConn) error {
		// 复用 zm_set_socket_hook（Android protect / 鸿蒙防回环），VPN 已起时 reload 下载也不会绕回 tun
		if h := dialer.DefaultSocketHook; h != nil {
			return h(network, address, c)
		}
		return nil
	}}
	cl := &http.Client{Transport: &http.Transport{DialContext: nd.DialContext, Proxy: nil, ForceAttemptHTTP2: true}}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, f.url, nil)
	if err != nil {
		return err
	}
	resp, err := cl.Do(req)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) || ctx.Err() != nil {
			return fmt.Errorf("%v 内未完成（%v）", geodataTimeout(), err)
		}
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	if err := os.MkdirAll(filepath.Dir(f.path), 0o755); err != nil {
		return err
	}
	tmp := f.path + ".zm-tmp"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	_, err = io.Copy(out, resp.Body)
	if cerr := out.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(tmp)
		if ctx.Err() != nil {
			return fmt.Errorf("%v 内未完成（%v）", geodataTimeout(), err)
		}
		return err
	}
	if err := os.Rename(tmp, f.path); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := f.valid(); err != nil {
		os.Remove(f.path)
		return fmt.Errorf("下载内容无效：%v", err)
	}
	return nil
}
