# Keep SnakeYAML classes
-keep class org.yaml.snakeyaml.** { *; }
-dontwarn java.beans.**
-dontwarn org.yaml.snakeyaml.**

# Keep R8 from removing classes that might be needed at runtime
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.fasterxml.jackson.annotation.* <fields>;
    @com.fasterxml.jackson.annotation.* <methods>;
}

-keep class org.xmlpull.** { *; }
