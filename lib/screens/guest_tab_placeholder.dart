import 'package:flutter/material.dart';
import '../widgets/guest_signup_sheet.dart';

class GuestTabPlaceholder extends StatelessWidget {
  final String featureName;
  final IconData icon;

  const GuestTabPlaceholder({
    super.key,
    required this.featureName,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white24, size: 56),
              const SizedBox(height: 20),
              Text(
                featureName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create a free account to access this feature.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => GuestSignUpSheet.show(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Sign up — it\'s free',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
