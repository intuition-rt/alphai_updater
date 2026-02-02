// Implementation web réelle
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class WebJS {
  static dynamic get globalThis => globalContext;
  static dynamic getProperty(dynamic obj, String prop) => (obj as JSObject).getProperty(prop.toJS);
  static void setProperty(dynamic obj, String prop, dynamic value) {
    JSAny? jsValue;
    if (value is JSAny) {
      jsValue = value;
    } else {
      jsValue = (value as Object?).jsify();
    }
    (obj as JSObject).setProperty(prop.toJS, jsValue);
  }
  static bool hasProperty(dynamic obj, String prop) => (obj as JSObject).hasProperty(prop.toJS).toDart;
  static dynamic callMethod(dynamic obj, String method, List args) {
    final jsObj = obj as JSObject;
    final func = jsObj.getProperty(method.toJS) as JSFunction;
    return func.callMethod('apply'.toJS, jsObj, args.jsify() as JSAny);
  }
  static Future promiseToFuture(dynamic promise) => (promise as JSPromise).toDart;
  static dynamic jsify(dynamic object) {
    if (object is JSAny) return object;
    return (object as Object?).jsify();
  }
  static dynamic allowInterop(Function f) {
    if (f is void Function(String, int, int, int)) {
      return f.toJS;
    }
    throw UnimplementedError('allowInterop: Unsupported function type ${f.runtimeType}');
  }
}
