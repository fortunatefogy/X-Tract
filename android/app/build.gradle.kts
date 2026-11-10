plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.chaquo.python")
}

android {
    namespace = "com.example.linky"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }

    defaultConfig {
        applicationId = "com.example.linky"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
            ndk {
                // The connected device and current target phone are arm64. The
                // embedded Python runtime otherwise multiplies APK size by ABI.
                abiFilters += listOf("arm64-v8a")
            }
    }
    buildTypes {
        release { signingConfig = signingConfigs.getByName("debug") }
    }
}

chaquopy {
    defaultConfig {
        version = "3.11"
        pip {
            install("yt-dlp")
        }
    }
}

flutter { source = "../.." }

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
