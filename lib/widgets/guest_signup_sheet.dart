import 'package:flutter/material.dart';
import '../screens/auth/landing_screen.dart';
import '../services/guest_session.dart';

class GuestSignUpSheet extends StatelessWidget {
  const GuestSignUpSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const GuestSignUpSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.lock_outline, color: Colors.white54, size: 40),
          const SizedBox(height: 16),
          const Text(
            'Sign up to continue',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a free account to save highlights, join communities, track your reading streak, and more.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () async {
                await GuestSession.end();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LandingScreen()),
                    (_) => false,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Sign up',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Maybe later',
                style: TextStyle(color: Colors.white38, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
