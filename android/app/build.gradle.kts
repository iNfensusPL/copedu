// android/app/build.gradle.kts
import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("org.jetbrains.kotlin.android")
    // Flutter plugin MUSI być po Android/Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

// Wczytanie podpisu z key.properties (jeśli jest)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    println("✔ Loaded signing config from ${keystorePropertiesFile.absolutePath}")
} else {
    println("⚠ key.properties not found. Using debug signing for release.")
}

android {
    namespace = "com.ptoo.copedu"

    // mobile_scanner wymaga compileSdk 36
    compileSdk = 36

    // Firebase/niektóre pluginy wymagają NDK 27
    ndkVersion = "27.0.12077973"

    compileOptions {
        // AGP 8.x wymaga Javy 17
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.ptoo.copedu"
        // CameraX / mobile_scanner wymagają co najmniej 23
        minSdk = 23
        // pozwól Flutterowi zarządzać targetSdk
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasKeystore) {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                    ?: throw GradleException("key.properties missing 'storeFile'")
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: throw GradleException("key.properties missing 'storePassword'")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: throw GradleException("key.properties missing 'keyAlias'")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: throw GradleException("key.properties missing 'keyPassword'")
            }
        }
    }

    buildTypes {
        getByName("release") {
            // podpisujemy releasa naszym kluczem (jeśli jest); w przeciwnym razie poleci debug
            signingConfig = if (hasKeystore)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")

            // aby uniknąć komunikatu o shrinkResources wymagającym minifyEnabled:
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("debug") {
            // nic specjalnego
        }
    }
}

// === Skopiuj APK do ścieżki, której oczekuje Flutter (poza /android) ===
val flutterProjectRoot = rootProject.projectDir.parentFile
val flutterApkOutDir = File(flutterProjectRoot, "build/app/outputs/flutter-apk")

val copyReleaseApkToFlutter by tasks.register<Copy>("copyReleaseApkToFlutter") {
    // skąd: standardowe miejsce AGP
    from(layout.buildDirectory.dir("outputs/apk/release"))
    include("*.apk")

    // dokąd: katalog na poziomie ROOT projektu Flutter (nie w /android)
    into(flutterApkOutDir)

    // Flutter oczekuje nazwy app-release.apk gdy nie ma split-per-abi
    rename { "app-release.apk" }

    doLast {
        println("✓ APK skopiowany do: $flutterApkOutDir")
    }
}

// Podepnij się po zbudowaniu release
tasks.configureEach {
    if (name == "packageRelease" || name == "assembleRelease") {
        finalizedBy(copyReleaseApkToFlutter)
    }
}

flutter {
    source = "../.."
}
