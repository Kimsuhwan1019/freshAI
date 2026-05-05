import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/openai_service.dart';
import '../../services/ingredient_service.dart';
import '../ingredients/ingredient_form_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _picker = ImagePicker();
  final _openAI = OpenAIService();
  final _ingredientSvc = IngredientService();

  File? _image;
  List<Map<String, dynamic>>? _recognized;
  List<bool> _selected = [];
  bool _isAnalyzing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _openAI.loadApiKey();
  }

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

  Future<void> _analyze() async {
    if (_image == null) return;

    setState(() => _isAnalyzing = true);
    try {
      final bytes = await _image!.readAsBytes();
      final result = await _openAI.recognizeIngredients(bytes);
      setState(() {
        _recognized = result;
        _selected = List.filled(result.length, true);
      });
    } catch (e) {
      _showSnack('인식 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

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
      for (final item in toSave) {
        await _ingredientSvc.addIngredient({
          'name': item['name'],
          if (item['quantity'] != null) 'quantity': item['quantity'],
          if (item['unit'] != null && item['unit'] != 'null')
            'unit': item['unit'],
          if (item['category'] != null) 'category': item['category'],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('냉장고 촬영',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildImageArea(),
            const SizedBox(height: 16),
            _buildPickButtons(),
            if (_recognized != null) ...[
              const SizedBox(height: 24),
              _buildRecognizedList(),
              const SizedBox(height: 16),
              _buildSaveButton(),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildImageArea() {
    if (_image != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(
              _image!,
              width: double.infinity,
              height: 280,
              fit: BoxFit.cover,
            ),
          ),
          if (_isAnalyzing)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF76C442)),
                    SizedBox(height: 16),
                    Text(
                      'AI가 식재료를 인식하는 중...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.camera_alt_outlined,
                size: 32, color: Color(0xFF4A4A4A)),
          ),
          const SizedBox(height: 16),
          const Text(
            '냉장고 사진을 촬영하거나\n갤러리에서 선택하세요',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Color(0xFF9A9A9A), fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'GPT-4o Vision이 식재료를 자동으로 인식합니다',
            style: TextStyle(color: Color(0xFF5A5A5A), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPickButtons() {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            icon: Icons.camera_alt,
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

  Widget _actionButton(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
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

  Widget _buildRecognizedList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '인식된 식재료',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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
            const Spacer(),
            GestureDetector(
              onTap: () {
                setState(() {
                  _selected = List.filled(
                    _recognized!.length,
                    !_selected.every((e) => e),
                  );
                });
              },
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
        ...List.generate(_recognized!.length, (i) {
          final item = _recognized![i];
          final qty = item['quantity'];
          final unit = item['unit'];
          final cat = item['category'];

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _selected[i]
                    ? const Color(0xFF76C442).withValues(alpha: 0.4)
                    : const Color(0xFF2A2A2A),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () =>
                  setState(() => _selected[i] = !_selected[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    AnimatedContainer(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name']?.toString() ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15),
                          ),
                          if ([qty, unit, cat].any((v) =>
                              v != null && v.toString() != 'null'))
                            Text(
                              [
                                if (qty != null &&
                                    qty.toString() != 'null')
                                  '$qty ${unit ?? ''}',
                                if (cat != null &&
                                    cat.toString() != 'null')
                                  cat.toString(),
                              ].join(' · '),
                              style: const TextStyle(
                                  color: Color(0xFF6A6A6A),
                                  fontSize: 12),
                            ),
                        ],
                      ),
                    ),
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
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSaveButton() {
    final count = _selected.where((e) => e).length;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF76C442), Color(0xFF4A9A24)],
        ),
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
}
