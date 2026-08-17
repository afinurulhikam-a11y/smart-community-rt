import 'dart:js_interop';

@JS('simpanKredensialWeb')
external void _simpanKredensialWeb(JSString username, JSString password);

/// Panggil Credential Management API via window.simpanKredensialWeb di web.
void simpanKredensialWeb(String username, String password) {
  try {
    _simpanKredensialWeb(username.toJS, password.toJS);
  } catch (_) {
    // Abaikan bila peramban tidak mendukung Credential Management API.
  }
}
