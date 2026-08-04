import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart';

import 'hlsjs.dart';

var hlsjsBundleUrl = "https://cdn.jsdelivr.net/npm/hls.js@1";

void setHlsjsCdnUrl(String url){
  hlsjsBundleUrl = url;
}

Future<void>? _loadHlsFuture;

Future<void> _loadHls() async {
  var completer = Completer<void>();
  var script = document.createElement('script');
  script.setAttribute('src', hlsjsBundleUrl);
  script.setAttribute('async', '');
  script.addEventListener('load', (void _){completer.complete();}.toJS);
  script.addEventListener('error', (void _){completer.completeError("Error loading Hls.js");}.toJS);
  document.head!.append(script);
  return completer.future;
}

Future<void> loadHls() async {
  _loadHlsFuture ??= _loadHls();
  return _loadHlsFuture;
}

void attachHlsjs(HTMLAudioElement element, String url){
  if (Hls.isSupported()) {
    var hls = Hls(HlsConfig());
    hls.loadSource(url);
    hls.attachMedia(element);
  } else {
    element.src = url;
  }
}