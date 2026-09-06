import 'package:flo/system_graph/system_graph_document.dart';
import 'package:flo/system_graph/system_graph_repository.dart';
import 'package:flo/ui/screens/system_graph_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bundled system graph asset parses', (tester) async {
    final document = await const AssetSystemGraphRepository().load();
    expect(document.nodes, isNotEmpty);
    expect(document.edges, isNotEmpty);
    expect(
      document.nodes.any((node) => node.id == 'surface.system_graph'),
      isTrue,
    );
  });

  test('SystemGraphDocument rejects dangling edges', () {
    expect(
      () => SystemGraphDocument.fromJson({
        'schema': 'flowspace.systemgraph.v1',
        'title': 'Graph',
        'product_rule': 'Visible means wired.',
        'source_fingerprint': 'fingerprint',
        'layer_order': ['surface', 'service'],
        'nodes': [
          {
            'id': 'surface.system_graph',
            'label': 'System',
            'layer': 'surface',
            'kind': 'surface',
            'status': 'wired',
            'contract': true,
            'path': 'lib/ui/screens/system_graph_screen.dart',
          },
        ],
        'edges': [
          {
            'from': 'surface.system_graph',
            'to': 'service.missing',
            'kind': 'invokes',
          },
        ],
      }),
      throwsFormatException,
    );
  });

  testWidgets('system graph renders, filters, and exposes evidence', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: SystemGraphScreen(repository: _MemoryGraphRepository(_document)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FlowSpace System Node Graph'), findsOneWidget);
    expect(find.text('2 of 3 nodes'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Quarantined screen'), findsOneWidget);
    expect(find.text('API client'), findsNothing);

    await tester.tap(find.text('All code'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 nodes'), findsOneWidget);
    expect(find.text('API client'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'api_service.dart');
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 nodes'), findsOneWidget);
    await tester.tap(find.text('API client'));
    await tester.pumpAndSettle();
    expect(find.text('Evidence path'), findsOneWidget);
    expect(
      find.text('client_flutter/lib/services/api_service.dart'),
      findsOneWidget,
    );
  });
}

class _MemoryGraphRepository implements SystemGraphRepository {
  const _MemoryGraphRepository(this.document);

  final SystemGraphDocument document;

  @override
  Future<SystemGraphDocument> load() async => document;
}

final _document = SystemGraphDocument.fromJson({
  'schema': 'flowspace.systemgraph.v1',
  'title': 'FlowSpace System Node Graph',
  'product_rule': 'Visible UI is a shipping claim.',
  'source_fingerprint': 'fixture-fingerprint',
  'layer_order': ['surface', 'service'],
  'nodes': [
    {
      'id': 'surface.system_graph',
      'label': 'System',
      'layer': 'surface',
      'kind': 'surface',
      'status': 'wired',
      'contract': true,
      'path': 'client_flutter/lib/ui/screens/system_graph_screen.dart',
    },
    {
      'id': 'surface.quarantined',
      'label': 'Quarantined screen',
      'layer': 'surface',
      'kind': 'surface',
      'status': 'quarantined',
      'contract': true,
      'path': 'client_flutter/lib/ui/screens/quarantined_screen.dart',
      'reason': 'No authority path.',
    },
    {
      'id': 'file:client_flutter/lib/services/api_service.dart',
      'label': 'API client',
      'layer': 'service',
      'kind': 'service',
      'status': 'present',
      'contract': false,
      'path': 'client_flutter/lib/services/api_service.dart',
    },
  ],
  'edges': [
    {
      'from': 'surface.system_graph',
      'to': 'file:client_flutter/lib/services/api_service.dart',
      'kind': 'invokes',
    },
  ],
});
