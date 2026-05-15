import 'package:flutter/material.dart';
import '../ui/screens/dashboard_screen.dart';
import '../ui/screens/workspace_screen.dart';
import '../ui/screens/channel_screen.dart';
import '../ui/screens/bulletin_panel_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/projects_screen.dart';
import '../ui/screens/legacy_placeholder_screen.dart';
import '../ui/screens/conversations_screen.dart';
import '../ui/screens/bot_list_screen.dart';

/// Unified navigation router for FlowSpace
/// 
/// Centralizes all route definitions and provides type-safe navigation
class AppRouter {
  // Route constants
  static const String dashboard = '/dashboard';
  static const String workspace = '/workspace';
  static const String channel = '/channel';
  static const String bulletins = '/bulletins';
  static const String settings = '/settings';
  static const String projects = '/projects';
  static const String conversations = '/conversations';
  static const String bots = '/bots';
  
  // Legacy routes (for backward compatibility)
  static const String home = '/';
  static const String createProject = '/create-project';

  /// Route map - all app routes defined here
  static Map<String, WidgetBuilder> get routes => {
    dashboard: (_) => const DashboardScreen(),
    workspace: (_) => const WorkspaceScreen(),
    channel: (_) => const ChannelScreen(),
    bulletins: (_) => const BulletinPanelScreen(),
    settings: (_) => const SettingsScreen(),
    projects: (_) => const ProjectsScreen(),
    conversations: (_) => const ConversationsScreen(),
    bots: (_) => const BotListScreen(workspaceId: ''), // dynamic workspaceId via push
    createProject: (_) => const ProjectsScreen(),
  };

  /// Fallback route for unknown destinations
  static Route<dynamic> onUnknownRoute(RouteSettings settings) {
    return MaterialPageRoute(
      builder: (_) => const LegacyPlaceholderScreen(),
    );
  }

  /// Navigate to a route by name
  static Future<T?> navigateTo<T>(BuildContext context, String routeName, {Object? arguments}) {
    return Navigator.pushNamed<T>(context, routeName, arguments: arguments);
  }

  /// Replace current route
  static Future<T?> replaceTo<T extends Object?>(BuildContext context, String routeName, {Object? arguments}) {
    return Navigator.pushReplacementNamed<T, Object?>(context, routeName, arguments: arguments);
  }

  /// Navigate and clear stack
  static Future<T?> navigateAndClearStack<T>(BuildContext context, String routeName, {Object? arguments}) {
    return Navigator.pushNamedAndRemoveUntil<T>(
      context,
      routeName,
      (route) => false,
      arguments: arguments,
    );
  }

  /// Go back
  static void goBack(BuildContext context, [dynamic result]) {
    Navigator.pop(context, result);
  }
}
