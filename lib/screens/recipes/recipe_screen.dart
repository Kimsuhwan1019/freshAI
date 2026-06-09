import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/ingredient.dart';
import '../../services/ingredient_service.dart';
import '../../services/openai_service.dart';
import '../../services/recipe_service.dart';
import '../../services/unsplash_service.dart';
import '../../services/animation_settings.dart';
import '../../utils/expiry_utils.dart';

// ──────────────────────────────────────────────────────────────
//  Main Screen
// ──────────────────────────────────────────────────────────────

class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key});

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  final _ingredientSvc = IngredientService();
  final _openAI = OpenAIService();
  final _recipeSvc = RecipeService();

  List<Ingredient> _ingredients = [];
  Set<String> _selectedIds = {};

  List<_RecipeCard> _recipes = [];
  bool _isLoading = false;
  bool _isFetching = true;
  int _lastRecommendedCount = 0;

  List<_HistoryEntry> _history = [];
  List<_FavoriteRecipe> _favorites = [];
  Set<String> _favoriteIds = {};   // recipe title set for O(1) lookup

  String _selectedDifficulty = '상관없음';
  String _selectedCookTime = '상관없음';
  String? _selectedRecipeStorageType;
  bool _buttonPressed = false;

  // ── Computed ───────────────────────────────────────────────

  List<Ingredient> get _selectedIngredients =>
      _ingredients.where((i) => _selectedIds.contains(i.id)).toList();

  List<Ingredient> get _expiringIngredients {
    final result = _ingredients.where((i) {
      final days = ExpiryUtils.daysUntil(i.expiryDate);
      return days != null && days <= 3;
    }).toList()
      ..sort((a, b) {
        final da = ExpiryUtils.daysUntil(a.expiryDate) ?? 999;
        final db = ExpiryUtils.daysUntil(b.expiryDate) ?? 999;
        return da.compareTo(db); // 만료된 것 먼저, 그 다음 임박순
      });
    return result;
  }

  bool get _allSelected =>
      _selectedIds.length == _ingredients.length && _ingredients.isNotEmpty;

  bool get _selectionChanged =>
      _recipes.isNotEmpty &&
      _selectedIngredients.length != _lastRecommendedCount;

  // ── Init ───────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _openAI.loadApiKey();
    await Future.wait([
      _loadIngredients(),
      _loadHistory(),
      _loadFavorites(),
    ]);
  }

  // ── Ingredient loading ─────────────────────────────────────

  Future<void> _loadIngredients() async {
    setState(() => _isFetching = true);
    try {
      final data = await _ingredientSvc.getIngredients();
      if (mounted) {
        setState(() {
          final prevDeselected = _ingredients
              .map((i) => i.id)
              .where((id) => !_selectedIds.contains(id))
              .toSet();
          _ingredients = data;
          _selectedIds = data
              .map((i) => i.id)
              .where((id) => !prevDeselected.contains(id))
              .toSet();
        });
      }
    } catch (e) {
      if (mounted) _showSnack('식재료 불러오기 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  // ── History ────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    final data = await _recipeSvc.loadHistory();
    if (mounted) {
      setState(() {
        _history = data.map((e) => _HistoryEntry(
          id: e['id'] as String,
          timestamp: DateTime.parse(e['timestamp'] as String),
          ingredientNames: (e['ingredient_names'] as List).cast<String>(),
          recipes: (e['recipes'] as List)
              .map((r) => _RecipeCard(
                    title: r['title'] as String,
                    content: r['content'] as String,
                  ))
              .toList(),
        )).toList();
      });
    }
  }

  Future<void> _addToHistory(
      List<String> names, List<_RecipeCard> recipes) async {
    final entry = _HistoryEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      ingredientNames: names,
      recipes: recipes,
    );
    setState(() {
      _history.insert(0, entry);
      if (_history.length > 5) _history = _history.sublist(0, 5);
    });
    _recipeSvc.addHistory(
      id: entry.id,
      timestamp: entry.timestamp,
      ingredientNames: names,
      recipes: recipes
          .map((r) => {'title': r.title, 'content': r.content})
          .toList(),
    );
  }

  Future<void> _clearHistory() async {
    setState(() => _history.clear());
    await _recipeSvc.clearHistory();
  }

  Future<void> _deleteHistoryEntry(String id) async {
    setState(() => _history.removeWhere((e) => e.id == id));
    await _recipeSvc.deleteHistoryEntry(id);
  }

  // ── Favorites ──────────────────────────────────────────────

  Future<void> _loadFavorites() async {
    final data = await _recipeSvc.loadFavorites();
    if (mounted) {
      setState(() {
        _favorites = data.map((e) => _FavoriteRecipe(
          title: e['title'] as String,
          content: e['content'] as String,
          savedAt: DateTime.parse(e['saved_at'] as String),
        )).toList();
        _favoriteIds = _favorites.map((f) => f.title).toSet();
      });
    }
  }

  void _toggleFavorite(_RecipeCard recipe) {
    if (_favoriteIds.contains(recipe.title)) {
      _confirmRemoveFavorite(recipe.title);
    } else {
      _addFavorite(recipe);
    }
  }

  void _addFavorite(_RecipeCard recipe) {
    final fav = _FavoriteRecipe(
      title: recipe.title,
      content: recipe.content,
      savedAt: DateTime.now(),
    );
    setState(() {
      _favorites.removeWhere((f) => f.title == recipe.title);
      _favorites.insert(0, fav);
      _favoriteIds.add(recipe.title);
    });
    _recipeSvc.addFavorite(recipe.title, recipe.content);
  }

  void _removeFavorite(String title) {
    setState(() {
      _favorites.removeWhere((f) => f.title == title);
      _favoriteIds.remove(title);
    });
    _recipeSvc.removeFavorite(title);
  }

  void _confirmRemoveFavorite(String title) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('즐겨찾기 해제'),
        content: const Text('관심 레시피에서 해제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소',
                style: TextStyle(color: Color(0xFF9A9A9A))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeFavorite(title);
            },
            child: const Text('확인',
                style: TextStyle(
                    color: Color(0xFFFF453A),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearFavorites() async {
    setState(() {
      _favorites.clear();
      _favoriteIds.clear();
    });
    await _recipeSvc.clearFavorites();
  }

  // ── Selection ──────────────────────────────────────────────

  void _selectAll() =>
      setState(() => _selectedIds = _ingredients.map((i) => i.id).toSet());

  void _deselectAll() => setState(() => _selectedIds.clear());

  void _toggleIngredientsByName(String name, List<String> ids) =>
      setState(() {
        if (ids.any((id) => _selectedIds.contains(id))) {
          _selectedIds.removeAll(ids);
        } else {
          _selectedIds.addAll(ids);
        }
      });

  Color _recipeStorageColor(String? type) {
    switch (type) {
      case '냉장': return const Color(0xFF42A5F5);
      case '냉동': return const Color(0xFF90CAF9);
      case '상온': return const Color(0xFFFF9F0A);
      default: return const Color(0xFF76C442);
    }
  }

  // ── Recipe generation ──────────────────────────────────────

  Future<void> _getRecipes() async {
    final selected = _selectedIngredients;
    if (selected.isEmpty) {
      _showSnack('식재료를 하나 이상 선택해주세요');
      return;
    }
    setState(() {
      _isLoading = true;
      _recipes = [];
    });
    try {
      final names = selected.map((i) => i.name).toList();
      final result = await _openAI.recommendRecipes(
        names,
        difficulty: _selectedDifficulty == '상관없음' ? null : _selectedDifficulty,
        cookTime: _selectedCookTime == '상관없음' ? null : _selectedCookTime,
      );
      if (mounted) {
        final parsed = _parseRecipes(result);
        setState(() {
          _recipes = parsed;
          _lastRecommendedCount = selected.length;
        });
        await _addToHistory(names, parsed);
      }
    } catch (e) {
      _showSnack('레시피 생성 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  List<_RecipeCard> _parseRecipes(String content) {
    return content
        .split('---')
        .where((s) => s.trim().isNotEmpty)
        .map((s) {
          String title = '레시피';
          for (final line in s.split('\n')) {
            if (line.startsWith('## ')) {
              title = line.substring(3).trim();
              break;
            }
          }
          return _RecipeCard(title: title, content: s.trim());
        })
        .toList();
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? const Color(0xFFFF453A) : const Color(0xFF76C442),
      ),
    );
  }

  // ── Cooking complete ───────────────────────────────────────

  Future<void> _showCookingCompleteDialog(_RecipeCard recipe) async {
    List<Ingredient> freshIngredients = List.from(_ingredients);
    try {
      freshIngredients = await _ingredientSvc.getIngredients();
      if (mounted) setState(() => _ingredients = freshIngredients);
    } catch (_) {}

    if (!mounted) return;

    final names = _parseIngredientsFromRecipe(recipe.content);
    final entries = names.expand<_CookingEntry>((name) {
      final lower = name.toLowerCase();
      final candidates = freshIngredients.where((i) {
        final n = i.name.toLowerCase();
        return n == lower || n.contains(lower) || lower.contains(n);
      }).toList()
        ..sort((a, b) {
          if (a.expiryDate == null && b.expiryDate == null) return 0;
          if (a.expiryDate == null) return 1;
          if (b.expiryDate == null) return -1;
          return a.expiryDate!.compareTo(b.expiryDate!);
        });
      return candidates.map((c) => _CookingEntry(recipeName: name, ingredient: c));
    }).toList();

    showDialog(
      context: context,
      builder: (_) => _CookingCompleteDialog(
        recipeName: recipe.title,
        entries: entries,
        onConfirm: _applyIngredientUsage,
      ),
    );
  }

  List<String> _parseIngredientsFromRecipe(String content) {
    final names = <String>[];
    bool inIngredients = false;

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (RegExp(r'^#{1,3}\s*(재료|식재료)').hasMatch(line)) {
        inIngredients = true;
        continue;
      }
      if (line.startsWith('#') && inIngredients) {
        inIngredients = false;
      }

      if (inIngredients && line.startsWith('-')) {
        var name = line.substring(1).trim();
        name = name.split(':').first.trim();
        name = name.split('(').first.trim();
        // \w는 한글 미인식 → [^\s]*로 한글 단위(개,모,g 등) 포함 제거
        name = name
            .replaceAll(RegExp(r'\s+[\d/.~]+[^\s]*\s*$'), '')
            .trim();
        name = name
            .replaceAll(
                RegExp(r'\s+(적당량|약간|조금|적량)\s*$'), '')
            .trim();
        if (name.length >= 2) names.add(name);
      }
    }
    return names.toSet().toList();
  }

  Future<void> _applyIngredientUsage(List<_CookingEntry> entries) async {
    for (final entry in entries.where((e) => e.included)) {
      final ingredient = entry.ingredient;
      final used = double.tryParse(entry.qtyCtrl.text.trim()) ?? 1.0;
      final current = ingredient.quantity ?? 1.0;
      final newQty = current - used;

      if (newQty <= 0) {
        await _ingredientSvc.deleteIngredient(ingredient.id);
      } else {
        await _ingredientSvc.updateIngredient(
          ingredient.id,
          {'quantity': newQty},
        );
      }
    }
    await _loadIngredients();
    if (mounted) _showSnack('요리 완료! 식재료가 업데이트됐어요 🎉');
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIngredients;
    final expiring = _expiringIngredients;

    return Scaffold(
      body: _isFetching
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF76C442)))
          : CustomScrollView(
              slivers: [
                _buildSliverAppBar(selected),

                // Expiring section
                if (expiring.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _buildExpiringSoonSection(expiring),
                    ),
                  ),

                // Ingredient selector
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        16, expiring.isEmpty ? 16 : 12, 16, 0),
                    child: _buildIngredientSelector(selected),
                  ),
                ),

                // Filter section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildFilterSection(),
                  ),
                ),

                // Change banner
                if (_selectionChanged)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: _buildChangeBanner(selected),
                    ),
                  ),

                // Recommend button
                if (_recipes.isEmpty && !_isLoading)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _buildRecommendButton(selected),
                    ),
                  ),

                // Loading
                if (_isLoading)
                  const SliverFillRemaining(child: _LoadingState()),

                // Active recipe cards
                if (_recipes.isNotEmpty && !_isLoading) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('AI 추천 레시피',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.3)),
                                Text('$_lastRecommendedCount개 식재료 기준',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6A6A6A))),
                              ],
                            ),
                          ),
                          _refreshButton(selected),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _RecipeCardWidget(
                          recipe: _recipes[i],
                          isFavorited:
                              _favoriteIds.contains(_recipes[i].title),
                          onToggleFavorite: () =>
                              _toggleFavorite(_recipes[i]),
                          onCookingComplete: () =>
                              _showCookingCompleteDialog(_recipes[i]),
                        ),
                      ),
                      childCount: _recipes.length,
                    ),
                  ),
                ],

                // Favorites section
                if (_favorites.isNotEmpty && !_isLoading)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: _buildFavoritesSection(),
                    ),
                  ),

                // History section
                if (_history.isNotEmpty && !_isLoading)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: _buildHistorySection(),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
    );
  }

  // ── App bar ────────────────────────────────────────────────

  Widget _buildSliverAppBar(List<Ingredient> selected) {
    return SliverAppBar(
      floating: true,
      snap: true,
      toolbarHeight: _ingredients.isNotEmpty ? 68 : kToolbarHeight,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AI 레시피',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  letterSpacing: -0.5)),
          if (_ingredients.isNotEmpty)
            Text('${selected.map((i) => i.name).toSet().length}종류 선택됨',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF76C442),
                    fontWeight: FontWeight.w500)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadIngredients,
          tooltip: '식재료 새로고침',
        ),
      ],
    );
  }

  // ── Expiring soon section ──────────────────────────────────

  Widget _buildExpiringSoonSection(List<Ingredient> expiring) {
    final hasExpired = expiring.any(
        (i) => (ExpiryUtils.daysUntil(i.expiryDate) ?? 1) <= 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasExpired
              ? const Color(0xFFFF453A).withValues(alpha: 0.5)
              : const Color(0xFFFF9F0A).withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F0A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                    child: Text('⚠️', style: TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('아래 식재료들을 먼저 사용해보세요!',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                            letterSpacing: -0.2)),
                    SizedBox(height: 3),
                    Text(
                      '재료 선택 칸에서 선택 후 레시피를 추천받을 수 있어요',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF9A9A9A)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Ingredient chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: expiring.map((i) {
              final days = ExpiryUtils.daysUntil(i.expiryDate)!;
              final chipColor = ExpiryUtils.color(days);
              final isSelected = _selectedIds.contains(i.id);

              return GestureDetector(
                onTap: () => setState(() {
                  if (isSelected) {
                    _selectedIds.remove(i.id);
                  } else {
                    _selectedIds.add(i.id);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF76C442).withValues(alpha: 0.18)
                        : chipColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF76C442)
                          : chipColor.withValues(alpha: 0.5),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected) ...[
                        const Icon(Icons.check_rounded,
                            size: 12, color: Color(0xFF76C442)),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        i.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? const Color(0xFF76C442)
                              : Colors.white,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: chipColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ExpiryUtils.label(days),
                          style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Ingredient selector ────────────────────────────────────

  Widget _buildIngredientSelector(List<Ingredient> selected) {
    // Filter by storage type, deduplicate by name, sort alphabetically
    final filteredByStorage = _selectedRecipeStorageType == null
        ? _ingredients
        : _ingredients
            .where((i) => i.storageType == _selectedRecipeStorageType)
            .toList();
    final nameToIds = <String, List<String>>{};
    for (final i in filteredByStorage) {
      nameToIds.putIfAbsent(i.name, () => []).add(i.id);
    }
    final uniqueNames = nameToIds.keys.toList()..sort();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF76C442).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: Color(0xFF76C442), size: 17),
              ),
              const SizedBox(width: 10),
              const Text('재료 선택',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white)),
              const SizedBox(width: 8),
              if (_ingredients.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected.isNotEmpty
                        ? const Color(0xFF76C442).withValues(alpha: 0.15)
                        : const Color(0xFF252525),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${selected.map((i) => i.name).toSet().length} / ${_ingredients.map((i) => i.name).toSet().length}종류',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: selected.isNotEmpty
                          ? const Color(0xFF76C442)
                          : const Color(0xFF6A6A6A),
                    ),
                  ),
                ),
              const Spacer(),
              if (_ingredients.isNotEmpty)
                GestureDetector(
                  onTap: _allSelected ? _deselectAll : _selectAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: const Color(0xFF2A2A2A)),
                    ),
                    child: Text(
                      _allSelected ? '전체 해제' : '전체 선택',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9A9A9A)),
                    ),
                  ),
                ),
            ],
          ),
          // Storage type filter tabs
          if (_ingredients.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  (null, '전체'),
                  ('냉장', '🧊 냉장'),
                  ('냉동', '❄️ 냉동'),
                  ('상온', '🌡️ 상온'),
                ].map((t) {
                  final (type, label) = t;
                  final isTab = _selectedRecipeStorageType == type;
                  final color = _recipeStorageColor(type);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(
                          () => _selectedRecipeStorageType = type),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: isTab
                              ? color.withValues(alpha: 0.15)
                              : const Color(0xFF252525),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isTab ? color : const Color(0xFF2A2A2A),
                            width: isTab ? 1.5 : 1.0,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isTab
                                ? color
                                : const Color(0xFF9A9A9A),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_ingredients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('식재료가 없습니다. 식재료 탭에서 추가해주세요.',
                  style: TextStyle(
                      color: Color(0xFF6A6A6A), fontSize: 13)),
            )
          else if (uniqueNames.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('해당 보관 방법의 식재료가 없습니다.',
                  style: TextStyle(
                      color: Color(0xFF6A6A6A), fontSize: 13)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: uniqueNames.map((name) {
                final ids = nameToIds[name]!;
                final isSelected =
                    ids.any((id) => _selectedIds.contains(id));
                return _IngredientChip(
                  ingredient:
                      _ingredients.firstWhere((i) => i.name == name),
                  selected: isSelected,
                  onTap: () => _toggleIngredientsByName(name, ids),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ── Filter section ────────────────────────────────────────

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF76C442).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.filter_list_rounded,
                    color: Color(0xFF76C442), size: 17),
              ),
              const SizedBox(width: 10),
              const Text('레시피 필터',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 14),
          const Text('난이도',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9A9A9A),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['상관없음', '초급', '중급', '고급']
                .map((d) => _filterChip(
                      label: d,
                      selected: _selectedDifficulty == d,
                      onTap: () =>
                          setState(() => _selectedDifficulty = d),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          const Text('조리시간',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9A9A9A),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['상관없음', '10분 이내', '30분 이내', '1시간 이내']
                .map((t) => _filterChip(
                      label: t,
                      selected: _selectedCookTime == t,
                      onTap: () =>
                          setState(() => _selectedCookTime = t),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF76C442).withValues(alpha: 0.15)
              : const Color(0xFF252525),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? const Color(0xFF76C442)
                : const Color(0xFF2A2A2A),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
            color: selected
                ? Colors.white
                : const Color(0xFF6A6A6A),
          ),
        ),
      ),
    );
  }

  // ── Change banner ──────────────────────────────────────────

  Widget _buildChangeBanner(List<Ingredient> selected) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9F0A).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFFF9F0A).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: Color(0xFFFF9F0A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '선택이 변경됐어요 — ${selected.map((i) => i.name).toSet().length}종류로 다시 추천받으세요',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFFFF9F0A)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: (selected.isEmpty || _isLoading) ? null : _getRecipes,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9F0A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('추천',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recommend button ───────────────────────────────────────

  Widget _buildRecommendButton(List<Ingredient> selected) {
    final disabled = selected.isEmpty;
    final animEnabled = AnimationSettings().isEnabled;
    return AnimatedOpacity(
      opacity: disabled ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: AnimatedScale(
        scale: (animEnabled && _buttonPressed && !disabled) ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          decoration: BoxDecoration(
            gradient: disabled
                ? null
                : const LinearGradient(
                    colors: [Color(0xFF76C442), Color(0xFF4A9A24)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: disabled ? const Color(0xFF252525) : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFF76C442)
                          .withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: disabled ? null : _getRecipes,
              onTapDown: disabled
                  ? null
                  : (_) => setState(() => _buttonPressed = true),
              onTapUp: disabled
                  ? null
                  : (_) => setState(() => _buttonPressed = false),
              onTapCancel: disabled
                  ? null
                  : () => setState(() => _buttonPressed = false),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome,
                      color: disabled
                          ? const Color(0xFF6A6A6A)
                          : Colors.black,
                      size: 22),
                  const SizedBox(width: 10),
                  Text(
                    disabled
                        ? '식재료를 선택해주세요'
                        : '${selected.map((i) => i.name).toSet().length}종류 식재료로 추천받기',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: disabled
                          ? const Color(0xFF6A6A6A)
                          : Colors.black,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }

  Widget _refreshButton(List<Ingredient> selected) {
    return GestureDetector(
      onTap: _isLoading || selected.isEmpty ? null : _getRecipes,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded,
                size: 14, color: Color(0xFF76C442)),
            const SizedBox(width: 4),
            Text('${selected.map((i) => i.name).toSet().length}종류로 다시',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF76C442),
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Favorites section ──────────────────────────────────────

  Widget _buildFavoritesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFFFF453A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.favorite_rounded,
                  color: Color(0xFFFF453A), size: 16),
            ),
            const SizedBox(width: 10),
            const Text('관심 레시피',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF453A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${_favorites.length}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF453A))),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _confirmClearFavorites,
              child: const Text('전체 삭제',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6A6A6A),
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Favorite recipe items
        ..._favorites.map(
          (fav) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HistoryRecipeItem(
              recipe: _RecipeCard(
                  title: fav.title, content: fav.content),
              isFavorited: true,
              onToggleFavorite: () =>
                  _confirmRemoveFavorite(fav.title),
              onCookingComplete: () =>
                  _showCookingCompleteDialog(
                      _RecipeCard(
                          title: fav.title,
                          content: fav.content)),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmClearFavorites() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('즐겨찾기 전체 삭제'),
        content: const Text('모든 관심 레시피를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소',
                style: TextStyle(color: Color(0xFF9A9A9A))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearFavorites();
            },
            child: const Text('삭제',
                style: TextStyle(
                    color: Color(0xFFFF453A),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── History section ────────────────────────────────────────

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history_rounded,
                  color: Color(0xFF9A9A9A), size: 16),
            ),
            const SizedBox(width: 10),
            const Text('지난 추천 레시피',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3)),
            const Spacer(),
            GestureDetector(
              onTap: _confirmClearHistory,
              child: const Text('전체 삭제',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6A6A6A),
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._history.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildHistoryCard(entry),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryCard(_HistoryEntry entry) {
    final dateStr = _formatDate(entry.timestamp);
    final namesStr = entry.ingredientNames.length > 4
        ? '${entry.ingredientNames.take(4).join(', ')} 외 ${entry.ingredientNames.length - 4}개'
        : entry.ingredientNames.join(', ');

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                setState(() => entry.isExpanded = !entry.isExpanded),
            borderRadius: entry.isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(15))
                : BorderRadius.circular(15),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.calendar_today_rounded,
                        size: 14, color: Color(0xFF6A6A6A)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dateStr,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(
                          '$namesStr · ${entry.ingredientNames.length}개 식재료',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6A6A6A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF76C442)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('레시피 ${entry.recipes.length}',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF76C442),
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: entry.isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF6A6A6A),
                        size: 20),
                  ),
                ],
              ),
            ),
          ),
          if (entry.isExpanded) ...[
            const Divider(height: 1, color: Color(0xFF2A2A2A)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ...entry.recipes.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _HistoryRecipeItem(
                        recipe: r,
                        isFavorited:
                            _favoriteIds.contains(r.title),
                        onToggleFavorite: () =>
                            _toggleFavorite(r),
                        onCookingComplete: () =>
                            _showCookingCompleteDialog(r),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => _confirmDeleteSingleHistoryEntry(entry.id),
                      child: const Text('이 기록 삭제',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF4A4A4A),
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('히스토리 삭제'),
        content: const Text('모든 추천 기록을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소',
                style: TextStyle(color: Color(0xFF9A9A9A))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearHistory();
            },
            child: const Text('삭제',
                style: TextStyle(
                    color: Color(0xFFFF453A),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSingleHistoryEntry(String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('기록 삭제'),
        content: const Text('정말로 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소',
                style: TextStyle(color: Color(0xFF9A9A9A))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteHistoryEntry(id);
            },
            child: const Text('확인',
                style: TextStyle(
                    color: Color(0xFFFF453A),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Date formatting ────────────────────────────────────────

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dtDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(dtDay).inDays;
    final time = _formatTime(dt);
    if (diff == 0) return '오늘 $time';
    if (diff == 1) return '어제 $time';
    return '${dt.month}월 ${dt.day}일 $time';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? '오전' : '오후';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$period $h:$minute';
  }
}

// ──────────────────────────────────────────────────────────────
//  History recipe item (compact card with heart)
// ──────────────────────────────────────────────────────────────

class _HistoryRecipeItem extends StatefulWidget {
  final _RecipeCard recipe;
  final bool isFavorited;
  final VoidCallback onToggleFavorite;
  final VoidCallback onCookingComplete;

  const _HistoryRecipeItem({
    required this.recipe,
    required this.isFavorited,
    required this.onToggleFavorite,
    required this.onCookingComplete,
  });

  @override
  State<_HistoryRecipeItem> createState() => _HistoryRecipeItemState();
}

class _HistoryRecipeItemState extends State<_HistoryRecipeItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(11),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF76C442)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.restaurant_rounded,
                        size: 14, color: Color(0xFF76C442)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.recipe.title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                  // Heart icon
                  GestureDetector(
                    onTap: widget.onToggleFavorite,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          widget.isFavorited
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          key: ValueKey(widget.isFavorited),
                          color: widget.isFavorited
                              ? const Color(0xFFFF453A)
                              : const Color(0xFF4A4A4A),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF4A4A4A), size: 18),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFF2A2A2A)),
            ClipRRect(
              borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(11),
                  bottomRight: Radius.circular(11)),
              child: Column(
                children: [
                  FutureBuilder<String?>(
                    future: UnsplashService.getRecipeImageUrl(
                        widget.recipe.title),
                    builder: (ctx, snap) {
                      if (snap.hasData && snap.data != null) {
                        return AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(color: const Color(0xFF111111)),
                              CachedNetworkImage(
                                imageUrl: snap.data!,
                                fit: BoxFit.contain,
                                placeholder: (_, _) => _miniPlaceholder(),
                                errorWidget: (_, _, _) =>
                                    _miniPlaceholder(),
                              ),
                            ],
                          ),
                        );
                      }
                      return AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _miniPlaceholder(),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: _RecipeContent(
                        content: widget.recipe.content),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onCookingComplete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              const Color(0xFF76C442),
                          side: const BorderSide(
                              color: Color(0xFF2E5C1A)),
                          backgroundColor:
                              const Color(0xFF76C442)
                                  .withValues(alpha: 0.06),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10)),
                        ),
                        icon: const Text('🍳',
                            style: TextStyle(fontSize: 14)),
                        label: const Text('요리 완료',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniPlaceholder() => Container(
        color: const Color(0xFF1A1A1A),
        child: const Center(
          child: Icon(Icons.restaurant_outlined,
              size: 32, color: Color(0xFF3A3A3A)),
        ),
      );
}

