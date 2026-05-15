import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import '../../services/workspace_service.dart';

import '../screens/bot_list_screen.dart';
class WorkspaceSettingsView extends StatefulWidget {
  final String? workspaceName;
  
  const WorkspaceSettingsView({super.key, this.workspaceName});

  @override
  State<WorkspaceSettingsView> createState() => _WorkspaceSettingsViewState();
}

class _WorkspaceSettingsViewState extends State<WorkspaceSettingsView> {
  bool _loading = true;
  Map<String, dynamic>? _workspace;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _channels = [];
  String _tier = 'free';

  @override
  void initState() {
    super.initState();
    _loadWorkspaceData();
  }

  bool _hasLoaded = false;
  String? _lastWorkspaceName;

  @override
  void didUpdateWidget(WorkspaceSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload when workspace name changes
    if (widget.workspaceName != oldWidget.workspaceName) {
      _lastWorkspaceName = widget.workspaceName;
      _hasLoaded = false;
      _loadWorkspaceData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload data when view becomes visible for the first time
    if (!_hasLoaded && !_loading) {
      _lastWorkspaceName = widget.workspaceName;
      _loadWorkspaceData();
    }
  }

  Future<void> _loadWorkspaceData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    
    try {
      final user = await DatabaseService.getCurrentUser();
      if (user == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      
      Map<String, dynamic>? workspace;
      
      // If workspace name is provided and not the default, use that to find the workspace
      if (widget.workspaceName != null && 
          widget.workspaceName!.isNotEmpty && 
          widget.workspaceName != 'FlowSpace') {
        try {
          workspace = await WorkspaceService.selectWorkspaceByName(widget.workspaceName!);
        } catch (e) {
          print('WorkspaceSettings: Error finding workspace by name "${widget.workspaceName}": $e');
          // Fall through to get first available workspace
        }
      }
      
      // If not found or not provided, get all workspaces and pick the most recent
      if (workspace == null) {
        try {
          final workspaces = await DatabaseService.getUserWorkspaces(user['id'] as String);
          if (workspaces.isEmpty) {
            if (!mounted) return;
            setState(() => _loading = false);
            return;
          }
          
          // Get the most recently updated workspace, or first one if none updated
          workspace = workspaces.reduce((a, b) {
            final aUpdated = DateTime.tryParse(a['updated_at'] as String? ?? '') ?? DateTime(1970);
            final bUpdated = DateTime.tryParse(b['updated_at'] as String? ?? '') ?? DateTime(1970);
            return bUpdated.isAfter(aUpdated) ? b : a;
          });
        } catch (e) {
          print('WorkspaceSettings: Error loading workspaces: $e');
          if (!mounted) return;
          setState(() => _loading = false);
          return;
        }
      }
      
      if (workspace == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      
      final workspaceId = workspace['id'] as String?;
      if (workspaceId == null || workspaceId.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      
      final members = await DatabaseService.getWorkspaceMembers(workspaceId);
      final channels = await DatabaseService.getWorkspaceChannels(workspaceId);
      
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _members = members;
        _channels = channels;
        _tier = workspace?['subscription_tier'] as String? ?? 'free';
        _loading = false;
        _hasLoaded = true;
      });
    } catch (e, stackTrace) {
      print('WorkspaceSettings: Error loading data: $e');
      print('WorkspaceSettings: Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_workspace == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'No workspace found',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadWorkspaceData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0066FF),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTierBanner(),
          const SizedBox(height: 32),
          _buildWorkspaceInfo(),
          const SizedBox(height: 32),
          _buildMembersList(),
          const SizedBox(height: 32),
          _buildChannelsList(),
          const SizedBox(height: 32),
          _buildBotsButton(),
        ],
      ),
    );
  }

