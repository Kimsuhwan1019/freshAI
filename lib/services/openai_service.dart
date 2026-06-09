import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config.dart';

class RecognitionResult {
  final bool singleIngredient;
  final List<Map<String, dynamic>> items;
  const RecognitionResult({required this.singleIngredient, required this.items});
}

class OpenAIService {
  static final OpenAIService _instance = OpenAIService._internal();
  factory OpenAIService() => _instance;
  OpenAIService._internal();

  String get _apiKey => AppConfig.openAiApiKey;
  bool get hasApiKey => _apiKey.isNotEmpty;

  Future<void> loadApiKey() async {}

  // ── 냉장고 촬영 → 식재료 인식 ────────────────────────────────

  Future<RecognitionResult> recognizeIngredients(List<int> imageBytes) async {
    if (!hasApiKey) throw Exception('OpenAI API 키가 설정되지 않았습니다');

    final base64Image = base64Encode(imageBytes);

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${AppConfig.openAiBaseUrl}/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': AppConfig.openAiModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text':
                      '이 사진에서 식재료를 분석해 아래 JSON 형식으로만 반환하세요.\n'
                      '{"single_ingredient": true/false, "items": [{"name":"핵심식재료명","quantity":수량또는null,"unit":"단위또는null","category":"카테고리","expiry_date":"YYYY-MM-DD 또는 null","storage_type":"냉장/냉동/상온","reason":"인식근거"}]}\n'
                      '- name: 핵심 식재료명만 (형용사·수식어·원산지 제거: "국내산 유기농 계란"→"계란", "냉동 손질 오징어"→"오징어", "간편 깐 대파"→"대파")\n'
                      '- single_ingredient: 식재료 종류가 딱 1가지만 보이면 true (같은 종류 여러 개도 true), 2종류 이상이면 false\n'
                      '- expiry_date: 패키지/라벨에 유통기한·소비기한·Best Before 표시가 있으면 반드시 "YYYY-MM-DD" 형식으로 변환\n'
                      '  인식 가능 형식 예시: "2026.04.28"→"2026-04-28", "26.04.28"→"2026-04-28", "26년 4월 28일까지"→"2026-04-28"\n'
                      '  유통기한이 없거나 안 보이면 null\n'
                      '- storage_type: 냉장/냉동/상온 중 하나 (채소·육류·어류·계란·유제품→냉장, 아이스크림·냉동식품→냉동, 감자·양파·마늘·라면·조미료·통조림→상온)\n'
                      '- reason: 이 식재료로 판단한 근거 30자 이내 (형태·색상·패키지 텍스트 등)\n'
                      '카테고리: 채소, 과일, 육류, 어류, 유제품, 곡류, 조미료, 음료, 기타 중 하나\n'
                      '순수 JSON 객체만 반환하고 다른 텍스트는 포함하지 마세요.',
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image',
                    'detail': 'high',
                  },
                },
              ],
            }
          ],
          'max_tokens': 1000,
          'temperature': 0.2,
        }),
      ).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw Exception('서버 응답이 느려요. 잠시 후 다시 시도해주세요');
    } on SocketException {
      throw Exception('인터넷 연결을 확인해주세요');
    }

    if (response.statusCode != 200) {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(
          'AI 오류: ${error['error']?['message'] ?? response.statusCode}');
    }

    final result = jsonDecode(utf8.decode(response.bodyBytes));
    final content = result['choices'][0]['message']['content'] as String;
    debugPrint('[OpenAI 냉장고] 원본 응답: $content');

    final cleaned =
        content.replaceAll('```json', '').replaceAll('```', '').trim();
    final Map<String, dynamic> parsed = jsonDecode(cleaned);
    final single = parsed['single_ingredient'] == true;
    final List<dynamic> rawItems = parsed['items'] as List? ?? [];
    final items = rawItems.cast<Map<String, dynamic>>().map((item) {
      final expiryRaw = item['expiry_date']?.toString();
      final normalizedExpiry =
          (expiryRaw != null && expiryRaw != 'null' && expiryRaw.isNotEmpty)
              ? _normalizeExpiryDate(expiryRaw)
              : null;
      return {...item, 'expiry_date': normalizedExpiry};
    }).toList();

    debugPrint('[OpenAI 냉장고] single_ingredient: $single, 아이템 수: ${items.length}');
    for (final item in items) {
      debugPrint('[OpenAI 냉장고] → ${item['name']} / 유통기한: ${item['expiry_date']} / 보관: ${item['storage_type']} / 근거: ${item['reason']}');
    }

    return RecognitionResult(
      singleIngredient: single,
      items: items,
    );
  }

  // 다양한 유통기한 형식 → YYYY-MM-DD 정규화
  String? _normalizeExpiryDate(String raw) {
    final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (isoMatch != null) return raw;

    final dotFull = RegExp(r'^(\d{4})\.(\d{1,2})\.(\d{1,2})$').firstMatch(raw);
    if (dotFull != null) {
      return '${dotFull[1]!}-${dotFull[2]!.padLeft(2, '0')}-${dotFull[3]!.padLeft(2, '0')}';
    }

    final dotShort =
        RegExp(r'^(\d{2})[.\-](\d{1,2})[.\-](\d{1,2})$').firstMatch(raw);
    if (dotShort != null) {
      final year = '20${dotShort[1]!}';
      return '$year-${dotShort[2]!.padLeft(2, '0')}-${dotShort[3]!.padLeft(2, '0')}';
    }

    final korean =
        RegExp(r'(\d{2,4})년\s*(\d{1,2})월\s*(\d{1,2})일').firstMatch(raw);
    if (korean != null) {
      final y = korean[1]!.length == 2 ? '20${korean[1]!}' : korean[1]!;
      return '$y-${korean[2]!.padLeft(2, '0')}-${korean[3]!.padLeft(2, '0')}';
    }

    return null;
  }

  // ── 영수증 스캔 → 식재료 + 유통기한 추정 ──────────────────────

  Future<List<Map<String, dynamic>>> extractReceiptIngredients(
    List<int> imageBytes, {
    required DateTime purchaseDate,
  }) async {
    if (!hasApiKey) throw Exception('OpenAI API 키가 설정되지 않았습니다');

    final base64Image = base64Encode(imageBytes);
    final dateStr = DateFormat('yyyy-MM-dd').format(purchaseDate);

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${AppConfig.openAiBaseUrl}/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': AppConfig.openAiModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': '''이 마트/슈퍼마켓 영수증에서 식품 및 식재료 항목만 추출해주세요.
구매일: $dateStr

[포함] 채소, 과일, 육류, 어류, 유제품, 계란, 조미료, 소스, 가공식품, 냉동식품, 음료 등 식품류
[제외] 세제, 샴푸, 화장품, 생활용품, 주방용품, 비닐봉지, 영수증 수수료 등 비식품류

구매일($dateStr) 기준 일반적인 신선도 유지 기간 추정 기준:
- 생채소(상추/대파/양파/당근 등): 3~7일
- 과일(사과/배/딸기 등): 5~14일
- 신선 육류(돼지/닭/소): 3~5일
- 냉동 육류: 90일
- 생선/해산물: 2~3일
- 계란/달걀: 30일
- 우유: 10~14일
- 두부: 5~7일
- 요거트/치즈: 14~21일
- 간장/고추장/된장 등 조미료: 180~365일
- 통조림/레토르트: 365일
- 냉동식품: 90~180일
- 음료/주스: 30~90일
- 라면/과자/스낵: 90~180일

반드시 순수 JSON 배열만 반환 (다른 텍스트 없이):
[{"name":"상품명","category":"카테고리","quantity":수량또는null,"unit":"단위또는null","estimated_shelf_days":정수,"expiry_date":"YYYY-MM-DD"}]

카테고리: 채소/과일/육류/어류/유제품/곡류/조미료/음료/기타 중 하나
expiry_date = 구매일($dateStr)에 estimated_shelf_days를 더한 날짜''',
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image',
                    'detail': 'high',
                  },
                },
              ],
            }
          ],
          'max_tokens': 2000,
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw Exception('서버 응답이 느려요. 잠시 후 다시 시도해주세요');
    } on SocketException {
      throw Exception('인터넷 연결을 확인해주세요');
    }

    if (response.statusCode != 200) {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(
          'AI 오류: ${error['error']?['message'] ?? response.statusCode}');
    }

    final result = jsonDecode(utf8.decode(response.bodyBytes));
    final content = result['choices'][0]['message']['content'] as String;
    final cleaned =
        content.replaceAll('```json', '').replaceAll('```', '').trim();
    final List<dynamic> items = jsonDecode(cleaned);
    return items.cast<Map<String, dynamic>>();
  }

  // ── 레시피 추천 ───────────────────────────────────────────────

  Future<String> recommendRecipes(
    List<String> ingredientNames, {
    String? difficulty,
    String? cookTime,
  }) async {
    if (!hasApiKey) throw Exception('OpenAI API 키가 설정되지 않았습니다');

    final filterBuf = StringBuffer();
    if (difficulty != null) filterBuf.write('\n- 난이도: $difficulty');
    if (cookTime != null) filterBuf.write('\n- 조리시간: $cookTime 이내');
    final filterClause = filterBuf.isNotEmpty
        ? '\n\n[필수 조건]$filterBuf\n위 조건에 정확히 맞는 레시피만 추천해주세요.'
        : '';

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${AppConfig.openAiBaseUrl}/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': AppConfig.openAiModel,
          'messages': [
            {
              'role': 'system',
              'content': '당신은 한국 요리 전문가입니다. 주어진 식재료로 만들 수 있는 맛있는 레시피를 추천하세요.',
            },
            {
              'role': 'user',
              'content': '보유 식재료: ${ingredientNames.join(', ')}\n\n'
                  '이 재료들로 만들 수 있는 레시피 3가지를 추천해주세요. 각 레시피 형식:\n\n'
                  '## [요리명]\n'
                  '**난이도**: 초급/중급/고급\n'
                  '**조리시간**: XX분\n'
                  '**칼로리**: XXXkcal\n'
                  '### 재료\n'
                  '- 재료 목록\n'
                  '### 만들기\n'
                  '1. 단계\n'
                  '2. 단계\n\n'
                  '---$filterClause',
            }
          ],
          'max_tokens': 2000,
          'temperature': 0.7,
        }),
      ).timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw Exception('서버 응답이 느려요. 잠시 후 다시 시도해주세요');
    } on SocketException {
      throw Exception('인터넷 연결을 확인해주세요');
    }

    if (response.statusCode != 200) {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(
          'AI 오류: ${error['error']?['message'] ?? response.statusCode}');
    }

    final result = jsonDecode(utf8.decode(response.bodyBytes));
    return result['choices'][0]['message']['content'] as String;
  }
}
