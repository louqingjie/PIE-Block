import groovy.json.JsonOutput
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val repositoryRoot = rootProject.projectDir.resolve("../../..").canonicalFile
val generatedSdccAssets = layout.buildDirectory.dir("generated/pieblockSdccAssets")
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.isFile) {
        FileInputStream(keystorePropertiesFile).use(::load)
    }
}

val preparePieBlockSdccAssets by tasks.registering(Sync::class) {
    val firmwareRoot = repositoryRoot.resolve("stc32g_sdcc")
    val toolchainRoot = repositoryRoot.resolve("vendor/sdcc-toolchain")
    into(generatedSdccAssets.map { it.dir("pieblock_sdcc") })
    from(firmwareRoot) {
        into("firmware")
        include("build_manifest.json")
        include("include/**")
        include("startup/**")
        include("libraries/**")
        include("projects/ROBOMASTER_INFANTRY/inc/**")
        include("projects/ROBOMASTER_INFANTRY/src/isr.c")
        include("projects/ROBOMASTER_ENGINEER/inc/**")
        include("projects/ROBOMASTER_ENGINEER/src/isr.c")
        exclude("**/*.exe", "**/*.dll", "**/*.hex", "**/*.map", "**/*.rel")
    }
    from(toolchainRoot) {
        into("toolchain")
        include("include/**")
        include("lib/mcs251-large-stack-auto/**")
        include("COPYING", "COPYING3")
        exclude("**/*.exe", "**/*.dll")
    }
    from(repositoryRoot.resolve("packages/pieblock_sdcc_native/LICENSE")) {
        into("licenses")
        rename { "PIE-Block-GPL-3.0-or-later.txt" }
    }
    from(repositoryRoot.resolve("packages/pieblock_sdcc_native/THIRD_PARTY_NOTICES.md")) {
        into("licenses")
    }
    doLast {
        val assetRoot = destinationDir
        val entries = assetRoot.walkTopDown()
            .filter { it.isFile && it.name != "bundle_manifest.json" }
            .map { file ->
                val relative = file.relativeTo(assetRoot).invariantSeparatorsPath
                val digest = MessageDigest.getInstance("SHA-256")
                    .digest(file.readBytes())
                    .joinToString("") { "%02x".format(it) }
                relative to digest
            }
            .sortedBy { it.first }
            .toList()
        require(entries.none { (path, _) ->
            path.endsWith(".exe", ignoreCase = true) ||
                path.endsWith(".dll", ignoreCase = true)
        }) { "Android SDCC 资源包不得包含可执行工具" }
        val fingerprintInput = entries.joinToString("\n") { "${it.first}:${it.second}" }
        val fingerprint = MessageDigest.getInstance("SHA-256")
            .digest(fingerprintInput.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        val manifest = linkedMapOf(
            "format_version" to 1,
            "sdcc_commit" to "912a589d4080c9cd5c5c1faf871c62dd5023580d",
            "fingerprint" to fingerprint,
            "files" to linkedMapOf(*entries.toTypedArray()),
        )
        assetRoot.resolve("bundle_manifest.json")
            .writeText(JsonOutput.prettyPrint(JsonOutput.toJson(manifest)) + "\n")
    }
}

android {
    namespace = "cn.edu.cnu.pieblock_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cn.edu.cnu.pieblock_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs.excludes += "**/armeabi-v7a/**"
    }

    signingConfigs {
        if (keystorePropertiesFile.isFile) {
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
            if (keystorePropertiesFile.isFile) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

android.sourceSets.getByName("main").assets.srcDir(generatedSdccAssets.get().asFile)
tasks.named("preBuild").configure { dependsOn(preparePieBlockSdccAssets) }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
