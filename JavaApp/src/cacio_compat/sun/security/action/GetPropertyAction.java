package sun.security.action;

import java.security.AccessController;
import java.security.PrivilegedAction;

// Caciocavallo17 still references this JDK internal class, but it is gone on Java 25.
@SuppressWarnings("removal")
public final class GetPropertyAction implements PrivilegedAction<String> {
    private final String key;
    private final String defaultValue;

    public GetPropertyAction(String key) {
        this(key, null);
    }

    public GetPropertyAction(String key, String defaultValue) {
        this.key = key;
        this.defaultValue = defaultValue;
    }

    @Override
    public String run() {
        return System.getProperty(key, defaultValue);
    }

    public static String privilegedGetProperty(String key) {
        if (System.getSecurityManager() == null) {
            return System.getProperty(key);
        }
        return AccessController.doPrivileged(new GetPropertyAction(key));
    }

    public static String privilegedGetProperty(String key, String defaultValue) {
        if (System.getSecurityManager() == null) {
            return System.getProperty(key, defaultValue);
        }
        return AccessController.doPrivileged(new GetPropertyAction(key, defaultValue));
    }
}
