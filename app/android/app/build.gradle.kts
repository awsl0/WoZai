plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wozai.wozai_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wozai.wozai_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 统一签名：使用仓库内的 app/android/debug.keystore（本地与 CI 同一把 key，保证覆盖安装）
            // 密码/别名可用环境变量覆盖，默认 android/androiddebugkey
            signingConfig = signingConfigs.create("wozai") {
                storeFile = file("debug.keystore")
                storePassword = System.getenv("WOZAI_KEYSTORE_PASS") ?: "android"
                keyAlias = System.getenv("WOZAI_KEY_ALIAS") ?: "androiddebugkey"
                keyPassword = System.getenv("WOZAI_KEY_PASS") ?: "android"
                // 开启 v1 签名，兼容 Android 7.0 以下设备（否则会报"包已损坏/解析失败"）
                enableV1Signing = true
                enableV2Signing = true
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
