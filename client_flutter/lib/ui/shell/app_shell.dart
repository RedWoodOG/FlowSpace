import 'package:flutter/material.dart';

import '../../system_graph/shipping_surface_registry.dart';

/// The product shell renders only surfaces declared by the shipping registry.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final selectedSurface = shippingSurfaces[_selectedIndex];
    return Scaffold(
      backgroundColor: const Color(0xFF090D13),
      body: Row(
        children: [
          Semantics(
            label: 'Shipping surfaces',
            child: NavigationRail(
              backgroundColor: const Color(0xFF0E151F),
              selectedIndex: _selectedIndex,
              labelType: NavigationRailLabelType.all,
              minWidth: 78,
              minExtendedWidth: 150,
              indicatorColor: const Color(0xFF65E6B9),
              selectedIconTheme: const IconThemeData(
                color: Color(0xFF07110E),
                size: 23,
              ),
              unselectedIconTheme: const IconThemeData(
                color: Color(0xFFB7C3D2),
                size: 22,
              ),
              selectedLabelTextStyle: const TextStyle(
                color: Color(0xFFF8FAFC),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: Color(0xFFB7C3D2),
                fontSize: 12,
              ),
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: [
                for (final surface in shippingSurfaces)
                  NavigationRailDestination(
                    icon: Tooltip(
                      message: surface.tooltip,
                      child: Icon(surface.icon),
                    ),
                    selectedIcon: Tooltip(
                      message: surface.tooltip,
                      child: Icon(surface.activeIcon),
                    ),
                    label: Text(surface.label),
                  ),
              ],
            ),
          ),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: Color(0xFF344151),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(selectedSurface.graphNodeId),
              child: selectedSurface.builder(context),
            ),
          ),
        ],
      ),
    );
  }
}
