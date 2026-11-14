import org.gradle.api.tasks.Sync

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val webRoot = rootProject.projectDir.parentFile
val webAssetsDir = layout.buildDirectory.dir("generated/launcherAssets")
val copyLauncherWebAssets by tasks.registering(Sync::class) {
    from(webRoot.resolve("index.html")) { into("www") }
    from(webRoot.resolve("assets")) { into("www/assets") }
    into(webAssetsDir)
}

android {
    namespace = "com.neeflow.launcher"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.neeflow.launcher"
        minSdk = 23
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    sourceSets.getByName("main").assets.srcDir(webAssetsDir)

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(copyLauncherWebAssets)
}

dependencies {
    implementation("androidx.webkit:webkit:1.12.1")
}
