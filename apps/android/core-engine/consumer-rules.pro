# UniFFI / JNA bindings (CoreEngine, Mihomo) are reflected by name: Structure fields, Library
# interfaces and callback interfaces must survive R8 untouched.
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-keep class uniffi.** { *; }
-keep class com.zephyr.core.mobile.** { *; }
-keep class com.zephyr.engine.core.Mihomo** { *; }
-dontwarn java.awt.**
-dontwarn com.sun.jna.**
