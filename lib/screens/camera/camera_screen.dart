import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/openai_service.dart';
import '../../services/ingredient_service.dart';
import '../../services/storage_service.dart';
import '../../services/animation_settings.dart';
import '../../utils/expiry_utils.dart';
import '../ingredients/ingredient_form_screen.dart';

enum _ScanMode { fridge, receipt }

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _picker = ImagePicker();
  final _openAI = OpenAIService();
  final _ingredientSvc = IngredientService();
  final _storage = StorageService();

  File? _image;
  List<Map<String, dynamic>>? _recognized;
  List<bool> _selected = [];
  bool _isAnalyzing = false;
  bool _isSaving = false;
  bool _isSingleIngredient = false;

  _ScanMode _mode = _ScanMode.fridge;
  DateTime _purchaseDate = DateTime.now();

  bool get _isReceiptMode => _mode == _ScanMode.receipt;

  // ── Mode switch ────────────────────────────────────────────

  void _switchMode(_ScanMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _image = null;
      _recognized = null;
      _selected = [];
      _isSingleIngredient = false;
    });
  }

  // ── Image picking ──────────────────────────────────────────

  Future<void> _pick(ImageSource source) async {
    try {
      final img = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (img == null) return;

      setState(() {
        _image = File(img.path);
        _recognized = null;
        _selected = [];
      });
      await _analyze();
    } catch (e) {
      _showSnack('이미지 선택 실패: $e', error: true);
    }
  }

  // ── Analysis dispatch ──────────────────────────────────────

  Future<void> _analyze() async {
    if (_image == null) return;
    setState(() => _isAnalyzing = true);
    try {
      final bytes = await _image!.readAsBytes();
      if (_isReceiptMode) {
        final items = await _openAI.extractReceiptIngredients(
          bytes,
          purchaseDate: _purchaseDate,
        );
        setState(() {
          _isSingleIngredient = false;
          _recognized = items;
          _selected = List.filled(items.length, true);
        });
      } else {
        final result = await _openAI.recognizeIngredients(bytes);
        debugPrint('[CameraScreen] singleIngredient=${result.singleIngredient}, 아이템=${result.items.length}개');
        for (final item in result.items) {
          debugPrint('[CameraScreen] 아이템: ${item['name']} / expiry_date: ${item['expiry_date']}');
        }
        setState(() {
          _isSingleIngredient = result.singleIngredient;
          _recognized = result.items;
          _selected = List.filled(result.items.length, true);
        });
      }
    } catch (e) {
      _showSnack('인식 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  // ── Purchase date change → recalculate expiry dates ────────

  void _onPurchaseDateChanged(DateTime newDate) {
    setState(() {
      _purchaseDate = newDate;
      if (_recognized != null && _isReceiptMode) {
        _recognized = _recognized!.map((item) {
          final shelfDays = item['estimated_shelf_days'] as int?;
          if (shelfDays != null) {
            final newExpiry = newDate.add(Duration(days: shelfDays));
            return {
              ...item,
              'expiry_date': DateFormat('yyyy-MM-dd').format(newExpiry),
            };
          }
          return item;
        }).toList();
      }
    });
  }

  // ── Save ───────────────────────────────────────────────────

  Future<void> _saveSelected() async {
    final toSave = <Map<String, dynamic>>[];
    for (int i = 0; i < (_recognized?.length ?? 0); i++) {
      if (_selected[i]) toSave.add(_recognized![i]);
    }
    if (toSave.isEmpty) {
      _showSnack('저장할 식재료를 선택해주세요');
      return;
    }

    setState(() => _isSaving = true);
    try {
      // 냉장고 촬영 + 1종류 식재료면 사진을 Storage에 업로드
      String? uploadedImageUrl;
      if (!_isReceiptMode && _isSingleIngredient && _image != null) {
        debugPrint('[CameraScreen] single_ingredient=true → 이미지 업로드 시작');
        final bytes = await _image!.readAsBytes();
        uploadedImageUrl = await _storage.uploadIngredientImage(bytes);
        debugPrint('[CameraScreen] 업로드 완료: $uploadedImageUrl');
      } else {
        debugPrint('[CameraScreen] 이미지 업로드 skip: isReceipt=$_isReceiptMode, isSingle=$_isSingleIngredient');
      }

      for (final item in toSave) {
        final expiryStr = item['expiry_date']?.toString();
        final hasExpiry = expiryStr != null &&
            expiryStr.isNotEmpty &&
            expiryStr != 'null';
        final storageTypeStr = item['storage_type']?.toString();
        final hasStorageType = storageTypeStr != null &&
            storageTypeStr.isNotEmpty &&
            storageTypeStr != 'null';
        await _ingredientSvc.addIngredient({
          'name': item['name'],
          if (item['quantity'] != null && item['quantity'].toString() != 'null')
            'quantity': item['quantity'] is num
                ? (item['quantity'] as num).toDouble()
                : double.tryParse(item['quantity'].toString()),
          if (item['unit'] != null && item['unit'].toString() != 'null')
            'unit': item['unit'].toString(),
          if (item['category'] != null) 'category': item['category'],
          if (hasExpiry) 'expiry_date': expiryStr,
          if (hasStorageType) 'storage_type': storageTypeStr,
          'image_url': ?uploadedImageUrl,
        });
      }
      if (mounted) {
        _showSnack('${toSave.length}개 식재료가 추가되었습니다');
        setState(() {
          _image = null;
          _recognized = null;
          _selected = [];
        });
      }
    } catch (e) {
      _showSnack('저장 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('촬영',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildModeToggle(),
            const SizedBox(height: 16),
            if (_isReceiptMode) ...[
              _buildPurchaseDateRow(),
              const SizedBox(height: 12),
            ],
            _buildImageArea(),
            const SizedBox(height: 12),
            _buildPickButtons(),
            if (_recognized != null) ...[
              const SizedBox(height: 24),
              _buildRecognizedList(),
              const SizedBox(height: 16),
              _buildSaveButton(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Mode toggle ────────────────────────────────────────────

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          _modeTab(
            icon: Icons.kitchen_outlined,
            activeIcon: Icons.kitchen,
            label: '냉장고 촬영',
            mode: _ScanMode.fridge,
          ),
          _modeTab(
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long,
            label: '영수증 스캔',
            mode: _ScanMode.receipt,
          ),
        ],
      ),
    );
  }

  Widget _modeTab({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required _ScanMode mode,
  }) {
    final isActive = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1A1A1A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isActive
                ? Border.all(color: const Color(0xFF76C442).withValues(alpha: 0.4))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                size: 17,
                color: isActive
                    ? const Color(0xFF76C442)
                    : const Color(0xFF6A6A6A),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? Colors.white : const Color(0xFF6A6A6A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Purchase date row (receipt mode only) ──────────────────

  Widget _buildPurchaseDateRow() {
    return GestureDetector(
      onTap: _pickPurchaseDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFFFF9F0A).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9F0A).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_long,
                  color: Color(0xFFFF9F0A), size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '구매일',
                    style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9A9A9A),
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('yyyy년 MM월 dd일').format(_purchaseDate),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
            Text(
              _isToday(_purchaseDate) ? '오늘' : _daysAgo(_purchaseDate),
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFFFF9F0A)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit_calendar_rounded,
                size: 18, color: Color(0xFF6A6A6A)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPurchaseDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF9F0A),
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (d != null) _onPurchaseDateChanged(d);
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String _daysAgo(DateTime d) {
    final diff = DateTime.now().difference(d).inDays;
    return diff == 1 ? '어제' : '$diff일 전';
  }

  // ── Image area ─────────────────────────────────────────────

  Widget _buildImageArea() {
    if (_image != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: double.infinity,
              color: const Color(0xFF111111),
              child: Image.file(
                _image!,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ),
          if (_isAnalyzing)
            Positioned.fill(
              child: AnimationSettings().isEnabled
                  ? _SparkleOverlay(isReceiptMode: _isReceiptMode)
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                              color: Color(0xFF76C442)),
                          const SizedBox(height: 16),
                          Text(
                            _isReceiptMode
                                ? 'AI가 영수증을 분석하는 중...'
                                : 'AI가 식재료를 인식하는 중...',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                          ),
                          if (_isReceiptMode)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                '비식품 항목은 자동으로 제외됩니다',
                                style: TextStyle(
                                    color: Color(0xFF9A9A9A),
                                    fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
        ],
        ),
      );
    }

    // Placeholder
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isReceiptMode
              ? const Color(0xFFFF9F0A).withValues(alpha: 0.3)
              : const Color(0xFF2A2A2A),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _isReceiptMode
                  ? const Color(0xFFFF9F0A).withValues(alpha: 0.1)
                  : const Color(0xFF252525),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _isReceiptMode
                  ? Icons.receipt_long_outlined
                  : Icons.camera_alt_outlined,
              size: 32,
              color: _isReceiptMode
                  ? const Color(0xFFFF9F0A)
                  : const Color(0xFF4A4A4A),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isReceiptMode
                ? '마트 영수증을 촬영하거나\n갤러리에서 선택하세요'
                : '냉장고 사진을 촬영하거나\n갤러리에서 선택하세요',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF9A9A9A), fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            _isReceiptMode
                ? 'GPT-4o가 식재료만 자동 추출하고\n유통기한을 추정합니다'
                : 'GPT-4o Vision이 식재료를 자동으로 인식합니다',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF5A5A5A), fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ── Pick buttons ───────────────────────────────────────────

  Widget _buildPickButtons() {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            icon: Icons.camera_alt_rounded,
            label: '카메라',
            onTap: () => _pick(ImageSource.camera),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionButton(
            icon: Icons.photo_library_outlined,
            label: '갤러리',
            onTap: () => _pick(ImageSource.gallery),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF76C442)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ── Recognized list ────────────────────────────────────────

  Widget _buildRecognizedList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text(
              _isReceiptMode ? '추출된 식재료' : '인식된 식재료',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF76C442).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_recognized!.length}개',
                style: const TextStyle(
                    color: Color(0xFF76C442),
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
            if (_isReceiptMode) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F0A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 10, color: Color(0xFFFF9F0A)),
                    SizedBox(width: 3),
                    Text('유통기한 자동 추정',
                        style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFFFF9F0A),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ] else if (_recognized?.any((item) {
                    final e = item['expiry_date']?.toString();
                    return e != null && e.isNotEmpty && e != 'null';
                  }) ==
                true) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF76C442).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 10, color: Color(0xFF76C442)),
                    SizedBox(width: 3),
                    Text('유통기한 자동 인식',
                        style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF76C442),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() {
                final allSelected = _selected.every((e) => e);
                _selected = List.filled(
                    _recognized!.length, !allSelected);
              }),
              child: Text(
                _selected.every((e) => e) ? '전체 해제' : '전체 선택',
                style: const TextStyle(
                    color: Color(0xFF76C442),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Items
        ...List.generate(
          _recognized!.length,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildRecognizedItem(i),
          ),
        ),
      ],
    );
  }

  Widget _buildRecognizedItem(int i) {
    final item = _recognized![i];
    final name = item['name']?.toString() ?? '';
    final qty = item['quantity'];
    final unit = item['unit'];
    final cat = item['category'];
    final expiryStr = item['expiry_date']?.toString();
    final expiryDate = (expiryStr != null && expiryStr.isNotEmpty && expiryStr != 'null')
        ? DateTime.tryParse(expiryStr)
        : null;
    final days = ExpiryUtils.daysUntil(expiryDate);
    final storageStr = item['storage_type']?.toString();
    final reasonStr = item['reason']?.toString();

    return GestureDetector(
      onTap: () => setState(() => _selected[i] = !_selected[i]),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _selected[i]
                ? (days != null && days <= 3
                    ? ExpiryUtils.color(days).withValues(alpha: 0.5)
                    : const Color(0xFF76C442).withValues(alpha: 0.4))
                : const Color(0xFF2A2A2A),
            width: _selected[i] ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _selected[i]
                      ? const Color(0xFF76C442)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _selected[i]
                        ? const Color(0xFF76C442)
                        : const Color(0xFF4A4A4A),
                    width: 1.5,
                  ),
                ),
                child: _selected[i]
                    ? const Icon(Icons.check,
                        size: 14, color: Colors.black)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + category + storage
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white),
                        ),
                      ),
                      if (cat != null && cat.toString() != 'null')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _catColor(cat.toString())
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            cat.toString(),
                            style: TextStyle(
                              fontSize: 10,
                              color: _catColor(cat.toString()),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (!_isReceiptMode &&
                          storageStr != null &&
                          storageStr.isNotEmpty &&
                          storageStr != 'null') ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _storageColor(storageStr)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _storageEmoji(storageStr),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  // Quantity row
                  if (qty != null && qty.toString() != 'null')
                    Text(
                      '수량: $qty ${unit != null && unit.toString() != 'null' ? unit : ''}',
                      style: const TextStyle(
                          color: Color(0xFF9A9A9A), fontSize: 12),
                    ),
                  // Expiry row
                  if (expiryDate != null && days != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.event_rounded,
                            size: 12,
                            color: ExpiryUtils.color(days)),
                        const SizedBox(width: 4),
                        Text(
                          '유통기한 ${DateFormat('yyyy.MM.dd').format(expiryDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: ExpiryUtils.color(days),
                            fontWeight: (days <= 3)
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: ExpiryUtils.color(days)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            ExpiryUtils.label(days),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: ExpiryUtils.color(days),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (_isReceiptMode)
                          Text(
                            '(${item['estimated_shelf_days']}일)',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF5A5A5A)),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF76C442)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome,
                                    size: 8,
                                    color: Color(0xFF76C442)),
                                SizedBox(width: 2),
                                Text(
                                  'AI 인식',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF76C442),
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                  // Reason (AI 인식 근거)
                  if (!_isReceiptMode &&
                      reasonStr != null &&
                      reasonStr.isNotEmpty &&
                      reasonStr != 'null') ...[
                    const SizedBox(height: 5),
                    Text(
                      '근거: $reasonStr',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF5A5A5A),
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Edit button
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: Color(0xFF6A6A6A)),
              onPressed: () async {
                await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        IngredientFormScreen(initialData: item),
                  ),
                );
                setState(() => _selected[i] = false);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Save button ────────────────────────────────────────────

  Widget _buildSaveButton() {
    final count = _selected.where((e) => e).length;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF76C442), Color(0xFF4A9A24)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _isSaving ? null : _saveSelected,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2.5),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.save_alt_rounded,
                            color: Colors.black, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '$count개 식재료 저장하기',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────

  Color _catColor(String cat) {
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

  Color _storageColor(String storage) {
    switch (storage) {
      case '냉장': return const Color(0xFF42A5F5);
      case '냉동': return const Color(0xFF90CAF9);
      case '상온': return const Color(0xFFFF9F0A);
      default: return const Color(0xFF9A9A9A);
    }
  }

  String _storageEmoji(String storage) {
    switch (storage) {
      case '냉장': return '🧊';
      case '냉동': return '❄️';
      case '상온': return '🌡️';
      default: return storage;
    }
  }
}

