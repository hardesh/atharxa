import 'dart:async';

import 'package:atharxa/app_clock.dart';
import 'package:atharxa/ai/ai_models.dart';
import 'package:atharxa/ai/ai_runtime.dart';
import 'package:atharxa/data/chat_repo.dart';
import 'package:atharxa/data/food_repo.dart';
import 'package:atharxa/data/models.dart';
import 'package:atharxa/state/ai_controller.dart';
import 'package:atharxa/ui/widgets/meal_card.dart';
import 'package:atharxa/ui/widgets/model_download_banner.dart';
import 'package:atharxa/ui/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nutrition_test.dart' as sample;
import 'render_helpers.dart';

/// In-memory runtime: instant downloads, canned replies.
class FakeAiRuntime implements AiRuntime {
  FakeAiRuntime({Set<String>? installed, this.reply = 'Try paneer tikka.', this.gate}) : installed = installed ?? {};

  /// When set, downloads stop at 40 % until it completes.
  final Completer<void>? gate;
  final Set<String> installed;
  final String reply;
  String? loaded;

  static const pixel10 = DeviceCapabilities(
    desktop: false,
    ramBytes: 11840768 * 1024,
    chip: 'Tensor G5',
    freeBytes: 84000000000,
  );

  @override
  Future<DeviceCapabilities> deviceCapabilities() async => pixel10;
  @override
  Future<Set<String>> installedFiles() async => {...installed};
  @override
  Future<List<AiModel>> importedModels() async => const [];
  @override
  Future<void> download(AiModel m, {required void Function(double) onProgress, required AiCancel cancel}) async {
    onProgress(gate == null ? 0.5 : 0.4);
    await gate?.future;
    installed.add(m.fileName);
  }

  @override
  Future<AiModel> importFile(String path) => throw UnimplementedError();
  @override
  Future<void> remove(AiModel m) async => installed.remove(m.fileName);
  @override
  Future<AiBackend?> load(AiModel m) async {
    loaded = m.id;
    return AiBackend.npu;
  }

  @override
  Future<AiConversation> open({String? system}) async {
    this.system = system;
    return _FakeConversation(reply);
  }

  /// The instructions the last conversation was opened with.
  String? system;
  @override
  Future<void> unload() async => loaded = null;
}