  Widget _buildTierBanner() {
    final isFree = _tier == 'free';
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                isFree ? Icons.rocket_outlined : Icons.workspace_premium,
                color: const Color(0xFF0066FF),
                size: 48,
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFree ? 'FlowSpace Free' : 'FlowSpace Pro',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isFree
                          ? '1 workspace • 2 channels • 5GB storage • Up to 5 members'
                          : 'Unlimited workspaces • Unlimited channels • 100GB storage • Unlimited members',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              if (isFree)
                FilledButton.icon(
                  onPressed: _showUpgradeDialog,
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('Upgrade to Pro'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0066FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceInfo() {
    return _buildSection(
      title: 'Workspace Settings',
      children: [
        _buildInfoRow('Name', _workspace!['name'] ?? 'Unnamed'),
        _buildInfoRow('Slug', _workspace!['slug'] ?? ''),
        _buildInfoRow('Created', _formatDate(_workspace!['created_at'] as String?)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _showRenameDialog,
          icon: const Icon(Icons.edit),
          label: const Text('Rename Workspace'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0066FF),
            side: const BorderSide(color: Color(0xFF0066FF)),
          ),
        ),
      ],
    );
  }

  Widget _buildMembersList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSection(
          title: 'Team Members (${_members.length}/5)',
          children: [
            ..._members.map((member) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF0066FF).withValues(alpha: 0.2),
                  child: Text(
                    (member['name'] as String? ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(color: Color(0xFF0066FF)),
                  ),
                ),
                title: Text(
                  member['name'] as String? ?? 'Unknown',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  member['email'] as String? ?? '',
                  style: const TextStyle(color: Colors.white54),
                ),
                trailing: Chip(
                  label: Text(
                    (member['role'] as String? ?? 'member').toUpperCase(),
                    style: const TextStyle(fontSize: 10),
                  ),
                  backgroundColor: const Color(0xFF0066FF).withValues(alpha: 0.2),
                  labelStyle: const TextStyle(color: Color(0xFF0066FF)),
                ),
              );
            }),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            print('FlowSpace: Invite Member FilledButton pressed!');
            print('FlowSpace: Current tier: $_tier, members: ${_members.length}');
            if (_tier == 'free' && _members.length >= 5) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Free tier limit: Maximum 5 members reached'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            print('FlowSpace: Calling _showInviteDialog');
            _showInviteDialog();
          },
          icon: const Icon(Icons.person_add),
          label: const Text('Invite Member'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0066FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelsList() {
    return _buildSection(
      title: 'Channels (${_channels.length}/2)',
      children: [
        ..._channels.map((channel) {
          return ListTile(
            leading: const Icon(Icons.tag, color: Color(0xFF0066FF)),
            title: Text(
              '# ${channel['name']}',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              channel['description'] as String? ?? '',
              style: const TextStyle(color: Colors.white54),
            ),
          );
        }),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _tier == 'free' && _channels.length >= 2 ? null : null, // TODO: implement add channel
          icon: const Icon(Icons.add),
          label: const Text('Add Channel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0066FF),
            side: const BorderSide(color: Color(0xFF0066FF)),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final date = DateTime.tryParse(iso);
    if (date == null) return '';
    return '${date.month}/${date.day}/${date.year}';
  }

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Upgrade to Pro',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FlowSpace Pro - \$9/user/month',
              style: TextStyle(color: Color(0xFF0066FF), fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ...[
              'Unlimited workspaces',
              'Unlimited channels',
              '100GB storage per workspace',
              'Project management & Kanban boards',
              'Calendar & scheduling',
              'Screen recording',
              'API access',
              'Cloud sync backup (optional)',
            ].map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF0066FF), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: implement upgrade flow
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Upgrade flow coming soon!')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
            ),
            child: const Text('Upgrade Now'),
          ),
        ],
      ),
    );
  }

  Widget _buildBotsButton() {
    final workspaceId = _workspace?['id'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Automation',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.smart_toy, color: Color(0xFF0066FF)),
          title: const Text('Bots', style: TextStyle(color: Colors.white)),
          subtitle: const Text(
            'Create and manage bot assistants',
            style: TextStyle(color: Colors.white54),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tileColor: Colors.white.withOpacity(0.05),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BotListScreen(
                  workspaceId: workspaceId,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showInviteDialog() {
    final emailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => _InviteDialog(
        emailController: emailController,
        workspaceId: _workspace!['id'] as String,
        members: _members,
        tier: _tier,
        onMemberAdded: () {
          _loadWorkspaceData();
        },
      ),
    );
  }
  
  void _showRenameDialog() {
    final controller = TextEditingController(text: _workspace!['name'] as String?);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Rename Workspace',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Workspace Name',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white54),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: implement rename
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Rename feature coming soon!')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

class _InviteDialog extends StatefulWidget {
  final TextEditingController emailController;
  final String workspaceId;
  final List<Map<String, dynamic>> members;
  final String tier;
  final VoidCallback onMemberAdded;

  const _InviteDialog({
    required this.emailController,
    required this.workspaceId,
    required this.members,
    required this.tier,
    required this.onMemberAdded,
  });

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}


class _InviteDialogState extends State<_InviteDialog> {
  bool _isInviting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text(
        'Invite Team Member',
        style: TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.emailController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Email Address',
              labelStyle: TextStyle(color: Colors.white70),
              hintText: 'user@example.com',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white54),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF0066FF)),
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            enabled: !_isInviting,
          ),
          const SizedBox(height: 16),
          if (widget.tier == 'free')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Free tier: Max 5 members (${widget.members.length}/5)',
                      style: const TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isInviting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isInviting ? null : () async {
            final email = widget.emailController.text.trim();
            if (email.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter an email address')),
              );
              return;
            }
            
            if (!email.contains('@') || !email.contains('.')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a valid email address')),
              );
              return;
            }
            
            setState(() => _isInviting = true);
            
            try {
              final user = await DatabaseService.getUserByEmail(email);
              
              if (user == null) {
                final userId = '${DateTime.now().millisecondsSinceEpoch}_user';
                final now = DateTime.now().toIso8601String();
                
                await DatabaseService.insertUser({
                  'id': userId,
                  'name': email.split('@')[0],
                  'email': email,
                  'password_hash': null,
                  'avatar_url': null,
                  'status': 'offline',
                  'created_at': now,
                  'updated_at': now,
                });
                
                await DatabaseService.addWorkspaceMember({
                  'workspace_id': widget.workspaceId,
                  'user_id': userId,
                  'role': 'member',
                  'joined_at': now,
                });
                
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$email has been added to the workspace'),
                    backgroundColor: Colors.green,
                  ),
                );
                
                widget.onMemberAdded();
              } else {
                final existingMembers = await DatabaseService.getWorkspaceMembers(widget.workspaceId);
                final isAlreadyMember = existingMembers.any((m) => m['email'] == email);
                
                if (isAlreadyMember) {
                  if (!mounted) return;
                  setState(() => _isInviting = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User is already a member of this workspace')),
                  );
                  return;
                }
                
                final now = DateTime.now().toIso8601String();
                await DatabaseService.addWorkspaceMember({
                  'workspace_id': widget.workspaceId,
                  'user_id': user['id'] as String,
                  'role': 'member',
                  'joined_at': now,
                });
                
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${user['name']} has been added to the workspace'),
                    backgroundColor: Colors.green,
                  ),
                );
                
                widget.onMemberAdded();
              }
            } catch (e) {
              if (!mounted) return;
              setState(() => _isInviting = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error adding member: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0066FF),
          ),
          child: _isInviting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Invite'),
        ),
      ],
    );
  }
}
