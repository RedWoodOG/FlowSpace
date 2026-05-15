import 'package:flutter/material.dart';
import '../../services/bot_service.dart';
import 'bot_detail_screen.dart';

class BotListScreen extends StatefulWidget {
  final String workspaceId;

  const BotListScreen({super.key, required this.workspaceId});

  @override
  State<BotListScreen> createState() => _BotListScreenState();
}

class _BotListScreenState extends State<BotListScreen> {
  List<Map<String, dynamic>> _bots = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBots();
  }

  Future<void> _loadBots() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bots = await BotService.listBots(widget.workspaceId);
      setState(() {
        _bots = bots;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createBot() async {
    final nameCtrl = TextEditingController();
    final displayCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Bot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Bot Name (slug)',
                hintText: 'e.g. pollbot',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: displayCtrl,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'e.g. Poll Bot',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What does this bot do?',
              ),
              maxLines: 2,
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
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await BotService.createBot(
          widget.workspaceId,
          name: nameCtrl.text.trim(),
          displayName: displayCtrl.text.trim(),
          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        );
        await _loadBots();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create bot: $e')),
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
        title: const Text('Bots'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBots,
          ),
          FilledButton.icon(
            onPressed: _createBot,
            icon: const Icon(Icons.add),
            label: const Text('New Bot'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Failed to load bots', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadBots, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_bots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('No bots yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Create your first bot to automate workflows', style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _createBot,
              icon: const Icon(Icons.add),
              label: const Text('Create Bot'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bots.length,
      itemBuilder: (context, index) {
        final bot = _bots[index];
        final isActive = bot['status'] == 'ACTIVE';
        final commandCount = (bot['_count'] as Map?)?['commands'] ?? 0;
        final eventCount = (bot['_count'] as Map?)?['events'] ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isActive
                  ? theme.colorScheme.primary.withOpacity(0.15)
                  : Colors.grey.withOpacity(0.15),
              child: Icon(
                Icons.smart_toy,
                color: isActive ? theme.colorScheme.primary : Colors.grey,
              ),
            ),
            title: Text(
              bot['displayName'] ?? bot['name'] ?? 'Unknown',
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@${bot['name'] ?? ''}'),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _StatusChip(active: isActive),
                    const SizedBox(width: 8),
                    Text('$commandCount commands', style: theme.textTheme.bodySmall),
                    const SizedBox(width: 8),
                    Text('$eventCount events', style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BotDetailScreen(
                    workspaceId: widget.workspaceId,
                    botId: bot['id'] as String,
                    botName: (bot['displayName'] ?? bot['name'] ?? 'Bot') as String,
                  ),
                ),
              ).then((_) => _loadBots());
            },
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool active;

  const _StatusChip({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? Colors.green.withOpacity(0.15) : Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        active ? 'ACTIVE' : 'DISABLED',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: active ? Colors.green : Colors.grey,
        ),
      ),
    );
  }
}
