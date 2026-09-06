import 'dart:convert';

class SystemGraphDocument {
  const SystemGraphDocument({
    required this.title,
    required this.productRule,
    required this.sourceFingerprint,
    required this.layerOrder,
    required this.nodes,
    required this.edges,
  });

  final String title;
  final String productRule;
  final String sourceFingerprint;
  final List<String> layerOrder;
  final List<SystemGraphNode> nodes;
  final List<SystemGraphEdge> edges;

  factory SystemGraphDocument.fromJsonString(String source) {
    return SystemGraphDocument.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  factory SystemGraphDocument.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 'flowspace.systemgraph.v1') {
      throw const FormatException('Unsupported FlowSpace system graph schema.');
    }

    final nodes = (json['nodes'] as List<dynamic>)
        .map((item) => SystemGraphNode.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    final nodeIds = nodes.map((node) => node.id).toSet();
    if (nodeIds.length != nodes.length) {
      throw const FormatException('System graph contains duplicate node IDs.');
    }

    final edges = (json['edges'] as List<dynamic>)
        .map((item) => SystemGraphEdge.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    for (final edge in edges) {
      if (!nodeIds.contains(edge.from) || !nodeIds.contains(edge.to)) {
        throw FormatException(
          'System graph edge ${edge.from} -> ${edge.to} has a missing node.',
        );
      }
    }

    return SystemGraphDocument(
      title: json['title'] as String,
      productRule: json['product_rule'] as String,
      sourceFingerprint: json['source_fingerprint'] as String,
      layerOrder: List<String>.unmodifiable(
        (json['layer_order'] as List<dynamic>).cast<String>(),
      ),
      nodes: List<SystemGraphNode>.unmodifiable(nodes),
      edges: List<SystemGraphEdge>.unmodifiable(edges),
    );
  }

  List<SystemGraphNode> visibleNodes({
    required bool includeAllCode,
    String query = '',
  }) {
    final normalized = query.trim().toLowerCase();
    return nodes
        .where((node) {
          if (!includeAllCode && !node.contract) return false;
          if (normalized.isEmpty) return true;
          return node.searchText.contains(normalized);
        })
        .toList(growable: false);
  }
}

class SystemGraphNode {
  const SystemGraphNode({
    required this.id,
    required this.label,
    required this.layer,
    required this.kind,
    required this.status,
    required this.contract,
    required this.path,
    this.symbol,
    this.reason,
  });

  final String id;
  final String label;
  final String layer;
  final String kind;
  final String status;
  final bool contract;
  final String path;
  final String? symbol;
  final String? reason;

  factory SystemGraphNode.fromJson(Map<String, dynamic> json) {
    return SystemGraphNode(
      id: json['id'] as String,
      label: json['label'] as String,
      layer: json['layer'] as String,
      kind: json['kind'] as String,
      status: json['status'] as String,
      contract: json['contract'] as bool? ?? false,
      path: json['path'] as String? ?? '',
      symbol: json['symbol'] as String?,
      reason: json['reason'] as String?,
    );
  }

  String get searchText => [
    id,
    label,
    layer,
    kind,
    status,
    path,
    symbol,
    reason,
  ].whereType<String>().join(' ').toLowerCase();
}

class SystemGraphEdge {
  const SystemGraphEdge({
    required this.from,
    required this.to,
    required this.kind,
  });

  final String from;
  final String to;
  final String kind;

  factory SystemGraphEdge.fromJson(Map<String, dynamic> json) {
    return SystemGraphEdge(
      from: json['from'] as String,
      to: json['to'] as String,
      kind: json['kind'] as String,
    );
  }
}
