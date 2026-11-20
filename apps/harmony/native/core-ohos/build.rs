fn main() {
    napi_build_ohos::setup();
    if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("ohos") {
        // 给 .so 一个 SONAME，便于 HAP 打包与 readelf 核对。
        println!("cargo:rustc-cdylib-link-arg=-Wl,-soname,libcore_ohos.so");
    }
}
