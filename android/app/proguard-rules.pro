# Flutter Wrapper & Engine
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep native methods (required for Dart FFI / llama.cpp / JNI bridges)
-keepclasseswithmembernames class * {
    native <methods>;
}

# flutter_local_notifications (Scheduled alarms & boot receiver)
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes *Annotation*
-keepattributes Signature

# Keep BroadcastReceivers and Services declared in AndroidManifest.xml
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.app.Service

# Suppress harmless warnings from optional Flutter Play Core deferred components & desugaring
-dontwarn com.google.android.play.core.**
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
