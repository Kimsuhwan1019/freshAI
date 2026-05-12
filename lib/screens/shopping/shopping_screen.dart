import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config.dart';
import '../../services/ingredient_service.dart';

// ── Data models ────────────────────────────────────────────────────────────────

class _ShoppingItem {
  String name;
  bool checked;
  final bool isAuto;

  _ShoppingItem({required this.name, this.checked = false, this.isAuto = false});

  Map<String, dynamic> toJson() =>
      {'name': name, 'checked': checked, 'isAuto': isAuto};

  factory _ShoppingItem.fromJson(Map<String, dynamic> j) => _ShoppingItem(
        name: j['name'] as String,
        checked: j['checked'] as bool? ?? false,
        isAuto: j['isAuto'] as bool? ?? false,
      );
}

class _PlaceResult {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final bool? isOpen;
  final double distance;
  final String? todayHours;
  final List<String> types;

  const _PlaceResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.isOpen,
    required this.distance,
    this.todayHours,
    this.types = const <String>[],
  });
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen>
    with SingleTickerProviderStateMixin {
  static const _kPrefsKey = 'shopping_list_v1';
  static const _kPrimary = Color(0xFF76C442);
  static const _kSurface = Color(0xFF1A1A1A);
  static const _kBorder = Color(0xFF2A2A2A);
  static const _kBlue = Color(0xFF5B9BD5);

  static const _martBrands = [
    '이마트', '홈플러스', '롯데마트', '코스트코',
    '하나로마트', '농협마트', 'GS더프레시', '노브랜드',
    '메가마트', '킴스클럽', '탑마트',
  ];
  static const _cvsBrands = [
    'CU', 'GS25', '세븐일레븐', '이마트24', '미니스톱', '씨스페이스',
  ];

  /// 브랜드명이 매장명 맨 앞에 있는지 확인
  static bool _startsWithBrand(String name, String brand) {
    if (!name.startsWith(brand)) return false;
    final rest = name.substring(brand.length);
    // 정확히 브랜드명만 있거나 뒤에 공백이 오는 경우 (예: "홈플러스 인하점")
    if (rest.isEmpty || rest.startsWith(' ')) return true;
    // "이마트24"는 편의점 → 마트 탭 제외
    if (brand == '이마트' && rest.startsWith('24')) return false;
    // "노브랜드버거" 제외 (한글 자모가 바로 붙는 경우)
    if (brand == '노브랜드' && !RegExp(r'^[\d\s]').hasMatch(rest)) return false;
    // 숫자로 시작 (지점 번호 등), 한글 복합어(이마트트레이더스 등)
    // → types 필터가 잘못된 매장 차단
    return true;
  }

  // Shopping list
  List<_ShoppingItem> _items = [];
  bool _loadingItems = true;
  bool _showAddField = false;
  final _addCtrl = TextEditingController();

  // Stores
  late TabController _tabController;
  List<_PlaceResult> _marts = [];
  List<_PlaceResult> _cvs = [];
  Position? _position;
  bool _loadingLocation = false;
  bool _loadingStores = false;
  String? _storeError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() {});
          _loadStoresForCurrentTab();
        }
      });
    _loadItems();
    _initLocation();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _addCtrl.dispose();
    super.dispose();
  }

  // ── Shopping list ──────────────────────────────────────────────────────────

  Future<void> _loadItems() async {
    setState(() => _loadingItems = true);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);

    List<_ShoppingItem> saved = [];
    if (raw != null) {
      final list = json.decode(raw) as List;
      saved = list
          .map((e) => _ShoppingItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    try {
      final ingredients = await IngredientService().getIngredients();
      final lowStock = ingredients
          .where((i) => i.quantity == null || i.quantity! <= 1)
          .map((i) => i.name)
          .toSet();

      saved.removeWhere((item) => item.isAuto && !lowStock.contains(item.name));
      final existing = saved.map((i) => i.name).toSet();
      for (final name in lowStock) {
        if (!existing.contains(name)) {
          saved.add(_ShoppingItem(name: name, isAuto: true));
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _items = saved;
      _loadingItems = false;
    });
    _saveItems();
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPrefsKey,
      json.encode(_items.map((i) => i.toJson()).toList()),
    );
  }

  void _toggle(int i) {
    setState(() => _items[i].checked = !_items[i].checked);
    _saveItems();
  }

  void _delete(int i) {
    setState(() => _items.removeAt(i));
    _saveItems();
  }

  void _addItem() {
    final name = _addCtrl.text.trim();
    if (name.isEmpty) return;
    if (!_items.any((i) => i.name == name)) {
      setState(() => _items.add(_ShoppingItem(name: name)));
      _saveItems();
    }
    setState(() {
      _addCtrl.clear();
      _showAddField = false;
    });
  }

  void _clearChecked() {
    setState(() => _items.removeWhere((i) => i.checked));
    _saveItems();
  }

  bool get _allChecked => _items.isNotEmpty && _items.every((i) => i.checked);

  // ── Location & stores ──────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    if (!mounted) return;
    setState(() {
      _loadingLocation = true;
      _storeError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        setState(() {
          _storeError = '위치 서비스가 꺼져 있어요.\n설정에서 켜주세요.';
          _loadingLocation = false;
        });
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _storeError = '위치 권한이 필요해요.\n설정에서 허용해주세요.';
          _loadingLocation = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() {
        _position = pos;
        _loadingLocation = false;
      });
      await _loadStoresForCurrentTab();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _storeError = '위치를 가져올 수 없어요.';
        _loadingLocation = false;
      });
    }
  }

  Future<void> _loadStoresForCurrentTab({bool forceRefresh = false}) async {
    if (_position == null || _loadingStores) return;
    final tab = _tabController.index;
    if (!forceRefresh && (tab == 0 ? _marts.isNotEmpty : _cvs.isNotEmpty)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _loadingStores = true;
      _storeError = null;
    });
    try {
      final results = await _fetchPlaces(tab);
      if (!mounted) return;
      setState(() {
        if (tab == 0) {
          _marts = results;
        } else {
          _cvs = results;
        }
        _loadingStores = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _storeError = '매장 정보를 불러올 수 없어요.';
        _loadingStores = false;
      });
    }
  }

  Future<void> _refreshStores() async {
    setState(() {
      if (_tabController.index == 0) {
        _marts = [];
      } else {
        _cvs = [];
      }
    });
    await _loadStoresForCurrentTab(forceRefresh: true);
  }

  Future<List<_PlaceResult>> _fetchPlaces(int tabIndex) async {
    final lat = _position!.latitude;
    final lng = _position!.longitude;

    final brands = tabIndex == 0 ? _martBrands : _cvsBrands;

    debugPrint('[Places] 위치: $lat,$lng | 탭: $tabIndex | 브랜드: $brands');

    // 한 번에 최대 4개씩 병렬 요청 (연결 풀 포화 방지)
    const batchSize = 4;
    final allLists = <List<_PlaceResult>>[];
    for (var i = 0; i < brands.length; i += batchSize) {
      final batch = brands.skip(i).take(batchSize).toList();
      final results =
          await Future.wait(batch.map((kw) => _fetchByKeyword(lat, lng, kw)));
      allLists.addAll(results);
    }

    // 마트/편의점 허용 타입
    const martTypes = {'supermarket', 'grocery_or_supermarket'};
    const cvsTypes = {'convenience_store'};
    final allowedTypes = tabIndex == 0 ? martTypes : cvsTypes;

    final seen = <String>{};
    final combined = <_PlaceResult>[];
    for (final list in allLists) {
      for (final place in list) {
        // [1] 브랜드명이 이름 맨 앞에 있는 매장만 허용
        if (!brands.any((b) => _startsWithBrand(place.name, b))) continue;
        // [2] types 정보가 있으면 허용 타입인지 검증
        if (place.types.isNotEmpty &&
            !place.types.any(allowedTypes.contains)) {
          continue;
        }
        // [3] 중복 제거
        final key = '${place.name}|${place.address}';
        if (seen.add(key)) combined.add(place);
      }
    }
    combined.sort((a, b) => a.distance.compareTo(b.distance));
    debugPrint('[Places] 최종 ${combined.length}건');
    return combined;
  }

  Future<List<_PlaceResult>> _fetchByKeyword(
      double lat, double lng, String keyword) async {
    try {
      // Places API (New) - Text Search
      final uri = Uri.parse(
          'https://places.googleapis.com/v1/places:searchText');
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': AppConfig.googleMapsApiKey,
              'X-Goog-FieldMask':
                  'places.displayName,places.shortFormattedAddress,'
                  'places.location,places.currentOpeningHours,'
                  'places.regularOpeningHours,places.types',
            },
            body: json.encode({
              'textQuery': keyword,
              'locationBias': {
                'circle': {
                  'center': {'latitude': lat, 'longitude': lng},
                  'radius': 3000.0,
                }
              },
              'maxResultCount': 20,
              'languageCode': 'ko',
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = json.decode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        debugPrint(
            '[Places] "$keyword" → HTTP ${res.statusCode}: '
            '${data['error']?['message']}');
        return [];
      }

      final list = data['places'] as List? ?? [];
      debugPrint('[Places] "$keyword" → ${list.length}건');

      return list.map((r) {
        final rlat =
            (r['location']['latitude'] as num).toDouble();
        final rlng =
            (r['location']['longitude'] as num).toDouble();
        final isOpen =
            r['currentOpeningHours']?['openNow'] as bool?;
        // 오늘 영업시간 파싱 (regularOpeningHours 우선, 없으면 current)
        final hours = r['regularOpeningHours']
                ?? r['currentOpeningHours'];
        String? todayHours;
        final descriptions =
            hours?['weekdayDescriptions'] as List?;
        if (descriptions != null && descriptions.isNotEmpty) {
          // weekday: 1=월 ~ 7=일, descriptions[0]=월 ~ [6]=일
          final idx = DateTime.now().weekday - 1;
          if (idx < descriptions.length) {
            final desc = descriptions[idx] as String;
            final colon = desc.indexOf(': ');
            todayHours =
                colon >= 0 ? desc.substring(colon + 2) : desc;
          }
        }
        final types = (r['types'] as List?)
                ?.map((t) => t as String)
                .toList() ??
            <String>[];
        return _PlaceResult(
          name: r['displayName']?['text'] as String? ?? '',
          address:
              r['shortFormattedAddress'] as String? ?? '',
          lat: rlat,
          lng: rlng,
          isOpen: isOpen,
          distance:
              Geolocator.distanceBetween(lat, lng, rlat, rlng),
          todayHours: todayHours,
          types: types,
        );
      }).toList();
    } catch (e) {
      debugPrint('[Places] "$keyword" 실패: $e');
      return [];
    }
  }

  Future<void> _openInMaps(_PlaceResult place) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${place.lat},${place.lng}'
      '&travelmode=transit',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('지도 앱을 열 수 없어요')),
        );
      }
    }
  }

  String _fmtDist(double m) =>
      m < 1000 ? '${m.round()}m' : '${(m / 1000).toStringAsFixed(1)}km';

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _buildShoppingListCard(),
              const SizedBox(height: 16),
              _buildNearbyStoresCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 16),
      child: Row(
        children: [
          const Text('🛒', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '스마트 쇼핑',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              _loadItems();
              _initLocation();
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF7A7A7A), size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shopping list card ─────────────────────────────────────────────────────

  Widget _buildShoppingListCard() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildListHeader(),
          const Divider(height: 1, color: Color(0xFF252525)),
          if (_loadingItems)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_allChecked) _buildCompleteBanner(),
            if (_items.isNotEmpty)
              _buildItemsList()
            else if (!_showAddField)
              _buildEmptyHint(),
          ],
          _buildAddRow(),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    final total = _items.length;
    final checked = _items.where((i) => i.checked).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.checklist_rounded, color: _kPrimary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '쇼핑 리스트',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: -0.3),
                ),
                Text(
                  total == 0 ? '항목 없음' : '$checked / $total 완료',
                  style: const TextStyle(
                      color: Color(0xFF7A7A7A), fontSize: 12),
                ),
              ],
            ),
          ),
          if (checked > 0) ...[
            GestureDetector(
              onTap: _clearChecked,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '완료 삭제',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6A6A6A)),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: () => setState(() => _showAddField = !_showAddField),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _showAddField
                    ? _kPrimary.withValues(alpha: 0.2)
                    : const Color(0xFF252525),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _showAddField ? Icons.close_rounded : Icons.add_rounded,
                color: _showAddField ? _kPrimary : const Color(0xFF7A7A7A),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _kPrimary.withValues(alpha: 0.15),
          _kPrimary.withValues(alpha: 0.05),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🎉', style: TextStyle(fontSize: 22)),
          SizedBox(width: 10),
          Text(
            '쇼핑 완료!',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: _kPrimary,
              letterSpacing: -0.3,
            ),
          ),
          SizedBox(width: 6),
          Text(
            '모든 항목을 구매했어요',
            style: TextStyle(color: Color(0xFF5A9A30), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (context, index) => const Divider(
          height: 1, indent: 54, color: Color(0xFF222222)),
      itemBuilder: (context, i) => _ShoppingItemRow(
        item: _items[i],
        onToggle: () => _toggle(i),
        onDelete: () => _delete(i),
      ),
    );
  }

  Widget _buildEmptyHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(Icons.shopping_basket_outlined,
              color: Color(0xFF3A3A3A), size: 40),
          const SizedBox(height: 8),
          const Text('리스트가 비어있어요',
              style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            '수량 1개 이하 식재료가 자동으로 추가돼요',
            style: TextStyle(
                color: const Color(0xFF6A6A6A).withValues(alpha: 0.6),
                fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAddRow() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: _showAddField
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addCtrl,
                      autofocus: true,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '항목 직접 추가...',
                        hintStyle:
                            const TextStyle(color: Color(0xFF5A5A5A)),
                        filled: true,
                        fillColor: const Color(0xFF252525),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF3A3A3A)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF3A3A3A)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kPrimary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addItem(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('추가',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),
            )
          : const SizedBox(height: 4),
    );
  }

  // ── Nearby stores card ─────────────────────────────────────────────────────

  Widget _buildNearbyStoresCard() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStoreHeader(),
          TabBar(
            controller: _tabController,
            tabs: const [Tab(text: '마트'), Tab(text: '편의점')],
            labelStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontSize: 14),
            dividerColor: const Color(0xFF252525),
            indicatorColor: _kPrimary,
            labelColor: _kPrimary,
            unselectedLabelColor: const Color(0xFF6A6A6A),
          ),
          const Divider(height: 1, color: Color(0xFF252525)),
          _buildStoreContent(),
        ],
      ),
    );
  }

  Widget _buildStoreHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.storefront_rounded, color: _kBlue, size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '근처 매장',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: -0.3),
                ),
                Text(
                  '현재 위치 기준 3km 이내',
                  style: TextStyle(color: Color(0xFF7A7A7A), fontSize: 12),
                ),
              ],
            ),
          ),
          if (_position != null && !_loadingStores)
            GestureDetector(
              onTap: _refreshStores,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.refresh_rounded,
                    color: Color(0xFF7A7A7A), size: 16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStoreContent() {
    if (_loadingLocation) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Column(children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('위치 확인 중...',
                style: TextStyle(color: Color(0xFF6A6A6A), fontSize: 13)),
          ]),
        ),
      );
    }

    if (_storeError != null && _position == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        child: Column(
          children: [
            const Icon(Icons.location_off_rounded,
                color: Color(0xFF3A3A3A), size: 40),
            const SizedBox(height: 12),
            Text(
              _storeError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6A6A6A), fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _initLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.my_location_rounded, size: 16),
              label: const Text('위치 허용하기',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    if (_loadingStores) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_storeError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: Color(0xFF3A3A3A), size: 36),
            const SizedBox(height: 8),
            Text(_storeError!,
                style: const TextStyle(
                    color: Color(0xFF6A6A6A), fontSize: 13)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _refreshStores,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    final stores = _tabController.index == 0 ? _marts : _cvs;
    final typeName = _tabController.index == 0 ? '마트' : '편의점';
    return _buildStoreList(stores, typeName);
  }

  Widget _buildStoreList(List<_PlaceResult> stores, String typeName) {
    if (stores.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          children: [
            const Icon(Icons.store_mall_directory_outlined,
                color: Color(0xFF3A3A3A), size: 36),
            const SizedBox(height: 8),
            Text('근처 3km 이내에 $typeName가 없어요',
                style: const TextStyle(
                    color: Color(0xFF6A6A6A), fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: stores.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 72, color: Color(0xFF222222)),
      itemBuilder: (context, i) => _StoreTile(
        place: stores[i],
        onTap: () => _openInMaps(stores[i]),
        fmtDist: _fmtDist,
      ),
    );
  }
}

// ── _ShoppingItemRow ───────────────────────────────────────────────────────────

class _ShoppingItemRow extends StatelessWidget {
  final _ShoppingItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ShoppingItemRow({
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });

  static const _kPrimary = Color(0xFF76C442);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: item.checked ? _kPrimary : Colors.transparent,
                border: Border.all(
                  color:
                      item.checked ? _kPrimary : const Color(0xFF4A4A4A),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: item.checked
                  ? const Icon(Icons.check_rounded,
                      color: Colors.black, size: 14)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: item.checked
                      ? const Color(0xFF5A5A5A)
                      : Colors.white,
                  decoration: item.checked
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: const Color(0xFF5A5A5A),
                ),
              ),
            ),
            if (item.isAuto)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  '자동',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _kPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.close_rounded,
                  color: Color(0xFF4A4A4A), size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _StoreTile ─────────────────────────────────────────────────────────────────

class _StoreTile extends StatelessWidget {
  final _PlaceResult place;
  final VoidCallback onTap;
  final String Function(double) fmtDist;

  const _StoreTile({
    required this.place,
    required this.onTap,
    required this.fmtDist,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = place.isOpen;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.store_rounded,
                  color: Color(0xFF7A7A7A), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: -0.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    place.address,
                    style: const TextStyle(
                        color: Color(0xFF7A7A7A), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  fmtDist(place.distance),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB0B0B0),
                  ),
                ),
                const SizedBox(height: 4),
                if (isOpen != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isOpen
                          ? const Color(0xFF76C442)
                              .withValues(alpha: 0.12)
                          : const Color(0xFFFF453A)
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      isOpen ? '영업중' : '영업종료',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isOpen
                            ? const Color(0xFF76C442)
                            : const Color(0xFFFF453A),
                      ),
                    ),
                  )
                else
                  const Text(
                    '영업시간 정보 없음',
                    style: TextStyle(
                        fontSize: 10, color: Color(0xFF5A5A5A)),
                  ),
                const SizedBox(height: 3),
                Text(
                  place.todayHours ?? '영업시간 정보 없음',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF7A7A7A)),
                  textAlign: TextAlign.end,
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF3A3A3A), size: 20),
          ],
        ),
      ),
    );
  }
}
