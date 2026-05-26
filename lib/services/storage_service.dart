import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  final _client = Supabase.instance.client;
  static const _bucket = 'ingredient-images';

  Future<String?> uploadIngredientImage(Uint8List bytes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('[StorageService] 업로드 실패: 로그인 안 됨');
      return null;
    }

    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '$userId/$fileName';
      debugPrint('[StorageService] 업로드 시작: bucket=$_bucket, path=$path');

      await _client.storage.from(_bucket).uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: false,
        ),
      );

      final url = _client.storage.from(_bucket).getPublicUrl(path);
      debugPrint('[StorageService] 업로드 성공: $url');
      return url;
    } catch (e, stack) {
      debugPrint('[StorageService] 업로드 실패: $e');
      debugPrint('[StorageService] StackTrace: $stack');
      return null;
    }
  }
}
