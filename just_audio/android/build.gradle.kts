group = "com.ryanheise.just_audio"
version = "1.0"

val compilerArgs = listOf("-Xlint:deprecation", "-Xlint:unchecked")

buildscript {
    val agpVersion = "9.0.1"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:$agpVersion")
    }
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.addAll(compilerArgs)
}

android {
    namespace = "com.ryanheise.just_audio"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        minSdk = 16
    }

    lint {
        disable.addAll(listOf("AndroidGradlePluginVersion", "InvalidPackage", "GradleDependency", "NewerVersionAvailable"))
    }
}

dependencies {
    val exoplayerVersion = "1.4.1"
    implementation("androidx.media3:media3-exoplayer:$exoplayerVersion")
    implementation("androidx.media3:media3-exoplayer-dash:$exoplayerVersion")
    implementation("androidx.media3:media3-exoplayer-hls:$exoplayerVersion")
    implementation("androidx.media3:media3-exoplayer-smoothstreaming:$exoplayerVersion")
}
