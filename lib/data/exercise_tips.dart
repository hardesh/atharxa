import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Offline form cues per exercise (assets/data/exercise_tips.json).
class ExerciseTips {
  const ExerciseTips(this.tips, this.mistake);
  final List<String> tips;
  final String? mistake;

  static Map<String, ExerciseTips>? _all;

  /// Exact name first, then the longest key contained in the name
  /// ("Goblet squat" → "goblet squat"; "Front squat" → "squat").
  static Future<ExerciseTips?> forExercise(String name) async {
    _all ??= _parse(await rootBundle.loadString('assets/data/exercise_tips.json'));
    return match(_all!, name);
  }

  static ExerciseTips? match(Map<String, ExerciseTips> all, String name) {
    final n = name.toLowerCase().trim();
    if (all.containsKey(n)) return all[n];
    final keys = all.keys.where(n.contains).toList()..sort((a, b) => b.length.compareTo(a.length));
    return keys.isEmpty ? null : all[keys.first];
  }

  static Map<String, ExerciseTips> _parse(String json) => {
    for (final e in (jsonDecode(json) as Map<String, dynamic>).entries)
      e.key: ExerciseTips(((e.value as Map)['tips'] as List).cast<String>(), (e.value as Map)['mistake'] as String?),
  };

  static Map<String, ExerciseTips> parseForTest(String json) => _parse(json);
}
