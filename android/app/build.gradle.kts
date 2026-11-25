import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名材料不入库；缺文件时 release 构建报错，debug 构建不受影响。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.transon_top.seekchat"
    // permission_handler_android 14.x 要求客户端至少编译到 API 37。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.transon_top.seekchat"
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

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            // 缺键不在这里抛错，交给 preReleaseBuild 的任务检查，debug 配置不受影响。
            create("release") {
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 不再回退 debug 签名；材料缺失时由下面的任务钩子给出明确错误。
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// 缺签名材料时立即失败。没有 signingConfig 时 AGP 不创建 validateSigningRelease，
// 会静默产出未签名 APK，所以把检查挂在 release 变体最早的构建任务上。
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        if (!keystorePropertiesFile.exists()) {
            throw GradleException(
                "缺少 android/key.properties：release 构建必须使用正式签名，见 docs/runbooks/release.md",
            )
        }
        val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
            .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "android/key.properties 缺少 ${missing.joinToString()}：见 docs/runbooks/release.md",
            )
        }
        val storePath = keystoreProperties.getProperty("storeFile")
        if (!file(storePath).exists()) {
            throw GradleException(
                "release keystore 不存在（$storePath）：见 docs/runbooks/release.md",
            )
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
