import 'package:flutter/material.dart';

import '../../core/theme/flo_theme.dart';
import '../shell/app_shell.dart';

class SetupCompleteScreen extends StatelessWidget {
  const SetupCompleteScreen({
    super.key,
    required this.teamName,
    required this.userName,
  });

  final String teamName;
  final String userName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D13),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(38),
            decoration: BoxDecoration(
              color: const Color(0xFF111923),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF344151)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 58,
                  color: Color(0xFF65E6B9),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Local account ready',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFF8FAFC),
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '$userName can now open the proof-first shell.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB7C3D2),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),
                _SavedFact(label: 'Local workspace', value: teamName),
                const SizedBox(height: 10),
                const _SavedFact(
                  label: 'Shipping surface',
                  value: 'System Node Graph',
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const AppShell()),
                      (_) => false,
                    );
                  },
                  icon: const Icon(Icons.account_tree),
                  label: const Text('Open System Graph'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF65E6B9),
                    foregroundColor: const Color(0xFF07110E),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FloTheme.radiusMd),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedFact extends StatelessWidget {
  const _SavedFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C121B),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF344151)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check, color: Color(0xFF65E6B9), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF93A3B5),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFFF1F5F9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
