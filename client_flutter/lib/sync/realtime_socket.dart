// lib/sync/realtime_socket.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../services/auth_service.dart';
import 'sync_message.dart';

typedef SyncMessageHandler = void Function(SyncMessage msg);
typedef VoidCallback = void Function();

enum RealtimeConnectionState {
  connecting,
  connected,
  disconnected,
  reconnecting,
}

class RealtimeSocket {
  final String url;
  final String workspaceId;
  final SyncMessageHandler onMessage;
  final VoidCallback? onConnected;

  WebSocket? _socket;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  static const int _maxRetryDelaySeconds = 30;
  RealtimeConnectionState _connectionState = RealtimeConnectionState.disconnected;

  RealtimeSocket({
    required this.url,
    required this.workspaceId,
    required this.onMessage,
    this.onConnected,
  });

  RealtimeConnectionState get connectionState => _connectionState;

  Future<void> connect() async {
    if (_connectionState == RealtimeConnectionState.connecting ||
        _connectionState == RealtimeConnectionState.connected) {
      return;
    }

    _connectionState = RealtimeConnectionState.connecting;

    try {
      final token = await AuthService.getToken();
      final uri = Uri.parse(url).replace(
        queryParameters: {
          'workspaceId': workspaceId,
          'token': token ?? '',
        },
      );

      _socket = await WebSocket.connect(
        uri.toString(),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      _connectionState = RealtimeConnectionState.connected;
      _retryCount = 0;

      onConnected?.call();

      _socket!.listen(
        _handleMessage,
        onDone: () {
          _connectionState = RealtimeConnectionState.disconnected;
          _scheduleReconnect();
        },
        onError: (_) {
          _connectionState = RealtimeConnectionState.disconnected;
          _scheduleReconnect();
        },
      );
    } catch (_) {
      _connectionState = RealtimeConnectionState.disconnected;
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic data) {
    if (data is String) {
      final msg = SyncMessage.decode(data);
      onMessage(msg);
    }
  }

  void send(SyncMessage msg) {
    if (_socket == null || _socket!.readyState != WebSocket.open) {
      return;
    }
    _socket!.add(msg.encode());
  }

  int _computeBackoff() {
    final delay = min(pow(2, _retryCount).toInt(), _maxRetryDelaySeconds);
    _retryCount++;
    return delay;
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;

    _connectionState = RealtimeConnectionState.reconnecting;

    final delaySeconds = _computeBackoff();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimer = null;
      connect();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket?.close();
    _socket = null;
    _connectionState = RealtimeConnectionState.disconnected;
    _retryCount = 0;
  }

  void dispose() {
    disconnect();
  }
}
