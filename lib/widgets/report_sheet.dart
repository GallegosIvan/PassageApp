import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// REPORT SHEET
// Reusable bottom sheet for reporting posts, replies, users, or
// church chat messages. Required for App Store approval.
// ============================================================

enum ReportType { post, reply, user, churchMessage }

class ReportSheet extends StatefulWidget {
  final ReportType type;
  final String targetId; // post_id, reply_id, user_id, or message_id
  final String? targetUserId; // the user who created the content

  const ReportSheet({
    super.key,
    required this.type,
    required this.targetId,
    this.targetUserId,
  });

  static Future<void> show(
    BuildContext context, {
    required ReportType type,
    required String targetId,
    String? targetUserId,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ReportSheet(
        type: type,
        targetId: targetId,
        targetUserId: targetUserId,
      ),
    );
  }

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  final _client = Supabase.instance.client;
  String? _selectedReason;
  bool _isSubmitting = false;

  final List<String> _reasons = [
    'Spam or misleading content',
    'Hate speech or harassment',
    'Sexually explicit content',
    'Violence or threatening behavior',
    'False information',
    'Violates community guidelines',
    'Other',
  ];

  String get _typeLabel {
    switch (widget.type) {
      case ReportType.post: return 'post';
      case ReportType.reply: return 'reply';
      case ReportType.user: return 'user';
      case ReportType.churchMessage: return 'message';
    }
  }

  // The report_type string stored in the database. Stored as
  // 'church_message' (snake_case) to stay consistent with the
  // existing 'post'/'reply'/'user' values rather than using
  // Dart's camelCase enum name directly.
  String get _typeValue {
    switch (widget.type) {
      case ReportType.post: return 'post';
      case ReportType.reply: return 'reply';
      case ReportType.user: return 'user';
      case ReportType.churchMessage: return 'church_message';
    }
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;
    setState(() => _isSubmitting = true);

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      await _client.from('reports').insert({
        'reporter_id': userId,
        'report_type': _typeValue,
        'target_id': widget.targetId,
        'target_user_id': widget.targetUserId,
        'reason': _selectedReason,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted. Thank you for helping keep Passage safe.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to submit report. Please try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Report ${_typeLabel[0].toUpperCase()}${_typeLabel.substring(1)}',
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select the reason for your report. All reports are reviewed by our team.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ..._reasons.map((reason) => GestureDetector(
            onTap: () => setState(() => _selectedReason = reason),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _selectedReason == reason
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _selectedReason == reason
                      ? Colors.white
                      : Colors.white12,
                ),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(reason,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
                if (_selectedReason == reason)
                  const Icon(Icons.check, color: Colors.white, size: 18),
              ]),
            ),
          )),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _selectedReason == null || _isSubmitting
                  ? null
                  : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2))
                  : const Text('Submit report',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}