import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants/api_constants.dart';

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  bool _isConnecting = false;
  Map<String, dynamic>? _lastAlarm;
  final List<Map<String, dynamic>> _messages = [];
  Timer? _reconnectTimer;

  bool get isConnected => _isConnected;
  Map<String, dynamic>? get lastAlarm => _lastAlarm;
  List<Map<String, dynamic>> get messages => List.unmodifiable(_messages);
  bool get hasActiveAlarm => _lastAlarm != null && _lastAlarm!['type'] == 'ALARM_ON';

  void connect() {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;
    _reconnectTimer?.cancel();

    try {
      _subscription?.cancel();
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(ApiConstants.wsUrl));
      
      _subscription = _channel!.stream.listen(
        (data) {
          if (!_isConnected) {
            _isConnected = true;
            _isConnecting = false;
            debugPrint('WS: Berhasil terhubung ke server!');
            notifyListeners();
          }
          try {
            final message = jsonDecode(data.toString()) as Map<String, dynamic>;
            _messages.insert(0, message);
            if (message['type'] == 'ALARM_ON') {
              _lastAlarm = message;
            } else if (message['type'] == 'ALARM_OFF') {
              _lastAlarm = null;
            }
            notifyListeners();
          } catch (e) {
            debugPrint('WS Parse Error: $e');
          }
        },
        onDone: () {
          _handleDisconnect();
        },
        onError: (error) {
          debugPrint('WS Error: $error');
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint('WS Connect Error: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _isConnecting = false;
    if (_isConnected) {
      _isConnected = false;
      notifyListeners();
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      debugPrint('WS: Mencoba reconnect...');
      connect();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _lastAlarm = null;
    notifyListeners();
  }

  void send(Map<String, dynamic> data) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void clearAlarm() {
    _lastAlarm = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
