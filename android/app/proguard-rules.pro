# Keep Flutter core classes
-keep class io.flutter.app.** { *; }
# Flutter core - must keep everything
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep file_picker plugin
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class androidx.lifecycle.** { *; }

# Keep camerawesome plugin
-keep class com.apparence.camerawesome.** { *; }

# Keep AndroidX classes
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**

# Keep Activity Result API (required by file_picker)
-keep class androidx.activity.result.** { *; }
# DO NOT obfuscate MethodChannel implementations
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler {
    public void onMethodCall(...);
}

# Keep all MethodChannel.Result implementations
-keep class * implements io.flutter.plugin.common.MethodChannel$Result { *; }

# file_picker - keep EVERYTHING
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keepclassmembers class com.mr.flutter.plugin.filepicker.** { *; }

# camerawesome plugin
-keep class com.apparence.camerawesome.** { *; }

# AndroidX - required by file_picker
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**

# Activity Result API (required by file_picker)
-keep class androidx.activity.result.** { *; }
-keep class androidx.activity.** { *; }
-keep class androidx.fragment.** { *; }
-keep class androidx.lifecycle.** { *; }

# Keep native methods
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Keep methods called from native code
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Gson (if used by plugins)
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Keep all model classes
-keep class * extends java.lang.Enum { *; }

# Suppress warnings
# Keep all Flutter plugin registrants
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class * extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }

# Keep native methods
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Keep MethodChannel and related classes
-keep class io.flutter.plugin.common.MethodChannel { *; }
-keep class io.flutter.plugin.common.MethodChannel$** { *; }
-keep class io.flutter.plugin.common.MethodCall { *; }

# Suppress warnings
-dontwarn com.google.android.play.core.**
-dontwarn java.beans.**
