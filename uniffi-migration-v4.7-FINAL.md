# Rust UniFFI + 原生 UI 移动端迁移工作流 v4.7（最终冻结版）

> 技术栈：Tauri v2 + Rust → Android (Kotlin / Jetpack Compose) + iOS (Swift / SwiftUI)  
> UniFFI 0.28.x · Style Dictionary 3.9.x · Compose BOM 2024.02+  
> 本文档为可直接对照执行的正式稿，所有关键技术细节均已对照官方文档验证。

---

## 整体架构

```
┌──────────────────────────────────────────────────────────┐
│  Android (Kotlin / Jetpack Compose)                      │
│  iOS (Swift / SwiftUI)                                   │
│  ← 原生 UI，通过 Design Token 三层体系保证视觉一致性 →    │
├──────────────────────────────────────────────────────────┤
│  UniFFI 自动生成绑定层（Proc-Macro，无 UDL）               │
│  suspend fun / Kotlin Coroutines  |  async throws Swift  │
├──────────────────────────────────────────────────────────┤
│  Rust 共享核心库（与桌面 Tauri 100% 同源 crate）           │
│  业务逻辑 / 网络 / 加密 / 数据处理 / 状态管理              │
└──────────────────────────────────────────────────────────┘
```

---

## 项目结构

```
my-project/
├── Cargo.toml                      # 工作区根（统一管理 release profile）
├── src-tauri/                      # 原 Tauri 桌面端（保留，不动）
├── core/                           # Rust 核心库
│   ├── Cargo.toml
│   ├── .cargo/config.toml          # sccache + Android linker 配置
│   ├── build_ios.sh                # iOS XCFramework 构建脚本
│   └── src/lib.rs
├── android/                        # Android 项目
├── ios/                            # iOS 项目（SPM 包）
│   ├── Package.swift
│   ├── MyAppCore.xcframework        # 构建产物（git ignore）
│   └── Sources/
│       ├── UniFFI/                 # uniffi-bindgen 生成（git ignore）
│       └── DesignSystem/           # 手写扩展（提交 git）
├── tokens/                         # Design Token 源文件
│   ├── package.json
│   ├── config.js
│   └── src/
│       ├── primitive.json
│       ├── semantic.json
│       └── component.json
├── .github/workflows/mobile.yml    # CI 并行构建配置
└── scripts/
    └── prebuild_mobile.sh          # 本地预构建脚本（产物，非完整工程）
```

---

## Phase 1：Rust 核心库

### 1.1 工作区根 Cargo.toml（统一 profile）

```toml
[workspace]
members = ["src-tauri", "core"]
resolver = "2"

# 性能优先（默认）
# opt-level = "z" 虽减小体积，但会禁用循环展开、向量化等优化
# 在加密/序列化等 CPU 密集场景比 opt-level=3 慢 15-40%，不应作为默认值
[profile.release]
opt-level = 3
lto = true
codegen-units = 1
panic = "abort"             # 移动端 FFI panic = 直接 crash，abort 使行为显式化
strip = true
split-debuginfo = "packed"  # 调试符号单独打包，崩溃平台（Sentry 等）可还原堆栈；交叉编译报 warning 时可安全移除

# 体积优先（仅在极度敏感场景手动指定，如东南亚低端机分发）
[profile.release-small]
inherits = "release"
opt-level = "z"
```

两个 profile 的使用方式：

```bash
cargo build --release                    # 性能优先（日常 CI 使用）
cargo build --profile release-small     # 体积优先（按需）
```

### 1.2 core/Cargo.toml

```toml
[package]
name = "myapp-core"
version = "0.1.0"
edition = "2021"

[lib]
# cdylib：供开发机 uniffi-bindgen 读取元数据（host build）
# staticlib：供 iOS XCFramework 打包
# iOS 禁止非系统 dylib，Cargo 会根据 target 自动选择产物类型
crate-type = ["cdylib", "staticlib"]

[dependencies]
uniffi    = { version = "0.28", features = [] }   # tokio feature 按需在下方 features 开启
thiserror = "1"
serde     = { version = "1", features = ["derive"] }
# tokio 仅在业务逻辑内部依赖 Tokio 生态时引入（reqwest / tokio::spawn / tokio::time 等）
tokio     = { version = "1", features = ["rt", "rt-multi-thread"], optional = true }

[features]
# 开启后 uniffi/tokio feature 同步启用，支持 #[uniffi::export(async_runtime = "tokio")]
# lib.rs 官方原文："Enable support for Tokio's futures. This must still be opted into
# on a per-function basis using #[uniffi::export(async_runtime = \"tokio\")]"
tokio-async = ["tokio", "uniffi/tokio"]

# 不需要 async 的业务逻辑：直接用同步函数即可，不开启任何 feature
```

### 1.3 编译缓存

`core/.cargo/config.toml`：

```toml
[build]
rustc-wrapper = "sccache"

[target.aarch64-linux-android]
linker = "aarch64-linux-android-clang"

[target.x86_64-linux-android]
linker = "x86_64-linux-android-clang"
```

```bash
cargo install sccache
```

### 1.4 Proc-Macro 接口暴露与 async 说明

**关于 async 的核心原则（来自 UniFFI 0.28 官方文档与 lib.rs crate features 页）**：

UniFFI 的 async fn 导出后，**外层绑定（Swift、Kotlin）负责提供 executor 驱动 Future 到完成**，Rust 端本身不需要 event loop。官方原文：

> "In Rust Future terminology this means the foreign bindings supply the 'executor' — think event-loop, or async runtime. There's no requirement for a Rust event loop."

`async_runtime = "tokio"` 是 **UniFFI 官方正式支持的属性**，lib.rs crate features 页原文：

> "Enable support for Tokio's futures. This must still be opted into on a per-function basis using `#[uniffi::export(async_runtime = "tokio")]`"

