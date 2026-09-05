plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.spendwise.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.spendwise.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two installs of the same code, side by side on one phone.
    //
    // `live` keeps the original applicationId to the letter, so an existing
    // install and its encrypted ledger are upgraded in place and never
    // touched. `sandbox` is a different application id, which Android treats
    // as a wholly separate app: its own data directory, its own keystore
    // entry, its own notification-listener grant, its own empty ledger to set
    // up from zero.
    flavorDimensions += "install"
    productFlavors {
        create("live") {
            dimension = "install"
        }
        create("sandbox") {
            dimension = "install"
            applicationIdSuffix = ".sandbox"
            versionNameSuffix = "-sandbox"
        }
    }

    buildTypes {
        release {
            // V1 release signing is intentionally supplied by the publisher.
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
