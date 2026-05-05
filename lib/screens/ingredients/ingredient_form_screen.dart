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

  final _service = IngredientService();

  static const _categories = [
    '채소', '과일', '육류', '어류', '유제품', '곡류', '조미료', '음료', '기타'
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
    } else if (widget.initialData != null) {
      _nameCtrl.text =
          widget.initialData!['name']?.toString() ?? '';
      final qty = widget.initialData!['quantity'];
      _qtyCtrl.text = qty != null ? qty.toString() : '';
      _unitCtrl.text =
          widget.initialData!['unit']?.toString() ?? '';
      _category =
          widget.initialData!['category']?.toString();
    }
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
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        if (_qtyCtrl.text.isNotEmpty)
          'quantity': double.tryParse(_qtyCtrl.text),
        if (_unitCtrl.text.isNotEmpty)
          'unit': _unitCtrl.text.trim(),
        if (_category != null) 'category': _category,
        if (_expiryDate != null)
          'expiry_date':
              DateFormat('yyyy-MM-dd').format(_expiryDate!),
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
            // Name
            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '식재료 이름 *',
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? '이름을 입력해주세요' : null,
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
                    value: _units.contains(_unitCtrl.text)
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
            const SizedBox(height: 14),
            // Category
            DropdownButtonFormField<String>(
              value: _category,
              dropdownColor: const Color(0xFF252525),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '카테고리',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _categories
                  .map((c) =>
                      DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v),
            ),
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
