// android/settings.gradle.kts

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    // Pobieramy ścieżkę Flutter SDK z local.properties (flutter.sdk)
    val flutterSdkPath = run {
        val props = java.util.Properties()
        file("local.properties").inputStream().use { props.load(it) }
        val path = props.getProperty("flutter.sdk")
        require(path != null) { "flutter.sdk not set in local.properties" }
        path
    }

    // Wpięcie narzędzi Fluttera
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
}

// ✅ Wersje pluginów deklarujemy w settings.gradle.kts (Kotlin DSL)
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
