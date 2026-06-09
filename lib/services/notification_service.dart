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

/// WorkManager 백그라운드 진입점 — top-level + vm:entry-point 필수
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

      // 오늘 기준 3일 이내 + 이미 만료된 식재료 조회
      final cutoff = DateFormat('yyyy-MM-dd')
          .format(DateTime.now().add(const Duration(days: 3)));

      final data = await Supabase.instance.client
          .from('ingredients')
          .select('name, expiry_date')
          .eq('user_id', userId)
          .not('expiry_date', 'is', null)
          .lte('expiry_date', cutoff);

      final rows = (data as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return true;

      final parts = <String>[];
      for (final row in rows) {
        final name = row['name'] as String;
        final expiry = DateTime.parse(row['expiry_date'] as String);
        final days = ExpiryUtils.daysUntil(expiry);
        if (days == null) continue;
        parts.add('$name(${days <= 0 ? '만료' : 'D-$days'})');
      }
      if (parts.isEmpty) return true;

      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await plugin.show(
        id: 0,
        title: '🧊 FreshAI 유통기한 알림',
        body: '${parts.join(', ')} 유통기한이 곧 만료됩니다!',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannelId,
            _kChannelName,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (_) {}

    return true;
  });
}

// ── App-side notification service ─────────────────────────────────────────────

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
    // Android 8+ 알림 채널 생성
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

  /// 알림 활성화 여부 조회
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kNotifEnabled) ?? true;
  }

  /// 알림 ON/OFF 설정
  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifEnabled, value);
    if (value) {
      await _scheduleDaily();
    } else {
      await Workmanager().cancelByUniqueName(_kTaskName);
    }
  }

  /// 앱 시작 시 스케줄 등록
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

  /// 다음 오전 9시까지 남은 시간
  static Duration _delayUntilNextNineAM() {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, 9);
    if (!now.isBefore(target)) target = target.add(const Duration(days: 1));
    return target.difference(now);
  }

  /// 설정 화면 테스트용 즉시 알림
  static Future<void> showPreview(String body) async {
    await _plugin.show(
      id: 0,
      title: '🧊 FreshAI 유통기한 알림',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}
