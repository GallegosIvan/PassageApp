import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import '../terms_gate_screen.dart';
import '../home/main_screen.dart';

// ============================================================
// LANDING SCREEN
// First thing an unauthenticated person sees. Two paths:
//   - Log in: straight to LoginScreen, no terms gate — an
//     existing account already implies prior acceptance.
//   - Sign up: goes through TermsGateScreen FIRST, then
//     SignUpScreen, then accept_terms is recorded server-side
//     right after the account is actually created.
//
// IMPORTANT: every navigation from here uses pushReplacement,
// not push. Using push left LandingScreen sitting on the
// navigation stack underneath everything else, which is why a
// stray back arrow was showing up on every screen in the app —
// MainScreen wasn't actually the root of the stack, LandingScreen
// was still sitting beneath it. Same reasoning applies inside
// LoginScreen and SignUpScreen's own navigation.
// ============================================================

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),

              Container(
                child: Image.asset('assets/icon/icon.png', width: 120, height: 120),
              ),

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
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),

              const Spacer(flex: 3),

              // ── CREATE ACCOUNT — goes through terms gate first ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const TermsGateScreen(
                          nextScreen: SignUpScreen(),
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Create account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── LOG IN — no terms gate, account already exists ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Log in',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── BROWSE AS GUEST ───────────────────────────
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const TermsGateScreen(
                        isGuestMode: true,
                        nextScreen: MainScreen(),
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Browse without account',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}