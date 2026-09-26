// Bonjour discovery of Macs (`_tab2mac._tcp`) for the Wi‑Fi transport (M7).
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "dev.tab2mac.discovery"
    compileSdk = 36

    defaultConfig {
        minSdk = 31
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    api(libs.kotlinx.coroutines.core)

    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.junit4)
}
