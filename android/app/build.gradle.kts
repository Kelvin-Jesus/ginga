// The receiver app: connection screen, fullscreen stream, session logic, diagnostics.
plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "dev.tab2mac.receiver"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.tab2mac.receiver"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

tasks.withType<Test>().configureEach {
    // AccessoryFilterTest checks the manifest and res/xml/accessory_filter.xml against the
    // accessory identity the Mac sends; StringsTest checks the translations.
    val main = layout.projectDirectory.dir("src/main").asFile
    systemProperty("t2m.appMainDir", main.absolutePath)
    inputs.files(fileTree(main) { include("AndroidManifest.xml", "res/xml/**", "res/values*/strings.xml") })
        .withPropertyName("manifestAndXmlResources")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

dependencies {
    implementation(project(":protocol"))
    implementation(project(":transport"))
    implementation(project(":decoder"))
    implementation(project(":renderer"))
    implementation(project(":input"))
    implementation(project(":discovery"))
    implementation(libs.kotlinx.coroutines.android)

    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.junit4)
    testImplementation(libs.kotlinx.coroutines.test)
}
