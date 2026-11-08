import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/meal_plan_screen.dart';
import 'screens/today_screen.dart';
import 'widgets/feedback.dart';
import 'widgets/layout.dart';
import 'widgets/top_bar.dart';

/// One main destination. [build] returns the page body (below the top bar).
class Destination {
  const Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.build,
    this.fab,
    this.actions,
  });

  final String label;
  final IconData icon, selectedIcon;
  final WidgetBuilder build;
  final Widget Function(BuildContext context)? fab;
  final List<Widget> Function(BuildContext context)? actions;
}

/// Responsive app shell (DESIGN.md §2):
/// phone → bottom NavigationBar (5 tabs), You via avatar;
/// ≥ 600 dp → NavigationRail with 6 destinations (5 + You).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  List<Destination> get _main => [
    Destination(
      label: 'Today',
      icon: Icons.restaurant_outlined,
      selectedIcon: Icons.restaurant,
      build: (_) => const TodayScreen(),
    ),
    Destination(
      label: 'Meal plan',
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
      build: (_) => const MealPlanScreen(),
    ),
    Destination(
      label: 'Water',
      icon: Icons.water_drop_outlined,
      selectedIcon: Icons.water_drop,
      build: (_) => const PlaceholderPage('Water'),
    ),
    Destination(
      label: 'Workout',
      icon: Icons.fitness_center_outlined,
      selectedIcon: Icons.fitness_center,
      build: (_) => const PlaceholderPage('Workout'),
    ),
    Destination(
      label: 'Finance',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      build: (_) => const PlaceholderPage('Finance'),
    ),
  ];

  Destination get _you => Destination(
    label: 'You',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    build: (_) => const PlaceholderPage('You'),
  );

  void _openYou() {
    if (context.isWide) {
      setState(() => _index = 5);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => Scaffold(
            appBar: AppBar(title: const Text('You')),
            body: _you.build(ctx),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    final dests = wide ? [..._main, _you] : _main;
    final index = _index.clamp(0, dests.length - 1);
    final d = dests[index];

    final page = Scaffold(
      appBar: AtharxaTopBar(title: d.label, onOpenYou: _openYou, actions: d.actions?.call(context) ?? const []),
      floatingActionButton: d.fab?.call(context),
      body: IndexedStack(
        index: index,
        children: [for (final x in dests) Builder(builder: x.build)],
      ),
    );

    final shortcuts = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => showAssistantComingSoon(context),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => showAssistantComingSoon(context),
      },
      child: Focus(autofocus: true, child: page),
    );

    if (!wide) {
      return Scaffold(
        body: shortcuts,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final x in dests)
              NavigationDestination(icon: Icon(x.icon), selectedIcon: Icon(x.selectedIcon), label: x.label),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              minWidth: 88,
              groupAlignment: -1,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final x in dests)
                  NavigationRailDestination(
                    icon: Icon(x.icon),
                    selectedIcon: Icon(x.selectedIcon),
                    label: Text(x.label),
                  ),
              ],
            ),
          ),
          Expanded(child: shortcuts),
        ],
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context) => Center(
    child: EmptyState(
      icon: Icons.construction_outlined,
      title: name,
      message: 'This screen arrives in an upcoming update.',
    ),
  );
}
