import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// ADMIN RESTRICTED USERS SCREEN
// Lists every permanently restricted user. Tapping one shows the
// full report history that led to their strikes, and gives the
// admin a manual override to lift the restriction entirely —
// a deliberate escape hatch for cases where 3-strike automation
// produced a disproportionate outcome.
// ============================================================

class AdminRestrictedUsersScreen extends StatefulWidget {
  const AdminRestrictedUsersScreen({super.key});

  @override
  State<AdminRestrictedUsersScreen> createState() => _AdminRestrictedUsersScreenState();
}

class _AdminRestrictedUsersScreenState extends State<AdminRestrictedUsersScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _restrictedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRestrictedUsers();
  }

  Future<void> _loadRestrictedUsers() async {
    setState(() => _isLoading = true);
    try {
      final result = await _client.rpc('get_restricted_users');
      if (mounted) {
        setState(() {
          _restrictedUsers = List<Map<String, dynamic>>.from(result);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('loadRestrictedUsers error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openUserHistory(Map<String, dynamic> user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _UserStrikeHistoryScreen(user: user),
      ),
    ).then((_) => _loadRestrictedUsers());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Restricted Users',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadRestrictedUsers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _restrictedUsers.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
                        SizedBox(height: 16),
                        Text('No restricted users', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRestrictedUsers,
                  color: Colors.white,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _restrictedUsers.length,
                    itemBuilder: (context, index) {
                      final user = _restrictedUsers[index];
                      final displayName = user['display_name'] ?? user['username'] ?? 'Unknown';
                      final username = user['username'] ?? '';
                      final strikes = user['strikes'] ?? 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.2)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: const CircleAvatar(
                            backgroundColor: Colors.red,
                            child: Icon(Icons.block, color: Colors.white, size: 18),
                          ),
                          title: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Text('@$username · $strikes strikes', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () => _openUserHistory(user),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ============================================================
// USER STRIKE HISTORY SCREEN
// ============================================================
class _UserStrikeHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const _UserStrikeHistoryScreen({required this.user});

  @override
  State<_UserStrikeHistoryScreen> createState() => _UserStrikeHistoryScreenState();
}

class _UserStrikeHistoryScreenState extends State<_UserStrikeHistoryScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  bool _isLifting = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final result = await _client.rpc('get_user_strike_history', params: {
        'p_user_id': widget.user['id'],
      });
      if (mounted) {
        setState(() {
          _history = List<Map<String, dynamic>>.from(result);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('loadHistory error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmLiftRestriction() async {
    final displayName = widget.user['display_name'] ?? widget.user['username'] ?? 'this user';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Lift restriction?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This resets $displayName\'s strikes to 0 and fully restores their ability to post, reply, and chat. Only do this if you believe the restriction was disproportionate.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lift restriction', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLifting = true);
    try {
      await _client.rpc('lift_restriction', params: {'p_user_id': widget.user['id']});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restriction lifted'), behavior: SnackBarBehavior.floating),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to lift restriction'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
        setState(() => _isLifting = false);
      }
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
    final displayName = widget.user['display_name'] ?? widget.user['username'] ?? 'Unknown';
    final username = widget.user['username'] ?? '';
    final strikes = widget.user['strikes'] ?? 0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@$username', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('$strikes strikes · Permanently restricted',
                          style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _isLifting ? null : _confirmLiftRestriction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.withOpacity(0.15),
                            foregroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Colors.green),
                            ),
                          ),
                          child: _isLifting
                              ? const SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(color: Colors.green, strokeWidth: 2))
                              : const Text('Lift restriction', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('REPORT HISTORY',
                          style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _history.isEmpty
                      ? const Center(child: Text('No report history found', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _history.length,
                          itemBuilder: (context, index) {
                            final report = _history[index];
                            final type = report['report_type'] as String? ?? '';
                            final reason = report['reason'] as String? ?? '';
                            final status = report['status'] as String? ?? 'pending';
                            final createdAt = report['created_at'] as String;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(type.toUpperCase().replaceAll('_', ' '),
                                            style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: status == 'resolved' ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(status.toUpperCase(),
                                            style: TextStyle(color: status == 'resolved' ? Colors.green : Colors.orange, fontSize: 10, fontWeight: FontWeight.w600)),
                                      ),
                                      const Spacer(),
                                      Text(_timeAgo(createdAt), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(reason, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}