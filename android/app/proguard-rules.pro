# UniFFI / JNA — keep native bridge classes
-dontwarn com.sun.jna.**
-keep class com.sun.jna.** { *; }
-keep class uniffi.** { *; }
-keepclassmembers class * extends com.sun.jna.Structure { *; }