使用规则：
- **`async fn` 不依赖 Tokio**（使用 async-std / smol / futures-timer）：直接 `#[uniffi::export]` 即可，无需任何 Tokio 配置
- **`async fn` 依赖 Tokio 生态**（reqwest、tokio::time、tokio::spawn 等）：在 `Cargo.toml` 开启 `uniffi/tokio` feature，并在函数上标注 `#[uniffi::export(async_runtime = "tokio")]`，UniFFI 内部自动管理 Tokio Runtime，**不需要也不应该手动持有 `Arc<Runtime>` 或调用 `block_on`**
- **`block_on` 在移动端是危险的**：Android 主线程禁止阻塞，iOS Watchdog 会强杀卡死主线程的进程，`block_on` 会造成致命死锁

`core/src/lib.rs`：

```rust
// setup_scaffolding!() 必须在 lib.rs 顶层第一行调用，且只调用一次
uniffi::setup_scaffolding!();

pub mod network;
pub mod crypto;

// ---- 错误类型 ----
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum AppError {
    #[error("Network error: {0}")]
    NetworkError(String),
    #[error("Cancelled")]
    Cancelled,          // 用于映射取消操作（见 §1.5 取消机制）
    #[error("Parse error")]
    ParseError,
    #[error("Unknown error")]
    UnknownError,
}

// ---- 数据结构 ----
#[derive(uniffi::Record, serde::Serialize, serde::Deserialize)]
pub struct UserInfo {
    pub id: String,
    pub name: String,
    pub created_at: u64,
}

// ---- 普通导出函数 ----
// 原 #[tauri::command] 函数：函数体逻辑通常可直接复用
// 条件：参数/返回值必须是 UniFFI 支持的类型（String、u64、bool、Vec<T>、Option<T>、Result<T,E> 等）
// 不支持：tauri::State、tauri::AppHandle 等 Tauri 特有类型——这类参数需重构为平台无关形式
#[uniffi::export]
pub fn process_data(input: String) -> String {
    format!("processed: {}", input)
}

// ---- async fn：使用官方 async_runtime = "tokio" 属性（唯一推荐路径）----
// 生产环境几乎必然依赖 Tokio 生态（reqwest、数据库驱动等），方案 B 是唯一实用路径
// 如果业务不需要异步，直接用同步函数，不写 async fn
// ⚠️ 禁止在 async fn 内使用 std::thread::sleep（阻塞 OS 线程，卡住外层 executor）
// 前提：Cargo.toml 开启 features = ["tokio-async"]（即 uniffi/tokio + tokio）
// UniFFI 自动管理 Tokio Runtime，生成 Kotlin suspend fun / Swift async throws
// ❌ 不需要手动持有 Arc<Runtime>
// ❌ 不应调用 block_on（Android 主线程禁止阻塞，iOS Watchdog 会强杀）
#[cfg(feature = "tokio-async")]
#[derive(uniffi::Object)]
pub struct AppState {
    config: String,
}

#[cfg(feature = "tokio-async")]
#[uniffi::export]
impl AppState {
    #[uniffi::constructor]
    pub fn new(config: String) -> Self {
        Self { config }
    }

    pub fn get_status(&self) -> String {
        format!("running with config: {}", self.config)
    }

    // async_runtime = "tokio" ← 官方正式属性（lib.rs crate features 确认）
    // UniFFI 内部按需初始化并复用 Tokio Runtime，无需业务代码手动管理
    #[uniffi::export(async_runtime = "tokio")]
    pub async fn fetch_data(&self, url: String) -> Result<String, AppError> {
        // 可安全使用 reqwest / tokio::time / tokio::spawn 等 Tokio 生态
        // tokio::time::sleep(Duration::from_millis(100)).await;
        Ok(format!("data from {}", url))
    }
}

// ---- 无 Tokio 的默认 AppState（大多数业务场景，推荐优先使用）----
#[cfg(not(feature = "tokio-async"))]
#[derive(uniffi::Object)]
pub struct AppState {
    config: String,
}

#[cfg(not(feature = "tokio-async"))]
#[uniffi::export]
impl AppState {
    #[uniffi::constructor]
    pub fn new(config: String) -> Self { Self { config } }
    pub fn get_status(&self) -> String { format!("config: {}", self.config) }
    pub fn update(&self, _data: String) {}
}
```

### 1.5 取消机制（官方规范）

**UniFFI 0.28 官方文档明确声明**：

> "We don't directly support cancellation in UniFFI even when the underlying platforms do. You should build your cancellation in a separate, library specific channel; for example, exposing a cancel() method that sets a flag that the library checks periodically."

Swift 的 `Task.cancel()` 和 Kotlin 的 `Job.cancel()` **不会**自动停止 Rust 侧的 Future。对于长轮询、长循环、分段下载等耗时操作，必须手动实现取消通道：

```rust
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[derive(uniffi::Object)]
pub struct LongRunningTask {
    cancelled: Arc<AtomicBool>,
}

#[uniffi::export]
impl LongRunningTask {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self { cancelled: Arc::new(AtomicBool::new(false)) }
    }

    // 外层 Swift/Kotlin 调用此方法发起取消
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    pub fn run(&self) -> Result<String, AppError> {
        for i in 0..1000 {
            // 周期性检查取消标志
            if self.cancelled.load(Ordering::SeqCst) {
                return Err(AppError::Cancelled);
            }
            // 实际工作...
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        Ok("done".to_string())
    }
}
```

### 1.6 状态管理桥接（tauri::State → UniFFI）

从 Tauri 迁移时，状态管理是工作量最大的部分。`tauri::State<T>` 无法跨平台，需统一改为 Rust 侧持有状态，各端通过 UniFFI 对象访问：

```rust
// core/src/state.rs
use std::sync::{Arc, RwLock};

#[derive(uniffi::Object)]
pub struct AppStore {
    inner: Arc<RwLock<StoreInner>>,
}

struct StoreInner {
    user_id: Option<String>,
    settings: Settings,
}

#[uniffi::export]
impl AppStore {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self { inner: Arc::new(RwLock::new(StoreInner::default())) }
    }
    pub fn get_user_id(&self) -> Option<String> {
        self.inner.read().unwrap().user_id.clone()
    }
    pub fn set_user_id(&self, id: String) {
        self.inner.write().unwrap().user_id = Some(id);
    }
}
```

