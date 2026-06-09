import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/animation_settings.dart';
import '../../services/ingredient_service.dart';
import '../../services/notification_service.dart';
import '../../services/recipe_service.dart';
import '../../utils/expiry_utils.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _animEnabled = true;
  bool _notifEnabled = true;
  bool _notifLoading = false;

  @override
  void initState() {
    super.initState();
    AnimationSettings().load().then((_) {
      if (mounted) setState(() => _animEnabled = AnimationSettings().isEnabled);
    });
    AnimationSettings().enabled.addListener(_onAnimChanged);
    _loadNotifState();
  }

  @override
  void dispose() {
    AnimationSettings().enabled.removeListener(_onAnimChanged);
    super.dispose();
  }

  void _onAnimChanged() {
    if (mounted) setState(() => _animEnabled = AnimationSettings().isEnabled);
  }

  Future<void> _loadNotifState() async {
    final enabled = await NotificationService.isEnabled();
    if (mounted) setState(() => _notifEnabled = enabled);
  }

  Future<void> _toggleNotification(bool value) async {
    if (_notifLoading) return;
    setState(() => _notifLoading = true);

    try {
      if (value) {
        // 권한 요청
        final granted = await NotificationService.requestPermission();
        if (!granted && mounted) {
          _showSnack('알림 권한이 필요합니다. 설정에서 허용해주세요.', error: true);
          setState(() => _notifLoading = false);
          return;
        }
      }
      await NotificationService.setEnabled(value);
      if (mounted) setState(() => _notifEnabled = value);

      if (value && mounted) {
        _showSnack('매일 오전 9시에 유통기한 알림을 드립니다');
      }
    } finally {
      if (mounted) setState(() => _notifLoading = false);
    }
  }

  Future<void> _testNotification() async {
    if (Supabase.instance.client.auth.currentUser == null) return;

    setState(() => _notifLoading = true);
    try {
      final ingredients = await IngredientService().getIngredients();

      // 유통기한 3일 이내 + 만료된 식재료 → 공용 ExpiryNotifItem 목록 생성
      final items = ingredients
          .where((i) {
            final days = ExpiryUtils.daysUntil(i.expiryDate);
            return days != null && days <= 3;
          })
          .map((i) => ExpiryNotifItem(
                name: i.name,
                days: ExpiryUtils.daysUntil(i.expiryDate)!,
              ))
          .toList();

      // 공용 함수로 알림 표시 (정렬 · BigTextStyle · HTML 포맷 모두 적용)
      final shown = await NotificationService.showExpiryNotif(items);
      if (mounted) {
        _showSnack(shown ? '테스트 알림을 전송했습니다' : '유통기한 임박 식재료가 없습니다 😊');
      }
    } catch (e) {
      if (mounted) _showSnack('알림 전송 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _notifLoading = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? const Color(0xFFFF453A) : const Color(0xFF76C442),
      ),
    );
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소',
                style: TextStyle(color: Color(0xFF9A9A9A))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃',
                style: TextStyle(
                    color: Color(0xFFFF453A),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await RecipeService().clearLocalCache();
      await Supabase.instance.client.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'U';

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _profileCard(email, initial),
          const SizedBox(height: 24),
          _sectionLabel('알림'),
          const SizedBox(height: 8),
          _notifCard(),
          const SizedBox(height: 24),
          _sectionLabel('화면'),
          const SizedBox(height: 8),
          _animCard(),
          const SizedBox(height: 24),
          _sectionLabel('앱 정보'),
          const SizedBox(height: 8),
          _infoCard(),
          const SizedBox(height: 32),
          _logoutButton(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Color(0xFF6A6A6A),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _profileCard(String email, String initial) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2A14), Color(0xFF1A1A1A)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF76C442), Color(0xFF4A9A24)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '로그인 계정',
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6A6A6A),
                      letterSpacing: 0.3),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 알림 카드 ──────────────────────────────────────────────────

  Widget _notifCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        children: [
          // 토글 행
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.notifications_rounded,
                      size: 16, color: Color(0xFFFF9F0A)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('유통기한 알림',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      Text('매일 오전 9시, 3일 이내 만료 식재료 알림',
                          style: TextStyle(
                              color: Color(0xFF6A6A6A), fontSize: 12)),
                    ],
                  ),
                ),
                if (_notifLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF76C442)),
                  )
                else
                  Switch(
                    value: _notifEnabled,
                    onChanged: _toggleNotification,
                    activeThumbColor: const Color(0xFFFF9F0A),
                    activeTrackColor:
                        const Color(0xFFFF9F0A).withValues(alpha: 0.4),
                  ),
              ],
            ),
          ),
          // 테스트 알림 버튼 (알림 ON일 때만 표시)
          if (_notifEnabled) ...[
            const Divider(height: 1, color: Color(0xFF252525), indent: 16),
            InkWell(
              onTap: _notifLoading ? null : _testNotification,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(17)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.send_rounded,
                        size: 15, color: Color(0xFF9A9A9A)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '테스트 알림 보내기',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF9A9A9A)),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 16, color: Color(0xFF4A4A4A)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _animCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF76C442).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.animation,
                  size: 16, color: Color(0xFF76C442)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('애니메이션 효과',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text('카드 등장, 반짝임, 버튼 효과 등',
                      style: TextStyle(
                          color: Color(0xFF6A6A6A), fontSize: 12)),
                ],
              ),
            ),
            Switch(
              value: _animEnabled,
              onChanged: (v) => AnimationSettings().setEnabled(v),
              activeThumbColor: const Color(0xFF76C442),
              activeTrackColor:
                  const Color(0xFF76C442).withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        children: [
          _infoRow(
            icon: Icons.kitchen,
            iconColor: const Color(0xFF76C442),
            title: 'FreshAI',
            subtitle: '스마트 냉장고 식재료 관리',
          ),
          const Divider(height: 1, indent: 16),
          _infoRow(
            icon: Icons.auto_awesome,
            iconColor: const Color(0xFFFF9F0A),
            title: 'AI 기능',
            subtitle: 'GPT-4o Vision · 레시피 추천',
          ),
          const Divider(height: 1, indent: 16),
          _infoRow(
            icon: Icons.info_outline,
            iconColor: const Color(0xFF6A6A6A),
            title: '버전',
            trailing: '1.0.0',
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    String? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if (subtitle != null)
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF6A6A6A), fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing,
                style: const TextStyle(
                    color: Color(0xFF6A6A6A), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _logoutButton() {
    return GestureDetector(
      onTap: _signOut,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFF453A).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFFFF453A).withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded,
                color: Color(0xFFFF453A), size: 20),
            SizedBox(width: 8),
            Text(
              '로그아웃',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF453A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
