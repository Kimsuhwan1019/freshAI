import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecipeService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  // ── Favorites ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> loadFavorites() async {
    if (_userId == null) return [];
    try {
      final data = await _client
          .from('recipe_favorites')
          .select()
          .eq('user_id', _userId!)
          .order('saved_at', ascending: false);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> addFavorite(String title, String content) async {
    if (_userId == null) return;
    try {
      await _client.from('recipe_favorites').upsert({
        'user_id': _userId,
        'title': title,
        'content': content,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,title');
    } catch (_) {}
  }

  Future<void> removeFavorite(String title) async {
    if (_userId == null) return;
    try {
      await _client
          .from('recipe_favorites')
          .delete()
          .eq('user_id', _userId!)
          .eq('title', title);
    } catch (_) {}
  }

  Future<void> clearFavorites() async {
    if (_userId == null) return;
    try {
      await _client
          .from('recipe_favorites')
          .delete()
          .eq('user_id', _userId!);
    } catch (_) {}
  }

  // ── History ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> loadHistory() async {
    if (_userId == null) return [];
    try {
      final data = await _client
          .from('recipe_history')
          .select()
          .eq('user_id', _userId!)
          .order('timestamp', ascending: false)
          .limit(5);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> addHistory({
    required String id,
    required DateTime timestamp,
    required List<String> ingredientNames,
    required List<Map<String, String>> recipes,
  }) async {
    if (_userId == null) return;
    try {
      await _client.from('recipe_history').upsert({
        'id': id,
        'user_id': _userId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'ingredient_names': ingredientNames,
        'recipes': recipes,
      }, onConflict: 'id,user_id');

      // Enforce max 5 entries per user
      final all = await _client
          .from('recipe_history')
          .select('id')
          .eq('user_id', _userId!)
          .order('timestamp', ascending: false);
      if ((all as List).length > 5) {
        final toDelete = all.skip(5).map((e) => e['id'] as String).toList();
        await _client
            .from('recipe_history')
            .delete()
            .eq('user_id', _userId!)
            .inFilter('id', toDelete);
      }
    } catch (_) {}
  }

  Future<void> deleteHistoryEntry(String id) async {
    if (_userId == null) return;
    try {
      await _client
          .from('recipe_history')
          .delete()
          .eq('user_id', _userId!)
          .eq('id', id);
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    if (_userId == null) return;
    try {
      await _client
          .from('recipe_history')
          .delete()
          .eq('user_id', _userId!);
    } catch (_) {}
  }

  // ── Migration: clear old SharedPreferences cache ───────────

  Future<void> clearLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove('fresh_ai_favorites'),
      prefs.remove('fresh_ai_recipe_history'),
    ]);
  }
}
