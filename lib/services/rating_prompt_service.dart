import 'package:in_app_review/in_app_review.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// RATING PROMPT SERVICE
// Decides WHEN to ask for a rating, and shows the pre-prompt
// before triggering the native StoreKit / Play Review API.
//
// Rules (per current App Store / Play guidance):
// - Never on first launch
// - Only after a genuine positive moment (good quiz score,
//   streak milestone)
// - Minimum 3 app sessions before ever asking
// - At least 90 days since the last prompt
// - Max 3 prompts per 365 days (Apple's hard platform limit)
// - Pre-prompt filter: ask "Enjoying Passage?" first; only
//   route happy users to the native prompt, route unhappy users
//   to private feedback instead of risking a public bad review
// ============================================================

class RatingPromptService {
  final _client = Supabase.instance.client;
  final _inAppReview = InAppReview.instance;

  // ── CHECK IF ELIGIBLE TO BE PROMPTED ───────────────────────
  Future<bool> isEligibleForPrompt() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final history = await _client
          .from('rating_prompts')
          .select('shown_at')
          .eq('user_id', userId)
          .order('shown_at', ascending: false);

      final prompts = List<Map<String, dynamic>>.from(history);

      // Never prompted before — eligible (subject to session count
      // check done by the caller before calling this)
      if (prompts.isEmpty) return true;

      // Max 3 times per 365 days
      final oneYearAgo = DateTime.now().subtract(const Duration(days: 365));
      final promptsThisYear = prompts.where((p) {
        final shownAt = DateTime.parse(p['shown_at']);
        return shownAt.isAfter(oneYearAgo);
      }).length;
      if (promptsThisYear >= 3) return false;

      // At least 90 days since the most recent prompt
      final lastShown = DateTime.parse(prompts.first['shown_at']);
      final daysSinceLast = DateTime.now().difference(lastShown).inDays;
      if (daysSinceLast < 90) return false;

      return true;
    } catch (e) {
      print('isEligibleForPrompt error: $e');
      return false;
    }
  }

  // ── RECORD THAT A PROMPT WAS SHOWN ─────────────────────────
  Future<void> recordPromptShown({String? response}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _client.from('rating_prompts').insert({
        'user_id': userId,
        'response': response,
      });
    } catch (e) {
      print('recordPromptShown error: $e');
    }
  }

  // ── TRIGGER THE NATIVE REVIEW PROMPT ───────────────────────
  // Called only after the user answers "Yes" to the pre-prompt.
  // Tries the native StoreKit prompt first; falls back to opening
  // the App Store listing directly so the user can always rate.
  Future<void> requestNativeReview() async {
    try {
      final available = await _inAppReview.isAvailable();
      if (available) {
        await _inAppReview.requestReview();
      } else {
        await openStoreListing();
      }
    } catch (e) {
      print('requestNativeReview error: $e');
      // Native prompt failed — open the store listing so the user
      // can still leave a review.
      await openStoreListing();
    }
  }

  // ── OPEN STORE LISTING DIRECTLY ────────────────────────────
  // Fallback if the native prompt isn't available, or for a
  // manual "rate us" button elsewhere in Settings.
  Future<void> openStoreListing() async {
    try {
      await _inAppReview.openStoreListing(
        appStoreId: '6782405746', // numeric ID from App Store Connect once published
      );
    } catch (e) {
      print('openStoreListing error: $e');
    }
  }
}