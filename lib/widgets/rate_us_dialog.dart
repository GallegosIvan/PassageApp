import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/rating_prompt_service.dart';

// ============================================================
// RATE US DIALOG
// The pre-prompt pattern: ask satisfaction first, then route
// happy users to the native store review prompt and unhappy
// users to a private feedback form instead.
//
// Call RateUsDialog.maybeShow(context, trigger: 'quiz_score')
// from a positive-moment screen (quiz results, streak milestone)
// — it silently does nothing if the user isn't eligible yet.
// ============================================================

class RateUsDialog {
  static final _service = RatingPromptService();

  static Future<void> maybeShow(BuildContext context) async {
    final eligible = await _service.isEligibleForPrompt();
    if (!eligible || !context.mounted) return;

    // Small delay so it doesn't fire in the same UI frame as the
    // triggering action (e.g. right as quiz results render) —
    // this measurably improves response rates per platform guidance.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!context.mounted) return;

    _showPrePrompt(context);
  }

  static void _showPrePrompt(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enjoying Passage?',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
        content: const Text(
          'We\'d love to know how it\'s going.',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _service.recordPromptShown(response: 'negative');
              if (context.mounted) _showFeedbackSheet(context);
            },
            child: const Text('Not really', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _service.recordPromptShown(response: 'positive');
              await _service.requestNativeReview();
            },
            child: const Text('Yes!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  static void _showFeedbackSheet(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            const Text('What could be better?',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Your feedback goes directly to the developer, not a public review.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 4,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Tell us what\'s not working...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  final message = controller.text.trim();
                  if (message.isEmpty) return;

                  try {
                    await Supabase.instance.client.from('feedback').insert({
                      'user_id': Supabase.instance.client.auth.currentUser?.id,
                      'message': message,
                    });
                    Navigator.pop(sheetContext);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Thanks for letting us know!'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to send feedback. Please try again.'),
                          backgroundColor: Colors.red,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Send feedback', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}