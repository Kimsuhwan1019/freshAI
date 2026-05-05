import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const supabaseUrl = 'https://tsqhjwsruyohtnzonvvn.supabase.co';
  static const supabaseAnonKey = 'sb_publishable_ZKgYzZdb5i_ml-qLXaSB4g_QW8Glzl-';
  static const openAiBaseUrl = 'https://api.openai.com/v1';
  static const openAiModel = 'gpt-4o';

  static String get unsplashAccessKey =>
      dotenv.env['UNSPLASH_ACCESS_KEY'] ?? '';

  static String get openAiApiKey =>
      dotenv.env['OPENAI_API_KEY'] ?? '';

  static String get googleClientId =>
      dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
}