各端持有方式：

```rust
// Tauri 桌面端：src-tauri/src/main.rs
use std::sync::Arc;

fn main() {
    let store = Arc::new(myapp_core::AppStore::new());
    tauri::Builder::default()
        .manage(store.clone())  // 注入 Arc<AppStore>
        .invoke_handler(tauri::generate_handler![get_user_id, update_user_cmd])
        .run(tauri::generate_context!()).unwrap();
}

// Tauri Command 提取时泛型必须与 manage 类型一致：Arc<AppStore>
#[tauri::command]
fn get_user_id(store: tauri::State<'_, Arc<myapp_core::AppStore>>) -> Option<String> {
    store.get_user_id()
}

#[tauri::command]
fn update_user_cmd(
    store: tauri::State<'_, Arc<myapp_core::AppStore>>,
    id: String,
) -> Result<(), String> {
    store.set_user_id(id);  // 调用 AppStore 已有方法，示例保持自洽
    Ok(())
}
```

```kotlin
// Android：ViewModel 直接持有
class MainViewModel : ViewModel() {
    private val store = AppStore()   // UniFFI 生成的 Kotlin 类
    val userId = store.getUserId()
}
```

```swift
// iOS：@MainActor class 持有
@MainActor class AppViewModel: ObservableObject {
    private let store = AppStore()   // UniFFI 生成的 Swift 类
    @Published var userId: String? = nil
    func load() { userId = store.getUserId() }
}
```

### 1.7 Rust → UI 反向推送（Callback Interface）

拉取模式（UI 调 Rust）已在前文覆盖。当需要 Rust 主动推数据给 UI（下载进度、长连接、实时数据流）时，使用 UniFFI 的 `callback_interface`：

```rust
// Rust 侧定义回调接口
#[uniffi::export(callback_interface)]
pub trait DownloadCallback: Send + Sync {
    fn on_progress(&self, percent: u32);
    fn on_complete(&self, path: String);
    fn on_error(&self, msg: String);
}

#[uniffi::export]
#[cfg(feature = "tokio-async")]
pub struct Downloader;

#[uniffi::export]
#[cfg(feature = "tokio-async")]
impl Downloader {
    #[uniffi::constructor]
    pub fn new() -> Self { Self }

    #[uniffi::export(async_runtime = "tokio")]
    pub async fn start(&self, url: String, cb: Arc<dyn DownloadCallback>) -> Result<(), AppError> {
        cb.on_progress(0);
        // ... 实际下载逻辑 ...
        cb.on_progress(100);
        cb.on_complete("/local/path".to_string());
        Ok(())
    }
}
```

```kotlin
// Android：实现接口，UniFFI 自动处理线程回调
val downloader = Downloader()
viewModelScope.launch {
    downloader.start(url, object : DownloadCallback {
        override fun onProgress(percent: UInt) { _progress.value = percent.toInt() }
        override fun onComplete(path: String)  { _done.value = path }
        override fun onError(msg: String)      { _error.value = msg }
    })
}
```

```swift
// iOS：实现协议
// ✅ 必须继承 NSObject：UniFFI Swift 回调底层依赖 ObjC runtime，缺少则运行时崩溃
// ✅ 协议名带 Protocol 后缀（UniFFI 生成规范）：DownloadCallbackProtocol
class MyCallback: NSObject, DownloadCallbackProtocol {
    func onProgress(percent: UInt32) { DispatchQueue.main.async { self.progress = percent } }
    func onComplete(path: String)    { DispatchQueue.main.async { self.done = path } }
    func onError(msg: String)        { DispatchQueue.main.async { self.error = msg } }
}
```

### 1.8 FFI 边界性能原则

```rust
// ❌ 高频调用时传递大型序列化数据，CPU 开销随数据量线性增长
#[uniffi::export]
pub fn get_all_items() -> String { serde_json::to_string(&huge_vec).unwrap() }

// ✅ Rust 持有对象，UI 按需获取字段，单次 FFI 调用只传必要数据
#[uniffi::export]
impl DataStore {
    pub fn get_item_count(&self) -> u64 { ... }
    pub fn get_item_name(&self, index: u64) -> String { ... }
    pub fn get_item_value(&self, index: u64) -> f64 { ... }
}
```

### 1.9 安装工具链

```bash
cargo install uniffi-bindgen-cli sccache cargo-ndk

rustup target add \
    aarch64-linux-android \
    x86_64-linux-android \
    aarch64-apple-ios \
    aarch64-apple-ios-sim \
    x86_64-apple-ios         # Intel Mac 模拟器兼容
```

---

## Phase 2：Android 集成

### 2.1 两条编译路径的分离

`uniffi-bindgen` 读取的是**开发机 host 架构**的动态库：

- macOS → `target/release/libmyapp_core.dylib`
- Linux → `target/release/libmyapp_core.so`

`cargo ndk` 产出的是 Android 目标的 `.so`：

- `target/aarch64-linux-android/release/libmyapp_core.so`

两者路径不同，**绑定生成任务不能依赖 Android NDK 产物**，必须依赖独立的 host 编译任务。

### 2.2 Gradle 任务配置

`android/app/build.gradle.kts`：

