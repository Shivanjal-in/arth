# Flutter's own rules are added by the Flutter Gradle plugin.
# pdfium / pdfrx and sqflite reach native code through FFI/JNI; keep their entry points.
-keep class io.flutter.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class jp.espresso3389.** { *; }
-dontwarn org.jetbrains.annotations.**
# Flutter references Play Core for deferred components; we don't ship any.
-dontwarn com.google.android.play.core.**
# The ML Kit plugin references every script's recogniser; we bundle Latin only.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
