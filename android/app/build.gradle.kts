// The receiver app: connection screen, fullscreen stream, session logic, diagnostics.
plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "dev.ginga.receiver"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.ginga.receiver"
        minSdk = 31
        targetSdk = 36
        // Release builds pass -Pginga.version=X.Y.Z (the git tag); the code follows from it.
        val version = providers.gradleProperty("ginga.version").orNull
        versionName = version ?: "0.1.0"
        versionCode = version?.substringBefore('-')?.split('.')
            ?.let { (major, minor, patch) -> major.toInt() * 10_000 + minor.toInt() * 100 + patch.toInt() }
            ?: 1
    }

    // The release key lives outside the repo (scripts/setup-release-signing.sh); CI decodes it
    // from secrets. Without GINGA_KEYSTORE the release APK is left unsigned.
    val keystore = providers.environmentVariable("GINGA_KEYSTORE").orNull
    signingConfigs {
        if (keystore != null) {
            create("release") {
                storeFile = file(keystore)
                storePassword = providers.environmentVariable("GINGA_KEYSTORE_PASSWORD").get()
                keyAlias = providers.environmentVariable("GINGA_KEY_ALIAS").orNull ?: "ginga"
                keyPassword = providers.environmentVariable("GINGA_KEY_PASSWORD").orNull ?: storePassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (keystore != null) signingConfig = signingConfigs.getByName("release")
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
    systemProperty("ginga.appMainDir", main.absolutePath)
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
