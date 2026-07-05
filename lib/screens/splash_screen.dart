import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home/main_screen.dart';
import 'auth/landing_screen.dart';
import 'onboarding_flow.dart';

class SplashScreen extends StatefulWidget {
  final bool showNoInternet;
  const SplashScreen({super.key, this.showNoInternet = false});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _noInternet = false;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    if (widget.showNoInternet) {
      setState(() => _noInternet = true);
    } else {
      _checkAndNavigate();
    }
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('supabase.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkAndNavigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final connected = await _hasInternet();
    if (!connected) {
      if (mounted) setState(() => _noInternet = true);
      return;
    }

    await _navigate();
  }

  Future<void> _navigate() async {
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
    bool onboardingComplete =
        prefs.getBool('onboarding_complete_$userId') ?? false;

    if (!onboardingComplete && userId.isNotEmpty) {
      try {
        final result = await client
            .from('users')
            .select('has_completed_onboarding')
            .eq('id', userId)
            .single();
        onboardingComplete =
            result['has_completed_onboarding'] as bool? ?? false;
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

  Future<void> _retry() async {
    setState(() {
      _noInternet = false;
      _retrying = true;
    });

    final connected = await _hasInternet();
    if (!connected) {
      if (mounted) setState(() { _noInternet = true; _retrying = false; });
      return;
    }

    setState(() => _retrying = false);
    await _navigate();
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
            const Text(
              'Passage',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Study together. Grow together.',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 48),
            if (_noInternet) ...[
              const Icon(Icons.wifi_off, color: Colors.white54, size: 36),
              const SizedBox(height: 16),
              const Text(
                'No Internet Connection',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Passage requires an internet connection to run.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: _retry,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF2A2A2A),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Try Again'),
              ),
            ] else if (_retrying) ...[
              const CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            ] else ...[
              const CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            ],
          ],
        ),
      ),
    );
  }
}
