import 'package:flutter/material.dart';

// ============================================================
// RESTRICTED DIALOG
// Shown whenever a permanently restricted user attempts to
// post or reply. Reusable across community posts, replies,
// and church announcements.
// ============================================================

class RestrictedDialog {
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.block, color: Colors.red, size: 22),
            SizedBox(width: 10),
            Text('Chat access restricted',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Your account has been permanently restricted from posting or replying in communities and churches due to repeated violations of our community guidelines.\n\n'
          'This restriction is permanent and applies regardless of subscription status. All other features — including Bible reading, notes, highlights, quizzes, and the AI assistant — remain fully available to you.',
          style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
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