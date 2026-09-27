// Moves framed protocol messages over a byte stream: TCP through `adb reverse` today,
// Android Open Accessory (M6) and Wi‑Fi (M7) later.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "dev.ginga.transport"
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
    api(project(":protocol"))
    api(libs.kotlinx.coroutines.core)

    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.junit4)
    testImplementation(libs.kotlinx.coroutines.test)
}
