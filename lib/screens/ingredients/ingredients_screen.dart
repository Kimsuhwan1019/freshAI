import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/ingredient.dart';
import '../../services/ingredient_service.dart';
import '../../services/unsplash_service.dart';
import '../../services/animation_settings.dart';
import '../../utils/app_error.dart';
import '../../utils/expiry_utils.dart';
import 'ingredient_form_screen.dart';

class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen>
    with SingleTickerProviderStateMixin {
  final _service = IngredientService();
  List<Ingredient> _ingredients = [];
  bool _isLoading = true;
  bool _hasNetworkError = false;
  bool _isOffline = false;       // 네트워크 오류 세부 구분
  String _searchQuery = '';
  String? _selectedStorageType;

  late AnimationController _entranceCtrl;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    AnimationSettings().load();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _load();
    _listenConnectivity();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// 네트워크 복구 감지 → 자동 재로드
  void _listenConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && _hasNetworkError && mounted) {
        _load();
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasNetworkError = false;
      _isOffline = false;
    });
    try {
      final data = await _service.getIngredients();
      if (mounted) {
        setState(() => _ingredients = data);
        _entranceCtrl.forward(from: 0);
      }
    } catch (e) {
      if (!mounted) return;
      if (isAuthError(e)) {
        await Supabase.instance.client.auth.signOut();
        return;
      }
      if (isNetworkError(e)) {
        // 실제 연결 상태를 확인해 오프라인 여부를 구분
        final results = await Connectivity().checkConnectivity();
        if (!mounted) return;
        final offline = results.every((r) => r == ConnectivityResult.none);
        setState(() {
          _hasNetworkError = true;
          _isOffline = offline;
        });
        // 기존 데이터가 있으면 에러 UI 대신 스낵바로만 알림
        if (_ingredients.isNotEmpty) {
          _showSnack(
            offline
                ? '인터넷 연결을 확인해주세요'
                : '서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요',
            error: true,
          );
        }
      } else {
        _showSnack(friendlyError(e), error: true);
      }
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
      _showSnack(friendlyError(e), error: true);
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
      final matchStorage =
          _selectedStorageType == null || i.storageType == _selectedStorageType;
      return matchSearch && matchStorage;
    }).toList();
  }

  // 같은 이름의 식재료를 병합한 리스트 (유통기한 빠른 순 정렬)
  List<_MergedIngredient> get _mergedFiltered {
    final grouped = <String, List<Ingredient>>{};
    for (final ing in _filtered) {
      grouped.putIfAbsent(ing.name, () => []).add(ing);
    }
    return grouped.entries.map((e) {
      final sorted = List<Ingredient>.from(e.value)
        ..sort((a, b) {
          if (a.expiryDate == null && b.expiryDate == null) return 0;
          if (a.expiryDate == null) return 1;
          if (b.expiryDate == null) return -1;
          return a.expiryDate!.compareTo(b.expiryDate!);
        });
      return _MergedIngredient(name: e.key, items: sorted);
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
          SliverToBoxAdapter(child: _buildStorageFilter()),
          if (!_isLoading)
            SliverToBoxAdapter(child: _buildStatsRow(expiredCount)),
          _isLoading
              ? const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF76C442)),
                  ),
                )
              : (_hasNetworkError && _ingredients.isEmpty)
                  ? SliverFillRemaining(child: _networkErrorState())
              : _mergedFiltered.isEmpty
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
                          (_, i) {
                            final card = _ingredientCard(_mergedFiltered[i]);
                            if (!AnimationSettings().isEnabled) return card;
                            final start = (i * 0.06).clamp(0.0, 0.65);
                            final end = (start + 0.4).clamp(0.1, 1.0);
                            final interval = Interval(start, end,
                                curve: Curves.easeOutCubic);
                            return FadeTransition(
                              opacity: _entranceCtrl.drive(
                                Tween(begin: 0.0, end: 1.0)
                                    .chain(CurveTween(curve: interval)),
                              ),
                              child: SlideTransition(
                                position: _entranceCtrl.drive(
                                  Tween(
                                    begin: const Offset(0, 0.25),
                                    end: Offset.zero,
                                  ).chain(CurveTween(curve: interval)),
                                ),
                                child: card,
                              ),
                            );
                          },
                          childCount: _mergedFiltered.length,
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

  Widget _buildStorageFilter() {
    const types = [
      (null, '전체'),
      ('냉장', '🧊 냉장'),
      ('냉동', '❄️ 냉동'),
      ('상온', '🌡️ 상온'),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        children: types.map((t) {
          final (value, label) = t;
          final selected = _selectedStorageType == value;
          final color = _storageColor(value);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () =>
                  setState(() => _selectedStorageType = value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? color : const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? color : const Color(0xFF2A2A2A),
                  ),
                ),
                child: Text(
                  label,
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
        }).toList(),
      ),
    );
  }

  Color _storageColor(String? type) {
    switch (type) {
      case '냉장': return const Color(0xFF42A5F5);
      case '냉동': return const Color(0xFF90CAF9);
      case '상온': return const Color(0xFFFF9F0A);
      default: return const Color(0xFF76C442);
    }
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

  Widget _networkErrorState() {
    final icon = _isOffline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded;
    final title = _isOffline ? '인터넷 연결을 확인해주세요' : '서버에 연결할 수 없어요';
    final subtitle = _isOffline
        ? '연결되면 자동으로 새로고침됩니다'
        : '잠시 후 다시 시도해주세요\n연결되면 자동으로 새로고침됩니다';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
              child: Icon(icon, size: 40, color: const Color(0xFF4A4A4A)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                  color: Color(0xFF6A6A6A), fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF76C442),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('다시 시도',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
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

  void _showIngredientDetailSheet(_MergedIngredient merged) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _IngredientDetailSheet(
        merged: merged,
        catColor: _catColor(merged.category),
        onEdit: (item) async {
          Navigator.pop(context);
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => IngredientFormScreen(ingredient: item)),
          );
          if (ok == true && mounted) _load();
        },
        onDelete: (item) {
          Navigator.pop(context);
          _confirmDelete(item);
        },
        onAddNew: () {
          Navigator.pop(context);
          Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const IngredientFormScreen()),
          ).then((ok) {
            if (ok == true && mounted) _load();
          });
        },
      ),
    );
  }

  Widget _ingredientCard(_MergedIngredient merged) {
    final days = merged.earliestDays;
    final expired = days != null && days <= 0;
    final soon = days != null && days >= 1 && days <= 3;
    final catColor = _catColor(merged.category);

    final card = GestureDetector(
      onTap: () {
        if (merged.hasMultiple) {
          _showIngredientDetailSheet(merged);
        } else {
          Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    IngredientFormScreen(ingredient: merged.items.first)),
          ).then((ok) {
            if (ok == true && mounted) _load();
          });
        }
      },
      onLongPress: () {
        if (merged.hasMultiple) {
          _showIngredientDetailSheet(merged);
        } else {
          _confirmDelete(merged.items.first);
        }
      },
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
                  future: merged.imageUrl != null
                      ? Future.value(merged.imageUrl)
                      : UnsplashService.getImageUrl(
                          merged.name,
                          category: merged.category,
                        ),
                  builder: (ctx, snap) {
                    final countBadge = merged.hasMultiple
                        ? Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black
                                    .withValues(alpha: 0.55),
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Text(
                                '×${merged.items.length}',
                                style: const TextStyle(
                                  color: Color(0xFF76C442),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        : null;

                    if (snap.hasData && snap.data != null) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: snap.data!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                _imagePlaceholder(catColor),
                            errorWidget: (_, _, _) =>
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
                                child: _expiryBadge(days)),
                          ?countBadge,
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
                              child: _expiryBadge(days)),
                        ?countBadge,
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
                      merged.name,
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
                        const SizedBox.shrink(),
                        if (merged.totalQuantity != null)
                          Text(
                            () {
                              final q = merged.totalQuantity!;
                              return '${q % 1 == 0 ? q.toInt() : q}${merged.unit ?? ''}';
                            }(),
                            style: const TextStyle(
                                color: Color(0xFF6A6A6A),
                                fontSize: 11),
                          ),
                      ],
                    ),
                    if (merged.items.any((i) => i.expiryDate != null))
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
                            DateFormat('MM.dd').format(
                              merged.items
                                  .firstWhere(
                                      (i) => i.expiryDate != null)
                                  .expiryDate!,
                            ),
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

    if (AnimationSettings().isEnabled && (expired || soon)) {
      return _PulsingBorder(
        color: expired ? const Color(0xFFFF453A) : const Color(0xFFFF9F0A),
        child: card,
      );
    }
    return card;
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

