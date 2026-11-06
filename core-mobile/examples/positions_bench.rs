//! fastestNodes 首次的指纹→行号全表扫描耗时（1310 万节点）。
//! cargo run --release --example positions_bench -- <dir>
use std::time::Instant;
use zephyr_mobile_core::engine::MobileCore;
use zephyr_mobile_core::latency::LatencySample;

fn main() {
    let dir = std::env::args().nth(1).expect("dir");
    let core = MobileCore::new(dir).unwrap();
    let t = Instant::now();
    let r = core.rebuild_mock_nodes(1.0).unwrap();
    println!("build {} nodes {:?}", r.total, t.elapsed());
    let q = core.query_nodes(String::new()).unwrap();
    let total = q.total;
    let mut s = vec![];
    for k in 0..2000u64 {
        let off = (k * 6_700_417) % total;
        let row = core.node_rows(q.token, off, 1).unwrap().rows.remove(0);
        s.push(LatencySample { id: row.id, ms: 40 + (k % 300) as i32, at: 1000 });
    }
    let t = Instant::now();
    core.record_latencies(s).unwrap();
    println!("record_latencies 2000（含行号补齐，后台线程）{:?}", t.elapsed());
        for i in 0..2 {
        let t = Instant::now();
        let v = core.fastest_nodes(String::new(), 50, 1000, i64::MAX / 4).unwrap();
        println!("fastest_nodes #{i}: {} rows {:?}", v.len(), t.elapsed());
    }
    drop(core);
    // 冷开（模拟 App 重启）：行号从 positions.bin 读回
    let t = Instant::now();
    let core = MobileCore::new(std::env::args().nth(1).unwrap()).unwrap();
    let open = t.elapsed();
    let t = Instant::now();
    let v = core.fastest_nodes(String::new(), 50, 1000, i64::MAX / 4).unwrap();
    println!("cold open {open:?}, fastest_nodes {} rows {:?}", v.len(), t.elapsed());
    // 重建：预热在建库阶段完成
    let t = Instant::now();
    core.rebuild_mock_nodes(1.0).unwrap();
    println!("rebuild (含预热) {:?}", t.elapsed());
    let t = Instant::now();
    let v = core.fastest_nodes(String::new(), 50, 1000, i64::MAX / 4).unwrap();
    println!("after rebuild fastest_nodes {} rows {:?}", v.len(), t.elapsed());
}
