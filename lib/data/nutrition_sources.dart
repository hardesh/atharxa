import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';

import 'db.dart';
import 'food_repo.dart';
import 'models.dart';

/// Anything that can answer "what's the nutrition of X?".
///
/// Implementations today: [LocalFoodsSource] (your custom foods) and
/// [OpenFoodFactsSource]. A local-LLM source can be added later by
/// implementing this interface and registering it in the food picker.
abstract class NutritionSource {
  String get name;
  bool get needsNetwork;
  Future<List<FoodItem>> search(String query);
}

class LocalFoodsSource implements NutritionSource {
  LocalFoodsSource(this.db);
  final AppDb db;

  @override
  String get name => 'My foods';
  @override
  bool get needsNetwork => false;

  @override
  Future<List<FoodItem>> search(String query) => FoodRepo(db).myFoods(query);
}

class OpenFoodFactsSource implements NutritionSource {
  static const _ua = '${AppInfo.name}/1.0 (personal nutrition tracker)';

  @override
  String get name => 'Open Food Facts';
  @override
  bool get needsNetwork => true;

  @override
  Future<List<FoodItem>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.https('world.openfoodfacts.org', '/cgi/search.pl', {
      'search_terms': query,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '30',
      'fields': 'code,product_name,brands,nutriments,serving_quantity',
    });
    final res = await http.get(uri, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw OnlineSearchException('Open Food Facts is not responding (${res.statusCode}).');
    final products = (jsonDecode(res.body)['products'] as List?) ?? [];
    return products.map((p) => _parse(p as Map<String, dynamic>)).whereType<FoodItem>().toList();
  }

  Future<FoodItem?> byBarcode(String code) async {
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$code.json', {
      'fields': 'code,product_name,brands,nutriments,serving_quantity',
    });
    final res = await http.get(uri, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 1) return null;
    return _parse(body['product'] as Map<String, dynamic>);
  }

  FoodItem? _parse(Map<String, dynamic> p) {
    final name = (p['product_name'] as String?)?.trim();
    final n = (p['nutriments'] as Map?)?.cast<String, dynamic>() ?? {};
    double? num_(String k) {
      final v = n[k];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    var kcal = num_('energy-kcal_100g');
    final kj = num_('energy_100g');
    if (kcal == null && kj != null) kcal = kj / 4.184;
    if (name == null || name.isEmpty || kcal == null) return null;
    return FoodItem(
      name: name,
      brand: (p['brands'] as String?)?.split(',').first.trim(),
      barcode: p['code'] as String?,
      servingG: switch (p['serving_quantity']) {
        final num v when v > 0 => v.toDouble(),
        final String v => double.tryParse(v),
        _ => null,
      },
      source: 'off',
      per100g: Nutrients(
        kcal: kcal,
        // Missing nutrients stay null (unknown), never 0 (DESIGN.md §7.4).
        protein: num_('proteins_100g'),
        carbs: num_('carbohydrates_100g'),
        fiber: num_('fiber_100g'),
        fat: num_('fat_100g'),
      ),
    );
  }
}

class OnlineSearchException implements Exception {
  OnlineSearchException(this.message);
  final String message;
  @override
  String toString() => message;
}
