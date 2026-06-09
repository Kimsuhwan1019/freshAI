import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/ingredient.dart';
import '../../services/ingredient_service.dart';
import '../../utils/expiry_utils.dart';

class IngredientFormScreen extends StatefulWidget {
  final Ingredient? ingredient;
  final Map<String, dynamic>? initialData;

  const IngredientFormScreen({
    super.key,
    this.ingredient,
    this.initialData,
  });

  @override
  State<IngredientFormScreen> createState() => _IngredientFormScreenState();
}

class _IngredientFormScreenState extends State<IngredientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();

  String? _category;
  DateTime? _expiryDate;
  bool _isLoading = false;
  List<String> _nameSuggestions = [];
  String _storageType = '냉장';

  final _service = IngredientService();

  static const _commonIngredients = [
    '계란', '두부', '양파', '대파', '마늘', '감자', '당근', '고추', '배추',
    '시금치', '깻잎', '상추', '오이', '토마토', '브로콜리', '파프리카', '버섯',
    '닭고기', '돼지고기', '소고기', '삼겹살', '닭가슴살', '다진고기',
    '생선', '오징어', '새우', '조개', '어묵', '참치',
    '우유', '치즈', '버터', '요거트', '생크림', '두유',
    '밥', '면', '빵', '라면', '쌀', '밀가루', '떡',
    '간장', '된장', '고추장', '소금', '설탕', '식용유', '참기름', '식초', '굴소스',
    '사과', '바나나', '오렌지', '포도', '딸기', '수박', '배', '귤',
    '햄', '소시지', '베이컨', '통조림', '김치',
  ];

  static const _units = [
    '개', 'g', 'kg', 'ml', 'L', '봉지', '팩', '캔', '병', '컵', '큰술', '작은술', '마리', '포기'
  ];

  // 날짜 퀵 프리셋 (label → days)
  static const _datePresets = [
    ('오늘', 0),
    ('+1일', 1),
    ('+3일', 3),
    ('+1주', 7),
    ('+2주', 14),
    ('+1달', 30),
    ('+3달', 90),
  ];

  bool get _isEditing => widget.ingredient != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameCtrl.text = widget.ingredient!.name;
      _qtyCtrl.text = widget.ingredient!.quantity?.toString() ?? '';
      _unitCtrl.text = widget.ingredient!.unit ?? '';
      _category = widget.ingredient!.category;
      _expiryDate = widget.ingredient!.expiryDate;
      _storageType = widget.ingredient!.storageType ?? '냉장';
    } else if (widget.initialData != null) {
      _nameCtrl.text =
          widget.initialData!['name']?.toString() ?? '';
      final qty = widget.initialData!['quantity'];
      _qtyCtrl.text = qty != null ? qty.toString() : '';
      _unitCtrl.text =
          widget.initialData!['unit']?.toString() ?? '';
      _category =
          widget.initialData!['category']?.toString();
      _storageType =
          widget.initialData!['storage_type']?.toString() ?? '냉장';
    }
  }

  void _onNameChanged(String value) {
    if (value.isEmpty) {
      setState(() => _nameSuggestions.clear());
      return;
    }
    final filtered = _commonIngredients
        .where((s) => s.contains(value))
        .take(8)
        .toList();
    setState(() => _nameSuggestions = filtered);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final parsedQty = double.tryParse(_qtyCtrl.text);
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        if (_qtyCtrl.text.isNotEmpty && parsedQty != null)
          'quantity': parsedQty,
        if (_unitCtrl.text.isNotEmpty)
          'unit': _unitCtrl.text.trim(),
        if (_category != null) 'category': _category,
        if (_expiryDate != null)
          'expiry_date':
              DateFormat('yyyy-MM-dd').format(_expiryDate!),
        'storage_type': _storageType,
      };

      if (_isEditing) {
        await _service.updateIngredient(
            widget.ingredient!.id, data);
      } else {
        await _service.addIngredient(data);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('오류: $e'),
              backgroundColor: const Color(0xFFFF453A)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate:
          _expiryDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate:
          DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF76C442),
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (d != null) setState(() => _expiryDate = d);
  }

  void _applyPreset(int days) {
    setState(() {
      _expiryDate = DateTime.now().add(Duration(days: days));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '식재료 수정' : '식재료 추가'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isLoading ? null : _save,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF76C442),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Color(0xFF76C442), strokeWidth: 2),
                    )
                  : const Text(
                      '저장',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionLabel('식재료 정보'),
            const SizedBox(height: 8),
            // Name with autocomplete
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: '식재료 이름 *',
                    prefixIcon: const Icon(Icons.label_outline),
                    suffixIcon: _nameCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _nameCtrl.clear();
                              setState(() => _nameSuggestions.clear());
                            },
                          )
                        : null,
                  ),
                  onChanged: _onNameChanged,
                  validator: (v) =>
                      v == null || v.isEmpty ? '이름을 입력해주세요' : null,
                ),
                if (_nameSuggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF3A3A3A)),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _nameSuggestions.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFF2A2A2A)),
                      itemBuilder: (ctx, i) {
                        final s = _nameSuggestions[i];
                        return InkWell(
                          onTap: () {
                            _nameCtrl.text = s;
                            setState(() => _nameSuggestions.clear());
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 13),
                            child: Row(
                              children: [
                                const Icon(Icons.search_rounded,
                                    size: 14,
                                    color: Color(0xFF6A6A6A)),
                                const SizedBox(width: 10),
                                Text(s,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Quantity + Unit
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '수량',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _units.contains(_unitCtrl.text)
                        ? _unitCtrl.text
                        : null,
                    dropdownColor: const Color(0xFF252525),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '단위',
                    ),
                    items: _units
                        .map((u) => DropdownMenuItem(
                            value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _unitCtrl.text = v ?? ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _sectionLabel('보관 방법'),
            const SizedBox(height: 10),
            _buildStorageTypeSelector(),
            const SizedBox(height: 24),
            _sectionLabel('유통기한'),
            const SizedBox(height: 8),
            // Quick presets
            _buildDatePresets(),
            const SizedBox(height: 10),
            // Date picker row
            _buildDatePickerRow(),
            // D-day preview
            if (_expiryDate != null) ...[
              const SizedBox(height: 10),
              _buildExpiryPreview(),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Color(0xFF6A6A6A),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildDatePresets() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _datePresets.map((preset) {
          final (label, days) = preset;
          final targetDate =
              DateTime.now().add(Duration(days: days));
          final isSelected = _expiryDate != null &&
              _expiryDate!.year == targetDate.year &&
              _expiryDate!.month == targetDate.month &&
              _expiryDate!.day == targetDate.day;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _applyPreset(days),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF76C442)
                      : const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF76C442)
                        : const Color(0xFF2A2A2A),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
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

  Widget _buildDatePickerRow() {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _expiryDate != null
                ? const Color(0xFF76C442).withValues(alpha: 0.5)
                : const Color(0xFF2A2A2A),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: 20,
              color: _expiryDate != null
                  ? const Color(0xFF76C442)
                  : const Color(0xFF6A6A6A),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _expiryDate != null
                    ? DateFormat('yyyy년 MM월 dd일').format(_expiryDate!)
                    : '날짜 직접 선택',
                style: TextStyle(
                  fontSize: 15,
                  color: _expiryDate != null
                      ? Colors.white
                      : const Color(0xFF5A5A5A),
                  fontWeight: _expiryDate != null
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
              ),
            ),
            if (_expiryDate != null)
              GestureDetector(
                onTap: () => setState(() => _expiryDate = null),
                child: const Icon(Icons.close_rounded,
                    size: 18, color: Color(0xFF6A6A6A)),
              )
            else
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: Color(0xFF4A4A4A)),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageTypeSelector() {
    const types = [
      ('냉장', '🧊', Color(0xFF42A5F5)),
      ('냉동', '❄️', Color(0xFF64B5F6)),
      ('상온', '🌡️', Color(0xFFFF9F0A)),
    ];
    return Row(
      children: types.map((t) {
        final (label, emoji, color) = t;
        final isSelected = _storageType == label;
        final isLast = label == '상온';
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _storageType = label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(right: isLast ? 0 : 10),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.12)
                    : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? color : const Color(0xFF2A2A2A),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? color : const Color(0xFF9A9A9A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExpiryPreview() {
    final days = ExpiryUtils.daysUntil(_expiryDate);
    if (days == null) return const SizedBox.shrink();

    final color = ExpiryUtils.color(days);
    final label = ExpiryUtils.label(days);
    final status = ExpiryUtils.statusText(days);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            days <= 0
                ? Icons.error_outline_rounded
                : days <= 3
                    ? Icons.schedule_rounded
                    : Icons.check_circle_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              days <= 0
                  ? '이미 만료되었거나 오늘 만료됩니다'
                  : days <= 3
                      ? '3일 이내에 만료됩니다 — 주의하세요'
                      : '유통기한이 충분히 남아있어요',
              style: TextStyle(
                  fontSize: 12,
                  color: color.withValues(alpha: 0.9)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
                Text(
                  status,
                  style: TextStyle(
                      fontSize: 9,
                      color: color.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
