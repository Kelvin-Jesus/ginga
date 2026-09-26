// Root build: plugin versions only. Every module applies what it needs.
//
// Android modules use AGP 9's built-in Kotlin (no org.jetbrains.kotlin.android plugin).
// Declaring the Kotlin plugins here puts the catalog's KGP on the shared build classpath,
// which also upgrades the KGP that built-in Kotlin uses (AGP's own runtime dependency is 2.2.10).
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
