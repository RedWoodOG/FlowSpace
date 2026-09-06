import 'package:flutter/material.dart';

import '../ui/screens/system_graph_screen.dart';

class ShippingSurfaceDefinition {
  const ShippingSurfaceDefinition({
    required this.graphNodeId,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.activeIcon,
    required this.builder,
  });

  final String graphNodeId;
  final String label;
  final String tooltip;
  final IconData icon;
  final IconData activeIcon;
  final WidgetBuilder builder;
}

final List<ShippingSurfaceDefinition> shippingSurfaces = [
  ShippingSurfaceDefinition(
    graphNodeId: 'surface.system_graph',
    label: 'System',
    tooltip: 'System wiring graph',
    icon: Icons.account_tree_outlined,
    activeIcon: Icons.account_tree,
    builder: (_) => const SystemGraphScreen(),
  ),
];
