# The Matter SDK is called from its native code by class and method name.
-keep class chip.** { *; }
-keep class matter.** { *; }
# So are the callbacks and the phone key this app hands to it.
-keep class dev.sagron.zerotrusthome.Matter** { *; }
-dontwarn chip.**
-dontwarn matter.**
-dontwarn javax.annotation.**
-dontwarn com.google.protobuf.**
