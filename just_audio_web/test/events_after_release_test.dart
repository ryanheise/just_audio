@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_web/just_audio_web.dart';
import 'package:web/web.dart';

void main() {
  test('media events after release() do not throw', () async {
    // The player's audio element is private and never attached to the page, so
    // catch it as it is created.
    globalContext.callMethod(
      'eval'.toJS,
      '''
      window.__audioElements = [];
      const create = Document.prototype.createElement;
      Document.prototype.createElement = function (tag, ...rest) {
        const element = create.call(this, tag, ...rest);
        if (String(tag).toLowerCase() === 'audio') window.__audioElements.push(element);
        return element;
      };
      '''
          .toJS,
    );
    final player = Html5AudioPlayer(id: 'player');
    final audioElements = globalContext
        .getProperty<JSArray<HTMLAudioElement>>('__audioElements'.toJS)
        .toDart;
    expect(audioElements, hasLength(1));
    final element = audioElements.single;

    // An exception in an element's event listener is reported to the window,
    // not to the test's zone.
    final errors = <String>[];
    final onError = ((ErrorEvent event) => errors.add(event.message)).toJS;
    window.addEventListener('error', onError);
    addTearDown(() => window.removeEventListener('error', onError));

    await player.release();

    // The element keeps firing events after release closed the event stream.
    for (final type in [
      'progress',
      'loadstart',
      'waiting',
      'stalled',
      'canplaythrough',
      'error'
    ]) {
      element.dispatchEvent(Event(type));
    }
    await Future<void>.delayed(Duration.zero);

    expect(errors, isEmpty);
  });
}
