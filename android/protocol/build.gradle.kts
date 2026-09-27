import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Pure Kotlin/JVM: the wire protocol (PROTOCOL.md v1). No Android dependencies, so it runs
// in plain JVM unit tests and shares the golden vectors with the Swift implementation.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    api(libs.kotlinx.serialization.json)

    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.junit4)
}

tasks.test {
    // protocol/test-vectors lives next to android/ in the repository.
    val vectors = rootProject.layout.projectDirectory.dir("../protocol/test-vectors").asFile.canonicalFile
    systemProperty("ginga.testVectorsDir", vectors.absolutePath)
    inputs.files(fileTree(vectors))
        .withPropertyName("goldenVectors")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}