// ── _SparkleOverlay ────────────────────────────────────────────────────────────

class _SparkleOverlay extends StatefulWidget {
  final bool isReceiptMode;

  const _SparkleOverlay({required this.isReceiptMode});

  @override
  State<_SparkleOverlay> createState() => _SparkleOverlayState();
}

class _SparkleOverlayState extends State<_SparkleOverlay>
    with TickerProviderStateMixin {
  late AnimationController _rotCtrl;
  late AnimationController _rotCtrl2;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _rotCtrl2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    _rotCtrl2.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RotationTransition(
                  turns: _rotCtrl,
                  child: _SparkleRing(
                    radius: 36,
                    count: 5,
                    color: const Color(0xFF76C442),
                    dotSize: 7,
                  ),
                ),
                RotationTransition(
                  turns: Tween(begin: 0.0, end: -1.0).animate(_rotCtrl2),
                  child: _SparkleRing(
                    radius: 22,
                    count: 3,
                    color: const Color(0xFFFF9F0A),
                    dotSize: 5,
                  ),
                ),
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Text(
                    '✨',
                    style: TextStyle(fontSize: 22 + _pulseCtrl.value * 6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.isReceiptMode
                ? 'AI가 영수증을 분석하는 중...'
                : 'AI가 식재료를 인식하는 중...',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          if (widget.isReceiptMode)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '비식품 항목은 자동으로 제외됩니다',
                style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _SparkleRing extends StatelessWidget {
  final double radius;
  final int count;
  final Color color;
  final double dotSize;

  const _SparkleRing({
    required this.radius,
    required this.count,
    required this.color,
    required this.dotSize,
  });

  @override
  Widget build(BuildContext context) {
    final total = radius * 2 + dotSize;
    return SizedBox(
      width: total,
      height: total,
      child: Stack(
        children: List.generate(count, (i) {
          final angle = (i / count) * 2 * math.pi;
          final cx = (radius + dotSize / 2) +
              radius * math.cos(angle) -
              dotSize / 2;
          final cy = (radius + dotSize / 2) +
              radius * math.sin(angle) -
              dotSize / 2;
          return Positioned(
            left: cx,
            top: cy,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.7),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
