import 'package:flutter/material.dart';

class ExpiryUtils {
  /// 오늘(자정 기준)부터 expiryDate까지 남은 일수.
  /// 음수 = 이미 만료, 0 = 오늘, 양수 = 남은 일
  static int? daysUntil(DateTime? expiryDate) {
    if (expiryDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry =
        DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return expiry.difference(today).inDays;
  }

  /// days <= 0 : 오늘 or 만료
  static bool isExpired(DateTime? d) {
    final days = daysUntil(d);
    return days != null && days <= 0;
  }

  /// 1 ≤ days ≤ 3 : 3일 이내 만료 예정
  static bool isExpiringSoon(DateTime? d) {
    final days = daysUntil(d);
    return days != null && days >= 1 && days <= 3;
  }

  /// "D-day", "D-3", "D+1" 형식 레이블
  static String label(int days) {
    if (days == 0) return 'D-day';
    if (days > 0) return 'D-$days';
    return 'D+${-days}';
  }

  /// 상태에 따른 색상
  static Color color(int days) {
    if (days <= 0) return const Color(0xFFFF453A);
    if (days <= 3) return const Color(0xFFFF9F0A);
    return const Color(0xFF76C442);
  }

  /// 알림 문자열 (예: "D-day", "D-3 후 만료")
  static String statusText(int days) {
    if (days < 0) return '${-days}일 지남';
    if (days == 0) return '오늘 만료';
    return '$days일 남음';
  }
}
