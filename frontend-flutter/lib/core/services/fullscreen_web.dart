// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

bool isSupportedFullscreen() {
  return html.document.fullscreenEnabled ?? false;
}

bool isCurrentlyFullscreen() {
  return html.document.fullscreenElement != null;
}

Future<void> toggleFullscreen() async {
  try {
    if (html.document.fullscreenElement != null) {
      html.document.exitFullscreen();
    } else {
      html.document.documentElement?.requestFullscreen();
    }
  } catch (e) {
    debugPrint('Fullscreen error: $e');
  }
}

final List<VoidCallback> _listeners = [];
bool _listenerInitialized = false;

void _onFullscreenChange(html.Event event) {
  for (final cb in List.of(_listeners)) {
    cb();
  }
}

void addFullscreenListener(VoidCallback callback) {
  if (!_listenerInitialized) {
    html.document.addEventListener('fullscreenchange', _onFullscreenChange);
    _listenerInitialized = true;
  }
  _listeners.add(callback);
}

void removeFullscreenListener(VoidCallback callback) {
  _listeners.remove(callback);
}
