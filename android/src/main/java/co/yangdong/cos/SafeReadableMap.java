package co.yangdong.cos;


import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;

public class SafeReadableMap {
    public static String safeGetString(ReadableMap options, String key) {
        try {
            return options.getString(key);
        } catch (Exception e) {
            return null;
        }
    }

    public static int safeGetInt(ReadableMap options, String key) {
        try {
            return options.getInt(key);
        } catch (Exception e) {
            return -1;
        }
    }

    public static double safeGetDouble(ReadableMap options, String key) {
        try {
            return options.getDouble(key);
        } catch (Exception e) {
            return -1;
        }
    }

    public static ReadableArray safeGetArray(ReadableMap options, String key) {
        try {
            return options.getArray(key);
        } catch (Exception e) {
            return Arguments.createArray();
        }
    }
}

