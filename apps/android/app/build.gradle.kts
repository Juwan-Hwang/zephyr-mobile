import java.io.ByteArrayOutputStream
import javax.inject.Inject
import org.gradle.process.ExecOperations

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
        // D3（docs/release.md）：上架标识 com.juwanh.zephyr；namespace / Kotlin 包名保持 com.zephyr.app（只影响代码包名）。
        applicationId = "com.juwanh.zephyr"
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
    // minSdk 28: calling a newer API without a version check must fail the build, not crash a device.
    lint { fatal += "NewApi"; ignoreTestSources = true }
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
    // Ship only the App's own languages (keeps library translations out); keep in sync with res/xml/locales_config.xml.
    androidResources { localeFilters += listOf("en", "zh", "ja", "ko", "ru", "es", "fa", "tk", "my", "ar", "ur", "sw", "tr", "vi") }
    buildFeatures { compose = true; buildConfig = true }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}

dependencies {
    implementation(project(":core-engine"))
    implementation(project(":design"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.work.runtime)
    // QR import (contract §15): CameraX preview + ZXing decoding, no Play services needed.
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.zxing.core)
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

// Contract fixtures (command-parse-v1.json …) live at repo root; tests read them via this system property.
tasks.withType<Test>().configureEach {
    systemProperty("zephyr.fixtures", rootProject.file("../../contract/fixtures").absolutePath)
    inputs.dir(rootProject.file("../../contract/fixtures")).withPropertyName("contractFixtures").withPathSensitivity(PathSensitivity.RELATIVE)
}

// Local-only: run unit/screenshot tests on another JVM (e.g. x86_64 under qemu on aarch64 hosts, where
// Paparazzi's layoutlib has no native build). `-Pzephyr.testJava=/path/to/java`. CI leaves it unset.
providers.gradleProperty("zephyr.testJava").orNull?.let { java ->
    tasks.withType<Test>().configureEach {
        javaLauncher.unset()
        executable = java
        // ByteBuddy (Paparazzi) must self-attach: it can't spawn a helper JVM through qemu.
        jvmArgs("-Duser.timezone=UTC", "-Djdk.attach.allowAttachSelf=true", "-XX:+EnableDynamicAgentLoading")
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

// ── In-app 开源许可 page (GPL-3.0 distribution, docs/release.md §6) ────────────────────────────────
// The repo-root LICENSE / THIRD_PARTY_NOTICES.md / THIRD_PARTY_LICENSES.txt (from tools/gen-third-party.sh) are
// copied into the APK's assets/licenses/ at build time, so the App always ships the committed files, never a copy.
abstract class BundleLicenses : DefaultTask() {
    @get:InputFiles @get:PathSensitive(PathSensitivity.NAME_ONLY)
    abstract val sources: ConfigurableFileCollection
    @get:OutputDirectory abstract val outputDir: DirectoryProperty

    @TaskAction fun copy() {
        val dir = outputDir.get().dir("licenses").asFile
        dir.deleteRecursively(); dir.mkdirs()
        sources.forEach { f ->
            if (!f.isFile) throw GradleException("Missing license file: $f (run tools/gen-third-party.sh)")
            f.copyTo(File(dir, f.name), overwrite = true)
        }
    }
}
val bundleLicenses = tasks.register<BundleLicenses>("bundleLicenseAssets") {
    group = "build"
    description = "Copies the repo-root license files into assets/licenses/"
    sources.from(listOf("LICENSE", "THIRD_PARTY_NOTICES.md", "THIRD_PARTY_LICENSES.txt").map { rootProject.file("../../$it") })
    outputDir.set(layout.buildDirectory.dir("generated/licenseAssets"))
}

// ── Bundled kernel geodata (contract §20.d, docs/geodata.md) ──────────────────────────────────────
// tools/fetch-geodata.sh pulls the pinned snapshot (geoip.metadb + GeoSite.dat, sha256 from tools/geodata.lock) into
// the repo-root build/geodata cache (skips files whose hash already matches), then the files are copied to the APK's
// assets/geodata/. Nothing is committed. Release builds fail without them; debug builds only warn (offline dev
// machines still build; the app then falls back to mihomo's bounded 15 s download) and retry on the next build.
abstract class BundleGeodata : DefaultTask() {
    @get:InputFile @get:PathSensitive(PathSensitivity.NAME_ONLY) abstract val lockFile: RegularFileProperty
    @get:InputFile @get:PathSensitive(PathSensitivity.NAME_ONLY) abstract val script: RegularFileProperty
    @get:Internal abstract val cacheDir: DirectoryProperty
    @get:Input abstract val required: Property<Boolean>
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @get:Inject abstract val exec: ExecOperations

    /** File names listed in tools/geodata.lock (`<name> <sha256> <url>` per line). */
    fun names(): List<String> = lockFile.get().asFile.readLines()
        .map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }.map { it.split(Regex("\\s+")).first() }

    @TaskAction fun bundle() {
        val dir = outputDir.get().dir("geodata").asFile
        dir.deleteRecursively(); dir.mkdirs()
        val cache = cacheDir.get().asFile
        val log = ByteArrayOutputStream()
        val result = exec.exec {
            commandLine("bash", script.get().asFile.absolutePath, cache.absolutePath)
            standardOutput = log; errorOutput = log; isIgnoreExitValue = true
        }
        val missing = names().filterNot { File(cache, it).isFile }
        if (result.exitValue != 0 || missing.isNotEmpty()) {
            val msg = "Kernel geodata not bundled (tools/fetch-geodata.sh exit ${result.exitValue}, missing $missing):\n$log" +
                "Run tools/fetch-geodata.sh by hand or check the network; see docs/geodata.md."
            if (required.get()) throw GradleException(msg)
            logger.warn("w: $msg\nw: this debug APK ships without geodata (mihomo downloads it on first connect, ≤15 s).")
            return
        }
        names().forEach { File(cache, it).copyTo(File(dir, it), overwrite = true) }
        logger.lifecycle("geodata → assets/geodata: ${names()}")
    }
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(bundleLicenses, BundleLicenses::outputDir)
        val geodata = tasks.register<BundleGeodata>("bundleGeodataAssets${variant.name.replaceFirstChar { it.uppercase() }}") {
            group = "build"
            description = "Fetches the pinned mihomo geodata snapshot into assets/geodata/ (docs/geodata.md)"
            lockFile.set(rootProject.file("../../tools/geodata.lock"))
            script.set(rootProject.file("../../tools/fetch-geodata.sh"))
            cacheDir.set(rootProject.layout.projectDirectory.dir("../../build/geodata"))
            required.set(variant.buildType == "release" || providers.gradleProperty("zephyr.requireGeodata").orNull == "true")
            // A debug build that could not fetch the files is not up to date: try again next build.
            outputs.upToDateWhen { t -> (t as BundleGeodata).names().all { t.outputDir.get().dir("geodata").file(it).asFile.isFile } }
        }
        variant.sources.assets?.addGeneratedSourceDirectory(geodata, BundleGeodata::outputDir)
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
