pluginManagement {
    includeBuild("../.dart_tool/flutter_build")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("dev.flutter.flutter-plugin-loader") version "1.0.0"
        id("com.android.application") version "8.7.0"
        id("org.jetbrains.kotlin.android") version "2.0.21"
    }
}
plugins {
    id("dev.flutter.flutter-plugin-loader")
}
include(":app")
