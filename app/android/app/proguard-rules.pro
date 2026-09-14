# Flutter's own rules are added by the Flutter Gradle plugin.
# pdfium / pdfrx and sqflite reach native code through FFI/JNI; keep their entry points.
-keep class io.flutter.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class jp.espresso3389.** { *; }
-dontwarn org.jetbrains.annotations.**
# Flutter references Play Core for deferred components; we don't ship any.
-dontwarn com.google.android.play.core.**
