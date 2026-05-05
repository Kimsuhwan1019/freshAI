import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/ingredient.dart';
import '../../services/ingredient_service.dart';
import '../../services/unsplash_service.dart';
import '../../utils/expiry_utils.dart';
import 'ingredient_form_screen.dart';

class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  final _service = IngredientService();
  List<Ingredient> _ingredients = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCategory;

  static const _categories = [
    '전체', '채소', '과일', '육류', '어류', '유제품', '곡류', '조미료', '음료', '기타'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await _service.getIngredients();
      if (mounted) setState(() => _ingredients = data);
    } catch (e) {
      if (mounted) _showSnack('불러오기 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete(Ingredient item) async {
    try {
      await _service.deleteIngredient(item.id);
      setState(() => _ingredients.removeWhere((i) => i.id == item.id));
      _showSnack('삭제되었습니다');
    } catch (e) {
      _showSnack('삭제 실패: $e', error: true);
    }
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

  List<Ingredient> get _filtered {
    return _ingredients.where((i) {
      final matchSearch =
          i.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchCat = _selectedCategory == null ||
          _selectedCategory == '전체' ||
          i.category == _selectedCategory;
      return matchSearch && matchCat;
    }).toList();
  }

  Color _catColor(String? cat) {
    switch (cat) {
      case '채소': return const Color(0xFF4CAF50);
      case '과일': return const Color(0xFFFF9800);
      case '육류': return const Color(0xFFE57373);
      case '어류': return const Color(0xFF42A5F5);
      case '유제품': return const Color(0xFFFFCA28);
      case '곡류': return const Color(0xFF8D6E63);
      case '조미료': return const Color(0xFFAB47BC);
      case '음료': return const Color(0xFF26C6DA);
      default: return const Color(0xFF78909C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiredCount =
        _ingredients.where((i) => ExpiryUtils.isExpired(i.expiryDate)).length;
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount =
        screenWidth > 900 ? 4 : screenWidth > 600 ? 3 : 2;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(expiredCount),
          SliverToBoxAdapter(child: _buildSearchBar()),
          SliverToBoxAdapter(child: _buildCategoryChips()),
          if (!_isLoading)
            SliverToBoxAdapter(child: _buildStatsRow(expiredCount)),
          _isLoading
              ? const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF76C442)),
                  ),
                )
              : _filtered.isEmpty
                  ? SliverFillRemaining(child: _emptyState())
                  : SliverPadding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.82,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _ingredientCard(_filtered[i]),
                          childCount: _filtered.length,
                        ),
                      ),
                    ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => const IngredientFormScreen()),
          );
          if (ok == true) _load();
        },
        backgroundColor: const Color(0xFF76C442),
        foregroundColor: Colors.black,
        elevation: 0,
        icon: const Icon(Icons.add, size: 22),
        label: const Text('추가',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  Widget _buildSliverAppBar(int expiredCount) {
    return SliverAppBar(
      floating: true,
      snap: true,
      title: Row(
        children: [
          const Text('식재료',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  letterSpacing: -0.5)),
          if (!_isLoading && _ingredients.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF76C442).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_ingredients.length}',
                style: const TextStyle(
                    color: Color(0xFF76C442),
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _load,
          tooltip: '새로고침',
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: '식재료 검색...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () =>
                      setState(() => _searchQuery = ''),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        itemCount: _categories.length,
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final selected = _selectedCategory == cat ||
              (_selectedCategory == null && cat == '전체');
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedCategory = cat == '전체' ? null : cat;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF76C442)
                      : const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF76C442)
                        : const Color(0xFF2A2A2A),
                  ),
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.black
                        : const Color(0xFF9A9A9A),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsRow(int expiredCount) {
    final soonCount = _ingredients
        .where((i) => ExpiryUtils.isExpiringSoon(i.expiryDate))
        .length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            '${_filtered.length}개',
            style: const TextStyle(
                color: Color(0xFF6A6A6A),
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          if (soonCount > 0 && expiredCount == 0)
            _statBadge('$soonCount개 임박', const Color(0xFFFF9F0A),
                Icons.schedule_rounded),
          if (expiredCount > 0) ...[
            if (soonCount > 0) ...[
              _statBadge('$soonCount개 임박', const Color(0xFFFF9F0A),
                  Icons.schedule_rounded),
              const SizedBox(width: 6),
            ],
            _statBadge('$expiredCount개 만료', const Color(0xFFFF453A),
                Icons.error_outline_rounded),
          ],
        ],
      ),
    );
  }

  Widget _statBadge(String text, Color color, IconData icon) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.kitchen_outlined,
                size: 40, color: Color(0xFF4A4A4A)),
          ),
          const SizedBox(height: 20),
          Text(
            _searchQuery.isNotEmpty ? '검색 결과가 없습니다' : '식재료를 추가해보세요',
            style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? '다른 검색어를 입력해보세요'
                : '카메라로 촬영하거나 직접 추가할 수 있어요',
            style: const TextStyle(
                color: Color(0xFF6A6A6A), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _ingredientCard(Ingredient item) {
    final days = ExpiryUtils.daysUntil(item.expiryDate);
    final expired = days != null && days <= 0;
    final soon = days != null && days >= 1 && days <= 3;
    final catColor = _catColor(item.category);

    return GestureDetector(
      onTap: () async {
        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => IngredientFormScreen(ingredient: item)),
        );
        if (ok == true) _load();
      },
      onLongPress: () => _confirmDelete(item),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: expired
                ? const Color(0xFFFF453A).withValues(alpha: 0.5)
                : soon
                    ? const Color(0xFFFF9F0A).withValues(alpha: 0.5)
                    : const Color(0xFF2A2A2A),
            width: (expired || soon) ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            Expanded(
              flex: 6,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(17)),
                child: FutureBuilder<String?>(
                  future: UnsplashService.getImageUrl(
                    item.name,
                    category: item.category,
                  ),
                  builder: (ctx, snap) {
                    if (snap.hasData && snap.data != null) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: snap.data!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                _imagePlaceholder(catColor),
                            errorWidget: (_, __, ___) =>
                                _imagePlaceholder(catColor),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: 50,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black
                                        .withValues(alpha: 0.6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (days != null)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: _expiryBadge(days),
                            ),
                        ],
                      );
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        _imagePlaceholder(catColor),
                        if (snap.connectionState ==
                            ConnectionState.waiting)
                          const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white30),
                            ),
                          ),
                        if (days != null)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: _expiryBadge(days),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // Info area
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        if (item.category != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.category!,
                              style: TextStyle(
                                fontSize: 10,
                                color: catColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (item.quantity != null)
                          Text(
                            '${item.quantity!.toStringAsFixed(item.quantity! % 1 == 0 ? 0 : 1)}${item.unit ?? ''}',
                            style: const TextStyle(
                                color: Color(0xFF6A6A6A),
                                fontSize: 11),
                          ),
                      ],
                    ),
                    if (item.expiryDate != null)
                      Row(
                        children: [
                          Icon(
                            Icons.event_rounded,
                            size: 11,
                            color: days != null
                                ? ExpiryUtils.color(days)
                                : const Color(0xFF5A5A5A),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            DateFormat('MM.dd').format(item.expiryDate!),
                            style: TextStyle(
                              fontSize: 11,
                              color: days != null
                                  ? ExpiryUtils.color(days)
                                  : const Color(0xFF5A5A5A),
                              fontWeight: (expired || soon)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          if (days != null && days <= 3) ...[
                            const SizedBox(width: 4),
                            Text(
                              ExpiryUtils.statusText(days),
                              style: TextStyle(
                                fontSize: 10,
                                color: ExpiryUtils.color(days)
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder(Color catColor) {
    return Container(
      color: catColor.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 32,
          color: catColor.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _expiryBadge(int days) {
    final color = ExpiryUtils.color(days);
    final label = ExpiryUtils.label(days);
    // Only show badge when within 7 days or expired
    if (days > 7) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  void _confirmDelete(Ingredient item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('식재료 삭제'),
        content: Text("'${item.name}'을(를) 삭제하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소',
                style: TextStyle(color: Color(0xFF9A9A9A))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _delete(item);
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
}
