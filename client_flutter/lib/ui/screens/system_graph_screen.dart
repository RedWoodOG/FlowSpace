import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../system_graph/system_graph_document.dart';
import '../../system_graph/system_graph_repository.dart';

class SystemGraphScreen extends StatefulWidget {
  const SystemGraphScreen({
    super.key,
    this.repository = const AssetSystemGraphRepository(),
  });

  final SystemGraphRepository repository;

  @override
  State<SystemGraphScreen> createState() => _SystemGraphScreenState();
}

class _SystemGraphScreenState extends State<SystemGraphScreen> {
  late Future<SystemGraphDocument> _document;
  String _query = '';
  bool _showAllCode = false;
  String? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _document = widget.repository.load();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF090D13),
      child: FutureBuilder<SystemGraphDocument>(
        future: _document,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _GraphLoadFailure(
              onRetry: () => setState(() {
                _document = widget.repository.load();
              }),
            );
          }
          final document = snapshot.data;
          if (document == null) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF65E6B9)),
            );
          }
          return _buildDocument(document);
        },
      ),
    );
  }

  Widget _buildDocument(SystemGraphDocument document) {
    final nodes = document.visibleNodes(
      includeAllCode: _showAllCode,
      query: _query,
    );
    final selected = _selectedNodeId == null
        ? null
        : document.nodes.cast<SystemGraphNode?>().firstWhere(
            (node) => node?.id == _selectedNodeId,
            orElse: () => null,
          );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GraphHeader(document: document),
            const SizedBox(height: 18),
            _GraphControls(
              query: _query,
              showAllCode: _showAllCode,
              shownNodeCount: nodes.length,
              totalNodeCount: document.nodes.length,
              onQueryChanged: (value) => setState(() => _query = value),
              onScopeChanged: (value) => setState(() {
                _showAllCode = value;
                _selectedNodeId = null;
              }),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final inspector = _GraphInspector(
                    document: document,
                    nodes: nodes,
                    selected: selected,
                    onClear: () => setState(() => _selectedNodeId = null),
                    onSelected: (node) =>
                        setState(() => _selectedNodeId = node.id),
                  );
                  final graph = _SystemGraphCanvas(
                    document: document,
                    nodes: nodes,
                    selectedNodeId: _selectedNodeId,
                    onSelected: (node) =>
                        setState(() => _selectedNodeId = node.id),
                  );
                  if (constraints.maxWidth < 900) {
                    return Column(
                      children: [
                        Expanded(flex: 3, child: graph),
                        const SizedBox(height: 12),
                        Expanded(flex: 2, child: inspector),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: graph),
                      const SizedBox(width: 14),
                      SizedBox(width: 310, child: inspector),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphHeader extends StatelessWidget {
  const _GraphHeader({required this.document});

  final SystemGraphDocument document;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF65E6B9).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF65E6B9)),
          ),
          child: const Icon(Icons.account_tree, color: Color(0xFF65E6B9)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                document.title,
                style: const TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                document.productRule,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFB7C3D2),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          label: 'Graph source fingerprint ${document.sourceFingerprint}',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF111923),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF344151)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'SOURCE',
                  style: TextStyle(
                    color: Color(0xFF93A3B5),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  document.sourceFingerprint.substring(0, 8),
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GraphControls extends StatelessWidget {
  const _GraphControls({
    required this.query,
    required this.showAllCode,
    required this.shownNodeCount,
    required this.totalNodeCount,
    required this.onQueryChanged,
    required this.onScopeChanged,
  });

  final String query;
  final bool showAllCode;
  final int shownNodeCount;
  final int totalNodeCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onScopeChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 330,
          child: TextField(
            onChanged: onQueryChanged,
            style: const TextStyle(color: Color(0xFFF8FAFC)),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Find a surface, service, state, or file',
              hintStyle: const TextStyle(color: Color(0xFF8795A7)),
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFFA9B7C8),
                size: 20,
              ),
              filled: true,
              fillColor: const Color(0xFF111923),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF344151)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF65E6B9),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Contract'),
              icon: Icon(Icons.verified_outlined),
            ),
            ButtonSegment(
              value: true,
              label: Text('All code'),
              icon: Icon(Icons.code),
            ),
          ],
          selected: {showAllCode},
          onSelectionChanged: (selection) => onScopeChanged(selection.first),
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFF07110E)
                  : const Color(0xFFD2DCE8),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFF65E6B9)
                  : const Color(0xFF111923),
            ),
            side: const WidgetStatePropertyAll(
              BorderSide(color: Color(0xFF465568)),
            ),
          ),
        ),
        Text(
          '$shownNodeCount of $totalNodeCount nodes',
          style: const TextStyle(color: Color(0xFFB7C3D2), fontSize: 12),
        ),
      ],
    );
  }
}

