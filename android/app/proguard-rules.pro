# ProGuard/R8 rules for Blackout Kit.
#
# Release builds run with minifyEnabled + shrinkResources. Most of the keeps
# below are the standard set a Flutter app needs; the libv2ray/go rules are
# already contributed by libv2ray.aar's own proguard.txt, but they are repeated
# here so the dependency between the core and reflection is explicit rather than
# implicit in a binary.

# ── Flutter engine and generated plugin registrant ──────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# ── gomobile-bound Xray core ────────────────────────────────────────────────
# libv2ray.CoreController and the go.Seq runtime are reached through JNI and
# reflection; R8 cannot see those references and would strip them.
-keep class go.** { *; }
-keep class libv2ray.** { *; }
-keepclassmembers class go.** { *; }
-keepclassmembers class libv2ray.** { *; }

# ── Plugins registered manually in MainActivity ─────────────────────────────
# VpnPlugin and NetworkPlugin are added with flutterEngine.plugins.add(...) and
# are never referenced from Dart, so R8 has no other reason to keep them.
-keep class com.blackoutkit.vpn.VpnPlugin { *; }
-keep class com.blackoutkit.vpn.NetworkPlugin { *; }
-keep class com.blackoutkit.vpn.MainActivity { *; }
-keep class com.blackoutkit.vpn.BlackoutVpnService { *; }

# ── Android components referenced only from the manifest ────────────────────
-keep class * extends android.app.Service
-keep class * extends android.app.Activity

# ── Library reflection ─────────────────────────────────────────────────────
# Hive, GetX and the JSON codecs resolve members by name at runtime.
-keep class * extends com.google.gson.TypeAdapter
-dontwarn com.google.gson.**
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod

# keep_annotations
-keep @interface *

# Coroutines / Kotlin metadata used by the Kotlin stdlib.
-dontwarn kotlin.**
-dontwarn kotlinx.**
-keep class kotlin.Metadata { *; }

# ── Flutter deferred components ─────────────────────────────────────────────
# The engine references Play Core's split-install API for deferred components.
# This app does not use them, so the classes are absent by design and R8's
# missing-class warnings are noise. Flutter's own template ships these too.
-dontwarn com.google.android.play.core.**