// ── _PulsingBorder ─────────────────────────────────────────────────────────────

class _PulsingBorder extends StatefulWidget {
  final Widget child;
  final Color color;

  const _PulsingBorder({required this.child, required this.color});

  @override
  State<_PulsingBorder> createState() => _PulsingBorderState();
}

class _PulsingBorderState extends State<_PulsingBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _anim.value * 0.55),
              blurRadius: 10 + _anim.value * 8,
              spreadRadius: _anim.value * 1.5,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ── _MergedIngredient ──────────────────────────────────────────────────────────

class _MergedIngredient {
  final String name;
  final List<Ingredient> items; // 유통기한 빠른 순 정렬됨

  const _MergedIngredient({required this.name, required this.items});

  double? get totalQuantity {
    if (items.every((i) => i.quantity == null)) return null;
    return items.fold<double>(0, (s, i) => s + (i.quantity ?? 0));
  }

  String? get unit =>
      items.firstWhere((i) => i.unit != null, orElse: () => items.first).unit;

  String? get category => items
      .firstWhere((i) => i.category != null, orElse: () => items.first)
      .category;

  int? get earliestDays {
    final days = items
        .map((i) => ExpiryUtils.daysUntil(i.expiryDate))
        .whereType<int>()
        .toList();
    if (days.isEmpty) return null;
    return days.reduce((a, b) => a < b ? a : b);
  }

