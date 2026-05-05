import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ingredient.dart';

class IngredientService {
  final _client = Supabase.instance.client;
  static const _table = 'ingredients';

  Future<List<Ingredient>> getIngredients() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final data = await _client
        .from(_table)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (data as List).map((e) => Ingredient.fromJson(e)).toList();
  }

  Future<Ingredient> addIngredient(Map<String, dynamic> data) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('로그인이 필요합니다');

    final result = await _client
        .from(_table)
        .insert({...data, 'user_id': userId})
        .select()
        .single();

    return Ingredient.fromJson(result);
  }

  Future<Ingredient> updateIngredient(
      String id, Map<String, dynamic> data) async {
    final result = await _client
        .from(_table)
        .update(data)
        .eq('id', id)
        .select()
        .single();

    return Ingredient.fromJson(result);
  }

  Future<void> deleteIngredient(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}
