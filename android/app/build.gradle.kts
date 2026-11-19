import java.util.Properties
import java.io.File
import java.io.FileInputStream
import java.net.HttpURLConnection
import java.net.URI
import java.util.zip.ZipInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. On CI the workflow restores the keystore from repository
// secrets and exports the CM_* variables (same names the other Zero Trust apps
// use). Locally, put the keystore details in android/key.properties.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// The Matter SDK's Android libraries. The SDK project publishes none, so
// .github/workflows/matter-sdk.yml builds them and keeps them as a release
// of this repository (see matter/README.md). They are fetched once, into
// android/app/libs/matter (not committed), for the release named in
// matter/sdk.env.
val matterSdkDir = file("libs/matter")
val matterSdkTag = rootProject.file("../matter/sdk.env").readLines()
    .first { it.startsWith("MATTER_SDK_TAG=") }
    .substringAfter("=").trim()

fun fetchMatterSdk() {
    val marker = File(matterSdkDir, "$matterSdkTag.fetched")
    if (marker.exists()) return
    val url = "https://github.com/EdoSag/Zero-Trust-Home/releases/download/" +
        "matter-sdk-$matterSdkTag/matter-android-sdk-$matterSdkTag.zip"
    logger.lifecycle("Fetching the Matter SDK libraries $matterSdkTag")
    matterSdkDir.deleteRecursively()
    matterSdkDir.mkdirs()
    val root = matterSdkDir.canonicalFile
    var failure: Exception? = null
    for (attempt in 1..4) {
        try {
            val connection = URI(url).toURL().openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout = 120_000
            connection.instanceFollowRedirects = true
            if (connection.responseCode != 200) {
                throw GradleException("HTTP ${connection.responseCode} for $url")
            }
            ZipInputStream(connection.inputStream.buffered()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    // libs/*.jar and jniLibs/<abi>/*.so, kept under their paths.
                    val target = File(root, entry.name).canonicalFile
                    if (!target.path.startsWith(root.path + File.separator)) {
                        throw GradleException("Unexpected path in the SDK zip: ${entry.name}")
                    }
                    if (entry.isDirectory) {
                        target.mkdirs()
                    } else {
                        target.parentFile.mkdirs()
                        target.outputStream().use { zip.copyTo(it) }
                    }
                }
            }
            failure = null
            break
        } catch (e: Exception) {
            failure = e
            logger.warn("Fetching the Matter SDK failed (attempt $attempt): ${e.message}")
            Thread.sleep(attempt * 5_000L)
        }
    }
    failure?.let {
        throw GradleException(
            "The Matter SDK libraries could not be fetched from $url. They are " +
                "published by the \"Matter SDK for Android\" workflow; see matter/README.md.",
            it,
        )
    }
    if (!File(matterSdkDir, "libs/CHIPController.jar").exists()) {
        throw GradleException("The Matter SDK zip has no libs/CHIPController.jar")
    }
    marker.writeText(url)
}
fetchMatterSdk()

android {
    namespace = "dev.sagron.zerotrusthome"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.sagron.zerotrusthome"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 28: the shared core keeps the biometric unlock key in the Keystore.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (System.getenv("CM_BUILD_DIR") != null) {
                storeFile = file(System.getenv("CM_BUILD_DIR") + "/codemagic.keystore")
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CM_KEY_ALIAS")
                keyPassword = System.getenv("CM_KEY_PASSWORD")
            } else if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir("libs/matter/jniLibs")
        }
    }

    packaging {
        jniLibs {
            // Flutter plugins may bring their own copy.
            pickFirsts += "**/libc++_shared.so"
        }
    }

    buildTypes {
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Without a release keystore (a fresh local checkout), fall back to
            // the debug keys so `flutter run --release` still works.
            signingConfig = if (System.getenv("CM_BUILD_DIR") != null || keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
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
    // The Matter SDK (see fetchMatterSdk above) and what its jars use.
    implementation(fileTree(mapOf("dir" to "libs/matter/libs", "include" to listOf("*.jar"))))
    implementation("com.google.code.findbugs:jsr305:3.0.2")
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("com.google.protobuf:protobuf-java:3.22.0")
}
