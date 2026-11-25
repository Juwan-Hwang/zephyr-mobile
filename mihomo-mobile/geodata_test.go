package main

import (
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/geodata/router"
	"github.com/metacubex/mihomo/config"
	"google.golang.org/protobuf/proto"
)

func geositeDat(t *testing.T) []byte {
	b, err := proto.Marshal(&router.GeoSiteList{Entry: []*router.GeoSite{
		{CountryCode: "CN", Domain: []*router.Domain{{Type: router.Domain_Domain, Value: "qq.com"}}},
	}})
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func geoipDat(t *testing.T) []byte {
	b, err := proto.Marshal(&router.GeoIPList{Entry: []*router.GeoIP{
		{CountryCode: "CN", Cidr: []*router.CIDR{{Ip: []byte{223, 5, 5, 0}, Prefix: 24}}},
	}})
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// blackhole：接受连接但永远不回，模拟大陆 VPN 起来之前连 GitHub 的样子（连得上、等不到数据）。
func blackhole(t *testing.T) string {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	var conns []net.Conn
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			conns = append(conns, c)
		}
	}()
	t.Cleanup(func() {
		ln.Close()
		for _, c := range conns {
			c.Close()
		}
	})
	return "http://" + ln.Addr().String()
}

func geoCfg(geodataMode bool, host string) string {
	return "mode: rule\nlog-level: warning\n" +
		"geodata-mode: " + map[bool]string{true: "true", false: "false"}[geodataMode] + "\n" +
		"geox-url:\n  geoip: " + host + "/geoip.dat\n  mmdb: " + host + "/geoip.metadb\n  geosite: " + host + "/geosite.dat\n  asn: " + host + "/asn.mmdb\n" +
		"rules:\n  - GEOSITE,CN,DIRECT\n  - GEOIP,CN,DIRECT,no-resolve\n  - GEOIP,LAN,DIRECT\n  - MATCH,DIRECT\n"
}

// 地理数据已在内核目录、geox-url 不可达：解析直接成功，不联网、不等待。
func TestGeodataPresentNoNetwork(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "GeoSite.dat"), geositeDat(t), 0o644)
	os.WriteFile(filepath.Join(dir, "GeoIP.dat"), geoipDat(t), 0o644)
	t0 := time.Now()
	if err := start(dir, geoCfg(true, blackhole(t)), ""); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer stop()
	if d := time.Since(t0); d > 5*time.Second {
		t.Fatalf("start took %v with geodata present", d)
	}
}

// 缺地理数据、下载源只连得上不回数据：在设定时限内报清楚的错，而不是 mihomo 自带的 90 秒。
func TestGeodataMissingFailsFast(t *testing.T) {
	zm_set_geodata_timeout(2000)
	defer zm_set_geodata_timeout(-1)
	host := blackhole(t)
	for _, mode := range []bool{false, true} {
		dir := t.TempDir()
		t0 := time.Now()
		err := start(dir, geoCfg(mode, host), "")
		d := time.Since(t0)
		if err == nil {
			stop()
			t.Fatalf("geodata-mode=%v: start succeeded without geodata", mode)
		}
		if d > 6*time.Second {
			t.Fatalf("geodata-mode=%v: took %v, want ≤ ~2s", mode, d)
		}
		msg := err.Error()
		want := "geoip.metadb"
		if mode {
			want = "GeoIP.dat"
		}
		for _, s := range []string{"geodata missing", want, "GeoSite.dat", host} {
			if !strings.Contains(msg, s) {
				t.Fatalf("geodata-mode=%v: error %q lacks %q", mode, msg, s)
			}
		}
		t.Logf("geodata-mode=%v: failed in %v: %s", mode, d.Round(time.Millisecond), msg)
	}
}

