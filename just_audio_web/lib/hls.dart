@JS()
library hls.js;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart';

@JS('Hls.isSupported')
external bool isSupported();

extension type Hls._(JSObject _) implements JSObject {
  external factory Hls(HlsConfig config);

  external void stopLoad();
  external void loadSource(String videoSrc);
  external void attachMedia(HTMLAudioElement video);
  external void on(String event, JSFunction callback);

  external HlsConfig get config;
}

extension type HlsConfig._(JSObject _) implements JSObject {
  external factory HlsConfig({JSFunction xhrSetup, JSBoolean debug});
  external JSFunction get xhrSetup;
  external JSBoolean get debug;
}

class HlsError {
  late final String type;
  late final String details;
  late final bool fatal;

  HlsError(JSObject errorData) {
    type = errorData.getProperty<JSString>("type".toJS).toDart;
    details = errorData.getProperty<JSString>("details".toJS).toDart;
    fatal = errorData.getProperty<JSBoolean>("fatal".toJS).toDart;
  }
}
