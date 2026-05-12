import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../services/ingredient_service.dart';
import '../utils/expiry_utils.dart';
import 'ingredients/ingredients_screen.dart';
import 'camera/camera_screen.dart';
import 'recipes/recipe_screen.dart';
import 'settings/settings_screen.dart';
import 'shopping/shopping_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _screens = const [
    IngredientsScreen(),
    CameraScreen(),
    RecipeScreen(),
    ShoppingScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkExpiry());
  }

  Future<void> _checkExpiry() async {
    if (!mounted) return;
    try {
      final ingredients = await IngredientService().getIngredients();
      final expired = <Ingredient>[];
      final soon = <Ingredient>[];

      for (final item in ingredients) {
        final days = ExpiryUtils.daysUntil(item.expiryDate);
        if (days == null) continue;
        if (days <= 0) {
          expired.add(item);
        } else if (days <= 3) {
          soon.add(item);
        }
      }

      if ((expired.isNotEmpty || soon.isNotEmpty) && mounted) {
        _showExpirySheet(expired, soon);
      }
    } catch (_) {}
  }

  void _showExpirySheet(
      List<Ingredient> expired, List<Ingredient> soon) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ExpiryNotificationSheet(
        expired: expired,
        soon: soon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            selectedIcon: Icon(Icons.kitchen),
            label: '식재료',
          ),
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: '촬영',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '레시피',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: '쇼핑',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '설정',
          ),
        ],
      ),
    );
  }
}

class _ExpiryNotificationSheet extends StatelessWidget {
  final List<Ingredient> expired;
  final List<Ingredient> soon;

  const _ExpiryNotificationSheet({
    required this.expired,
    required this.soon,
  });

  @override
  Widget build(BuildContext context) {
    final total = expired.length + soon.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.notifications_rounded,
                      color: Color(0xFFFF9F0A), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '유통기한 알림',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '주의가 필요한 식재료가 $total개 있어요',
                        style: const TextStyle(
                            color: Color(0xFF9A9A9A), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF6A6A6A), size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFF2A2A2A),
              indent: 20, endIndent: 20),
          const SizedBox(height: 8),

          // Expired section
          if (expired.isNotEmpty) ...[
            _sectionHeader(
              '만료됨 (${expired.length}개)',
              const Color(0xFFFF453A),
              Icons.error_outline_rounded,
            ),
            ...expired.map((i) => _itemRow(i)),
            const SizedBox(height: 4),
          ],

          // Soon section
          if (soon.isNotEmpty) ...[
            if (expired.isNotEmpty)
              const Divider(height: 1, color: Color(0xFF2A2A2A),
                  indent: 20, endIndent: 20),
            const SizedBox(height: 4),
            _sectionHeader(
              '3일 이내 만료 (${soon.length}개)',
              const Color(0xFFFF9F0A),
              Icons.schedule_rounded,
            ),
            ...soon.map((i) => _itemRow(i)),
          ],

          const SizedBox(height: 12),
          // CTA button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF76C442),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text(
                  '확인했어요',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(Ingredient item) {
    final days = ExpiryUtils.daysUntil(item.expiryDate)!;
    final color = ExpiryUtils.color(days);
    final label = ExpiryUtils.label(days);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.name,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          if (item.category != null)
            Text(
              item.category!,
              style: const TextStyle(
                  color: Color(0xFF6A6A6A), fontSize: 12),
            ),
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
