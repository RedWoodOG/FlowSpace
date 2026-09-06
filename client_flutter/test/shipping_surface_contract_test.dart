import 'dart:convert';
import 'dart:io';

import 'package:flo/system_graph/shipping_surface_registry.dart';
import 'package:flo/ui/onboarding/login_screen.dart';
import 'package:flo/ui/onboarding/setup_complete_screen.dart';
import 'package:flo/ui/onboarding/welcome_screen.dart';
import 'package:flo/ui/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shipping registry matches the generated graph contract', () {
    final graph =
        jsonDecode(
              File(
                'assets/system_graph/flowspace_system_graph.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final graphNodes = {
      for (final node in graph['nodes'] as List<dynamic>)
        (node as Map<String, dynamic>)['id'] as String: node,
    };

    expect(
      shippingSurfaces.map((surface) => surface.graphNodeId),
      orderedEquals(['surface.system_graph']),
    );
    for (final surface in shippingSurfaces) {
      final node = graphNodes[surface.graphNodeId];
      expect(node, isNotNull, reason: '${surface.graphNodeId} is absent');
      expect(node!['status'], 'wired');
      expect(node['visible'], isTrue);
      expect(node['nav_visible'], isTrue);
    }
  });

  test('quarantined surfaces are unreachable from the shipping shell', () {
    final shell = File('lib/ui/shell/app_shell.dart').readAsStringSync();
    final registry = File(
      'lib/system_graph/shipping_surface_registry.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    final onboarding = [
      'lib/ui/onboarding/welcome_screen.dart',
      'lib/ui/onboarding/login_screen.dart',
      'lib/ui/onboarding/setup_user_screen.dart',
      'lib/ui/onboarding/setup_complete_screen.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    final reachableSource = '$shell\n$registry\n$mainSource\n$onboarding';

    for (final forbidden in [
      'workspace_screen.dart',
      'streams_screen.dart',
      'meet_view.dart',
      'calendar_view.dart',
      'vault_screen.dart',
      'projects_screen.dart',
      'settings_screen.dart',
      'app_router.dart',
      'workspace_shell.dart',
    ]) {
      expect(reachableSource, isNot(contains(forbidden)));
    }
  });

  testWidgets('welcome states only the wired product boundary', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));

    expect(find.text('A proof-first local workspace.'), findsOneWidget);
    expect(find.text('Visible system wiring'), findsOneWidget);
    expect(find.text('Video Meetings'), findsNothing);
    expect(find.text('Secure Vault'), findsNothing);

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('account completion enters the shipping graph shell', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: SetupCompleteScreen(teamName: 'Local', userName: 'Joe'),
      ),
    );

    await tester.tap(find.text('Open System Graph'));
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('FlowSpace System Node Graph').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('FlowSpace System Node Graph'), findsOneWidget);
  });
}
