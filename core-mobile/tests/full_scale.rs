//! 全量 1310 万节点与原型 fixtures 逐条对照（耗时 ~30 s、峰值 ~0.8 GB）：
//! cargo test --release --test full_scale -- --ignored
use zephyr_mobile_core::MobileCore;

#[test]
#[ignore]
fn full_scale_queries_match_prototype() {
    let fx: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../contract/fixtures/mock-v0.json")).unwrap()).unwrap();
    let dir = std::env::temp_dir().join("zephyr-full-scale-test");
    let _ = std::fs::remove_dir_all(&dir);
    let core = MobileCore::new(dir.to_string_lossy().into()).unwrap();
    let rep = core.rebuild_mock_nodes(1.0).unwrap();
    assert_eq!(rep.total, fx["total"].as_u64().unwrap());
    for q in fx["queries"].as_array().unwrap() {
        let text = q["query"].as_str().unwrap();
        let want = q["total"].as_u64().unwrap();
        let got = core.query_nodes(text.into()).unwrap();
        assert_eq!(got.total, want, "query {text:?}");
        let secs: Vec<(String, u64)> = q["sections"].as_array().unwrap().iter().map(|s| (s["region"].as_str().unwrap().to_string(), s["count"].as_u64().unwrap())).collect();
        let got_secs: Vec<(String, u64)> = got.sections.iter().map(|s| (s.region.clone(), s.count)).collect();
        assert_eq!(got_secs, secs, "sections {text:?}");
        let want_names: Vec<&str> = q["firstRows"].as_array().unwrap().iter().filter_map(|r| r["name"].as_str()).collect();
        let rows = core.node_rows(got.token, 0, want_names.len() as u32).unwrap();
        let got_names: Vec<&str> = rows.rows.iter().map(|r| r.name.as_str()).collect();
        assert_eq!(got_names, want_names, "first rows {text:?}");
        assert!(got.took_micros < 50_000, "query {text:?} took {} µs", got.took_micros);
    }
}
