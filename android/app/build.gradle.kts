import java.io.FileInputStream
import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()

if (hasKeystoreProperties) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

val requiredReleaseSigningKeys = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)

val missingReleaseSigningKeys = if (hasKeystoreProperties) {
    requiredReleaseSigningKeys.filter {
        keystoreProperties.getProperty(it).isNullOrBlank()
    }
} else {
    requiredReleaseSigningKeys
}

val hasCompleteReleaseSigning =
    hasKeystoreProperties && missingReleaseSigningKeys.isEmpty()

val wantsRelease = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

if (wantsRelease) {
    if (!hasKeystoreProperties) {
        throw GradleException(
            "Missing release signing config: android/key.properties. Copy android/key.properties.example and fill in real values.",
        )
    }

    if (!hasCompleteReleaseSigning) {
        throw GradleException(
            "android/key.properties is missing required values: ${missingReleaseSigningKeys.joinToString(", ")}",
        )
    }
}

android {
    namespace = "com.matthwlabs.cupola"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications requires this even when scheduled
        // notifications are never used: the plugin itself compiles against
        // java.time, which is API 26, so below that it needs the desugared
        // backport or the build fails at D8 with missing classes.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.matthwlabs.cupola"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_secure_storage 10.x requires Android 23+;
        // flutter_local_notifications 22.x requires 24+. Costs nothing worth
        // keeping: 24 is Android 7.0, and everything below it is a rounding
        // error on any current distribution.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasCompleteReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasCompleteReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // Version matched to the one flutter_local_notifications 22.x declares, so
    // the app and the plugin never disagree on which backport is on the path.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
