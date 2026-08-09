# Keep ProGuard rules for release builds.
# The Compose compiler and Room generate code that should not be obfuscated.
-keep class com.huochang.yard.data.local.** { *; }
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-keepclassmembers class * {
    @androidx.room.* <methods>;
}
-dontwarn org.jetbrains.annotations.**
