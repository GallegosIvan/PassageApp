import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// ADMIN APPEALS SCREEN
// Lists pending restriction appeals. Tapping one shows the
// user's full appeal text and lets the admin approve (lifts the
// restriction automatically) or deny (requires an explanation,
// which the user will see).
// ============================================================

class AdminAppealsScreen extends StatefulWidget {
  const AdminAppealsScreen({super.key});

  @override
  State<AdminAppealsScreen> createState() => _AdminAppealsScreenState();
}

class _AdminAppealsScreenState extends State<AdminAppealsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _appeals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAppeals();
  }

  Future<void> _loadAppeals() async {
    setState(() => _isLoading = true);
    try {
      final result = await _client.rpc('get_pending_appeals');
      if (mounted) {
        setState(() {
          _appeals = List<Map<String, dynamic>>.from(result);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('loadAppeals error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openAppeal(Map<String, dynamic> appeal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AppealReviewSheet(
        appeal: appeal,
        onResolved: () {
          Navigator.pop(context);
          _loadAppeals();
        },
      ),
    );
  }

  String _timeAgo(String dateStr) {
    final date = DateTime.parse(dateStr);
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Restriction Appeals',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadAppeals,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _appeals.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
                        SizedBox(height: 16),
                        Text('No pending appeals', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAppeals,
                  color: Colors.white,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _appeals.length,
                    itemBuilder: (context, index) {
                      final appeal = _appeals[index];
                      final displayName = appeal['display_name'] ?? appeal['username'] ?? 'Unknown';
                      final username = appeal['username'] ?? '';
                      final appealText = appeal['appeal_text'] as String? ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.2)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(14),
                          title: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('@$username', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                const SizedBox(height: 6),
                                Text(
                                  appealText,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(_timeAgo(appeal['created_at']), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                          ),
                          onTap: () => _openAppeal(appeal),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ============================================================
// APPEAL REVIEW SHEET
// ============================================================
class _AppealReviewSheet extends StatefulWidget {
  final Map<String, dynamic> appeal;
  final VoidCallback onResolved;

  const _AppealReviewSheet({required this.appeal, required this.onResolved});

  @override
  State<_AppealReviewSheet> createState() => _AppealReviewSheetState();
}

class _AppealReviewSheetState extends State<_AppealReviewSheet> {
  final _client = Supabase.instance.client;
  final _responseController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  Future<void> _resolve(bool approve) async {
    if (!approve && _responseController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please explain why you\'re denying this appeal'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _client.rpc('resolve_restriction_appeal', params: {
        'p_appeal_id': widget.appeal['id'],
        'p_approve': approve,
        'p_admin_response': _responseController.text.trim().isEmpty ? null : _responseController.text.trim(),
      });
      widget.onResolved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to resolve appeal'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.appeal['display_name'] ?? widget.appeal['username'] ?? 'Unknown';
    final appealText = widget.appeal['appeal_text'] as String? ?? '';

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('APPEAL', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
              child: Text(appealText, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your response (required if denying — the user will see this)',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _responseController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Explain your decision...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => _resolve(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Deny'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : () => _resolve(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}