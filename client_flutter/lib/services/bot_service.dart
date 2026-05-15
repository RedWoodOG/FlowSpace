import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'auth_service.dart';

class BotService {
  /// List all bots in a workspace.
  static Future<List<Map<String, dynamic>>> listBots(String workspaceId) async {
    final response = await ApiClient.get('workspaces/$workspaceId/bots');
    if (response is List) {
      return response.cast<Map<String, dynamic>>();
    }
    final data = response as Map<String, dynamic>;
    final bots = data['bots'] as List? ?? [];
    return bots.cast<Map<String, dynamic>>();
  }

  /// Create a new bot.
  static Future<Map<String, dynamic>> createBot(
    String workspaceId, {
    required String name,
    required String displayName,
    String? description,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'displayName': displayName,
    };
    if (description != null) {
      body['description'] = description;
    }
    final response = await ApiClient.post(
      'workspaces/$workspaceId/bots',
      body: body,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Get a single bot by ID.
  static Future<Map<String, dynamic>> getBot(
    String workspaceId,
    String botId,
  ) async {
    final response = await ApiClient.get(
      'workspaces/$workspaceId/bots/$botId',
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Update bot fields.
  static Future<Map<String, dynamic>> updateBot(
    String workspaceId,
    String botId,
    Map<String, dynamic> data,
  ) async {
    final response = await ApiClient.patch(
      'workspaces/$workspaceId/bots/$botId',
      body: data,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Delete a bot.
  static Future<void> deleteBot(String workspaceId, String botId) async {
    await ApiClient.delete('workspaces/$workspaceId/bots/$botId');
  }

  /// Generate a new API key for a bot. Returns `{apiKey, prefix}`.
  static Future<Map<String, dynamic>> generateApiKey(
    String workspaceId,
    String botId,
  ) async {
    final response = await ApiClient.post(
      'workspaces/$workspaceId/bots/$botId/keys',
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// List API keys for a bot.
  static Future<List<Map<String, dynamic>>> listApiKeys(
    String workspaceId,
    String botId,
  ) async {
    final response = await ApiClient.get(
      'workspaces/$workspaceId/bots/$botId/keys',
    );
    if (response is List) {
      return response.cast<Map<String, dynamic>>();
    }
    final data = response as Map<String, dynamic>;
    final keys = data['keys'] as List? ?? [];
    return keys.cast<Map<String, dynamic>>();
  }

  /// Revoke an API key.
  static Future<void> revokeApiKey(
    String workspaceId,
    String botId,
    String keyId,
  ) async {
    await ApiClient.delete(
      'workspaces/$workspaceId/bots/$botId/keys/$keyId',
    );
  }

  /// List slash commands for a bot.
  static Future<List<Map<String, dynamic>>> listCommands(
    String workspaceId,
    String botId,
  ) async {
    final response = await ApiClient.get(
      'workspaces/$workspaceId/bots/$botId/commands',
    );
    if (response is List) {
      return response.cast<Map<String, dynamic>>();
    }
    final data = response as Map<String, dynamic>;
    final commands = data['commands'] as List? ?? [];
    return commands.cast<Map<String, dynamic>>();
  }

  /// Add a slash command to a bot.
  static Future<Map<String, dynamic>> addCommand(
    String workspaceId,
    String botId, {
    required String command,
    required String description,
  }) async {
    final response = await ApiClient.post(
      'workspaces/$workspaceId/bots/$botId/commands',
      body: {'command': command, 'description': description},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Remove a slash command from a bot.
  static Future<void> removeCommand(
    String workspaceId,
    String botId,
    String commandId,
  ) async {
    await ApiClient.delete(
      'workspaces/$workspaceId/bots/$botId/commands/$commandId',
    );
  }

  /// List event subscriptions for a bot.
  static Future<List<Map<String, dynamic>>> listEvents(
    String workspaceId,
    String botId,
  ) async {
    final response = await ApiClient.get(
      'workspaces/$workspaceId/bots/$botId/events',
    );
    if (response is List) {
      return response.cast<Map<String, dynamic>>();
    }
    final data = response as Map<String, dynamic>;
    final events = data['events'] as List? ?? [];
    return events.cast<Map<String, dynamic>>();
  }

  /// Subscribe a bot to an event type.
  static Future<Map<String, dynamic>> subscribeEvent(
    String workspaceId,
    String botId,
    String event,
  ) async {
    final response = await ApiClient.post(
      'workspaces/$workspaceId/bots/$botId/events',
      body: {'event': event},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// Unsubscribe a bot from an event.
  static Future<void> unsubscribeEvent(
    String workspaceId,
    String botId,
    String subId,
  ) async {
    await ApiClient.delete(
      'workspaces/$workspaceId/bots/$botId/events/$subId',
    );
  }

  /// Get the list of available event types across all bots.
  static Future<List<String>> getAvailableEvents() async {
    final response = await ApiClient.get('bots/available-events');
    if (response is List) {
      return response.cast<String>();
    }
    final data = response as Map<String, dynamic>;
    final events = data['events'] as List? ?? [];
    return events.cast<String>();
  }
}
