import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home/main_screen.dart';
import 'auth/landing_screen.dart';
import 'onboarding_flow.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final client = Supabase.instance.client;
    final session = client.auth.currentSession;

    if (session == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LandingScreen()),
      );
      return;
    }

    final userId = client.auth.currentUser?.id ?? '';
    final prefs = await SharedPreferences.getInstance();
    bool onboardingComplete = prefs.getBool('onboarding_complete_$userId') ?? false;

    // Fall back to server if local flag is missing — handles reinstalls
    // and cases where the flag was never written (e.g. null userId at
    // write time).
    if (!onboardingComplete && userId.isNotEmpty) {
      try {
        final result = await client
            .from('users')
            .select('has_completed_onboarding')
            .eq('id', userId)
            .single();
        onboardingComplete = result['has_completed_onboarding'] as bool? ?? false;
        if (onboardingComplete) {
          await prefs.setBool('onboarding_complete_$userId', true);
        }
      } catch (e) {
        print('onboarding server check error: $e');
      }
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => onboardingComplete
            ? const MainScreen()
            : const OnboardingFlow(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icon/icon.png', width: 140, height: 140),
            const SizedBox(height: 24),
            const Text('Passage',
                style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            const Text('Study together. Grow together.',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 48),
            const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          ],
        ),
      ),
    );
  }
}