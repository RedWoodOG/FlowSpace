// lib/sync/sync_manager.dart

import 'package:flutter/material.dart';

import 'realtime_socket.dart';
import 'sync_message.dart';
import 'sync_buffer.dart';
import 'merge_engine.dart';
import 'op_queue.dart';
import 'version_vector.dart';
import 'sync_channel_router.dart';

class SyncManager extends ChangeNotifier {
  static final SyncManager instance = SyncManager._internal();

  late final RealtimeSocket _socket;
  final SyncBuffer buffer = SyncBuffer();
  final OpQueue opQueue = OpQueue();
  final VersionVector versionVector = VersionVector();
  final MergeEngine merge = MergeEngine();
  final SyncChannelRouter router = SyncChannelRouter();

  final Set<String> _seenEventIds = {};
  static const int _maxDedupEntries = 1000;

  String clientId = '';
  String? _projectId;
  String? _channelId;
  bool connected = false;

  SyncManager._internal();

  /// Initialize with project and channel scope
  void initialize({
    required String url,
    required String clientId,
    String workspaceId = '',
    String? projectId,
    String? channelId,
  }) {
    this.clientId = clientId;
    _projectId = projectId;
    _channelId = channelId;

    // Build scoped URL: ws://host/sync/{projectId}/{channelId}
    final scopedUrl = _buildScopedUrl(url, projectId, channelId);

    _socket = RealtimeSocket(
      url: scopedUrl,
      workspaceId: workspaceId,
      onMessage: _handleIncoming,
      onConnected: _clearDedupCache,
    );

    _socket.connect();
    _startFlushLoop();
  }

  /// Set active project and channel scope
  void setScope({required String? projectId, String? channelId}) {
    if (_projectId == projectId && _channelId == channelId) return;

    print('[SyncManager] Scope changed: project=$projectId, channel=$channelId');
    _projectId = projectId;
    _channelId = channelId;

    // Reconnect with new scope
    if (connected) {
      _socket.disconnect();
      // Note: URL was already set in initialize, need to update if scope changes
    }
  }

  String _buildScopedUrl(String baseUrl, String? projectId, String? channelId) {
    if (projectId == null) return baseUrl;
    final path = channelId != null ? '$projectId/$channelId' : projectId;
    return baseUrl.replaceFirst('/sync', '/sync/$path');
  }

  void send(String boardId, String opType, Map<String, dynamic> payload) {
    versionVector.increment(clientId);

    final msg = SyncMessage(
      boardId: boardId,
      opType: opType,
      payload: {
        ...payload,
        'clientId': clientId,
        'version': versionVector.get(clientId),
        'projectId': _projectId, // Add project scope to every operation
        'channelId': _channelId, // Add channel scope to every operation
      },
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    opQueue.enqueue(msg);
  }

  void _handleIncoming(SyncMessage msg) {
    final client = msg.payload['clientId'];
    final version = msg.payload['version'];

    // Deduplicate by clientId-version-boardId combo
    final eventId = '$client-$version-${msg.boardId}';
    if (isDuplicate(eventId)) return;

    if (client != null && version != null) {
      versionVector.update(client, version);
    }

    router.route(msg);
    merge.apply(msg);
  }

  /// Check if an event ID has already been processed.
  bool isDuplicate(String eventId) {
    if (_seenEventIds.contains(eventId)) return true;
    _seenEventIds.add(eventId);
    while (_seenEventIds.length > _maxDedupEntries) {
      _seenEventIds.remove(_seenEventIds.first);
    }
    return false;
  }

  void _clearDedupCache() {
    _seenEventIds.clear();
  }

  void _startFlushLoop() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 80));

      final next = opQueue.nextToSend();
      if (next != null) {
        _socket.send(next);
      }

      return true;
    });
  }

  void acknowledge(SyncMessage msg) {
    opQueue.ack(msg);
  }

  void retryPending() {
    opQueue.retryUnacked();
  }
}