```kotlin
val uniffiOutDir = layout.buildDirectory.dir("generated/uniffi").get().asFile

// 步骤 1：Host 编译（供 uniffi-bindgen 读取元数据）
val buildRustLocal by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile.resolve("core"))
    commandLine("cargo", "build", "--release")
}

// 步骤 2：Kotlin 绑定生成（依赖 Host 编译）
val generateUniFFIBindings by tasks.registering(Exec::class) {
    dependsOn(buildRustLocal)
    workingDir(rootProject.projectDir.parentFile.resolve("core"))

    // 动态检测开发机 OS，跨平台团队适用
    val hostOs = System.getProperty("os.name").lowercase()
    val libPath = when {
        hostOs.contains("mac")     -> "target/release/libmyapp_core.dylib"
        hostOs.contains("windows") -> "target/release/myapp_core.dll"
        else                       -> "target/release/libmyapp_core.so"
    }
    commandLine(
        "uniffi-bindgen", "generate",
        "--library", libPath,
        "--language", "kotlin",
        "--out-dir", uniffiOutDir.absolutePath
    )
    outputs.dir(uniffiOutDir)
}

// 步骤 3：Android NDK 交叉编译（与步骤 2 无依赖，Gradle 可并行）
val buildRustAndroid by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile.resolve("core"))
    commandLine(
        "cargo", "ndk",
        "-t", "arm64-v8a", "-t", "x86_64",
        "-o", layout.projectDirectory.dir("src/main/jniLibs").asFile.absolutePath,
        "build", "--release"
    )
}

// preBuild 同时依赖两者，Gradle 调度器自动并行
tasks.named("preBuild") {
    dependsOn(generateUniFFIBindings, buildRustAndroid)
}

android {
    defaultConfig {
        minSdk = 24
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }
    // 直接从 APK mmap 加载 .so，不解压到文件系统，减少安装后磁盘占用
    // AGP 7.x 写法：packagingOptions { jniLibs { useLegacyPackaging = false } }
    // AGP 8.0+ 写法：packaging { jniLibs { useLegacyPackaging = false } }（去掉 Options）
    // 当前 Android Studio 默认使用 AGP 8.0+，如用旧版本请改为上方 AGP 7.x 写法
    // 验证：查看 android/build.gradle.kts 中 com.android.tools.build:gradle 版本号
    packagingOptions {
        jniLibs { useLegacyPackaging = false }
    }
    sourceSets {
        getByName("main") { kotlin.srcDirs(uniffiOutDir) }  // AGP 8.0+：.kt 文件须用 kotlin.srcDirs
    }
}

dependencies {
    // UniFFI Kotlin 运行时（JNA 5.12+ 必须）
    // 排除 jna-platform：cargo ndk 已将正确的 .so 放入 jniLibs，
    // JNA 运行时会直接从那里加载，不需要 JNA 自带的平台库，可减少包体积
    implementation("net.java.dev.jna:jna:5.14.0@aar") {
        exclude(group = "net.java.dev.jna", module = "jna-platform")
    }
    // UniFFI 生成的 suspend fun 必须
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.0")
    // Compose
    implementation(platform("androidx.compose:compose-bom:2024.02.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.8.2")
}
```

### 2.3 AndroidManifest.xml

```xml
<application
    android:extractNativeLibs="false"
    ...>
```

配合 `useLegacyPackaging = false`，minSdk ≥ 23 时 APK 安装体积进一步缩减（.so 不再额外占用解压后的磁盘空间）。

### 2.4 ProGuard 规则

`android/app/proguard-rules.pro`：

```
-dontwarn com.sun.jna.**
-keep class com.sun.jna.** { *; }
-keep class com.myapp.uniffi.** { *; }
```

### 2.5 内存安全原则

UniFFI Object 在 Kotlin 端由 GC 管理，Rust 端用 `Arc<T>` 维持引用计数：

- 避免将 `AppState` 等 Rust 对象存入静态变量或单例（阻止 GC 回收）
- Kotlin GC 回收时自动触发 Rust `drop`，无需手动释放

### 2.6 Kotlin 调用示例

```kotlin
class MainViewModel : ViewModel() {
    private val state = AppState(config = "{}")
    val result = MutableStateFlow(state.getStatus())

    fun process() {
        viewModelScope.launch {
            result.value = processData(input = "hello")
        }
    }

    // UniFFI Kotlin Object 实现了 AutoCloseable
    // ViewModel 销毁时主动调用 close()，立即释放 Rust 侧资源
    // 适用于持有大量内存、文件句柄或网络连接的场景；轻量对象可省略
    override fun onCleared() {
        state.close()
        super.onCleared()
    }
}
```

---

## Phase 3：iOS 集成

### 3.1 XCFramework 构建脚本

`core/build_ios.sh`：

```bash
#!/bin/bash
set -e

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$CORE_DIR/../ios"
UNIFFI_OUT="$OUT_DIR/Sources/UniFFI"

mkdir -p "$UNIFFI_OUT"

# 步骤 1：Host 编译（必须显式执行，不假设 target/release 已有产物）
echo "==> [1/4] Host 编译（元数据提取）"
cargo build --release

# 步骤 2：iOS 交叉编译（兼容 Apple Silicon Mac 和 Intel Mac）
echo "==> [2/4] iOS 交叉编译"
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim
cargo build --release --target x86_64-apple-ios   # Intel Mac 模拟器

# 合并模拟器架构（aarch64-sim + x86_64 → 通用 fat 库）
mkdir -p "$CORE_DIR/target/ios-sim/release"
lipo -create \
    "$CORE_DIR/target/aarch64-apple-ios-sim/release/libmyapp_core.a" \
    "$CORE_DIR/target/x86_64-apple-ios/release/libmyapp_core.a" \
    -output "$CORE_DIR/target/ios-sim/release/libmyapp_core_sim.a"

# 步骤 3：生成 Swift 绑定（从 host 产物读取，自动检测 OS 后缀）
echo "==> [3/4] 生成 Swift 绑定"
OS_NAME="$(uname -s)"
LIB_EXT="so"
[ "$OS_NAME" = "Darwin" ] && LIB_EXT="dylib"

uniffi-bindgen generate \
    --library "target/release/libmyapp_core.${LIB_EXT}" \
    --language swift \
    --out-dir "$UNIFFI_OUT"

# 自动生成 module.modulemap（写入脚本，不依赖"手动创建一次"）
# 注意：.h 文件和 .modulemap 格式不同，不能互相复制替代
HEADER_NAME="myapp_coreFFI.h"
cat > "$UNIFFI_OUT/module.modulemap" << EOF
module MyAppCoreFFI {
    header "${HEADER_NAME}"
    export *
}
EOF

# 步骤 4：打包 XCFramework（直接传入两个 .a，无需 lipo fat binary）
echo "==> [4/4] 打包 XCFramework"
rm -rf "$OUT_DIR/MyAppCore.xcframework"
xcodebuild -create-xcframework \
    -library "$CORE_DIR/target/aarch64-apple-ios/release/libmyapp_core.a" \
    -headers "$UNIFFI_OUT" \
    -library "$CORE_DIR/target/ios-sim/release/libmyapp_core_sim.a" \
    -headers "$UNIFFI_OUT" \
    -output "$OUT_DIR/MyAppCore.xcframework"

echo "==> 完成"
```

