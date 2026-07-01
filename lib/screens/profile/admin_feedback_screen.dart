import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// ADMIN FEEDBACK SCREEN
// Shows feedback submitted via the "Not really" path of the
// rate-us pre-prompt. Admin-only, gated by the is_admin() RPC
// the same way the reports screen is.
//
// SECURITY FIX: _loadFeedback previously used `users(username,
// display_name)` relational embedding, which relied on the users
// table's RLS SELECT policy — found to be `qual = true`, meaning
// any authenticated user could read any other user's full row.
// That policy is now tightened to self-only. _loadFeedback now
// fetches only public-safe fields via the get_public_profiles
// RPC instead. This is a defense-in-depth fix on the display
// layer; the actual feedback table's RLS (admin-only SELECT,
// per the original feedback table design) remains the real gate
// on who can read feedback rows at all.
// ============================================================

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _feedback = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  // SECURITY FIX: see file header — switched from the users(...)
  // relational embed to fetching display info via the
  // get_public_profiles RPC.
  Future<void> _loadFeedback() async {
    setState(() => _isLoading = true);
    try {
      final response = await _client
          .from('feedback')
          .select('id, message, created_at, user_id')
          .order('created_at', ascending: false);

      final feedback = List<Map<String, dynamic>>.from(response);
      await _hydrateUsers(feedback, 'user_id');

      if (mounted) {
        setState(() {
          _feedback = feedback;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('loadFeedback error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── HYDRATE USER DISPLAY INFO ──────────────────────────────
  // Fetches ONLY public-safe display fields (username,
  // display_name, avatar_url — never email/strikes/is_restricted)
  // via the get_public_profiles RPC, then attaches a 'users' key
  // to each row in the same shape the old `users(...)` embed
  // produced.
  Future<void> _hydrateUsers(List<Map<String, dynamic>> rows, String idField) async {
    final ids = rows
        .map((r) => r[idField] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
      final profiles = await _client.rpc('get_public_profiles', params: {'p_user_ids': ids});
      final profileMap = {
        for (final p in List<Map<String, dynamic>>.from(profiles)) p['id'] as String: p
      };
      for (final row in rows) {
        final id = row[idField] as String?;
        row['users'] = id != null ? profileMap[id] : null;
      }
    } catch (e) {
      print('_hydrateUsers error: $e');
    }
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
        title: const Text('Feedback',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadFeedback,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _feedback.isEmpty
              ? const Center(
                  child: Text('No feedback yet', style: TextStyle(color: Colors.grey)),
                )
              : RefreshIndicator(
                  onRefresh: _loadFeedback,
                  color: Colors.white,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _feedback.length,
                    itemBuilder: (context, index) {
                      final item = _feedback[index];
                      final user = item['users'];
                      final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown user';
                      final timeAgo = _timeAgo(item['created_at']);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(displayName,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                              const Spacer(),
                              Text(timeAgo, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            ]),
                            const SizedBox(height: 8),
                            Text(item['message'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}