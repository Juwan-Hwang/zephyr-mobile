//! 规模基准：cargo run --release --example scale -- [scale] [rules_millions]
//! 输出建库耗时、文件大小、查询/分页/规则测试延迟、常驻内存。
use std::time::Instant;
use zephyr_mobile_core::rules::{LayerBuilder, LayerKind, Rule};
use zephyr_mobile_core::MobileCore;

fn rss_mb() -> f64 {
    std::fs::read_to_string("/proc/self/status").ok().and_then(|s| s.lines().find(|l| l.starts_with("VmRSS")).and_then(|l| l.split_whitespace().nth(1)?.parse::<f64>().ok())).unwrap_or(0.0) / 1024.0
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let scale: f64 = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(1.0);
    let rules_m: f64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(10.0);
    let dir = std::env::temp_dir().join("zephyr-scale");
    let _ = std::fs::remove_dir_all(&dir);
    let core = MobileCore::new(dir.to_string_lossy().into()).unwrap();

    let rep = core.rebuild_mock_nodes(scale).unwrap();
    let size: u64 = std::fs::read_dir(&dir).unwrap().flatten().filter(|e| e.file_name().to_string_lossy().ends_with(".zn")).map(|e| e.metadata().unwrap().len()).sum();
    println!("nodes: {} built in {} ms, file {:.1} MB ({:.1} B/node)", rep.total, rep.took_millis, size as f64 / 1e6, size as f64 / rep.total as f64);
    drop(core);
    let core = MobileCore::new(dir.to_string_lossy().into()).unwrap();
    println!("rss after reopen: {:.1} MB", rss_mb());

    for q in ["", "jp", "东京", "东京 iplc", "us 家宽", "香港 hkt bgp", "tw hinet 原生", "cn2 gia", "美国 洛杉矶", "zzz"] {
        let t = Instant::now();
        let r = core.query_nodes(q.into()).unwrap();
        let qt = t.elapsed();
        let t = Instant::now();
        let mid = r.total / 2;
        let p = core.node_rows(r.token, mid, 60).unwrap();
        let pt = t.elapsed();
        println!("query {:>14} → {:>10} in {:>7.2} ms · page(60 @ mid) {:>6.2} ms · first: {}", format!("{q:?}"), r.total, qt.as_secs_f64() * 1e3, pt.as_secs_f64() * 1e3, p.rows.first().map(|x| x.name.as_str()).unwrap_or("-"));
    }
    println!("rss after queries: {:.1} MB", rss_mb());

    // 规则：rules_m 百万条域名后缀 + 10 万 CIDR
    let n = (rules_m * 1e6) as u64;
    let t = Instant::now();
    let mut b = LayerBuilder::new("广告与跟踪", LayerKind::Domain, "规则集", "REJECT");
    for i in 0..n {
        b.add(Rule::DomainSuffix(format!("d{i}.example{}.com", i % 1000)), None);
    }
    let p = dir.join("rules").join("003.zr");
    b.write(&p).unwrap();
    let mut b = LayerBuilder::new("geoip:cn", LayerKind::Ip, "规则集", "DIRECT");
    for i in 0..100_000u32 {
        b.add(Rule::IpCidr(i << 12, 20), None);
    }
    b.write(&dir.join("rules").join("006.zr")).unwrap();
    println!("rules compiled {} in {} ms, file {:.1} MB", n + 100_000, t.elapsed().as_millis(), std::fs::metadata(&p).unwrap().len() as f64 / 1e6);
    core.load_rules("other".into()).unwrap();
    for q in ["a.b.d12345.example345.com", "nothing.example.org", "0.1.2.3", "8.8.8.8", "2001:db8::1"] {
        let t = Instant::now();
        let r = core.test_rule(q.into()).unwrap();
        println!("rule {q:>28} → {:<32} {:<7} {:.1} µs", r.rule, r.policy, t.elapsed().as_secs_f64() * 1e6);
    }
    println!("rss end: {:.1} MB", rss_mb());
}