  bool get hasMultiple => items.length > 1;

  String? get imageUrl =>
      items.firstWhere((i) => i.imageUrl != null, orElse: () => items.first).imageUrl;

  String? get storageType =>
      items.firstWhere((i) => i.storageType != null, orElse: () => items.first).storageType;
}

// ── _IngredientDetailSheet ─────────────────────────────────────────────────────

class _IngredientDetailSheet extends StatelessWidget {
  final _MergedIngredient merged;
  final Color catColor;
  final void Function(Ingredient) onEdit;
  final void Function(Ingredient) onDelete;
  final VoidCallback onAddNew;

  const _IngredientDetailSheet({
    required this.merged,
    required this.catColor,
    required this.onEdit,
    required this.onDelete,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    final total = merged.totalQuantity;
    final totalStr = total == null
        ? null
        : '${total % 1 == 0 ? total.toInt() : total}${merged.unit ?? ''}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.kitchen_rounded,
                      color: catColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merged.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            letterSpacing: -0.3),
                      ),
                      if (totalStr != null)
                        Text(
                          '총 $totalStr · ${merged.items.length}종',
                          style: const TextStyle(
                              color: Color(0xFF7A7A7A), fontSize: 12),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF6A6A6A), size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF252525)),
          // Items
          ...merged.items.map((item) => _itemRow(item)),
          // Add new button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAddNew,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF76C442),
                  side: const BorderSide(color: Color(0xFF2E5C1A)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('추가 등록',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(Ingredient item) {
    final days = ExpiryUtils.daysUntil(item.expiryDate);
    final expiryColor =
        days != null ? ExpiryUtils.color(days) : null;

    final qtyStr = item.quantity == null
        ? '수량 미설정'
        : '${item.quantity! % 1 == 0 ? item.quantity!.toInt() : item.quantity!}${item.unit ?? ''}';

    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: days != null
                      ? ExpiryUtils.color(days)
                      : const Color(0xFF3A3A3A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(qtyStr,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    if (item.expiryDate != null)
                      Text(
                        '유통기한 ${DateFormat('MM.dd').format(item.expiryDate!)}'
                        '${days != null ? '  ${ExpiryUtils.label(days)}' : ''}',
                        style: TextStyle(
                            fontSize: 12,
                            color: expiryColor ??
                                const Color(0xFF7A7A7A)),
                      )
                    else
                      const Text('유통기한 없음',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF5A5A5A))),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => onEdit(item),
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: Color(0xFF7A7A7A)),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                onPressed: () => onDelete(item),
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: Color(0xFF5A5A5A)),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
        if (merged.items.last != item)
          const Divider(
              height: 1, indent: 32, color: Color(0xFF252525)),
      ],
    );
  }
}
