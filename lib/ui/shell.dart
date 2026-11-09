import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/food_repo.dart';
import '../state/reminders_controller.dart';
import 'screens/assistant/assistant_screen.dart';
import 'screens/finance/finance_screen.dart';
import 'screens/food/food_picker_screen.dart';

import 'screens/meal_plan_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/water_screen.dart';
import 'screens/workout/workout_screen.dart';
import 'screens/you/you_screen.dart';
import 'widgets/layout.dart';
import 'widgets/model_download_banner.dart';
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
    this.fullWidthHeader = false,
  });

  final String label;
  final IconData icon, selectedIcon;
  final WidgetBuilder build;
  final Widget Function(BuildContext context)? fab;
  final List<Widget> Function(BuildContext context, WidgetRef ref)? actions;
  final bool fullWidthHeader;
}

/// Responsive app shell (DESIGN.md §2):
/// phone → bottom NavigationBar (5 tabs), You via avatar;
/// ≥ 600 dp → NavigationRail with 6 destinations (5 + You).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    // "Add lunch" / tapping a meal reminder: open Overview and the food picker.
    ref.listenManual(pendingMealProvider, (_, meal) {
      if (meal == null) return;
      ref.read(pendingMealProvider.notifier).request(null);
      setState(() => _index = 0);
      FoodPickerScreen.open(context, table: FoodRepo.logs, date: DateTime.now(), meal: meal);
    }, fireImmediately: true);
  }

  int _index = 0;

  List<Destination> get _main => [
    Destination(
      label: 'Overview',
      icon: Icons.restaurant_outlined,
      selectedIcon: Icons.restaurant,
      build: (_) => const OverviewScreen(),
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
      build: (_) => const WaterScreen(),
    ),
    Destination(
      label: 'Workout',
      icon: Icons.fitness_center_outlined,
      selectedIcon: Icons.fitness_center,
      build: (_) => const WorkoutScreen(),
    ),
    Destination(
      label: 'Finance',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      build: (_) => const FinanceScreen(),
      fab: FinanceScreen.fab,
      actions: FinanceScreen.actions,
    ),
  ];

  Destination get _you => Destination(
    label: 'You',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    build: (_) => const YouScreen(),
    fullWidthHeader: true,
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
      appBar: AppTopBar(
        title: d.label,
        onOpenYou: _openYou,
        actions: d.actions?.call(context, ref) ?? const [],
        fullWidth: d.fullWidthHeader,
      ),
      // Wide layouts put primary actions in the header instead of a FAB.
      floatingActionButton: wide ? null : d.fab?.call(context),
      // Only the selected tab is built (not all of them kept alive), which
      // keeps memory and background work down; its data reloads quickly from
      // the local database when you come back.
      body: Column(
        children: [
          const ModelDownloadBanner(),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(d.label),
              child: Builder(builder: d.build),
            ),
          ),
        ],
      ),
    );

    final shortcuts = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => openAssistant(context),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => openAssistant(context),
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
          // Rail background runs to the top edge (under the macOS title bar);
          // only its contents are inset.
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
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
