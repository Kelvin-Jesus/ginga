// Touch and S Pen capture → protocol INPUT messages (M5).
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "dev.tab2mac.input"
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

    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.junit4)
}
