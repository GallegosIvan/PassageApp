import 'package:shared_preferences/shared_preferences.dart';

class GuestSession {
  static bool _isGuest = false;

  static bool get isGuest => _isGuest;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isGuest = prefs.getBool('is_guest') ?? false;
  }

  static Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest', true);
    _isGuest = true;
  }

  static Future<void> end() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_guest');
    _isGuest = false;
  }
}
