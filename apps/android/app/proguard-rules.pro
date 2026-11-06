# kotlinx.serialization route classes for type-safe navigation
-keepclassmembers @kotlinx.serialization.Serializable class com.zephyr.** { *** Companion; }
-keepclasseswithmembers class com.zephyr.** { kotlinx.serialization.KSerializer serializer(...); }
