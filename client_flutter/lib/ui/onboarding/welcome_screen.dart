import 'package:flutter/material.dart';

import '../../core/theme/flo_theme.dart';
import 'login_screen.dart';
import 'setup_user_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D13),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 540),
            padding: const EdgeInsets.all(38),
            decoration: BoxDecoration(
              color: const Color(0xFF111923),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF344151)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFF65E6B9).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF65E6B9)),
                    ),
                    child: const Icon(
                      Icons.account_tree,
                      color: Color(0xFF65E6B9),
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'FlowSpace',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFF8FAFC),
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A proof-first local workspace.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB7C3D2), fontSize: 15),
                ),
                const SizedBox(height: 32),
                const _TruthRow(
                  icon: Icons.person_outline,
                  title: 'Local account',
                  detail: 'Credentials are handled by the local auth service.',
                ),
                const SizedBox(height: 14),
                const _TruthRow(
                  icon: Icons.account_tree_outlined,
                  title: 'Visible system wiring',
                  detail: 'The shipping surface is traced in the node graph.',
                ),
                const SizedBox(height: 14),
                const _TruthRow(
                  icon: Icons.shield_outlined,
                  title: 'Fail-closed navigation',
                  detail: 'Unproven modules stay out of the product shell.',
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF65E6B9),
                    foregroundColor: const Color(0xFF07110E),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FloTheme.radiusMd),
                    ),
                  ),
                  child: const Text(
                    'Log in',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SetupUserScreen(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDCE5EF),
                    side: const BorderSide(color: Color(0xFF526277)),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FloTheme.radiusMd),
                    ),
                  ),
                  child: const Text('Create local account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TruthRow extends StatelessWidget {
  const _TruthRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF65E6B9), size: 21),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  color: Color(0xFFA9B7C8),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
