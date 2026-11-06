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