class _SystemGraphCanvas extends StatelessWidget {
  const _SystemGraphCanvas({
    required this.document,
    required this.nodes,
    required this.selectedNodeId,
    required this.onSelected,
  });

  final SystemGraphDocument document;
  final List<SystemGraphNode> nodes;
  final String? selectedNodeId;
  final ValueChanged<SystemGraphNode> onSelected;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const _EmptyGraph();
    }
    final layout = _GraphLayout.create(document.layerOrder, nodes);
    return Semantics(
      label: 'System node graph with ${nodes.length} nodes',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0C121B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF344151)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: InteractiveViewer(
            minScale: 0.35,
            maxScale: 2.4,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(140),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final node = layout.nodeAt(details.localPosition);
                if (node != null) onSelected(node);
              },
              child: CustomPaint(
                size: layout.size,
                painter: _GraphPainter(
                  document: document,
                  layout: layout,
                  selectedNodeId: selectedNodeId,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GraphInspector extends StatelessWidget {
  const _GraphInspector({
    required this.document,
    required this.nodes,
    required this.selected,
    required this.onClear,
    required this.onSelected,
  });

  final SystemGraphDocument document;
  final List<SystemGraphNode> nodes;
  final SystemGraphNode? selected;
  final VoidCallback onClear;
  final ValueChanged<SystemGraphNode> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111923),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF344151)),
      ),
      child: selected == null ? _nodeList() : _nodeDetail(selected!),
    );
  }

  Widget _nodeList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 15, 16, 9),
          child: Text(
            'Nodes',
            style: TextStyle(
              color: Color(0xFFF8FAFC),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFF344151)),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: nodes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 2),
            itemBuilder: (context, index) {
              final node = nodes[index];
              return ListTile(
                dense: true,
                minLeadingWidth: 18,
                leading: Icon(
                  node.status == 'quarantined'
                      ? Icons.block_outlined
                      : Icons.circle,
                  size: node.status == 'quarantined' ? 17 : 9,
                  color: _nodeAccent(node),
                ),
                title: Text(
                  node.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE6EDF5),
                    fontSize: 12,
                  ),
                ),
                subtitle: Text(
                  node.layer,
                  style: const TextStyle(
                    color: Color(0xFF93A3B5),
                    fontSize: 10,
                  ),
                ),
                onTap: () => onSelected(node),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _nodeDetail(SystemGraphNode node) {
    final incoming = document.edges.where((edge) => edge.to == node.id).length;
    final outgoing = document.edges
        .where((edge) => edge.from == node.id)
        .length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.list, size: 18),
            label: const Text('Node list'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF65E6B9),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            node.label,
            style: const TextStyle(
              color: Color(0xFFF8FAFC),
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _DetailRow(label: 'Status', value: node.status),
          _DetailRow(label: 'Layer', value: node.layer),
          _DetailRow(label: 'Kind', value: node.kind),
          _DetailRow(label: 'Incoming', value: '$incoming'),
          _DetailRow(label: 'Outgoing', value: '$outgoing'),
          const SizedBox(height: 12),
          const Text(
            'Evidence path',
            style: TextStyle(color: Color(0xFF9BACBF), fontSize: 11),
          ),
          const SizedBox(height: 4),
          SelectableText(
            node.path,
            style: const TextStyle(
              color: Color(0xFFDCE5EF),
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.4,
            ),
          ),
          if (node.reason != null) ...[
            const SizedBox(height: 14),
            Text(
              node.reason!,
              style: const TextStyle(
                color: Color(0xFFF2C57C),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF93A3B5), fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFFE6EDF5), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphLayout {
  const _GraphLayout({required this.size, required this.entries});

  final Size size;
  final Map<SystemGraphNode, Rect> entries;

  static _GraphLayout create(
    List<String> layerOrder,
    List<SystemGraphNode> nodes,
  ) {
    const nodeWidth = 184.0;
    const nodeHeight = 70.0;
    const columnGap = 52.0;
    const rowGap = 22.0;
    const left = 32.0;
    const top = 64.0;
    final entries = <SystemGraphNode, Rect>{};
    var maxRows = 1;
    for (var column = 0; column < layerOrder.length; column++) {
      final layerNodes = nodes
          .where((node) => node.layer == layerOrder[column])
          .toList();
      maxRows = math.max(maxRows, layerNodes.length);
      for (var row = 0; row < layerNodes.length; row++) {
        entries[layerNodes[row]] = Rect.fromLTWH(
          left + column * (nodeWidth + columnGap),
          top + row * (nodeHeight + rowGap),
          nodeWidth,
          nodeHeight,
        );
      }
    }
    return _GraphLayout(
      size: Size(
        left * 2 +
            layerOrder.length * nodeWidth +
            (layerOrder.length - 1) * columnGap,
        math.max(650, top * 2 + maxRows * nodeHeight + (maxRows - 1) * rowGap),
      ),
      entries: entries,
    );
  }

  SystemGraphNode? nodeAt(Offset position) {
    for (final entry in entries.entries) {
      if (entry.value.contains(position)) return entry.key;
    }
    return null;
  }
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter({
    required this.document,
    required this.layout,
    required this.selectedNodeId,
  });

  final SystemGraphDocument document;
  final _GraphLayout layout;
  final String? selectedNodeId;

  @override
  void paint(Canvas canvas, Size size) {
    final idToEntry = {
      for (final entry in layout.entries.entries) entry.key.id: entry,
    };
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF47586C);

    for (final edge in document.edges) {
      final from = idToEntry[edge.from]?.value;
      final to = idToEntry[edge.to]?.value;
      if (from == null || to == null) continue;
      final start = Offset(from.right, from.center.dy);
      final end = Offset(to.left, to.center.dy);
      final bend = math.max(32.0, (end.dx - start.dx).abs() * 0.38);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + bend,
          start.dy,
          end.dx - bend,
          end.dy,
          end.dx,
          end.dy,
        );
      canvas.drawPath(path, linePaint);
    }

    for (var index = 0; index < document.layerOrder.length; index++) {
      _paintText(
        canvas,
        document.layerOrder[index].toUpperCase(),
        Offset(32 + index * 236, 25),
        const TextStyle(
          color: Color(0xFF92A4B8),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
        184,
      );
    }

    for (final entry in layout.entries.entries) {
      final node = entry.key;
      final rect = entry.value;
      final selected = node.id == selectedNodeId;
      final accent = _nodeAccent(node);
      final fill = node.status == 'quarantined'
          ? const Color(0xFF251D16)
          : const Color(0xFF151E2A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.4 : 1.2
          ..color = selected ? const Color(0xFFF8FAFC) : accent,
      );
      canvas.drawCircle(
        Offset(rect.left + 13, rect.top + 15),
        4,
        Paint()..color = accent,
      );
      _paintText(
        canvas,
        node.label,
        Offset(rect.left + 24, rect.top + 8),
        const TextStyle(
          color: Color(0xFFF3F6FA),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        rect.width - 34,
      );
      _paintText(
        canvas,
        '${node.kind} · ${node.status}',
        Offset(rect.left + 12, rect.top + 32),
        const TextStyle(color: Color(0xFFAAB8C8), fontSize: 10),
        rect.width - 24,
      );
      _paintText(
        canvas,
        node.path,
        Offset(rect.left + 12, rect.top + 49),
        const TextStyle(
          color: Color(0xFF8392A5),
          fontFamily: 'monospace',
          fontSize: 9,
        ),
        rect.width - 24,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.document != document;
  }
}

Color _nodeAccent(SystemGraphNode node) {
  if (node.status == 'quarantined') return const Color(0xFFF0B665);
  if (node.contract) return const Color(0xFF65E6B9);
  return const Color(0xFF6FA8F7);
}

class _EmptyGraph extends StatelessWidget {
  const _EmptyGraph();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No nodes match this filter.',
        style: TextStyle(color: Color(0xFFB7C3D2)),
      ),
    );
  }
}

class _GraphLoadFailure extends StatelessWidget {
  const _GraphLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFF0B665), size: 36),
          const SizedBox(height: 12),
          const Text(
            'The bundled system graph could not be loaded.',
            style: TextStyle(color: Color(0xFFF8FAFC)),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
