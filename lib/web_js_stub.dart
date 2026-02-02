// Stub pour les plateformes non-web
class WebJS {
  static dynamic get globalThis => throw UnsupportedError('Web only');
  static dynamic getProperty(dynamic obj, String prop) => throw UnsupportedError('Web only');
  static void setProperty(dynamic obj, String prop, dynamic value) => throw UnsupportedError('Web only');
  static bool hasProperty(dynamic obj, String prop) => throw UnsupportedError('Web only');
  static dynamic callMethod(dynamic obj, String method, List args) => throw UnsupportedError('Web only');
  static Future promiseToFuture(dynamic promise) => throw UnsupportedError('Web only');
  static dynamic jsify(dynamic object) => throw UnsupportedError('Web only');
  static dynamic allowInterop(Function f) => throw UnsupportedError('Web only');
}
