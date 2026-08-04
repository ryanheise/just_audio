// @JS()
// library hls.js;

import 'dart:js_interop';
import 'package:web/web.dart' as web;

@JS()
@staticInterop
class Hls {
  external factory Hls(HlsConfig config);
  external static bool isSupported();
}

extension HlsExtension on Hls {
  external void stopLoad();
  external void loadSource(String videoSrc);
  external void attachMedia(web.HTMLElement video);
  external void on(String event, JSFunction callback);
  external HlsConfig config;
}

@JS()
@anonymous
@staticInterop
class HlsConfig {
  external factory HlsConfig({JSFunction xhrSetup});
}

extension HlsConfigExtension on HlsConfig {
  external JSFunction get xhrSetup;
}

class ErrorData {
  late final String type;
  late final String details;
  late final bool fatal;

  ErrorData(dynamic errorData) {
    type = errorData.type as String;
    details = errorData.details as String;
    fatal = errorData.fatal as bool;
  }
}