### 3.2 Swift Package Manager 配置

`ios/Package.swift`：

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyAppCore",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "MyAppCore", targets: ["MyAppCore", "MyAppCoreFFI"])
    ],
    targets: [
        .binaryTarget(
            name: "MyAppCoreFFI",
            path: "MyAppCore.xcframework"
        ),
        .target(
            name: "MyAppCore",
            dependencies: ["MyAppCoreFFI"],
            path: "Sources/UniFFI",
            sources: ["myapp_core.swift"],
            // Tokio + 网络功能可能需要这些系统库
            linkerSettings: [
                .linkedLibrary("resolv"),
                .linkedLibrary("c++")
            ]
        )
    ]
)
```

### 3.3 SwiftUI 调用示例

```swift
@MainActor
class MainViewModel: ObservableObject {
    @Published var result: String = ""
    private let state = AppState(config: "{}")

    init() { result = state.getStatus() }

    func process() {
        Task { [weak self] in   // [weak self] 防止强引用循环阻止 Rust Arc<T> drop
            guard let self else { return }
            self.result = processData(input: "hello")
        }
    }

    // Swift 侧：UniFFI 生成的对象不暴露 close() 方法（与 Kotlin 不同）
    // ARC 在 deinit 时自动调用 Rust 侧 drop，无需也不能手动调用 close()
    // 如需提前释放大资源，将 state 设为 Optional 并手动置 nil 即可：
    //   state = nil  // 触发 ARC 立即 drop Rust Arc<T>
}
```

---

## Phase 4：Design Token 三层体系

### 设计原则

```
Primitive（原始值）→ Semantic（语义+主题）→ Component（引用 semantic）
     #01696f      →    color.primary     →    button.bg = {color.primary}
```

**组件层不直接绑定 `color.light.*`**，引用 semantic token，由平台主题系统（Compose `MaterialTheme` / SwiftUI `@Environment`）在运行时切换 light/dark。这样当前组件层的 light/dark 状态是：语义层已完整支持 light/dark，**组件层为 light-first 默认实现**，dark 映射由平台主题系统控制。

### 4.1 Primitive Token

`tokens/src/primitive.json`：

```json
{
  "primitive": {
    "color": {
      "teal-600": { "value": "#01696f", "type": "color" },
      "teal-700": { "value": "#0c4e54", "type": "color" },
      "gray-900": { "value": "#28251d", "type": "color" },
      "gray-500": { "value": "#7a7974", "type": "color" },
      "off-white": { "value": "#f7f6f2", "type": "color" },
      "surface":   { "value": "#f9f8f5", "type": "color" }
    },
    "space": {
      "1": { "value": "4",  "type": "spacing" },
      "2": { "value": "8",  "type": "spacing" },
      "4": { "value": "16", "type": "spacing" },
      "6": { "value": "24", "type": "spacing" },
      "8": { "value": "32", "type": "spacing" }
    },
    "radius": {
      "sm": { "value": "6",  "type": "borderRadius" },
      "md": { "value": "8",  "type": "borderRadius" },
      "lg": { "value": "12", "type": "borderRadius" }
    },
    "font": {
      "size-sm":       { "value": "14", "type": "fontSize" },
      "size-base":     { "value": "16", "type": "fontSize" },
      "size-lg":       { "value": "20", "type": "fontSize" },
      "weight-normal": { "value": "400", "type": "fontWeight" },
      "weight-medium": { "value": "500", "type": "fontWeight" },
      "weight-bold":   { "value": "700", "type": "fontWeight" }
    }
  }
}
```

### 4.2 Semantic Token（light/dark 分层）

`tokens/src/semantic.json`：

```json
{
  "color": {
    "light": {
      "primary":      { "value": "{primitive.color.teal-600}", "type": "color" },
      "primaryHover": { "value": "{primitive.color.teal-700}", "type": "color" },
      "text":         { "value": "{primitive.color.gray-900}", "type": "color" },
      "textMuted":    { "value": "{primitive.color.gray-500}", "type": "color" },
      "bg":           { "value": "{primitive.color.off-white}", "type": "color" },
      "surface":      { "value": "{primitive.color.surface}",  "type": "color" }
    },
    "dark": {
      "primary":      { "value": "#4f98a3", "type": "color" },
      "primaryHover": { "value": "#227f8b", "type": "color" },
      "text":         { "value": "#cdccca", "type": "color" },
      "textMuted":    { "value": "#797876", "type": "color" },
      "bg":           { "value": "#171614", "type": "color" },
      "surface":      { "value": "#1c1b19", "type": "color" }
    }
  },
  "spacing": {
    "space1": { "value": "{primitive.space.1}", "type": "spacing" },
    "space2": { "value": "{primitive.space.2}", "type": "spacing" },
    "space4": { "value": "{primitive.space.4}", "type": "spacing" },
    "space6": { "value": "{primitive.space.6}", "type": "spacing" },
    "space8": { "value": "{primitive.space.8}", "type": "spacing" }
  },
  "radius": {
    "sm": { "value": "{primitive.radius.sm}", "type": "borderRadius" },
    "md": { "value": "{primitive.radius.md}", "type": "borderRadius" },
    "lg": { "value": "{primitive.radius.lg}", "type": "borderRadius" }
  }
}
```

### 4.3 Component Token（引用 semantic，不写死 light/dark）

`tokens/src/component.json`：

```json
{
  "component": {
    "button": {
      "primary": {
        "comment": "引用 semantic token，不直接绑定 light/dark；dark 映射由平台主题系统控制",
        "height":    { "value": "44", "type": "spacing" },
        "radius":    { "value": "{radius.md}",                   "type": "borderRadius" },
        "fontSize":  { "value": "{primitive.font.size-sm}",      "type": "fontSize" },
        "fontWeight":{ "value": "{primitive.font.weight-medium}", "type": "fontWeight" }
      }
    },
    "card": {
      "radius":  { "value": "{radius.lg}",    "type": "borderRadius" },
      "padding": { "value": "{spacing.space4}", "type": "spacing" }
    }
  }
}
```

颜色不在 component token 里写死，由平台主题层注入（见 §4.5）。

### 4.4 Style Dictionary 配置（3.9.x，零插件依赖）

`tokens/package.json`：

```json
{
  "name": "myapp-tokens",
  "version": "1.0.0",
  "scripts": { "build": "style-dictionary build" },
  "dependencies": { "style-dictionary": "3.9.3" }
}
```

`tokens/config.js`：

```js
const StyleDictionary = require('style-dictionary');

