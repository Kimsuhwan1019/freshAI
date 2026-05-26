import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/recipe_service.dart';
import '../../services/animation_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _animEnabled = true;

  @override
  void initState() {
    super.initState();
    AnimationSettings().load().then((_) {
      if (mounted) setState(() => _animEnabled = AnimationSettings().isEnabled);
    });
    AnimationSettings().enabled.addListener(_onAnimChanged);
  }

  @override
  void dispose() {
    AnimationSettings().enabled.removeListener(_onAnimChanged);
    super.dispose();
  }

  void _onAnimChanged() {
    if (mounted) setState(() => _animEnabled = AnimationSettings().isEnabled);
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
              activeTrackColor: const Color(0xFF76C442).withValues(alpha: 0.4),
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
