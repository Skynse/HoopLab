# ===========================
# Flutter Core
# ===========================
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# ===========================
# Flutter Plugin System
# ===========================
# Keep all Flutter plugin registrants
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class * extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keepclassmembers class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }

# Keep plugin registration attributes (critical for reflection)
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ===========================
# MethodChannel System
# ===========================
-keep class io.flutter.plugin.common.MethodChannel { *; }
-keep class io.flutter.plugin.common.MethodChannel$** { *; }
-keep class io.flutter.plugin.common.MethodCall { *; }
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler {
    public void onMethodCall(...);
}
-keep class * implements io.flutter.plugin.common.MethodChannel$Result { *; }

# ===========================
# image_picker Plugin
# ===========================
-keep class io.flutter.plugins.imagepicker.** { *; }

# ===========================
# AndroidX Lifecycle
# ===========================
-keep class androidx.lifecycle.DefaultLifecycleObserver { *; }
-keep class androidx.lifecycle.LifecycleOwner { *; }
-keep class androidx.lifecycle.** { *; }
-keep interface androidx.lifecycle.** { *; }

# ===========================
# AndroidX Activity Result API
# ===========================
-keep class androidx.activity.result.** { *; }
-keep class androidx.activity.** { *; }
-keep class androidx.fragment.** { *; }

# ===========================
# AndroidX Core (general)
# ===========================
-keep class androidx.core.** { *; }
-keep class androidx.annotation.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**

# ===========================
# camera Plugin
# ===========================
-keep class io.flutter.plugins.camera.** { *; }

# ===========================
# Native Methods
# ===========================
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# ===========================
# WebView JavaScript Interface
# ===========================
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# ===========================
# Gson (if used by plugins)
# ===========================
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-dontwarn sun.misc.**

# ===========================
# Enums
# ===========================
-keep class * extends java.lang.Enum { *; }

# ===========================
# Suppress Common Warnings
# ===========================
-dontwarn com.google.android.play.core.**
-dontwarn java.beans.**
