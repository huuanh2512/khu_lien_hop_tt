import 'dart:io';

/// Centralized app configuration.
class AppConfig {
  /// API base URL resolution order:
  /// - API_BASE from --dart-define if provided
  /// - Default server address (update this if your server is hosted elsewhere)
  ///
  /// For local development:
  /// - Android emulator: use 'http://10.0.2.2:3000'
  /// - iOS simulator/others: use 'http://localhost:3000'
  ///
  /// For deployed server, replace with your actual server URL:
  /// Example: 'https://your-server.com' or 'http://your-ip:3000'
  ///
  /// To override at runtime, use: flutter run --dart-define=API_BASE=http://your-server:3000
  static final String apiBase = _resolveApiBase();

  static String _resolveApiBase() {
    const env = String.fromEnvironment('API_BASE');
    if (env.isNotEmpty) return env;

    // Update this with your actual server address
    // If running server locally on your machine and testing on a physical device,
    // use your computer's local network IP (e.g., 'http://192.168.1.x:3000')
    const defaultServer = 'https://khu-lien-hop-tt.onrender.com';

    try {
      if (Platform.isAndroid) {
        const useAndroidEmulatorHost =
            bool.fromEnvironment('USE_ANDROID_EMULATOR_HOST');
        if (useAndroidEmulatorHost) {
          // For Android emulator, 10.0.2.2 maps to host machine's localhost
          return 'http://10.0.2.2:3000';
        }
      }
    } catch (_) {
      // Platform may not be available in some contexts; ignore
    }
    return defaultServer;
  }
}
