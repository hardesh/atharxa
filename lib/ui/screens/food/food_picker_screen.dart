import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../data/food_repo.dart';
import '../../../data/models.dart';
import '../../../data/nutrition_sources.dart';
import '../../../state/core_providers.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import '../../widgets/tag.dart';
import 'food_editor_screen.dart';
import 'portion_dialog.dart';

/// Food picker (DESIGN.md §5, FoodPicker.dc.html): one search field, tabs
/// My foods / Online / Ask AI (coming soon), two-line results with kcal per
/// 100 g on the right. Picking a food opens the portion dialog and adds it to
/// [table] (food_logs or meal_plans) for [date]. Online picks are cached into
/// My foods automatically.
class FoodPickerScreen extends StatefulWidget {
  const FoodPickerScreen({super.key, required this.table, required this.date, required this.meal});

  final String table;
  final DateTime date;
  final Meal meal;

  static Future<void> open(BuildContext context, {required String table, required DateTime date, required Meal meal}) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => FoodPickerScreen(table: table, date: date, meal: meal),
        ),
      );

  @override
  State<FoodPickerScreen> createState() => _FoodPickerScreenState();
}

enum _Tab { mine, online, ai }

class _FoodPickerScreenState extends State<FoodPickerScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late final FoodRepo _repo = FoodRepo(context.db);
  final _online = OpenFoodFactsSource();
  final _query = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  StreamSubscription<String>? _sub;

  List<FoodItem> _results = [];
  bool _loading = false;
  String? _error;
  bool _offline = false;
  int _searchSeq = 0;

  _Tab get _tab => _Tab.values[_tabs.index];
  bool get _isPlan => widget.table == FoodRepo.plans;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      _search();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sub = context.db.changes.where((t) => t == 'foods').listen((_) {
        if (_tab == _Tab.mine) _search();
      });
      _search();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _tabs.dispose();
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _fail(int seq, {bool offline = false, String? error}) {
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = [];
      _offline = offline;
      _error = error;
    });
  }

  Future<void> _search() async {
    final seq = ++_searchSeq;
    final tab = _tab;
    if (tab == _Tab.ai) return;
    final q = _query.text.trim();
    if (tab == _Tab.online && q.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _offline = false;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    try {
      final r = tab == _Tab.mine ? await _repo.myFoods(q) : await _online.search(q);
      if (!mounted || seq != _searchSeq) return;
      setState(() => _results = r);
    } on SocketException {
      _fail(seq, offline: true);
    } on TimeoutException {
      _fail(seq, offline: true);
    } on http.ClientException {
      _fail(seq, offline: true);
    } catch (e) {
      _fail(seq, error: '$e');
    } finally {
      if (mounted && seq == _searchSeq) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: _tab == _Tab.online ? 600 : 120), _search);
    setState(() {});
  }

  Future<void> _pick(FoodItem food) async {
    final r = await PortionDialog.add(context, food, widget.meal);
    if (r == null || !mounted) return;
    final saved = await _repo.cache(food);
    await _repo.add(widget.table, day: dayKey(widget.date), meal: r.meal, food: saved, grams: r.grams);
    if (!mounted) return;
    Navigator.pop(context);
    showMessage(context, '${_isPlan ? 'Planned' : 'Added'} ${saved.name} · ${fmtGrams(r.grams)} g to ${r.meal.label}');
  }

  Future<void> _newFood() async {
    final f = await FoodEditorScreen.open(context, initialName: _query.text.trim(), meal: widget.meal);
    if (f != null && mounted) await _pick(f);
  }

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => _searchFocus.requestFocus()},
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.pop(context)),
          title: Text.rich(
            TextSpan(
              text: '${_isPlan ? 'Plan' : 'Add to'} ${widget.meal.label}',
              children: [
                if (wide)
                  TextSpan(
                    text: '  ·  ${relativeDay(widget.date)}',
                    style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newFood,
          icon: const Icon(Icons.add),
          label: const Text('New food'),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(context.screenPad, 4, context.screenPad, 8),
                  child: TextField(
                    controller: _query,
                    focusNode: _searchFocus,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Search foods',
                      hintText: _tab == _Tab.online ? 'Search Open Food Facts' : 'Search my foods',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.text.isEmpty
                          ? (wide ? const Padding(padding: EdgeInsets.all(14), child: Text('⌘F')) : null)
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _query.clear();
                                _onQueryChanged('');
                              },
                            ),
                    ),
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) => _search(),
                  ),
                ),
                TabBar(
                  controller: _tabs,
                  onTap: (i) {
                    if (i == _Tab.ai.index) {
                      _tabs.index = _tabs.previousIndex;
                      showMessage(context, 'Ask AI food search is coming in a later version.');
                    }
                  },
                  tabs: [
                    const Tab(text: 'My foods'),
                    const Tab(text: 'Online'),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Ask AI', style: TextStyle(color: context.cs.outline)),
                          const SizedBox(width: 6),
                          const Tag('soon', small: true),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
                Expanded(child: _body(wide)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(bool wide) {
    if (_offline) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: "You're offline",
        message: 'Online search needs an internet connection. My foods works offline.',
        action: OutlinedButton(onPressed: _search, child: const Text('Try again')),
      );
    }
    if (_error != null) {
      return EmptyState(icon: Icons.error_outline, title: 'Search failed', message: _error);
    }
    if (_results.isEmpty && !_loading) {
      return _tab == _Tab.mine
          ? EmptyState(
              icon: Icons.restaurant_menu,
              title: _query.text.isEmpty ? 'No saved foods yet' : 'No matches in My foods',
              message: 'Search the Online tab or add your own with "New food".',
            )
          : const EmptyState(
              icon: Icons.travel_explore,
              title: 'Search Open Food Facts',
              message: 'Type a food or brand. Foods you pick are saved to My foods.',
            );
    }
    if (wide && _tab == _Tab.mine) return _table();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: _results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(context.screenPad, 8, context.screenPad, 4),
            child: Text('kcal per 100 g', textAlign: TextAlign.right, style: context.tt.bodySmall),
          );
        }
        final f = _results[i - 1];
        return ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: context.screenPad),
          title: Text(f.name, style: context.tt.titleSmall),
          subtitle: (f.brand ?? '').isEmpty ? null : Text(f.brand!, style: context.tt.bodySmall),
          trailing: Text(fmtInt(f.per100g.kcal), style: context.tt.titleSmall),
          onTap: () => _pick(f),
          onLongPress: f.id == null ? null : () => FoodEditorScreen.open(context, food: f),
        );
      },
    );
  }

  /// Mac: My foods as a table with per-100 g columns and an edit button.
  Widget _table() {
    final head = context.tt.bodySmall;
    Widget num(String v, [TextStyle? s]) => SizedBox(
      width: 64,
      child: Text(v, textAlign: TextAlign.right, style: s ?? context.tt.bodyMedium),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(context.screenPad, 8, context.screenPad, 96),
      children: [
        Row(
          children: [
            Expanded(child: Text('Recently used · ${_results.length} foods', style: head)),
            num('kcal', head),
            num('Protein', head),
            num('Carbs', head),
            num('Fiber', head),
            num('Fat', head),
            const SizedBox(width: 48),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 48, bottom: 4),
            child: Text('per 100 g', style: head),
          ),
        ),
        const Divider(),
        for (final f in _results)
          InkWell(
            onTap: () => _pick(f),
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.cs.outlineVariant)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.name, style: context.tt.titleSmall),
                        Text(
                          [
                            if ((f.brand ?? '').isNotEmpty) f.brand!,
                            if (f.servingG != null) '${fmtGrams(f.servingG!)} g serving',
                          ].join(' · '),
                          style: context.tt.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  num(fmtInt(f.per100g.kcal), context.tt.titleSmall),
                  num(fmtMacro(f.per100g.protein)),
                  num(fmtMacro(f.per100g.carbs)),
                  num(fmtMacro(f.per100g.fiber)),
                  num(fmtMacro(f.per100g.fat)),
                  IconButton(
                    tooltip: 'Edit ${f.name}',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => FoodEditorScreen.open(context, food: f),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
