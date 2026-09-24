import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.maboy.player"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The previous ID was distributed with two different signing keys.
        // A new stable ID prevents Android from treating this release as an
        // invalid update of the legacy debug-signed package.
        applicationId = "com.maboy.player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keyPropertiesFile = rootProject.file("key.properties")
    val hasKeyProperties = keyPropertiesFile.exists()

    if (hasKeyProperties) {
        val signingProperties = Properties().apply {
            keyPropertiesFile.inputStream().use(::load)
        }
        signingConfigs {
            create("release") {
                val storeFilePath = signingProperties.getProperty("storeFile")
                storeFile = if (file(storeFilePath).exists()) file(storeFilePath) else rootProject.file(storeFilePath)
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasKeyProperties) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                error("Missing android/key.properties! Release APK must be signed with official maboy_release.jks to prevent package update conflicts.")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
