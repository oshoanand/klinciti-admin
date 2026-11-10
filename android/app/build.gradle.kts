plugins {
    id("com.android.application")
    // Note: 'kotlin-android' is removed here because AGP 9.0+ has Kotlin built-in!
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.klincitiadmin.app"
    // ✅ CHANGED: Hardcoded to 36 to fix the flutter_ringtone_player error
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true 
    }

    defaultConfig {
        applicationId = "com.klincitiadmin.app"
        minSdk = flutter.minSdkVersion 
        // ✅ CHANGED: Hardcoded to 36 to match compileSdk
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}