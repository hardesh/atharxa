import 'package:atharxa/ai/ai_models.dart';
import 'package:atharxa/ai/device_info.dart';
import 'package:flutter_test/flutter_test.dart';

AiModel _m(String id) => aiCatalog.firstWhere((m) => m.id == id);

void main() {
  // The devices this app targets, as they report themselves.
  const pixel10 = DeviceCapabilities(desktop: false, ramBytes: 11840768 * 1024, chip: 'Tensor G5');
  const pixel9a = DeviceCapabilities(desktop: false, ramBytes: 7700000 * 1024, chip: 'Tensor G4');
  const mac = DeviceCapabilities(desktop: true, ramBytes: 16 << 30, chip: 'Apple M1 Pro');

  test('RAM shows as sold', () {
    expect(pixel10.ramGb, 12);
    expect(pixel9a.ramGb, 8);
    expect(mac.ramGb, 16);
  });

  test('the Tensor G5 NPU build is offered only on a Tensor G5', () {
    expect(fitFor(_m('gemma-4-e2b-npu-g5'), pixel10), AiFit.fits);
    expect(fitFor(_m('gemma-4-e2b-npu-g5'), pixel9a), AiFit.otherChip);
    expect(fitFor(_m('gemma-4-e2b-npu-g5'), mac), AiFit.otherChip);
  });

  test('desktop-only models are not offered on phones', () {
    expect(fitFor(_m('qwen3.5-9b'), pixel10), AiFit.desktopOnly);
    expect(fitFor(_m('gemma-4-12b'), mac), AiFit.fits);
    expect(fitFor(_m('qwen3.5-9b'), mac), AiFit.fits);
  });

  test('fits by memory', () {
    expect(fitFor(_m('qwen3.5-2b'), pixel9a), AiFit.fits);
    expect(fitFor(_m('gemma-4-e2b'), pixel9a), AiFit.fits);
    expect(fitFor(_m('gemma-4-e4b'), pixel10), AiFit.fits);
    const small = DeviceCapabilities(desktop: false, ramBytes: 4 << 30);
    expect(fitFor(_m('gemma-4-e4b'), small), AiFit.tooLarge);
    // Unknown RAM: don't block anything.
    expect(fitFor(_m('gemma-4-e4b'), const DeviceCapabilities(desktop: false)), AiFit.fits);
  });

  test('recommended model per device', () {
    expect(recommendedFor(pixel10)?.id, 'gemma-4-e2b-npu-g5');
    expect(recommendedFor(pixel9a)?.id, 'gemma-4-e2b');
    expect(recommendedFor(mac)?.id, 'gemma-4-e4b');
    expect(recommendedFor(const DeviceCapabilities(desktop: false, ramBytes: 4 << 30))?.id, 'qwen3.5-2b');
  });

  test('catalog entries are pinned and well formed', () {
    final ids = <String>{};
    for (final m in aiCatalog) {
      expect(ids.add(m.id), isTrue, reason: 'duplicate id ${m.id}');
      expect(m.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: m.id);
      expect(m.revision, matches(RegExp(r'^[0-9a-f]{40}$')), reason: m.id);
      expect(m.url, startsWith('https://huggingface.co/${m.repo}/resolve/${m.revision}/'));
      expect(m.engine == AiEngine.litert ? m.fileName.endsWith('.litertlm') : m.fileName.endsWith('.gguf'), isTrue);
    }
  });

  test('imported files', () {
    final q = AiModel.imported('Qwen3.5-4B-Q8_0.gguf', 4 << 30);
    expect(q.family, AiFamily.qwen);
    expect(q.engine, AiEngine.llama);
    expect(q.name, 'Qwen3.5-4B-Q8_0');
    expect(q.imported, isTrue);
    expect(AiModel.imported('gemma-custom.litertlm', 1).engine, AiEngine.litert);
    expect(AiModel.isModelFile('notes.txt'), isFalse);
    expect(AiModel.isModelFile('X.GGUF'), isTrue);
  });

  test('device facts parse', () {
    expect(parseMemTotal('MemTotal:       11840768 kB\nMemFree: 1 kB'), 11840768 * 1024);
    expect(parseMemTotal(null), isNull);
    const df =
        'Filesystem     1K-blocks     Used Available Use% Mounted on\n/dev/fuse  235000000 120000000 115000000  52% /data';
    expect(parseDfAvailable(df), 115000000 * 1024);
    expect(parseDfAvailable(''), isNull);
  });
}
