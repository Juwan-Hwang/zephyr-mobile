plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.paparazzi)
}

android {
    namespace = "com.zephyr.app"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.zephyr.app"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        // ./gradlew -Pzephyr.demo=true installDebug → starts in the prototype's connected "2:14:07" state.
        buildConfigField("double", "CORE_SEED", (providers.gradleProperty("zephyr.coreSeed").orNull ?: "0.0"))
        // core-mobile and mihomo ship only for these ABIs (tools/build-*.sh); dropping JNA's armeabi/mips/x86
        // stubs keeps the APK lean and avoids installing on devices where the engine cannot load.
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        buildConfigField("boolean", "DEMO", (providers.gradleProperty("zephyr.demo").orNull == "true").toString())
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug") // CI-only; real signing via env in release pipeline
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    androidResources { localeFilters += listOf("zh-rCN", "en") }
    buildFeatures { compose = true; buildConfig = true }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}

dependencies {
    implementation(project(":core-engine"))
    implementation(project(":design"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.work.runtime)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.profileinstaller)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    debugImplementation(libs.compose.ui.tooling)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}

// Local-only: run unit/screenshot tests on another JVM (e.g. x86_64 under qemu on aarch64 hosts, where
// Paparazzi's layoutlib has no native build). `-Pzephyr.testJava=/path/to/java`. CI leaves it unset.
providers.gradleProperty("zephyr.testJava").orNull?.let { java ->
    tasks.withType<Test>().configureEach {
        javaLauncher.unset()
        executable = java
        // ByteBuddy (Paparazzi) must self-attach: it can't spawn a helper JVM through qemu.
        jvmArgs("-Djdk.attach.allowAttachSelf=true", "-XX:+EnableDynamicAgentLoading")
    }
}

// ── 16 KB page alignment (Android 15+, Google Play requirement) ───────────────────────────────────
// Every 64-bit .so packaged into the APK must have PT_LOAD p_align >= 16384, otherwise it fails to load
// on 16 KB-page devices and Play rejects the update. Scans the merged native libs of each variant
// (ours + JNA + any AAR). Warns locally; `-Pzephyr.strict16k=true` (CI) turns violations into failures.
abstract class Verify16kAlignment : DefaultTask() {
    @get:InputFiles @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val libs: ConfigurableFileCollection
    @get:Input abstract val strict: Property<Boolean>

    @TaskAction fun verify() {
        val bad = mutableListOf<String>()
        libs.asFileTree.matching { include("**/arm64-v8a/*.so", "**/x86_64/*.so") }.forEach { so ->
            val align = minLoadAlign(so.readBytes())
            if (align != null && align < 16384) bad += "${so.parentFile.name}/${so.name}: p_align=$align"
        }
        if (bad.isEmpty()) return
        val msg = "Native libs not 16 KB aligned (link with -Wl,-z,max-page-size=16384):\n  " + bad.joinToString("\n  ")
        if (strict.get()) throw GradleException(msg) else logger.warn("w: $msg")
    }

    /** Smallest p_align among PT_LOAD segments of an ELF64 little-endian file; null if not ELF64. */
    private fun minLoadAlign(b: ByteArray): Long? {
        if (b.size < 64 || b[0] != 0x7f.toByte() || b[1] != 'E'.code.toByte() || b[4] != 2.toByte() || b[5] != 1.toByte()) return null
        fun u16(o: Int) = (b[o].toInt() and 0xff) or ((b[o + 1].toInt() and 0xff) shl 8)
        fun u32(o: Int) = u16(o).toLong() or (u16(o + 2).toLong() shl 16)
        fun u64(o: Int) = u32(o) or (u32(o + 4) shl 32)
        val phoff = u64(0x20).toInt(); val phentsize = u16(0x36); val phnum = u16(0x38)
        var min: Long? = null
        for (i in 0 until phnum) {
            val p = phoff + i * phentsize
            if (p + 56 > b.size) break
            if (u32(p) == 1L) { val a = u64(p + 48); min = if (min == null) a else minOf(min, a) }
        }
        return min
    }
}

androidComponents {
    onVariants { variant ->
        val cap = variant.name.replaceFirstChar { it.uppercase() }
        val check = tasks.register<Verify16kAlignment>("verify16kAlignment$cap") {
            group = "verification"
            description = "Checks 64-bit .so files of $cap are 16 KB page aligned"
            libs.from(layout.buildDirectory.dir("intermediates/merged_native_libs/${variant.name}"))
            strict.set(providers.gradleProperty("zephyr.strict16k").map { it.toBoolean() }.orElse(false))
            dependsOn("merge${cap}NativeLibs")
        }
        tasks.matching { it.name == "package$cap" }.configureEach { dependsOn(check) }
    }
}
