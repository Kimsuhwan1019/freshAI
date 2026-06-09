import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import '../config.dart';
import '../utils/expiry_utils.dart';

const _kTaskName = 'freshAI_expiryCheck';
const _kNotifEnabled = 'notifications_enabled';
const _kChannelId = 'freshAI_expiry';
const _kChannelName = '유통기한 알림';

// ── 공용 데이터 클래스 ─────────────────────────────────────────────────────────

/// 알림에 사용할 식재료 항목 (배경 태스크 · 설정 탭 공유)
class ExpiryNotifItem {
  final String name;
  final int days; // ≤ 0 = 이미 만료, > 0 = 남은 일수

  const ExpiryNotifItem({required this.name, required this.days});
}

// ── WorkManager 백그라운드 진입점 ──────────────────────────────────────────────

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    if (taskName != _kTaskName) return true;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_kNotifEnabled) ?? true)) return true;

      WidgetsFlutterBinding.ensureInitialized();

      try {
        await dotenv.load(fileName: '.env');
      } catch (_) {}

      try {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
        );
      } catch (_) {}

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return true;

      final cutoff = DateFormat('yyyy-MM-dd')
          .format(DateTime.now().add(const Duration(days: 3)));

      final data = await Supabase.instance.client
          .from('ingredients')
          .select('name, expiry_date')
          .eq('user_id', userId)
          .not('expiry_date', 'is', null)
          .lte('expiry_date', cutoff);

      final items = <ExpiryNotifItem>[];
      for (final row in (data as List).cast<Map<String, dynamic>>()) {
        final expiry = DateTime.parse(row['expiry_date'] as String);
        final days = ExpiryUtils.daysUntil(expiry);
        if (days == null) continue;
        items.add(ExpiryNotifItem(name: row['name'] as String, days: days));
      }

      if (items.isEmpty) return true;

      // 배경 태스크용 플러그인 인스턴스 초기화 후 공용 함수 호출
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await NotificationService.showExpiryNotif(items, pluginOverride: plugin);
    } catch (_) {}

    return true;
  });
}

// ── NotificationService ────────────────────────────────────────────────────────

class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();

  /// 앱 시작 시 1회 호출
  static Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _kChannelId,
            _kChannelName,
            description: '유통기한 임박 식재료를 매일 아침 알려드립니다',
            importance: Importance.high,
          ),
        );
  }

  /// Android 13+ 알림 권한 요청
  static Future<bool> requestPermission() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await impl?.requestNotificationsPermission() ?? false;
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kNotifEnabled) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifEnabled, value);
    if (value) {
      await _scheduleDaily();
    } else {
      await Workmanager().cancelByUniqueName(_kTaskName);
    }
  }

  static Future<void> ensureScheduled() async {
    if (await isEnabled()) await _scheduleDaily();
  }

  static Future<void> _scheduleDaily() async {
    await Workmanager().registerPeriodicTask(
      _kTaskName,
      _kTaskName,
      frequency: const Duration(hours: 24),
      initialDelay: _delayUntilNextNineAM(),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  static Duration _delayUntilNextNineAM() {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, 9);
    if (!now.isBefore(target)) target = target.add(const Duration(days: 1));
    return target.difference(now);
  }

  // ── 공용 알림 표시 함수 ────────────────────────────────────────────────────

  /// 만료·임박 식재료 알림을 BigTextStyle 형식으로 표시.
  /// items가 비어있으면 알림 미표시 후 false 반환.
  /// [pluginOverride]: 백그라운드 태스크처럼 별도 인스턴스가 필요할 때 전달.
  static Future<bool> showExpiryNotif(
    List<ExpiryNotifItem> items, {
    FlutterLocalNotificationsPlugin? pluginOverride,
  }) async {
    final payload = _buildPayload(items);
    if (payload == null) return false;

    final plugin = pluginOverride ?? _plugin;
    await plugin.show(
      id: 0,
      title: payload.title,
      body: payload.summary,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(
            payload.bigText,
            htmlFormatBigText: true,
          ),
        ),
      ),
    );
    return true;
  }

  // ── 페이로드 빌더 (정렬 · 그룹핑 · HTML) ──────────────────────────────────

  static ({String title, String summary, String bigText})? _buildPayload(
    List<ExpiryNotifItem> items,
  ) {
    // 만료된 항목: 많이 지난 순 (days 오름차순: -5 → -3 → -1 → 0)
    final expired = items.where((i) => i.days <= 0).toList()
      ..sort((a, b) => a.days.compareTo(b.days));

    // 임박한 항목: D-1, D-2, D-3 순 (days 오름차순)
    final upcoming = items.where((i) => i.days > 0).toList()
      ..sort((a, b) => a.days.compareTo(b.days));

    if (expired.isEmpty && upcoming.isEmpty) return null;

    final total = expired.length + upcoming.length;

    // 제목 (접힌 상태에서도 표시)
    final title = '🧊 유통기한 알림 · 총 $total개';

    // 한 줄 요약 (접혔을 때 body)
    final firstName = expired.isNotEmpty ? expired.first.name : upcoming.first.name;
    final rest = total - 1;
    final summary = rest > 0
        ? '$firstName 외 $rest개가 곧 만료돼요'
        : '$firstName 유통기한이 곧 만료돼요';

    // BigText HTML (펼쳤을 때)
    final buf = StringBuffer();
    if (expired.isNotEmpty) {
      buf.write('<b>🔴 이미 만료됨</b>');
      for (final item in expired) {
        buf.write('<br>• ${item.name}');
      }
    }
    if (upcoming.isNotEmpty) {
      if (expired.isNotEmpty) buf.write('<br>');
      buf.write('<b>🟠 유통기한 임박</b>');
      for (final item in upcoming) {
        buf.write('<br>• ${item.name} (D-${item.days})');
      }
    }

    return (title: title, summary: summary, bigText: buf.toString());
  }
}
