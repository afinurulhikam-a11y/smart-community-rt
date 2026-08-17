import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';

JSObject get _document => globalContext.getProperty('document'.toJS) as JSObject;

bool isSupportedFullscreen() {
  try {
    return _document.hasProperty('fullscreenEnabled'.toJS).toDart;
  } catch (_) {
    return false;
  }
}

bool isCurrentlyFullscreen() {
  try {
    final elem = _document.getProperty('fullscreenElement'.toJS);
    return elem.isDefinedAndNotNull;
  } catch (_) {
    return false;
  }
}

Future<void> toggleFullscreen() async {
  try {
    final doc = _document;
    final elem = doc.getProperty('fullscreenElement'.toJS);
    if (elem.isDefinedAndNotNull) {
      doc.callMethod('exitFullscreen'.toJS);
    } else {
      final docElem = doc.getProperty('documentElement'.toJS) as JSObject?;
      docElem?.callMethod('requestFullscreen'.toJS);
    }
  } catch (e) {
    debugPrint('Fullscreen error: $e');
  }
}

final List<VoidCallback> _listeners = [];
bool _listenerInitialized = false;

void _onFullscreenChange(JSAny? event) {
  for (final cb in List.of(_listeners)) {
    cb();
  }
}

void addFullscreenListener(VoidCallback callback) {
  if (!_listenerInitialized) {
    try {
      _document.callMethod(
        'addEventListener'.toJS,
        'fullscreenchange'.toJS,
        _onFullscreenChange.toJS,
      );
      _listenerInitialized = true;
    } catch (_) {}
  }
  _listeners.add(callback);
}

void removeFullscreenListener(VoidCallback callback) {
  _listeners.remove(callback);
}
