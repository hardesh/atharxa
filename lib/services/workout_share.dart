import 'dart:convert';

import '../app_info.dart';
import '../data/db.dart';
import '../data/workout_repo.dart';

/// Share workout plans as text (chat/email) or a file, and import them.
///
/// The text is a short how-to line followed by JSON, so it can be pasted
/// into any chat; [decode] finds the JSON inside whatever was pasted.
abstract final class WorkoutShare {
  static const format = 'workout-plans';
  static const version = 1;

  /// "workout-plan-lower-body-a.json" / "workout-plans.json".
  static String fileName(List<WorkoutPlan> plans) => plans.length == 1
      ? 'workout-plan-${plans.single.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '')}.json'
      : 'workout-plans.json';

  static Map<String, Object?> _plan(WorkoutPlan p) => {
    'name': p.name,
    'days': (p.days.toList()..sort()),
    'exercises': [
      for (final e in p.exercises)
        {
          'name': e.name,
          'sets': e.sets,
          'reps': e.reps,
          'kg': ?e.kg,
          'rest_s': e.restS,
          if (e.videos.isNotEmpty) 'videos': e.videos,
        },
    ],
  };

  /// Pretty JSON (for files).
  static String encodeJson(List<WorkoutPlan> plans) => const JsonEncoder.withIndent('  ').convert({
    'format': format,
    'version': version,
    'app': AppInfo.name,
    'plans': [for (final p in plans) _plan(p)],
  });

  /// A chat-friendly message: how-to line + compact JSON.
  static String encodeMessage(List<WorkoutPlan> plans) {
    final names = plans.map((p) => p.name).join(', ');
    return '${AppInfo.name} workout plan${plans.length == 1 ? '' : 's'}: $names\n'
        'To add it: open ${AppInfo.name} › Workout › Import, then paste this whole message.\n\n'
        '${jsonEncode({
          'format': format,
          'version': version,
          'plans': [for (final p in plans) _plan(p)],
        })}';
  }

  /// Plans found in [text] (a pasted message or a file). Throws
  /// [FormatException] with a user-facing message when nothing valid is found.
  static List<PlanDraft> decode(String text) {
    final start = text.indexOf('{'), end = text.lastIndexOf('}');
    if (start < 0 || end <= start) throw const FormatException('No workout plan found in that text.');
    final Object? j;
    try {
      j = jsonDecode(text.substring(start, end + 1));
    } on FormatException {
      throw const FormatException('The plan text looks incomplete — copy the whole message and try again.');
    }
    if (j is! Map || j['format'] != format || j['plans'] is! List) {
      throw const FormatException('That isn’t a shared workout plan.');
    }
    final drafts = <PlanDraft>[];
    for (final p in (j['plans'] as List).whereType<Map>()) {
      final name = (p['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      drafts.add(
        PlanDraft(
          name: name,
          days: {
            for (final d in (p['days'] as List? ?? const []))
              if (d is int && d >= 1 && d <= 7) d,
          },
          exercises: [
            for (final e in (p['exercises'] as List? ?? const []).whereType<Map>())
              if ((e['name'] as String?)?.trim().isNotEmpty == true)
                {
                  'name': (e['name'] as String).trim(),
                  'sets': ((e['sets'] as num?) ?? 3).toInt().clamp(1, 20),
                  'reps': ((e['reps'] as num?) ?? 10).toInt().clamp(1, 200),
                  'kg': (e['kg'] as num?)?.toDouble(),
                  'rest_s': ((e['rest_s'] as num?) ?? 90).toInt().clamp(0, 900),
                  'videos': e['videos'] is List ? jsonEncode((e['videos'] as List).whereType<String>().toList()) : null,
                },
          ],
        ),
      );
    }
    if (drafts.isEmpty) throw const FormatException('No workout plan found in that text.');
    return drafts;
  }

  /// Adds [drafts] as new plans (never overwrites); a name already in use
  /// gets " (2)", " (3)", …. Returns the names used.
  static Future<List<String>> import(AppDb db, List<PlanDraft> drafts) async {
    final repo = WorkoutRepo(db);
    final taken = {for (final p in await repo.plans()) p.name.toLowerCase()};
    final names = <String>[];
    for (final d in drafts) {
      var name = d.name;
      for (var n = 2; taken.contains(name.toLowerCase()); n++) {
        name = '${d.name} ($n)';
      }
      taken.add(name.toLowerCase());
      await repo.savePlan(name: name, days: d.days, exercises: d.exercises);
      names.add(name);
    }
    return names;
  }
}

/// A plan read from shared text, not yet saved.
class PlanDraft {
  const PlanDraft({required this.name, required this.days, required this.exercises});
  final String name;
  final Set<int> days;
  final List<Map<String, Object?>> exercises;
}
