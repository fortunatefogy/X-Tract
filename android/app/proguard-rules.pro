# Keep the app's own Kotlin so the method channels stay resolvable.
-keep class com.example.linky.** { *; }

# Flutter embedding and plugin registration are reflective.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_inappwebview bridges native and JS through reflection.
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Chaquopy runs the embedded Python runtime through JNI.
-keep class com.chaquo.python.** { *; }
-dontwarn com.chaquo.python.**
