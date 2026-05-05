import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class UnsplashService {
  static final _cache = <String, String>{};

  // Korean → English translation table (all values must be English)
  static const _translations = <String, String>{
    // 채소
    '당근': 'carrot',
    '양파': 'onion',
    '감자': 'potato',
    '고구마': 'sweet potato',
    '토마토': 'tomato',
    '방울토마토': 'cherry tomato',
    '상추': 'lettuce',
    '오이': 'cucumber',
    '고추': 'chili pepper',
    '청고추': 'green chili pepper',
    '홍고추': 'red chili pepper',
    '마늘': 'garlic',
    '파': 'green onion',
    '대파': 'green onion',
    '쪽파': 'scallion',
    '배추': 'napa cabbage',
    '양배추': 'cabbage',
    '무': 'radish',
    '브로콜리': 'broccoli',
    '시금치': 'spinach',
    '버섯': 'mushroom',
    '표고버섯': 'shiitake mushroom',
    '팽이버섯': 'enoki mushroom',
    '새송이버섯': 'king oyster mushroom',
    '애호박': 'zucchini',
    '호박': 'pumpkin',
    '단호박': 'kabocha squash',
    '가지': 'eggplant',
    '피망': 'bell pepper',
    '파프리카': 'bell pepper',
    '셀러리': 'celery',
    '아스파라거스': 'asparagus',
    '콩나물': 'bean sprouts',
    '숙주': 'mung bean sprouts',
    '깻잎': 'perilla leaves',
    '부추': 'garlic chives',
    '미나리': 'water parsley',
    '연근': 'lotus root',
    '우엉': 'burdock root',
    '도라지': 'bellflower root',
    '두릅': 'aralia shoot',
    // 과일
    '사과': 'apple',
    '배': 'pear',
    '바나나': 'banana',
    '딸기': 'strawberry',
    '포도': 'grape',
    '수박': 'watermelon',
    '참외': 'korean melon',
    '오렌지': 'orange',
    '귤': 'tangerine',
    '레몬': 'lemon',
    '라임': 'lime',
    '자몽': 'grapefruit',
    '복숭아': 'peach',
    '자두': 'plum',
    '체리': 'cherry',
    '망고': 'mango',
    '파인애플': 'pineapple',
    '키위': 'kiwi',
    '블루베리': 'blueberry',
    '라즈베리': 'raspberry',
    '아보카도': 'avocado',
    '코코넛': 'coconut',
    '멜론': 'melon',
    // 육류
    '소고기': 'beef',
    '쇠고기': 'beef',
    '돼지고기': 'pork',
    '닭고기': 'chicken',
    '닭': 'chicken',
    '오리고기': 'duck meat',
    '양고기': 'lamb',
    '삼겹살': 'pork belly',
    '갈비': 'ribs',
    '스테이크': 'steak',
    '소시지': 'sausage',
    '베이컨': 'bacon',
    '햄': 'ham',
    '다짐육': 'ground meat',
    // 어류·해산물
    '연어': 'salmon',
    '참치': 'tuna',
    '고등어': 'mackerel',
    '갈치': 'hairtail fish',
    '조기': 'croaker fish',
    '명태': 'pollock',
    '대구': 'cod fish',
    '광어': 'flounder',
    '새우': 'shrimp',
    '오징어': 'squid',
    '낙지': 'small octopus',
    '문어': 'octopus',
    '게': 'crab',
    '조개': 'clam',
    '홍합': 'mussel',
    '굴': 'oyster',
    '전복': 'abalone',
    '가리비': 'scallop',
    '미역': 'seaweed',
    '김': 'dried seaweed nori',
    '다시마': 'kelp',
    '멸치': 'anchovy',
    // 유제품·달걀
    '우유': 'milk',
    '달걀': 'egg',
    '계란': 'egg',
    '치즈': 'cheese',
    '버터': 'butter',
    '요거트': 'yogurt',
    '생크림': 'heavy cream',
    '아이스크림': 'ice cream',
    '두부': 'tofu',
    // 곡류·가공품
    '쌀': 'rice',
    '현미': 'brown rice',
    '밀가루': 'flour',
    '빵': 'bread',
    '파스타': 'pasta',
    '면': 'noodle',
    '국수': 'noodle',
    '라면': 'ramen noodle',
    '스파게티': 'spaghetti',
    '오트밀': 'oatmeal',
    '콩': 'soybean',
    '팥': 'red bean',
    '옥수수': 'corn',
    '보리': 'barley',
    // 조미료·소스
    '간장': 'soy sauce',
    '고추장': 'gochujang korean chili paste',
    '소금': 'salt',
    '설탕': 'sugar',
    '꿀': 'honey',
    '식초': 'vinegar',
    '올리브오일': 'olive oil',
    '식용유': 'cooking oil',
    '참기름': 'sesame oil',
    '케첩': 'ketchup',
    '마요네즈': 'mayonnaise',
    '고춧가루': 'red pepper powder',
    '후추': 'black pepper',
    '생강': 'ginger',
    '강황': 'turmeric',
    '계피': 'cinnamon',
    '커민': 'cumin',
    '카레': 'curry',
    '된장': 'soybean paste',
    // 음료
    '커피': 'coffee',
    '녹차': 'green tea',
    '홍차': 'black tea',
    '주스': 'juice',
    '오렌지주스': 'orange juice',
    '맥주': 'beer',
    '와인': 'wine',
    '소주': 'korean soju',
    '막걸리': 'makgeolli rice wine',
    '물': 'water bottle',
    '탄산수': 'sparkling water',
    '콜라': 'cola drink',
    // 기타 식품
    '김치': 'kimchi',
    '어묵': 'fish cake',
    '떡': 'rice cake tteok',
    '만두': 'dumpling',
    '초콜릿': 'chocolate',
    '쿠키': 'cookie',
    '케이크': 'cake',
    '과자': 'snack crackers',
    '땅콩': 'peanut',
    '아몬드': 'almond',
    '호두': 'walnut',
    '잣': 'pine nut',
    '깨': 'sesame seed',
    '참깨': 'sesame seed',
    '들깨': 'perilla seed',
  };

  // Fallback: category → English search term (all English)
  static String _categoryToEnglish(String? category) {
    switch (category) {
      case '채소': return 'fresh vegetable produce';
      case '과일': return 'fresh fruit';
      case '육류': return 'raw meat protein';
      case '어류': return 'fresh seafood fish';
      case '유제품': return 'dairy product';
      case '곡류': return 'grain rice food';
      case '조미료': return 'cooking sauce condiment';
      case '음료': return 'beverage drink bottle';
      default: return 'fresh food ingredient';
    }
  }

  /// Returns an English-only search term for any Korean (or English) ingredient name.
  static String toEnglishQuery(String name, {String? category}) {
    // Direct lookup
    if (_translations.containsKey(name)) return _translations[name]!;

    // Partial match (e.g. "방울토마토 2개" → find "방울토마토")
    for (final entry in _translations.entries) {
      if (name.contains(entry.key)) return entry.value;
    }

    // If the name is already ASCII/English, use it directly
    final isLatin = RegExp(r'^[a-zA-Z\s]+$').hasMatch(name.trim());
    if (isLatin) return '${name.trim()} food';

    // Fall back to category-based English term — never use raw Korean
    return _categoryToEnglish(category);
  }

  static Future<String?> getImageUrl(String name,
      {String? category, String size = 'small'}) async {
    final query = toEnglishQuery(name, category: category);
    final cacheKey = '$query-$size';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    try {
      final uri = Uri.https('api.unsplash.com', '/search/photos', {
        'query': query,
        'per_page': '1',
        'orientation': 'squarish',
        'content_filter': 'high',
      });
      final res = await http
          .get(uri, headers: {
            'Authorization': 'Client-ID ${AppConfig.unsplashAccessKey}',
          })
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final url = results[0]['urls'][size] as String?;
          if (url != null) _cache[cacheKey] = url;
          return url;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> getRecipeImageUrl(String recipeName) async {
    // Recipe titles may be Korean — translate key terms to English
    String query = recipeName;
    for (final entry in _translations.entries) {
      query = query.replaceAll(entry.key, entry.value);
    }
    // Append context so Unsplash returns plated dish photos
    query = '$query recipe dish plated food';

    final cacheKey = 'recipe-$recipeName';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    try {
      final uri = Uri.https('api.unsplash.com', '/search/photos', {
        'query': query,
        'per_page': '1',
        'orientation': 'landscape',
        'content_filter': 'high',
      });
      final res = await http
          .get(uri, headers: {
            'Authorization': 'Client-ID ${AppConfig.unsplashAccessKey}',
          })
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final url = results[0]['urls']['regular'] as String?;
          if (url != null) _cache[cacheKey] = url;
          return url;
        }
      }
    } catch (_) {}
    return null;
  }
}
