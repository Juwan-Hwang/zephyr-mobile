plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val uniffiOutDir = layout.buildDirectory.dir("generated/uniffi").get().asFile

// ── Mihomo core binary download ──────────────────────────────────────────
// mihomo naming: mihomo-{os}-{arch}-v{version}.gz
// Android uses "arm64" (not "arm64-v8a"), x86_64 uses "amd64"
val mihomoVersion = "1.19.26"
val mihomoAssetsDir = layout.projectDirectory.dir("src/main/assets/core").asFile

val downloadMihomoArm64 by tasks.registering {
    val outputFile = File(mihomoAssetsDir, "mihomo-android-arm64-v8.gz")
    outputs.file(outputFile)
    doLast {
        if (outputFile.exists()) return@doLast
        mihomoAssetsDir.mkdirs()
        val url = "https://github.com/MetaCubeX/mihomo/releases/download/v${mihomoVersion}/mihomo-android-arm64-v8-v${mihomoVersion}.gz"
        println("Downloading mihomo arm64: $url")
        ant.invokeMethod("get", mapOf("src" to url, "dest" to outputFile))
    }
}

val downloadMihomoX86 by tasks.registering {
    val outputFile = File(mihomoAssetsDir, "mihomo-android-amd64.gz")
    outputs.file(outputFile)
    doLast {
        if (outputFile.exists()) return@doLast
        mihomoAssetsDir.mkdirs()
        val url = "https://github.com/MetaCubeX/mihomo/releases/download/v${mihomoVersion}/mihomo-android-amd64-v${mihomoVersion}.gz"
        println("Downloading mihomo amd64: $url")
        ant.invokeMethod("get", mapOf("src" to url, "dest" to outputFile))
    }
}

// ── Rust / UniFFI build steps ────────────────────────────────────────────

// Step 1: Host build (for uniffi-bindgen to read metadata)
val buildRustLocal by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile.resolve("core/ffi/uniffi"))
    commandLine("cargo", "build", "--release")
}

// Step 2: Kotlin binding generation (depends on host build)
val generateUniFFIBindings by tasks.registering(Exec::class) {
    dependsOn(buildRustLocal)
    workingDir(rootProject.projectDir.parentFile.resolve("core/ffi/uniffi"))

    // Cargo workspace puts output in workspace root target/, not crate-local
    val workspaceTargetDir = rootProject.projectDir.parentFile.resolve("target/release")
    val hostOs = System.getProperty("os.name").lowercase()
    val libPath = when {
        hostOs.contains("mac")     -> workspaceTargetDir.resolve("libzephyr_core_ffi.dylib").absolutePath
        hostOs.contains("windows") -> workspaceTargetDir.resolve("zephyr_core_ffi.dll").absolutePath
        else                       -> workspaceTargetDir.resolve("libzephyr_core_ffi.so").absolutePath
    }
    commandLine(
        "uniffi-bindgen", "generate",
        "--library", libPath,
        "--language", "kotlin",
        "--out-dir", uniffiOutDir.absolutePath
    )
    outputs.dir(uniffiOutDir)
}

// Step 3: Android NDK cross-compilation (independent of step 2, Gradle can parallelize)
val buildRustAndroid by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile.resolve("core/ffi/uniffi"))
    commandLine(
        "cargo", "ndk",
        "-t", "arm64-v8a", "-t", "x86_64",
        "-o", layout.projectDirectory.dir("src/main/jniLibs").asFile.absolutePath,
        "build", "--release"
    )
}

// preBuild depends on all build steps, Gradle scheduler auto-parallelizes
tasks.named("preBuild") {
    dependsOn(generateUniFFIBindings, buildRustAndroid, downloadMihomoArm64, downloadMihomoX86)
}

android {
    namespace = "com.zephyr.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.zephyr.app"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    packaging {
        jniLibs {
            // Must use legacy packaging so .so files are extracted to nativeLibraryDir
            // on device. This is required for libmihomo.so (mihomo binary) to be
            // executable — Android 10+ blocks exec from filesDir (WRIX policy).
            useLegacyPackaging = true
        }
    }

    sourceSets {
        getByName("main") {
            kotlin.srcDirs("src/main/uniffi")
        }
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.8"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // UniFFI Kotlin runtime (JNA 5.12+ required)
    implementation("net.java.dev.jna:jna:5.14.0@aar") {
        exclude(group = "net.java.dev.jna", module = "jna-platform")
    }
    // UniFFI generated suspend fun requires
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.0")
    // AppCompat
    implementation("androidx.appcompat:appcompat:1.6.1")
    // Compose
    implementation(platform("androidx.compose:compose-bom:2024.02.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
    // Navigation
    implementation("androidx.navigation:navigation-compose:2.7.7")
}
