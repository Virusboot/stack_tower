# Flutter Engine and Plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.util.** { *; }
-dontwarn io.flutter.**

# Google Mobile Ads (AdMob) - Completely Preserved
-keep class com.google.android.gms.ads.** { *; }
-keep interface com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-keep interface com.google.ads.** { *; }
-keep class com.google.android.gms.internal.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
-dontwarn com.google.ads.**
-dontwarn com.google.android.gms.internal.ads.**

# Google Play Services & Tasks
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-dontwarn com.google.android.gms.common.**
-dontwarn com.google.android.gms.tasks.**

# Application Packages
-keep class com.stacktower.game.stack_tower.** { *; }
-keep class com.stacktower.casual.game.** { *; }

# AndroidX, SharedPreferences & JNI
-keep class androidx.datastore.** { *; }
-keep class androidx.preference.** { *; }
-keep class androidx.startup.** { *; }
-keep class androidx.work.** { *; }
-keep class androidx.lifecycle.** { *; }
-keep class com.github.dart_lang.jni.** { *; }

# Preserve reflection, annotations, line numbers and native JNI methods
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes SourceFile,LineNumberTable
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve view getters/setters and activity onClick handlers
-keepclassmembers public class * extends android.view.View {
    void set*(***);
    *** get*();
}
-keepclassmembers class * extends android.app.Activity {
    public void *(android.view.View);
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