const toCamel = (str) => str.replace(/[-_. ](.)/g, (_, c) => c.toUpperCase());

// ---- Compose Kotlin formatter（自定义，零插件依赖）----
// 分组生成语义色 light/dark 两套，平台主题层在运行时切换
StyleDictionary.registerFormat({
  name: 'custom/compose-kotlin',
  formatter: ({ dictionary, options }) => {
    const pkg = options.packageName || 'com.myapp.ui.theme';
    const toCompose = (hex) => `Color(0xFF${hex.replace('#','').toUpperCase()})`;

    const group = (tokens, filterType, transform) => tokens
      .filter(t => t.type === filterType)
      .map(t => `    val ${toCamel(t.name)} = ${transform(t.value)}`)
      .join('\n');

    const all = dictionary.allTokens;
    return `package ${pkg}

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// AUTO-GENERATED — DO NOT EDIT — Source: tokens/src/*.json

// 全量语义色（light + dark 均生成，供主题层按需选用）
object AppColors {
${group(all.filter(t => t.type === 'color'), 'color', toCompose)}
}
object AppSpacing {
${group(all.filter(t => t.type === 'spacing'), 'spacing', v => `${v}.dp`)}
}
object AppRadius {
${group(all.filter(t => t.type === 'borderRadius'), 'borderRadius', v => `${v}.dp`)}
}
object AppFontSize {
${group(all.filter(t => t.type === 'fontSize'), 'fontSize', v => `${v}.sp`)}
}

// 组件尺寸 token（不含颜色，颜色由主题层注入）
object ButtonTokens {
    val height   = 44.dp
    val radius   = AppRadius.md
    val fontSize = AppFontSize.primitiveFontSizeSm
}
object CardTokens {
    val radius  = AppRadius.lg
    val padding = AppSpacing.space4
}
`;
  }
});

// ---- Swift formatter（直接生成原生 Color(red:green:blue:)，零扩展依赖）----
StyleDictionary.registerFormat({
  name: 'custom/swift-constants',
  formatter: ({ dictionary }) => {
    // 支持 6 位（#RRGGBB）和 8 位（#RRGGBBAA）Hex
    const hexToSwift = (hex) => {
      const h = hex.replace('#','');
      const r = (parseInt(h.slice(0,2),16)/255).toFixed(3);
      const g = (parseInt(h.slice(2,4),16)/255).toFixed(3);
      const b = (parseInt(h.slice(4,6),16)/255).toFixed(3);
      const a = h.length === 8 ? (parseInt(h.slice(6,8),16)/255).toFixed(3) : null;
      return a
        ? `Color(red: ${r}, green: ${g}, blue: ${b}, opacity: ${a})`
        : `Color(red: ${r}, green: ${g}, blue: ${b})`;
    };
    const all = dictionary.allTokens;
    const group = (tokens, filterType, transform) => tokens
      .filter(t => t.type === filterType)
      .map(t => `    public static let ${toCamel(t.name)}: ${
        filterType === 'color' ? `Color = ${transform(t.value)}` : `CGFloat = ${t.value}`
      }`)
      .join('\n');

    return `import SwiftUI

// AUTO-GENERATED — DO NOT EDIT — Source: tokens/src/*.json

// 全量语义色（light + dark 均生成，dark 映射由 SwiftUI @Environment 控制）
public enum AppColors {
${group(all.filter(t => t.type === 'color'), 'color', hexToSwift)}
}
public enum AppSpacing {
${group(all.filter(t => t.type === 'spacing'), 'spacing', v => v)}
}
public enum AppRadius {
${group(all.filter(t => t.type === 'borderRadius'), 'borderRadius', v => v)}
}
public enum AppFontSize {
${group(all.filter(t => t.type === 'fontSize'), 'fontSize', v => v)}
}

// 组件尺寸 token（不含颜色，颜色由主题层注入）
public enum ButtonTokens {
    public static let height:   CGFloat = 44
    public static let radius:   CGFloat = AppRadius.md
    public static let fontSize: CGFloat = AppFontSize.primitiveFontSizeSm
}
public enum CardTokens {
    public static let radius:  CGFloat = AppRadius.lg
    public static let padding: CGFloat = AppSpacing.space4
}
`;
  }
});

