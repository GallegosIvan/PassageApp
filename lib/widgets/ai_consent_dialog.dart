import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiConsentDialog {
  static const _prefKey = 'ai_consent_given';

  static Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> _saveConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  /// Shows the consent dialog if the user hasn't already consented.
  /// Returns true if the user may proceed (already consented or just accepted).
  /// Returns false if the user declined.
  static Future<bool> requestConsent(BuildContext context) async {
    if (await hasConsent()) return true;

    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AiConsentDialogWidget(),
    );

    if (result == true) {
      await _saveConsent();
      return true;
    }
    return false;
  }
}

class _AiConsentDialogWidget extends StatelessWidget {
  const _AiConsentDialogWidget();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'AI-Powered Features',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: const SingleChildScrollView(
        child: Text(
          'To power the Bible AI assistant and chapter quizzes, Passage sends the following data to Anthropic:\n\n'
          '• Your messages and questions\n'
          '• The Bible chapter you are reading\n'
          '• Your selected Bible translation\n\n'
          'This data is sent to Anthropic solely to generate responses and is not used to train AI models. '
          'You can delete your AI conversation history at any time from within the app.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Decline', style: TextStyle(color: Colors.white38)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('I agree', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