// 时限 0：不下载，缺了立即报错。
func TestGeodataOfflineOnly(t *testing.T) {
	zm_set_geodata_timeout(0)
	defer zm_set_geodata_timeout(-1)
	t0 := time.Now()
	err := start(t.TempDir(), geoCfg(true, blackhole(t)), "")
	if err == nil {
		stop()
		t.Fatal("want error")
	}
	if d := time.Since(t0); d > time.Second || !strings.Contains(err.Error(), "zm_set_geodata_timeout=0") {
		t.Fatalf("%v %v", d, err)
	}
}

// 缺文件但 geox-url 可达：有界下载后正常启动，文件落在内核目录。
func TestGeodataDownloadsWhenReachable(t *testing.T) {
	gs, gi := geositeDat(t), geoipDat(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/geosite.dat":
			w.Write(gs)
		case "/geoip.dat":
			w.Write(gi)
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()
	dir := t.TempDir()
	if err := start(dir, geoCfg(true, srv.URL), ""); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer stop()
	for _, f := range []string{"GeoSite.dat", "GeoIP.dat"} {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			t.Fatal(err)
		}
	}
}

func TestGeodataNeeds(t *testing.T) {
	cases := []struct {
		cfg                 string
		geoip, geosite, asn bool
	}{
		{"rules: [MATCH,DIRECT]", false, false, false},
		{"rules: ['GEOIP,LAN,DIRECT', 'GEOIP,lan,DIRECT,no-resolve']", false, false, false},
		{"rules: ['GEOIP,CN,DIRECT']", true, false, false},
		{"rules: ['SRC-GEOIP,cn,DIRECT']", true, false, false},
		{"rules: ['AND,((NETWORK,UDP),(GEOSITE,youtube)),REJECT']", false, true, false},
		{"rules: ['IP-ASN,13335,DIRECT']", false, false, true},
		{"rules: ['DOMAIN-SUFFIX,geoip.example,DIRECT', 'DOMAIN-KEYWORD,geosite,DIRECT']", false, false, false},
		{"sub-rules: {s: ['GEOSITE,cn,DIRECT']}\nrules: ['SUB-RULE,(NETWORK,tcp),s']", false, true, false},
		{"dns: {enable: true, nameserver: [223.5.5.5], nameserver-policy: {'geosite:cn,private': 223.5.5.5}}", false, true, false},
		{"dns: {enable: true, nameserver: [223.5.5.5], fallback: [8.8.8.8]}", true, false, false},
		{"dns: {enable: true, nameserver: [223.5.5.5], fallback: [8.8.8.8], fallback-filter: {geoip: false}}", false, false, false},
		{"dns: {enable: false, nameserver: [223.5.5.5], fallback: [8.8.8.8]}", false, false, false},
	}
	for _, c := range cases {
		raw, err := config.UnmarshalRawConfig([]byte(c.cfg))
		if err != nil {
			t.Fatalf("%s: %v", c.cfg, err)
		}
		gi, gs, asn := geodataNeeds(raw)
		if gi != c.geoip || gs != c.geosite || asn != c.asn {
			t.Errorf("%s: got geoip=%v geosite=%v asn=%v", c.cfg, gi, gs, asn)
		}
	}
}

// CI：tools/fetch-geodata.sh 拉下的真实快照（ZM_GEODATA_DIR）拷进内核目录、geox-url 指向黑洞，
// 默认（MMDB）模式下 GEOIP + GEOSITE 规则照样秒级启动。
func TestGeodataRealSnapshotNoNetwork(t *testing.T) {
	src := os.Getenv("ZM_GEODATA_DIR")
	if src == "" {
		t.Skip("ZM_GEODATA_DIR 未设置")
	}
	dir := t.TempDir()
	for _, f := range []string{"geoip.metadb", "GeoSite.dat"} {
		b, err := os.ReadFile(filepath.Join(src, f))
		if err != nil {
			t.Fatal(err)
		}
		os.WriteFile(filepath.Join(dir, f), b, 0o644)
	}
	t0 := time.Now()
	if err := start(dir, geoCfg(false, blackhole(t)), ""); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer stop()
	if d := time.Since(t0); d > 10*time.Second {
		t.Fatalf("start took %v", d)
	}
	t.Logf("real snapshot start took %v", time.Since(t0))
}
