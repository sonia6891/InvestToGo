plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// Signing for Google Play (spec 9.1): the upload key lives outside the repository. CI decodes it from GitHub Secrets and
// sets these variables; on a computer without them a release build is simply left unsigned.
val uploadKeystore: String? = System.getenv("ETF_UPLOAD_KEYSTORE")

android {
    namespace = "com.sonia.etftogo"
    // Compose and lifecycle 2026.09 need the Android 37 SDK to compile; the app still targets 36 (spec 7.1).
    compileSdk = 37

    defaultConfig {
        applicationId = "com.sonia.etftogo"
        minSdk = 28
        targetSdk = 36
        // Play needs a new code for every upload; CI passes one. The name is the iPhone's MARKETING_VERSION.
        versionCode = System.getenv("ETF_VERSION_CODE")?.toIntOrNull() ?: 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (uploadKeystore != null) {
            create("upload") {
                storeFile = file(uploadKeystore)
                storePassword = System.getenv("ETF_UPLOAD_STORE_PASSWORD")
                keyAlias = System.getenv("ETF_UPLOAD_KEY_ALIAS")
                keyPassword = System.getenv("ETF_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            // Spec 11: development builds sit beside the store build on the same phone.
            applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = false
            if (uploadKeystore != null) signingConfig = signingConfigs.getByName("upload")
        }
    }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions { unitTests.isReturnDefaultValues = true }
}

kotlin { jvmToolchain(17) }

// The launcher icon is the iPhone's own AppIcon.png, copied at build time rather than committed twice (spec 7.2).
abstract class SharedResources : DefaultTask() {
    @get:InputFile abstract val icon: RegularFileProperty
    @get:OutputDirectory abstract val outputDir: DirectoryProperty

    @TaskAction fun copy() {
        val dir = outputDir.get().asFile.resolve("mipmap-nodpi")
        dir.mkdirs()
        icon.get().asFile.copyTo(dir.resolve("ic_launcher.png"), overwrite = true)
    }
}

val sharedRes = tasks.register<SharedResources>("copySharedResources") {
    icon.set(rootProject.layout.projectDirectory.file("../App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
    outputDir.set(layout.buildDirectory.dir("generated/shared-res"))
}

androidComponents {
    onVariants { variant -> variant.sources.res?.addGeneratedSourceDirectory(sharedRes, SharedResources::outputDir) }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.serialization.json)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)

    testImplementation(libs.junit4)
    testImplementation(kotlin("test-junit"))
}
