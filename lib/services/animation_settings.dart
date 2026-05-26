import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnimationSettings {
  static final AnimationSettings _i = AnimationSettings._();
  factory AnimationSettings() => _i;
  AnimationSettings._();

  static const _key = 'animations_enabled';
  final ValueNotifier<bool> enabled = ValueNotifier(true);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool v) async {
    enabled.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, v);
  }

  bool get isEnabled => enabled.value;
}
