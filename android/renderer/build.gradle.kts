// SurfaceView output: latest-frame-wins release, frame-rate voting, aspect fit, render timing.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "dev.ginga.renderer"
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
    api(project(":decoder"))

    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.junit4)
}