// ──────────────────────────────────────────────────────────────
//  Recipe content renderer
// ──────────────────────────────────────────────────────────────

class _RecipeContent extends StatelessWidget {
  final String content;
  const _RecipeContent({required this.content});

  @override
  Widget build(BuildContext context) {
    final lines = content
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.startsWith('## '))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((l) => _line(l)).toList(),
    );
  }

  Widget _line(String line) {
    if (line.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(line.substring(4),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF9A9A9A),
                letterSpacing: 0.5)),
      );
    }
    if (line.startsWith('- ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('• ',
              style: TextStyle(
                  color: Color(0xFF76C442),
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          Expanded(
              child: Text(line.substring(2),
                  style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFCCCCCC),
                      height: 1.4))),
        ]),
      );
    }
    if (RegExp(r'^\d+\.').hasMatch(line)) {
      final dot = line.indexOf('.');
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22, height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF76C442).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(line.substring(0, dot),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF76C442))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(line.substring(dot + 1).trim(),
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFCCCCCC),
                    height: 1.4)),
          )),
        ]),
      );
    }
    if (line.startsWith('**') && line.contains('**: ')) {
      final ci = line.indexOf('**: ');
      return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC)),
            children: [
              TextSpan(
                  text: '${line.substring(2, ci)}: ',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF9A9A9A))),
              TextSpan(text: line.substring(ci + 4)),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(line,
          style: const TextStyle(
              fontSize: 13, color: Color(0xFFCCCCCC), height: 1.4)),
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  Ingredient chip
// ──────────────────────────────────────────────────────────────

