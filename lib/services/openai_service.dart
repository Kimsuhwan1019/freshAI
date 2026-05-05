import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config.dart';

class OpenAIService {
  static final OpenAIService _instance = OpenAIService._internal();
  factory OpenAIService() => _instance;
  OpenAIService._internal();

  // API key comes from .env via AppConfig — no user input needed
  String get _apiKey => AppConfig.openAiApiKey;
  bool get hasApiKey => _apiKey.isNotEmpty;

  // No-op: kept for call-site compatibility; key is now loaded from .env
  Future<void> loadApiKey() async {}

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

    final cleaned = content
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    final List<dynamic> ingredients = jsonDecode(cleaned);
    return ingredients.cast<Map<String, dynamic>>();
  }

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
