# The Matter SDK is called from its native code by class and method name.
-keep class chip.** { *; }
-keep class matter.** { *; }
-dontwarn chip.**
-dontwarn matter.**
-dontwarn javax.annotation.**
-dontwarn com.google.protobuf.**
