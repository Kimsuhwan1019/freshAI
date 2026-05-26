import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const openAiBaseUrl = 'https://api.openai.com/v1';
  static const openAiModel = 'gpt-4o';

  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? '';

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';

  static String get openAiApiKey =>
      dotenv.env['OPENAI_API_KEY'] ?? '';

  static String get unsplashAccessKey =>
      dotenv.env['UNSPLASH_ACCESS_KEY'] ?? '';

  static String get googleClientId =>
      dotenv.env['GOOGLE_CLIENT_ID'] ?? '';

  static String get kakaoRestApiKey =>
      dotenv.env['KAKAO_REST_API_KEY'] ?? '';
}