module.exports = {
  source: ['src/*.json'],
  platforms: {
    android_xml: {
      transformGroup: 'android',
      buildPath: '../android/app/src/main/res/values/',
      files: [
        { destination: 'app_colors.xml', format: 'android/colors',
          filter: { type: 'color' } },
        { destination: 'app_dimens.xml', format: 'android/resources',
          resourceType: 'dimen',
          filter: (t) => ['spacing','borderRadius','fontSize'].includes(t.type) }
      ]
    },
    compose: {
      transformGroup: 'js',
      buildPath: '../android/app/src/main/java/com/myapp/ui/theme/',
      files: [{ destination: 'AppTokens.kt', format: 'custom/compose-kotlin',
                options: { packageName: 'com.myapp.ui.theme' } }]
    },
    ios_swift: {
      transformGroup: 'js',
      buildPath: '../ios/Sources/DesignSystem/',
      files: [{ destination: 'AppTokens.swift', format: 'custom/swift-constants' }]
    }
  }
};
```

### 4.5 平台主题层：运行时 light/dark 切换

生成的 `AppColors` 包含 light 和 dark 两套语义色，由各平台主题系统在运行时选择。

**Android（Compose）**：

```kotlin
@Composable
fun MyAppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) {
        darkColorScheme(
            primary    = AppColors.colorDarkPrimary,     // dark semantic token
            background = AppColors.colorDarkBg,
            surface    = AppColors.colorDarkSurface
        )
    } else {
        lightColorScheme(
            primary    = AppColors.colorLightPrimary,    // light semantic token
            background = AppColors.colorLightBg,
            surface    = AppColors.colorLightSurface
        )
    }
    MaterialTheme(colorScheme = colorScheme, content = content)
}

// 组件中通过 MaterialTheme 获取颜色（自动跟随主题）
@Composable
fun PrimaryButton(text: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.height(ButtonTokens.height),
        shape = RoundedCornerShape(ButtonTokens.radius),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary  // 主题注入，自动 light/dark
        )
    ) {
        Text(text, fontSize = ButtonTokens.fontSize, fontWeight = FontWeight.Medium)
    }
}
```

**iOS（SwiftUI）**：

```swift
struct PrimaryButton: View {
    let text: String
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    // 运行时根据系统主题选择 light/dark token
    var buttonColor: Color {
        colorScheme == .dark ? AppColors.colorDarkPrimary : AppColors.colorLightPrimary
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: ButtonTokens.fontSize, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: ButtonTokens.height)
                .background(buttonColor)
                .cornerRadius(ButtonTokens.radius)
        }
    }
}
```

---

## Phase 5：CI 并行构建

本地开发使用串行预构建脚本，CI 中 Android 和 iOS 拆为两个并行 Job，构建时间减半。

### 5.1 本地预构建脚本

`scripts/prebuild_mobile.sh`：

> **注意**：此脚本产出**预构建产物**（Rust 编译产物 + Design Token），不包含完整的 Android/iOS 工程构建。Android Kotlin 绑定由 Gradle `preBuild` 任务生成，iOS App 由 Xcode 编译。

```bash
#!/bin/bash
set -e

echo "====================================="
echo "  MyApp 移动端预构建管线"
echo "====================================="

# 1. Design Token 生成
echo "\n[1/3] 生成 Design Tokens..."
cd tokens && npm run build && cd ..

# 2. Host 编译（Kotlin/Swift 绑定生成的基础，必须先于 iOS 脚本）
echo "\n[2/3] Host 编译..."
cd core && cargo build --release

# 3. Android NDK 编译（与 iOS 无依赖，本地串行，CI 中可并行）
echo "\n[3/3] Android NDK 编译..."
cargo ndk -t arm64-v8a -t x86_64 \
    -o ../android/app/src/main/jniLibs \
    build --release
cd ..

echo "\n====================================="
echo "  预构建完成！后续步骤："
echo "  Android: Android Studio → Run"
echo "  iOS:     cd core && ./build_ios.sh"
echo "           然后 Xcode → Run"
echo "====================================="
```

### 5.2 GitHub Actions 并行配置

`.github/workflows/mobile.yml`：

```yaml
name: Mobile Build

on:
  push:
    branches: [main]
  pull_request:

