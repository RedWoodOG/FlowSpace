import 'package:flutter/material.dart';
import '../../services/bot_service.dart';

class BotDetailScreen extends StatefulWidget {
  final String workspaceId;
  final String botId;
  final String botName;

  const BotDetailScreen({
    super.key,
    required this.workspaceId,
    required this.botId,
    required this.botName,
  });

  @override
  State<BotDetailScreen> createState() => _BotDetailScreenState();
}

class _BotDetailScreenState extends State<BotDetailScreen> {
  Map<String, dynamic>? _bot;
  List<Map<String, dynamic>> _keys = [];
  List<Map<String, dynamic>> _commands = [];
  List<Map<String, dynamic>> _events = [];
  List<String> _availableEvents = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        BotService.getBot(widget.workspaceId, widget.botId),
        BotService.listApiKeys(widget.workspaceId, widget.botId),
        BotService.listCommands(widget.workspaceId, widget.botId),
        BotService.listEvents(widget.workspaceId, widget.botId),
        BotService.getAvailableEvents(),
      ]);
      setState(() {
        _bot = results[0] as Map<String, dynamic>;
        _keys = results[1] as List<Map<String, dynamic>>;
        _commands = results[2] as List<Map<String, dynamic>>;
        _events = results[3] as List<Map<String, dynamic>>;
        _availableEvents = results[4] as List<String>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _generateKey() async {
    try {
      final result = await BotService.generateApiKey(widget.workspaceId, widget.botId);
      final apiKey = result['apiKey'] as String;
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('API Key Generated'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Copy this key now. You won\'t see it again.',
                  style: TextStyle(color: Colors.orange)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    apiKey,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _loadAll();
                },
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate key: $e')),
        );
      }
    }
  }

  Future<void> _revokeKey(String keyId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Key'),
        content: const Text('This key will no longer work. Any bot using it will disconnect.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await BotService.revokeApiKey(widget.workspaceId, widget.botId, keyId);
        await _loadAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to revoke key: $e')),
          );
        }
      }
    }
  }

  Future<void> _addCommand() async {
    final cmdCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Command'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cmdCtrl,
              decoration: const InputDecoration(
                labelText: 'Command',
                hintText: '/help',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Display help information',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await BotService.addCommand(
          widget.workspaceId,
          widget.botId,
          command: cmdCtrl.text.trim(),
          description: descCtrl.text.trim(),
        );
        await _loadAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add command: $e')),
          );
        }
      }
    }
  }

  Future<void> _removeCommand(String commandId) async {
    try {
      await BotService.removeCommand(widget.workspaceId, widget.botId, commandId);
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove command: $e')),
        );
      }
    }
  }

  Future<void> _subscribeEvent(String event) async {
    try {
      await BotService.subscribeEvent(widget.workspaceId, widget.botId, event);
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to subscribe: $e')),
        );
      }
    }
  }

  Future<void> _unsubscribeEvent(String subId) async {
    try {
      await BotService.unsubscribeEvent(widget.workspaceId, widget.botId, subId);
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unsubscribe: $e')),
        );
      }
    }
  }

  Future<void> _toggleBotStatus() async {
    final isActive = _bot?['status'] == 'ACTIVE';
    try {
      await BotService.updateBot(
        widget.workspaceId,
        widget.botId,
        {'active': !isActive},
      );
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update bot: $e')),
        );
      }
    }
  }

  Future<void> _deleteBot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bot'),
        content: const Text('This permanently deletes the bot and all its keys/commands. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await BotService.deleteBot(widget.workspaceId, widget.botId);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete bot: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.botName),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadAll, child: const Text('Retry')),
          ],
        ),
      );
    }

    final isActive = _bot?['status'] == 'ACTIVE';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // API Keys
        _SectionHeader(
          title: 'API Keys',
          action: FilledButton.icon(
            onPressed: _generateKey,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Generate Key'),
          ),
        ),
        const SizedBox(height: 8),
        ..._keys.map((key) => Card(
          child: ListTile(
            leading: const Icon(Icons.vpn_key),
            title: Text(key['prefix'] as String? ?? 'Unknown', style: const TextStyle(fontFamily: 'monospace')),
            subtitle: Text('Created ${_fmtDate(key['createdAt'] as String?)}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _revokeKey(key['id'] as String),
            ),
          ),
        )),
        if (_keys.isEmpty) const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('No API keys'))),

        const SizedBox(height: 24),

        // Commands
        _SectionHeader(
          title: 'Slash Commands',
          action: FilledButton.icon(
            onPressed: _addCommand,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Command'),
          ),
        ),
        const SizedBox(height: 8),
        ..._commands.map((cmd) => Card(
          child: ListTile(
            leading: Icon(Icons.terminal, color: cmd['enabled'] == true ? Colors.green : Colors.grey),
            title: Text(
              cmd['command'] as String? ?? '',
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
            ),
            subtitle: Text(cmd['description'] as String? ?? ''),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: () => _removeCommand(cmd['id'] as String),
            ),
          ),
        )),
        if (_commands.isEmpty) const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('No commands'))),

        const SizedBox(height: 24),

        // Event Subscriptions
        _SectionHeader(
          title: 'Event Subscriptions',
          action: PopupMenuButton<String>(
            icon: const Icon(Icons.add_circle_outline),
            onSelected: _subscribeEvent,
            tooltip: 'Subscribe to event',
            itemBuilder: (ctx) {
              final subscribed = _events.map((e) => e['event'] as String).toSet();
              return _availableEvents
                  .where((e) => !subscribed.contains(e))
                  .map((e) => PopupMenuItem(value: e, child: Text(e)))
                  .toList();
            },
          ),
        ),
        const SizedBox(height: 8),
        ..._events.map((sub) => Card(
          child: ListTile(
            leading: const Icon(Icons.event),
            title: Text(sub['event'] as String? ?? '', style: const TextStyle(fontFamily: 'monospace')),
            trailing: IconButton(
              icon: const Icon(Icons.link_off, color: Colors.red, size: 20),
              onPressed: () => _unsubscribeEvent(sub['id'] as String),
            ),
          ),
        )),
        if (_events.isEmpty) const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('No event subscriptions'))),

        const SizedBox(height: 32),

        // Danger Zone
        _SectionHeader(title: 'Danger Zone'),
        const SizedBox(height: 8),
        Card(
          color: Colors.red.withOpacity(0.05),
          child: Column(
            children: [
              ListTile(
                leading: Icon(isActive ? Icons.pause_circle : Icons.play_circle, color: Colors.orange),
                title: Text(isActive ? 'Disable Bot' : 'Enable Bot'),
                subtitle: Text(isActive ? 'Bot will stop responding' : 'Bot will resume operation'),
                trailing: FilledButton(
                  onPressed: _toggleBotStatus,
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  child: Text(isActive ? 'Disable' : 'Enable'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete Bot'),
                subtitle: const Text('Permanently delete this bot and all its data'),
                trailing: FilledButton(
                  onPressed: _deleteBot,
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (action != null) action!,
      ],
    );
  }
}
