import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config.dart';

class OpenAIService {
  static final OpenAIService _instance = OpenAIService._internal();
  factory OpenAIService() => _instance;
  OpenAIService._internal();

  String get _apiKey => AppConfig.openAiApiKey;
  bool get hasApiKey => _apiKey.isNotEmpty;

  Future<void> loadApiKey() async {}

  // ── 냉장고 촬영 → 식재료 인식 ────────────────────────────────

  Future<List<Map<String, dynamic>>> recognizeIngredients(
      Uint8List imageBytes) async {
    if (!hasApiKey) throw Exception('OpenAI API 키가 설정되지 않았습니다');

    final base64Image = base64Encode(imageBytes);

    final response = await http.post(
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
                    '이 냉장고 사진에서 보이는 모든 식재료를 인식하고 JSON 배열로만 반환하세요.\n'
                    '각 항목 형식: {"name":"식재료명","quantity":수량또는null,"unit":"단위또는null","category":"카테고리"}\n'
                    '카테고리: 채소, 과일, 육류, 어류, 유제품, 곡류, 조미료, 음료, 기타 중 하나\n'
                    '반드시 순수 JSON 배열만 반환하고 다른 텍스트는 포함하지 마세요.',
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
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(
          'OpenAI 오류: ${error['error']?['message'] ?? response.statusCode}');
    }

    final result = jsonDecode(utf8.decode(response.bodyBytes));
    final content = result['choices'][0]['message']['content'] as String;
    final cleaned =
        content.replaceAll('```json', '').replaceAll('```', '').trim();
    final List<dynamic> items = jsonDecode(cleaned);
    return items.cast<Map<String, dynamic>>();
  }

  // ── 영수증 스캔 → 식재료 + 유통기한 추정 ──────────────────────

  Future<List<Map<String, dynamic>>> extractReceiptIngredients(
    Uint8List imageBytes, {
    required DateTime purchaseDate,
  }) async {
    if (!hasApiKey) throw Exception('OpenAI API 키가 설정되지 않았습니다');

    final base64Image = base64Encode(imageBytes);
    final dateStr = DateFormat('yyyy-MM-dd').format(purchaseDate);

    final response = await http.post(
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
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(
          'OpenAI 오류: ${error['error']?['message'] ?? response.statusCode}');
    }

    final result = jsonDecode(utf8.decode(response.bodyBytes));
    final content = result['choices'][0]['message']['content'] as String;
    final cleaned =
        content.replaceAll('```json', '').replaceAll('```', '').trim();
    final List<dynamic> items = jsonDecode(cleaned);
    return items.cast<Map<String, dynamic>>();
  }

  // ── 레시피 추천 ───────────────────────────────────────────────

  Future<String> recommendRecipes(List<String> ingredientNames) async {
    if (!hasApiKey) throw Exception('OpenAI API 키가 설정되지 않았습니다');

    final response = await http.post(
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
                '---',
          }
        ],
        'max_tokens': 2000,
        'temperature': 0.7,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(
          'OpenAI 오류: ${error['error']?['message'] ?? response.statusCode}');
    }

    final result = jsonDecode(utf8.decode(response.bodyBytes));
    return result['choices'][0]['message']['content'] as String;
  }
}
