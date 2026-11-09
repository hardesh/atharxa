import 'dart:async';

import 'package:atharxa/ai/ai_models.dart';
import 'package:atharxa/ai/ai_runtime.dart';
import 'package:atharxa/state/ai_controller.dart';
import 'package:atharxa/ui/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_helpers.dart';

/// In-memory runtime: instant downloads, canned replies.
class FakeAiRuntime implements AiRuntime {
  FakeAiRuntime({Set<String>? installed, this.reply = 'Try paneer tikka.'}) : installed = installed ?? {};
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
    onProgress(0.5);
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
  Future<AiConversation> open({String? system}) async => _FakeConversation(reply);
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
}