class _IngredientChip extends StatelessWidget {
  final Ingredient ingredient;
  final bool selected;
  final VoidCallback onTap;

  const _IngredientChip({
    required this.ingredient,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF76C442).withValues(alpha: 0.15)
              : const Color(0xFF252525),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? const Color(0xFF76C442)
                : const Color(0xFF2A2A2A),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: selected
                  ? const Icon(Icons.check_circle_rounded,
                      key: ValueKey('on'),
                      size: 13,
                      color: Color(0xFF76C442))
                  : const Icon(Icons.radio_button_unchecked_rounded,
                      key: ValueKey('off'),
                      size: 13,
                      color: Color(0xFF4A4A4A)),
            ),
            const SizedBox(width: 5),
            Text(
              ingredient.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? Colors.white
                    : const Color(0xFF6A6A6A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  Loading state
// ──────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF76C442).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF76C442))),
          ),
          const SizedBox(height: 20),
          const Text('AI가 맞춤 레시피를 준비하는 중...',
              style: TextStyle(
                  color: Color(0xFF9A9A9A),
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          const Text('잠시만 기다려주세요',
              style: TextStyle(
                  color: Color(0xFF5A5A5A), fontSize: 13)),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  Data classes
// ──────────────────────────────────────────────────────────────

class _RecipeCard {
  final String title;
  final String content;
  _RecipeCard({required this.title, required this.content});
}

class _FavoriteRecipe {
  final String title;
  final String content;
  final DateTime savedAt;

  _FavoriteRecipe({
    required this.title,
    required this.content,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'savedAt': savedAt.toIso8601String(),
      };

}

class _HistoryEntry {
  final String id;
  final DateTime timestamp;
  final List<String> ingredientNames;
  final List<_RecipeCard> recipes;
  bool isExpanded = false;

  _HistoryEntry({
    required this.id,
    required this.timestamp,
    required this.ingredientNames,
    required this.recipes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'ingredientNames': ingredientNames,
        'recipes': recipes
            .map((r) => {'title': r.title, 'content': r.content})
            .toList(),
      };

}

// ──────────────────────────────────────────────────────────────
//  Full recipe card (current session, with hero image + heart)
// ──────────────────────────────────────────────────────────────

class _RecipeCardWidget extends StatefulWidget {
  final _RecipeCard recipe;
  final bool isFavorited;
  final VoidCallback onToggleFavorite;
  final VoidCallback onCookingComplete;

  const _RecipeCardWidget({
    required this.recipe,
    required this.isFavorited,
    required this.onToggleFavorite,
    required this.onCookingComplete,
  });

  @override
  State<_RecipeCardWidget> createState() => _RecipeCardWidgetState();
}

class _RecipeCardWidgetState extends State<_RecipeCardWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.recipe.content
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    String? cookTime, difficulty, calories, servings;
    final List<String> steps = [];
    bool inSteps = false;

    for (final line in lines) {
      if (RegExp(r'^\*\*(조리\s*시간|시간)\*\*:').hasMatch(line)) {
        cookTime =
            line.replaceAll(RegExp(r'\*\*[^:]+\*\*:\s*'), '').trim();
      } else if (line.startsWith('**난이도**: ')) {
        difficulty =
            line.replaceAll(RegExp(r'\*\*[^:]+\*\*:\s*'), '').trim();
      } else if (RegExp(r'^\*\*(칼로리|열량)\*\*:').hasMatch(line)) {
        calories =
            line.replaceAll(RegExp(r'\*\*[^:]+\*\*:\s*'), '').trim();
      } else if (RegExp(r'^\*\*(인분|분량)\*\*:').hasMatch(line)) {
        servings =
            line.replaceAll(RegExp(r'\*\*[^:]+\*\*:\s*'), '').trim();
      } else if (RegExp(r'###.*(만들기|조리|방법)').hasMatch(line)) {
        inSteps = true;
      } else if (RegExp(r'^\d+\.').hasMatch(line) && inSteps) {
        steps.add(line);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image with heart overlay
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(19)),
            child: FutureBuilder<String?>(
              future: UnsplashService.getRecipeImageUrl(
                  widget.recipe.title),
              builder: (ctx, snap) {
                return AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: const Color(0xFF111111)),
                      if (snap.hasData && snap.data != null)
                        CachedNetworkImage(
                          imageUrl: snap.data!,
                          fit: BoxFit.contain,
                          placeholder: (_, _) => _heroPlaceholder(),
                          errorWidget: (_, _, _) => _heroPlaceholder(),
                        )
                      else
                        _heroPlaceholder(),
                      // Bottom gradient
                      Positioned(
                        bottom: 0, left: 0, right: 0, height: 80,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.7),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Heart button (top-right)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: widget.onToggleFavorite,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration:
                                    const Duration(milliseconds: 250),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(
                                        scale: anim, child: child),
                                child: Icon(
                                  widget.isFavorited
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  key: ValueKey(widget.isFavorited),
                                  color: widget.isFavorited
                                      ? const Color(0xFFFF453A)
                                      : Colors.white70,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.recipe.title,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3)),
                if (cookTime != null ||
                    difficulty != null ||
                    calories != null ||
                    servings != null) ...[
                  const SizedBox(height: 14),
                  _buildStatsRow(
                      cookTime, difficulty, calories, servings),
                ],
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFF2A2A2A)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onCookingComplete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF76C442),
                      side: const BorderSide(
                          color: Color(0xFF2E5C1A)),
                      backgroundColor: const Color(0xFF76C442)
                          .withValues(alpha: 0.06),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                    ),
                    icon: const Text('🍳',
                        style: TextStyle(fontSize: 15)),
                    label: const Text('요리 완료',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () =>
                      setState(() => _expanded = !_expanded),
                  child: Row(
                    children: [
                      const Text('레시피 보기',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF76C442))),
                      const Spacer(),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Color(0xFF76C442)),
                      ),
                    ],
                  ),
                ),
                if (_expanded) ...[
                  const SizedBox(height: 14),
                  _RecipeContent(content: widget.recipe.content),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPlaceholder() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A2A14), Color(0xFF252525)],
          ),
        ),
        child: const Center(
          child: Icon(Icons.restaurant_menu_outlined,
              size: 48, color: Color(0xFF3A3A3A)),
        ),
      );

  Widget _buildStatsRow(
      String? time, String? diff, String? cals, String? serv) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          if (time != null)
            _stat(Icons.access_time_rounded, time, '시간'),
          if (diff != null)
            _stat(Icons.signal_cellular_alt, diff, '난이도'),
          if (cals != null)
            _stat(Icons.local_fire_department, cals, '칼로리'),
          if (serv != null)
            _stat(Icons.people_outline, serv, '인분'),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) => Column(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF76C442)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Color(0xFF6A6A6A))),
        ],
      );
}

