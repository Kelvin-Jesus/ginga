// MediaCodec low-latency decoding into a Surface, plus the pure configuration planner.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "dev.tab2mac.decoder"
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
    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.junit4)
}
