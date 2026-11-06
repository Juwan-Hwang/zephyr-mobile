use std::time::Instant;
use zephyr_mobile_core::nodes::NodeStoreBuilder;
fn main() {
    let scale: f64 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(0.2);
    let t = Instant::now();
    let v: Vec<_> = zephyr_mobile_core::mock::nodes(scale).collect();
    println!("generate {} in {:?}", v.len(), t.elapsed());
    let t = Instant::now();
    let mut b = NodeStoreBuilder::with_capacity(v.len());
    for n in v { b.push(n); }
    println!("push {:?}", t.elapsed());
    let t = Instant::now();
    b.write(&std::env::temp_dir().join("prof.zn")).unwrap();
    println!("write {:?}", t.elapsed());
}