// ── Cooking complete data ──────────────────────────────────────────────────────

class _CookingEntry {
  final String recipeName;
  final Ingredient ingredient;
  bool included = true;
  final TextEditingController qtyCtrl;

  _CookingEntry({required this.recipeName, required this.ingredient})
      : qtyCtrl = TextEditingController(text: _fmt(ingredient.quantity));

  static String _fmt(double? q) {
    if (q == null) return '1';
    return q % 1 == 0 ? q.toInt().toString() : q.toString();
  }

  void dispose() => qtyCtrl.dispose();
}

// ── Cooking complete dialog ────────────────────────────────────────────────────

class _CookingCompleteDialog extends StatefulWidget {
  final String recipeName;
  final List<_CookingEntry> entries;
  final Future<void> Function(List<_CookingEntry>) onConfirm;

  const _CookingCompleteDialog({
    required this.recipeName,
    required this.entries,
    required this.onConfirm,
  });

  @override
  State<_CookingCompleteDialog> createState() =>
      _CookingCompleteDialogState();
}

class _CookingCompleteDialogState extends State<_CookingCompleteDialog> {
  bool _loading = false;

  @override
  void dispose() {
    for (final e in widget.entries) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _loading = true);
    try {
      await widget.onConfirm(widget.entries);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: $e'),
            backgroundColor: const Color(0xFFFF453A),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // pre-compute group info for sort hint and row rendering
    final nameCount = <String, int>{};
    for (final e in widget.entries) {
      nameCount[e.recipeName] = (nameCount[e.recipeName] ?? 0) + 1;
    }
    final seenNames = <String>{};

    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🍳',
                          style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      const Text('요리 완료',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: -0.3)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close_rounded,
                            color: Color(0xFF6A6A6A), size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(widget.recipeName,
                      style: const TextStyle(
                          color: Color(0xFF9A9A9A), fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text(
                    '사용한 수량을 입력하고 확인을 누르면 식재료가 자동 차감돼요.',
                    style: TextStyle(
                        color: Color(0xFF6A6A6A), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF252525)),
            // Content
            Flexible(
              child: widget.entries.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                          vertical: 28, horizontal: 22),
                      child: Column(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: Color(0xFF3A3A3A), size: 36),
                          SizedBox(height: 10),
                          Text(
                            '레시피에서 식재료를 인식하지 못했어요.\n식재료 탭에서 직접 수량을 수정해주세요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF6A6A6A),
                                fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: widget.entries.map((e) {
                          final isMulti =
                              (nameCount[e.recipeName] ?? 1) > 1;
                          final isFirst = seenNames.add(e.recipeName);
                          return _buildEntryRow(e,
                              isMulti: isMulti, isFirst: isFirst);
                        }).toList(),
                      ),
                    ),
            ),
            const Divider(height: 1, color: Color(0xFF252525)),
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _loading ? null : () => Navigator.pop(context),
                    child: const Text('취소',
                        style:
                            TextStyle(color: Color(0xFF9A9A9A))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF76C442),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black),
                          )
                        : const Text('확인',
                            style: TextStyle(
                                fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryRow(
    _CookingEntry entry, {
    required bool isMulti,
    required bool isFirst,
  }) {
    final c = entry.ingredient;
    final days = ExpiryUtils.daysUntil(c.expiryDate);
    final expiryColor = days != null ? ExpiryUtils.color(days) : null;
    final expiryLabel = days != null ? ExpiryUtils.label(days) : null;

    final qtyStr = c.quantity == null
        ? '?'
        : c.quantity! % 1 == 0
            ? c.quantity!.toInt().toString()
            : c.quantity!.toString();

    final inputQty =
        double.tryParse(entry.qtyCtrl.text.trim());
    final isOver = inputQty != null &&
        c.quantity != null &&
        inputQty > c.quantity!;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 정렬 안내 (동일 이름 그룹 첫 번째에만 표시)
          if (isMulti && isFirst)
            Padding(
              padding:
                  const EdgeInsets.only(left: 44, bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.sort_rounded,
                      size: 11, color: Color(0xFF5B9BD5)),
                  const SizedBox(width: 4),
                  Text(
                    '유통기한이 임박한 순서로 정렬됩니다',
                    style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFF5B9BD5)
                            .withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 포함 여부 체크박스
              SizedBox(
                width: 36,
                height: 36,
                child: Checkbox(
                  value: entry.included,
                  onChanged: (v) =>
                      setState(() => entry.included = v ?? false),
                  activeColor: const Color(0xFF76C442),
                  side: const BorderSide(
                      color: Color(0xFF4A4A4A), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5)),
                ),
              ),
              const SizedBox(width: 4),
              // 이름 + 유통기한 + 보유량
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.recipeName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: entry.included
                            ? Colors.white
                            : const Color(0xFF5A5A5A),
                      ),
                    ),
                    Row(
                      children: [
                        if (expiryLabel != null) ...[
                          Text(expiryLabel,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: expiryColor,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                        ],
                        Text('보유 $qtyStr${c.unit ?? ''}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF7A7A7A))),
                      ],
                    ),
                  ],
                ),
              ),
              // 사용량 입력
              if (entry.included)
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: entry.qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isOver
                          ? const Color(0xFFFF453A)
                          : Colors.white,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                      hintText: '1',
                      hintStyle: const TextStyle(
                          color: Color(0xFF5A5A5A)),
                      suffix: c.unit != null
                          ? Text(c.unit!,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF7A7A7A)))
                          : null,
                      filled: true,
                      fillColor: isOver
                          ? const Color(0xFFFF453A)
                              .withValues(alpha: 0.08)
                          : const Color(0xFF252525),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isOver
                              ? const Color(0xFFFF453A)
                              : const Color(0xFF3A3A3A),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isOver
                              ? const Color(0xFFFF453A)
                              : const Color(0xFF3A3A3A),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isOver
                              ? const Color(0xFFFF453A)
                              : const Color(0xFF76C442),
                        ),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(width: 90),
            ],
          ),
          // 보유량 초과 경고
          if (entry.included && isOver)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 4),
              child: Text(
                '보유량($qtyStr${c.unit ?? ''})을 초과했어요',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFFFF453A)),
              ),
            ),
          if (widget.entries.last != entry)
            const Divider(
                height: 16,
                indent: 44,
                color: Color(0xFF222222)),
        ],
      ),
    );
  }
}