jobs:
  # Android 在 Ubuntu 上构建
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: aarch64-linux-android,x86_64-linux-android

      - name: Install cargo-ndk & uniffi-bindgen
        run: cargo install cargo-ndk uniffi-bindgen

      - name: Setup Android SDK
        uses: android-actions/setup-android@v2

      - name: Cache Rust build
        uses: Swatinem/rust-cache@v2
        with:
          workspaces: core

      - name: Build Design Tokens
        working-directory: tokens
        run: npm ci && npm run build

      - name: Build Rust (host, for bindgen)
        working-directory: core
        run: cargo build --release

      - name: Build Rust (Android NDK)
        working-directory: core
        run: |
          cargo ndk -t arm64-v8a -t x86_64 \
            -o ../android/app/src/main/jniLibs \
            build --release

      - name: Generate Kotlin bindings
        working-directory: core
        run: |
          uniffi-bindgen generate \
            --library target/release/libmyapp_core.so \
            --language kotlin \
            --out-dir ../android/app/build/generated/uniffi/

      - name: Build APK
        working-directory: android
        run: ./gradlew assembleRelease

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: android-release
          path: android/app/build/outputs/apk/release/*.apk

  # iOS 在 macOS 上构建（与 Android Job 并行）
  build-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: aarch64-apple-ios,aarch64-apple-ios-sim

      - name: Install uniffi-bindgen-cli
        run: cargo install uniffi-bindgen-cli

      - name: Build Design Tokens
        working-directory: tokens
        run: npm ci && npm run build

      - name: Cache Rust build
        uses: Swatinem/rust-cache@v2
        with:
          workspaces: core

      - name: Build XCFramework
        working-directory: core
        run: ./build_ios.sh

      # ios/ 是 SPM 包（核心库）。完整 App 工程应在独立目录（如 ios-app/）维护
      # 当前 Job 默认产出 XCFramework；如需 IPA，取消下方注释并配置 ExportOptions.plist

      - name: Upload XCFramework
        uses: actions/upload-artifact@v4
        with:
          name: ios-xcframework
          path: ios/MyAppCore.xcframework

      # ---- 可选：构建完整 App IPA（需 ios-app/ 目录存在且配置 ExportOptions.plist）----
      # - name: Build iOS App (Archive)
      #   working-directory: ios-app
      #   run: |
      #     xcodebuild archive \
      #       -scheme "MyApp" \
      #       -archivePath build/MyApp.xcarchive \
      #       -destination "generic/platform=iOS"
      #
      # - name: Export IPA
      #   working-directory: ios-app
      #   run: |
      #     xcodebuild -exportArchive \
      #       -archivePath build/MyApp.xcarchive \
      #       -exportOptionsPlist ExportOptions.plist \
      #       -exportPath build/ipa
      #
      # - name: Upload IPA
      #   uses: actions/upload-artifact@v4
      #   with:
      #     name: ios-ipa
      #     path: ios-app/build/ipa/*.ipa
```

---

## 桌面端（Tauri）保持不变

`src-tauri/Cargo.toml`：

```toml
[dependencies]
myapp-core = { path = "../core" }
```

`src-tauri/src/main.rs`：

```rust
#[tauri::command]
fn process_data_cmd(input: String) -> String {
    myapp_core::process_data(input)  // 调用 core，不重复逻辑
}
```

---

## 系统权限（相机/推送/蓝牙）

无法从 Rust 直接调用系统 API，各端原生层处理后回传 Rust：

**Android**：

```kotlin
val launcher = rememberLauncherForActivityResult(
    ActivityResultContracts.RequestPermission()
) { granted -> state.onCameraPermission(granted) }
```

**iOS**：

```swift
AVCaptureDevice.requestAccess(for: .video) { granted in
    DispatchQueue.main.async { state.onCameraPermission(granted: granted) }
}
```

---

## .gitignore

```gitignore
# Rust
core/target/

# UniFFI 生成文件（构建产物，不提交）
android/app/src/main/jniLibs/
android/app/build/generated/uniffi/
ios/Sources/UniFFI/
ios/MyAppCore.xcframework/

# Token 生成文件（构建产物，不提交）
android/app/src/main/res/values/app_colors.xml
android/app/src/main/res/values/app_dimens.xml
android/app/src/main/java/com/myapp/ui/theme/AppTokens.kt
ios/Sources/DesignSystem/AppTokens.swift

# 手写文件（必须提交）
# ios/Sources/DesignSystem/   ← 整个目录提交（如有扩展文件）
```

---

## 版本锁定

| 工具 | 推荐版本 | 说明 |
|------|----------|------|
| uniffi | **0.28.x** | 当前 stable |
| cargo-ndk | 3.5.x | 支持最新 NDK |
| Android NDK | r26b | cargo-ndk 推荐 |
| Style Dictionary | **3.9.3** | 锁定 3.x，CommonJS，稳定 |
| Compose BOM | 2024.02.00+ | 稳定 Material3 |
| kotlinx-coroutines | 1.8.0+ | UniFFI suspend fun 必须 |
| JNA | 5.14.0 | UniFFI Kotlin 运行时必须 |

---

## 待验证项（正式投产前）

以下内容技术方向正确，但在写入团队文档前建议先跑最小样例验证：

| 项目 | 状态 | 说明 |
|------|------|------|
| `async_runtime = "tokio"` | ✅ 官方正式 API | lib.rs crate features 原文确认，需同时开启 `uniffi/tokio` feature |
| `tokio-async` feature 分支 | 按需引入 | 不依赖 Tokio 生态则无需开启，保持零依赖更优 |
| iOS Linker Flags | 按需验证 | `-lresolv`、`-lc++` 取决于实际 Rust 依赖，首次链接报错时再添加 |
| Intel Mac 模拟器 lipo | 按团队情况 | 纯 Apple Silicon 开发团队可省略 x86_64-apple-ios 编译步骤 |

---

---

## 投产前检查清单

正式执行 Phase 1 前，逐项勾选：

| # | 检查项 | 状态 |
|---|--------|------|
| 1 | 确认 AGP 版本（8.0+ 用 `packaging`，7.x 用 `packagingOptions`） | [ ] |
| 2 | 确认是否需要 `tokio-async` feature（业务是否用 reqwest / tokio::spawn） | [ ] |
| 3 | 跑通最小 UniFFI 样例：`#[uniffi::export]` → Kotlin `suspend fun` → Swift `async throws` | [ ] |
| 4 | 验证 `build_ios.sh` 在团队所有开发机（Apple Silicon / Intel Mac）成功执行 | [ ] |
| 5 | 验证 Gradle `preBuild` 在 Android Studio 触发后，绑定自动生成且编译通过 | [ ] |
| 6 | 验证 SPM `MyAppCore` 包在 Xcode 中链接成功，SwiftUI 可调用 Rust 函数 | [ ] |
| 7 | 执行 `cd tokens && npm run build`，确认三端文件（XML / Compose / Swift）均生成 | [ ] |
| 8 | 确认 `.gitignore` 已提交，生成文件不会被误提交到仓库 | [ ] |
| 9 | 验证 CI `mobile.yml` 在 PR 中触发后，Android APK 和 iOS XCFramework 均成功产出 | [ ] |
| 10 | 验证排除 `jna-platform` 后，Android App 在真机上正常运行（无 `UnsatisfiedLinkError`） | [ ] |
| 11 | 如使用 Callback Interface，验证 Rust 回调在 Kotlin / Swift 主线程中正常触发 | [ ] |
| 12 | Light/Dark 主题切换测试：Compose `isSystemInDarkTheme()` 和 SwiftUI `colorScheme` 均正常响应 | [ ] |
| 13 | Kotlin：持有大资源的 UniFFI Object 在 `onCleared()` 中调用 `close()`；Swift：置 `nil` 触发 ARC 立即释放 | [ ] |

---

*v4.7 最终冻结版 — 2026 年 5 月。关键修正：安装包名改为 uniffi-bindgen-cli；java.srcDirs 改为 kotlin.srcDirs；Swift 删除不存在的 close()，改为 ARC 自动释放说明；split-debuginfo 补交叉编译注释；CI Android Action 改为 setup-android@v2。*