class _FakeConversation implements AiConversation {
  _FakeConversation(this.reply);
  final String reply;
  @override
  Stream<String> send(String text) => Stream.fromIterable(reply.split(RegExp(r'(?<= )')));
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

void main() {
  setUpAll(loadFonts);

  testWidgets('assistant: set up, download the recommended model, chat', (tester) async {
    setSize(tester, const Size(412, 900));
    final rt = FakeAiRuntime();
    final t = await tester.runAsync(
      () => buildTestApp(prefs: {'ai_wifi_only': false}, overrides: [aiRuntimeProvider.overrideWithValue(rt)]),
    );
    await tester.pumpWidget(t!.app);
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('Ask Atharxa'));
    await step(tester);
    expect(find.text('Set up the assistant'), findsOneWidget);

    // Pixel 10: the NPU build is suggested first.
    await tester.tap(find.textContaining('Download Gemma 4 E2B · NPU'));
    await step(tester);
    expect(rt.installed, contains('gemma-4-E2B-it_Google_Tensor_G5.litertlm'));
    expect(find.text('Ask anything'), findsOneWidget);
    expect(find.textContaining('Gemma 4 E2B · NPU'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'Dinner idea?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await step(tester);
    expect(find.text('Dinner idea?'), findsOneWidget);
    expect(find.text('Try paneer tikka.'), findsOneWidget);
    expect(find.textContaining('Read Today’s log'), findsOneWidget);
    expect(rt.system, contains('DATA: {'));
    expect(rt.loaded, 'gemma-4-e2b-npu-g5');
  });

  for (final (name, size) in [('phone', const Size(412, 1500)), ('mac', const Size(1200, 1100))]) {
    testWidgets('AI models page · $name', (tester) async {
      setSize(tester, size);
      final rt = FakeAiRuntime(installed: {'Qwen3.5-2B-Q4_K_M.gguf'});
      final t = await tester.runAsync(
        () => buildTestApp(prefs: {'ai_wifi_only': false}, overrides: [aiRuntimeProvider.overrideWithValue(rt)]),
      );
      await tester.pumpWidget(t!.app);
      await settle(tester);
      if (name == 'phone') {
        await tester.tap(find.descendant(of: find.byType(AppTopBar), matching: find.byType(CircleAvatar)));
      } else {
        await goTo(tester, 'You');
      }
      await step(tester);
      await tester.tap(find.text('AI models'));
      await step(tester);
      expect(find.textContaining('12 GB RAM · Tensor G5'), findsOneWidget);
      expect(find.text('Qwen3.5 2B'), findsWidgets);
      expect(find.text('Recommended'), findsOneWidget);
      // Mac-only models are listed but can't be downloaded on a phone.
      expect(find.text('Mac only'), findsWidgets);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/ai_models_$name.png'));
    });
  }

  testWidgets('download banner: progress on every screen, then ready', (tester) async {
    setSize(tester, const Size(412, 900));
    final gate = Completer<void>();
    final rt = FakeAiRuntime(gate: gate);
    final t = await tester.runAsync(
      () => buildTestApp(prefs: {'ai_wifi_only': false}, overrides: [aiRuntimeProvider.overrideWithValue(rt)]),
    );
    await tester.pumpWidget(t!.app);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Ask Atharxa'));
    await step(tester);
    await tester.tap(find.textContaining('Download Gemma 4 E2B · NPU'));
    await step(tester);
    await tester.pageBack();
    await step(tester);
    expect(find.text('Downloading Gemma 4 E2B · NPU'), findsOneWidget);
    expect(find.textContaining('40 % · 1.2 GB of 3.1 GB'), findsOneWidget);
    await expectLater(find.byType(ModelDownloadBanner), matchesGoldenFile('goldens/download_banner_phone.png'));

    gate.complete();
    await step(tester);
    expect(find.text('Gemma 4 E2B · NPU is ready'), findsOneWidget);
    await tester.tap(find.text('Open assistant'));
    await step(tester);
    expect(find.text('Ask anything'), findsOneWidget);
    await tester.pageBack();
    await step(tester);
    expect(find.textContaining('is ready'), findsNothing);
  });

  testWidgets('a download cut off by closing the app is offered again', (tester) async {
    setSize(tester, const Size(412, 900));
    final rt = FakeAiRuntime();
    final t = await tester.runAsync(
      () => buildTestApp(
        prefs: {'ai_wifi_only': false, 'ai_pending_download': 'qwen3.5-2b'},
        overrides: [aiRuntimeProvider.overrideWithValue(rt)],
      ),
    );
    await tester.pumpWidget(t!.app);
    await settle(tester);
    expect(find.text('Download of Qwen3.5 2B stopped'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await step(tester);
    expect(rt.installed, contains('Qwen3.5-2B-Q4_K_M.gguf'));
    expect(find.text('Qwen3.5 2B is ready'), findsOneWidget);
  });

  testWidgets('answers offer My foods they name; chats are saved and reopened', (tester) async {
    setSize(tester, const Size(412, 900));
    final rt = FakeAiRuntime(installed: {'gemma-4-E2B-it.litertlm'}, reply: 'Have Paneer bhurji tonight.');
    final t = await tester.runAsync(
      () => buildTestApp(prefs: {'ai_wifi_only': false}, overrides: [aiRuntimeProvider.overrideWithValue(rt)]),
    );
    await tester.runAsync(() => FoodRepo(t!.db).cache(sample.paneer));
    await tester.pumpWidget(t!.app);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Ask Atharxa'));
    await step(tester);
    await tester.enterText(find.byType(TextField), 'Dinner idea?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await step(tester);

    final meal = mealForNow();
    final chip = find.textContaining('Add Paneer bhurji to ${meal.label} · 100 g · 220 kcal');
    expect(chip, findsOneWidget);
    expect(find.text('Try another'), findsOneWidget);
    await tester.tap(chip);
    await step(tester);
    final logged = await tester.runAsync(() => FoodRepo(t.db).entries(FoodRepo.logs, dayKey(AppClock.now())));
    expect(logged!.single.name, 'Paneer bhurji');
    expect(find.text('Added Paneer bhurji to ${meal.label}'), findsOneWidget);

    // Saved: start a new chat, then reopen it from history.
    await tester.tap(find.byTooltip('New chat'));
    await step(tester);
    expect(find.text('Ask anything'), findsOneWidget);
    await tester.tap(find.byTooltip('Chat history'));
    await step(tester);
    await tester.tap(find.text('Dinner idea?'));
    await step(tester);
    expect(find.text('Have Paneer bhurji tonight.'), findsOneWidget);
  });

  testWidgets('assistant · mac: chat history on the left', (tester) async {
    setSize(tester, const Size(1200, 800));
    final rt = FakeAiRuntime(
      installed: {'gemma-4-E4B-it.litertlm'},
      reply: 'Paneer bhurji with a Roti fits: about 520 kcal and 23 g protein, leaving 380 kcal for the day.',
    );
    final t = await tester.runAsync(
      () => buildTestApp(prefs: {'ai_wifi_only': false}, overrides: [aiRuntimeProvider.overrideWithValue(rt)]),
    );
    await tester.runAsync(() async {
      final food = FoodRepo(t!.db);
      await food.cache(sample.paneer);
      await food.cache(sample.roti);
      await ChatRepo(t.db).save(messages: [(true, 'How much did I spend on food this month?'), (false, '₹5,050.')]);
    });
    await tester.pumpWidget(t!.app);
    await settle(tester);
    await tester.tap(find.textContaining('Ask Atharxa'));
    await step(tester);
    await tester.enterText(find.byType(TextField), 'Suggest a high-protein dinner under 700 kcal from my foods');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await step(tester);
    expect(find.text('How much did I spend on food this month?'), findsOneWidget);
    expect(find.textContaining('Add Roti to Lunch'), findsOneWidget); // 12:30 on the test clock
    // The answered chat is saved and joins the history list.
    for (var i = 0; i < 50 && find.byTooltip('Delete chat').evaluate().length < 2; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.byTooltip('Delete chat'), findsNWidgets(2));
    await tester.pump();
    final tiles = tester.widgetList<ListTile>(
      find.ancestor(of: find.byTooltip('Delete chat'), matching: find.byType(ListTile)),
    );
    expect(tiles.where((t) => t.selected).length, 1, reason: 'the open chat is highlighted');
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/assistant_mac.png'));
  });
}
