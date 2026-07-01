import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// STRIKE WARNING DIALOG
// Checked once on app open. If the user has an unacknowledged
// strike, shows a dismissible warning naming the strike count
// and remaining strikes before permanent restriction (or, if
// already restricted, that this was their final strike).
// ============================================================

class StrikeWarningDialog {
  static Future<void> checkAndShow(BuildContext context) async {
    try {
      final result = await Supabase.instance.client.rpc('get_and_acknowledge_strike_warning');
      if (result == null) return;

      final info = Map<String, dynamic>.from(result);
      if (info['show_warning'] != true) return;

      final strikes = info['strikes'] as int? ?? 0;
      final isRestricted = info['is_restricted'] == true;

      if (!context.mounted) return;
      _show(context, strikes: strikes, isRestricted: isRestricted);
    } catch (e) {
      print('StrikeWarningDialog error: $e');
    }
  }

  static void _show(BuildContext context, {required int strikes, required bool isRestricted}) {
    final remaining = (3 - strikes).clamp(0, 3);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: isRestricted ? Colors.red : Colors.deepOrange, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isRestricted ? 'Account restricted' : 'You\'ve received a strike',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your account received strike $strikes of 3 for violating Passage\'s community guidelines.',
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            if (isRestricted)
              const Text(
                'You have now reached 3 strikes. You are permanently restricted from posting, replying, and sending messages in communities and churches. This does not affect your ability to read, study, or use the AI assistant.',
                style: TextStyle(color: Colors.red, fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
              )
            else
              Text(
                'You have $remaining ${remaining == 1 ? "strike" : "strikes"} remaining before your account is permanently restricted from posting and chatting.',
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
            const SizedBox(height: 14),
            const Text(
              'Passage has no tolerance for disrespectful behavior toward other users.',
              style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I understand', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}