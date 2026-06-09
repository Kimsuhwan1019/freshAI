import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config.dart';
import '../../services/ingredient_service.dart';
import '../../services/animation_settings.dart';

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
  final double distance;
  final bool? isOpen;
  final String? todayHours;

  const _PlaceResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distance,
    this.isOpen,
    this.todayHours,
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

  // ── Brand / filter constants ───────────────────────────────────────────────

  // 마트 탭: 이름에 포함되면 표시 (contains 방식)
  static const _martKeywords = [
    '이마트', '홈플러스', '롯데마트', '코스트코',
    '하나로마트', '농협마트', 'GS더프레시', '노브랜드',
    '메가마트', '킴스클럽', '탑마트', '슈퍼마켓', '슈퍼', '마트',
  ];
  // 편의점 탭: 시작 일치 방식 유지
  static const _cvsBrands = [
    'CU', 'GS25', '세븐일레븐', '이마트24', '미니스톱', '씨스페이스',
  ];
  // 마트 탭 제외 키워드
  static const _martExclude = [
    'CU', 'GS25', '세븐일레븐', '이마트24', '미니스톱',
    '편의점', '컴퓨터', '의류', '패션', '카페', '음식점', '버거', '치킨',
  ];
  // 편의점 탭 제외 키워드
  static const _cvsExclude = [
    '컴퓨터', '의류', '패션', '카페', '음식점', '버거', '치킨',
  ];

  // 브랜드명이 매장명 맨 앞에 있는지 확인 (편의점 탭 전용)
  static bool _startsWithBrand(String name, String brand) {
    if (!name.startsWith(brand)) return false;
    if (name.length == brand.length) return true;
    final after = name.substring(brand.length);
    return after.startsWith(' ') || RegExp(r'^[가-힣\d]').hasMatch(after);
  }

  // 마트 탭: 이름에 마트 키워드 포함 여부 (contains)
  static bool _isValidMart(String name) {
    if (_martExclude.any(name.contains)) return false;
    return _martKeywords.any(name.contains);
  }

  // 편의점 탭: CVS 브랜드로 시작하는지 확인 (startsWith)
  static bool _isValidCVS(String name) {
    if (_cvsExclude.any(name.contains)) return false;
    return _cvsBrands.any((b) => _startsWithBrand(name, b));
  }

  // 브랜드별 표준 영업시간 추정 (카카오 공개 API는 영업시간 미제공)
  static ({bool? isOpen, String? todayHours}) _estimateHours(String name) {
    // 편의점: 대부분 24시간
    if (_cvsBrands.any((b) => _startsWithBrand(name, b))) {
      return (isOpen: true, todayHours: '24시간');
    }
    // 마트별 표준 영업시간 — contains 방식으로 검사
    const martHours = <String, (int, int)>{
      '이마트':    (10, 23), '홈플러스':   (10, 23),
      '롯데마트':  (10, 23), '코스트코':   (10, 21),
      '메가마트':  (10, 22), 'GS더프레시': (9,  22),
      '농협마트':  (9,  21), '하나로마트': (9,  21),
      '킴스클럽':  (10, 22), '탑마트':    (9,  22),
      '노브랜드':  (10, 22),
    };
    for (final e in martHours.entries) {
      if (!name.contains(e.key)) continue;
      // 이마트24 → 편의점이므로 건너뜀
      if (e.key == '이마트' && name.contains('이마트24')) continue;
      return _calcHours(e.value.$1, e.value.$2);
    }
    // 브랜드 미매칭 → 일반 마트/슈퍼마켓 기본 시간
    if (name.contains('마트') || name.contains('슈퍼')) {
      return _calcHours(9, 22);
    }
    return (isOpen: null, todayHours: null);
  }

  static ({bool isOpen, String todayHours}) _calcHours(int openH, int closeH) {
    final h = DateTime.now().hour;
    final isOpen = h >= openH && h < closeH;
    final label = '${openH.toString().padLeft(2, '0')}:00'
        '~${closeH.toString().padLeft(2, '0')}:00';
    return (isOpen: isOpen, todayHours: label);
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
    AnimationSettings().load();
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
      final results = await _fetchKakaoPlaces(tab);
      if (!mounted) return;
      setState(() {
        if (tab == 0) {
          _marts = results;
        } else {
          _cvs = results;
        }
        _loadingStores = false;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _storeError = '인터넷 연결을 확인해주세요';
        _loadingStores = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _storeError = e.toString().replaceFirst('Exception: ', '');
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

  Future<List<_PlaceResult>> _fetchKakaoPlaces(int tabIndex) async {
    final lat = _position!.latitude;
    final lng = _position!.longitude;

    // 마트 탭: 마트 + 슈퍼마켓, 편의점 탭: 편의점
    final keywords = tabIndex == 0 ? ['마트', '슈퍼마켓'] : ['편의점'];

    final seen = <String>{};
    final combined = <_PlaceResult>[];
    for (final keyword in keywords) {
      final results = await _fetchKakaoByKeyword(lat, lng, keyword);
      for (final place in results) {
        // 브랜드 필터링
        final valid = tabIndex == 0
            ? _isValidMart(place.name)
            : _isValidCVS(place.name);
        if (!valid) continue;
        final key = '${place.name}|${place.address}';
        if (!seen.add(key)) continue;
        // 브랜드별 영업시간 추정
        final (:isOpen, :todayHours) = _estimateHours(place.name);
        combined.add(_PlaceResult(
          name: place.name,
          address: place.address,
          lat: place.lat,
          lng: place.lng,
          distance: place.distance,
          isOpen: isOpen,
          todayHours: todayHours,
        ));
      }
    }

    combined.sort((a, b) => a.distance.compareTo(b.distance));
    final filtered = combined.where((p) => p.distance <= 3000).toList();
    debugPrint('[Kakao] 최종 ${filtered.length}건 (3km 이내)');
    return filtered;
  }

  Future<List<_PlaceResult>> _fetchKakaoByKeyword(
      double lat, double lng, String keyword) async {
    // 카카오 로컬 API: x=경도, y=위도
    final uri = Uri.parse(
      'https://dapi.kakao.com/v2/local/search/keyword.json',
    ).replace(queryParameters: {
      'query': keyword,
      'x': lng.toString(),
      'y': lat.toString(),
      'radius': '3000',
      'size': '15',
      'sort': 'distance',
    });

    debugPrint('[Kakao] 요청: ${uri.toString()}');

    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'KakaoAK ${AppConfig.kakaoRestApiKey}',
      },
    ).timeout(const Duration(seconds: 10));

    debugPrint('[Kakao] "$keyword" → HTTP ${res.statusCode}');

    if (res.statusCode != 200) {
      final body = utf8.decode(res.bodyBytes);
      debugPrint('[Kakao] 오류 응답: $body');
      // 오류 메시지를 파싱해서 예외로 던짐
      try {
        final err = json.decode(body) as Map<String, dynamic>;
        final msg = err['message'] as String? ?? '알 수 없는 오류';
        throw Exception('카카오 API 오류: $msg (HTTP ${res.statusCode})');
      } catch (parseErr) {
        if (parseErr is Exception) rethrow;
        throw Exception('카카오 API 오류 (HTTP ${res.statusCode})');
      }
    }

    final data =
        json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final documents = data['documents'] as List? ?? [];
    debugPrint('[Kakao] "$keyword" → ${documents.length}건 원본:');
    for (final d in documents) {
      debugPrint('  · ${d['place_name']} / ${d['category_name']} / ${d['distance']}m');
    }

    return documents.map((d) {
      final dist =
          double.tryParse(d['distance'] as String? ?? '0') ?? 0.0;
      final placeLat =
          double.tryParse(d['y'] as String? ?? '') ?? 0.0;
      final placeLng =
          double.tryParse(d['x'] as String? ?? '') ?? 0.0;
      final roadAddr = d['road_address_name'] as String? ?? '';
      final addr = d['address_name'] as String? ?? '';
      return _PlaceResult(
        name: d['place_name'] as String? ?? '',
        address: roadAddr.isNotEmpty ? roadAddr : addr,
        lat: placeLat,
        lng: placeLng,
        distance: dist,
      );
    }).toList();
  }

  void _showTravelModeSheet(_PlaceResult place) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.store_rounded, color: _kBlue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  place.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _fmtDist(place.distance),
                style: const TextStyle(
                    color: Color(0xFF7A7A7A), fontSize: 13),
              ),
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                place.address,
                style: const TextStyle(
                    color: Color(0xFF7A7A7A), fontSize: 12),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '경로 안내 방법 선택',
              style: TextStyle(
                  color: Color(0xFF9A9A9A),
                  fontSize: 11,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 10),
            _travelModeRow(
                Icons.directions_walk_rounded, '도보', 'FOOT', place),
            const SizedBox(height: 8),
            _travelModeRow(
                Icons.directions_car_rounded, '자동차', 'CAR', place),
            const SizedBox(height: 8),
            _travelModeRow(
                Icons.directions_transit_rounded, '대중교통', 'PUBLICTRANSIT', place),
          ],
        ),
      ),
    );
  }

  Widget _travelModeRow(
      IconData icon, String label, String mode, _PlaceResult place) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _openInKakaoMaps(place, mode);
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2E2E2E)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _kBlue, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            const Icon(Icons.open_in_new_rounded,
                color: Color(0xFF5A5A5A), size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _openInKakaoMaps(_PlaceResult place, String kakaoMode) async {
    final userLat = _position?.latitude ?? 0;
    final userLng = _position?.longitude ?? 0;

    // 카카오맵 앱 딥링크 (sp=출발지, ep=목적지, by=이동수단)
    final kakaoUri = Uri.parse(
      'kakaomap://route?sp=$userLat,$userLng'
      '&ep=${place.lat},${place.lng}'
      '&by=$kakaoMode',
    );

    if (await canLaunchUrl(kakaoUri)) {
      await launchUrl(kakaoUri, mode: LaunchMode.externalApplication);
      return;
    }

    // 카카오맵 미설치 → Play Store로 이동
    if (!mounted) return;
    final install = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('카카오맵 필요'),
        content: const Text('카카오맵이 설치되어 있지 않습니다.\nPlay 스토어에서 설치하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소',
                style: TextStyle(color: Color(0xFF9A9A9A))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('설치하기',
                style: TextStyle(
                    color: Color(0xFF5B9BD5),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (install == true) {
      final storeUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=net.daum.android.map',
      );
      await launchUrl(storeUri, mode: LaunchMode.externalApplication);
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
            if (_allChecked) const _ConfettiBanner(),
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
        onTap: () => _showTravelModeSheet(stores[i]),
        fmtDist: _fmtDist,
      ),
    );
  }
}

// ── _ShoppingItemRow ───────────────────────────────────────────────────────────

class _ShoppingItemRow extends StatefulWidget {
  final _ShoppingItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ShoppingItemRow({
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<_ShoppingItemRow> createState() => _ShoppingItemRowState();
}

class _ShoppingItemRowState extends State<_ShoppingItemRow>
    with SingleTickerProviderStateMixin {
  static const _kPrimary = Color(0xFF76C442);

  late AnimationController _bounceCtrl;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _bounceAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.45), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.45, end: 0.85), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.12), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (AnimationSettings().isEnabled) _bounceCtrl.forward(from: 0);
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _handleTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _bounceAnim,
              builder: (_, child) => Transform.scale(
                scale: _bounceAnim.value,
                child: child,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: widget.item.checked ? _kPrimary : Colors.transparent,
                  border: Border.all(
                    color: widget.item.checked
                        ? _kPrimary
                        : const Color(0xFF4A4A4A),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: widget.item.checked
                    ? const Icon(Icons.check_rounded,
                        color: Colors.black, size: 14)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.item.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: widget.item.checked
                      ? const Color(0xFF5A5A5A)
                      : Colors.white,
                  decoration: widget.item.checked
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: const Color(0xFF5A5A5A),
                ),
              ),
            ),
            if (widget.item.isAuto)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: _kPrimary.withValues(alpha: 0.3)),
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
              onTap: widget.onDelete,
              child: const Icon(Icons.close_rounded,
                  color: Color(0xFF4A4A4A), size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _ConfettiBanner ────────────────────────────────────────────────────────────

class _ConfettiBanner extends StatefulWidget {
  const _ConfettiBanner();

  @override
  State<_ConfettiBanner> createState() => _ConfettiBannerState();
}

class _ConfettiBannerState extends State<_ConfettiBanner>
    with SingleTickerProviderStateMixin {
  static const _kPrimary = Color(0xFF76C442);

  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      height: 76,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _kPrimary.withValues(alpha: 0.15),
          _kPrimary.withValues(alpha: 0.05),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
      ),
      child: Stack(
        children: [
          if (AnimationSettings().isEnabled)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, _) => CustomPaint(
                    painter: _ConfettiPainter(_ctrl.value),
                  ),
                ),
              ),
            ),
          const Center(
            child: Row(
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
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double progress;

  _ConfettiPainter(this.progress);

  static final _particles = List.generate(22, (i) {
    final r = math.Random(i * 11 + 7);
    return (
      x: r.nextDouble(),
      y: r.nextDouble(),
      speed: 0.25 + r.nextDouble() * 0.65,
      size: 4.0 + r.nextDouble() * 5.0,
      angle: r.nextDouble() * math.pi * 2,
      colorIdx: i % 5,
    );
  });

  static const _colors = [
    Color(0xFF76C442),
    Color(0xFFFF9F0A),
    Color(0xFF42A5F5),
    Color(0xFFFF453A),
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final y = ((p.y + progress * p.speed) % 1.0) * size.height;
      final x = p.x * size.width;
      final paint = Paint()
        ..color = _colors[p.colorIdx].withValues(alpha: 0.65)
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.angle + progress * math.pi * 3);
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: p.size, height: p.size * 0.5),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
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
                  if (place.todayHours != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      place.todayHours!,
                      style: TextStyle(
                        fontSize: 11,
                        color: place.isOpen == true
                            ? const Color(0xFF76C442)
                            : const Color(0xFF9A9A9A),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  fmtDist(place.distance),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB0B0B0),
                  ),
                ),
                if (place.isOpen != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: place.isOpen!
                          ? const Color(0xFF76C442).withValues(alpha: 0.12)
                          : const Color(0xFFFF453A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      place.isOpen! ? '영업중' : '영업종료',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: place.isOpen!
                            ? const Color(0xFF76C442)
                            : const Color(0xFFFF453A),
                      ),
                    ),
                  ),
                ],
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
