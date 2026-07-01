import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;

  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _resolved = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    try {
      final response = await _client
          .from('reports')
          .select('*')
          .order('created_at', ascending: false);

      final all = List<Map<String, dynamic>>.from(response);

      // Enrich each report with its content
      final enriched = await Future.wait(all.map((r) => _enrichReport(r)));

      if (mounted) {
        setState(() {
          _pending = enriched
              .where((r) => r['status'] == 'pending' || r['status'] == null)
              .toList();
          _resolved = enriched
              .where((r) => r['status'] != 'pending' && r['status'] != null)
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('loadReports error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _enrichReport(Map<String, dynamic> report) async {
    final type = report['report_type'] as String? ?? '';
    final targetId = report['target_id'] as String? ?? '';
    final targetUserId = report['target_user_id'] as String?;
    final enriched = Map<String, dynamic>.from(report);

    try {
      if (type == 'post') {
        final post = await _client
            .from('posts')
            .select('content, verse_ref, user_id, users(display_name, username)')
            .eq('id', targetId)
            .maybeSingle();
        enriched['content_data'] = post;
        if (post != null && post['user_id'] != null) {
          enriched['strike_info'] = await _getStrikeInfo(post['user_id']);
        }
      } else if (type == 'reply') {
        final reply = await _client
            .from('replies')
            .select('content, user_id, users(display_name, username)')
            .eq('id', targetId)
            .maybeSingle();
        enriched['content_data'] = reply;
        if (reply != null && reply['user_id'] != null) {
          enriched['strike_info'] = await _getStrikeInfo(reply['user_id']);
        }
      } else if (type == 'church_message') {
        final message = await _client
            .from('church_messages')
            .select('content, user_id, community_id, users(display_name, username)')
            .eq('id', targetId)
            .maybeSingle();
        enriched['content_data'] = message;
        if (message != null && message['user_id'] != null) {
          enriched['strike_info'] = await _getStrikeInfo(message['user_id']);
        }
      } else if (type == 'user' && targetUserId != null) {
        // Fetch user info via the admin-gated RPC instead of a
        // direct .from('users') query — this previously relied
        // entirely on the (overly permissive) users RLS policy
        // plus client-side UI gating. Now it's enforced server-side
        // regardless of who calls it.
        final userResponse = await _client.rpc('get_user_display_info', params: {'p_user_id': targetUserId});
        final user = userResponse != null ? Map<String, dynamic>.from(userResponse) : null;

        final posts = await _client
            .from('posts')
            .select('content, verse_ref, created_at')
            .eq('user_id', targetUserId)
            .order('created_at', ascending: false)
            .limit(5);
        final replies = await _client
            .from('replies')
            .select('content, created_at')
            .eq('user_id', targetUserId)
            .order('created_at', ascending: false)
            .limit(5);
        final messages = await _client
            .from('church_messages')
            .select('content, created_at')
            .eq('user_id', targetUserId)
            .order('created_at', ascending: false)
            .limit(5);
        enriched['content_data'] = {
          'user': user,
          'posts': posts,
          'replies': replies,
          'messages': messages,
        };
        enriched['strike_info'] = await _getStrikeInfo(targetUserId);
      }
    } catch (e) {
      print('enrichReport error: $e');
    }

    return enriched;
  }

  // ── GET STRIKE INFO FOR A USER ─────────────────────────────
  // Routes through the admin-gated get_user_strike_info RPC
  // instead of a direct .from('users') query. The previous
  // version relied entirely on RLS (qual=true at the time) plus
  // this screen being hidden behind is_admin() client-side —
  // meaning any authenticated user could have called the same
  // query directly against Supabase and read another user's
  // strikes/is_restricted. The RPC checks is_admin() server-side
  // before returning anything, so this can no longer be bypassed.
  Future<Map<String, dynamic>> _getStrikeInfo(String userId) async {
    try {
      final response = await _client.rpc('get_user_strike_info', params: {'p_user_id': userId});
      if (response == null) return {'strikes': 0, 'is_restricted': false};
      final info = Map<String, dynamic>.from(response);
      return {
        'strikes': info['strikes'] ?? 0,
        'is_restricted': info['is_restricted'] ?? false,
      };
    } catch (e) {
      print('getStrikeInfo error: $e');
      return {'strikes': 0, 'is_restricted': false};
    }
  }

  Future<void> _resolveReport(Map<String, dynamic> report) async {
    final type = report['report_type'] as String? ?? '';
    final targetId = report['target_id'] as String? ?? '';
    final targetUserId = report['target_user_id'] as String?;

    final options = <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context, 'dismiss'),
        child: const Text('Dismiss report', style: TextStyle(color: Colors.grey)),
      ),
    ];

    if (type == 'post') {
      options.add(TextButton(
        onPressed: () => Navigator.pop(context, 'delete_post'),
        child: const Text('Delete post', style: TextStyle(color: Colors.red)),
      ));
      options.add(TextButton(
        onPressed: () => Navigator.pop(context, 'strike_and_delete_post'),
        child: const Text('Strike user + delete post', style: TextStyle(color: Colors.deepOrange)),
      ));
    } else if (type == 'reply') {
      options.add(TextButton(
        onPressed: () => Navigator.pop(context, 'delete_reply'),
        child: const Text('Delete reply', style: TextStyle(color: Colors.red)),
      ));
      options.add(TextButton(
        onPressed: () => Navigator.pop(context, 'strike_and_delete_reply'),
        child: const Text('Strike user + delete reply', style: TextStyle(color: Colors.deepOrange)),
      ));
    } else if (type == 'church_message') {
      options.add(TextButton(
        onPressed: () => Navigator.pop(context, 'delete_message'),
        child: const Text('Delete message', style: TextStyle(color: Colors.red)),
      ));
      options.add(TextButton(
        onPressed: () => Navigator.pop(context, 'strike_and_delete_message'),
        child: const Text('Strike user + delete message', style: TextStyle(color: Colors.deepOrange)),
      ));
    } else if (type == 'user') {
      options.add(TextButton(
        onPressed: () => Navigator.pop(context, 'delete_user_content'),
        child: const Text('Delete all user content', style: TextStyle(color: Colors.red)),
      ));
      options.add(TextButton(
        onPressed: () => Navigator.pop(context, 'strike_and_delete_user_content'),
        child: const Text('Strike user + delete all content', style: TextStyle(color: Colors.deepOrange)),
      ));
    }

    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Resolve report', style: TextStyle(color: Colors.white)),
        content: const Text('Choose an action:', style: TextStyle(color: Colors.grey)),
        actions: options,
      ),
    );

    if (action == null) return;

    try {
      if (action == 'delete_post') {
        await _client.from('posts').delete().eq('id', targetId);
      } else if (action == 'delete_reply') {
        await _client.from('replies').delete().eq('id', targetId);
      } else if (action == 'delete_message') {
        await _client.from('church_messages').delete().eq('id', targetId);
      } else if (action == 'delete_user_content' && targetUserId != null) {
        await _client.from('posts').delete().eq('user_id', targetUserId);
        await _client.from('replies').delete().eq('user_id', targetUserId);
        await _client.from('church_messages').delete().eq('user_id', targetUserId);
      } else if (action == 'strike_and_delete_post') {
        await _client.from('posts').delete().eq('id', targetId);
        if (targetUserId != null) await _issueStrike(targetUserId);
      } else if (action == 'strike_and_delete_reply') {
        await _client.from('replies').delete().eq('id', targetId);
        if (targetUserId != null) await _issueStrike(targetUserId);
      } else if (action == 'strike_and_delete_message') {
        await _client.from('church_messages').delete().eq('id', targetId);
        if (targetUserId != null) await _issueStrike(targetUserId);
      } else if (action == 'strike_and_delete_user_content' && targetUserId != null) {
        await _client.from('posts').delete().eq('user_id', targetUserId);
        await _client.from('replies').delete().eq('user_id', targetUserId);
        await _client.from('church_messages').delete().eq('user_id', targetUserId);
        await _issueStrike(targetUserId);
      }

      await _client
          .from('reports')
          .update({'status': 'resolved'})
          .eq('id', report['id']);

      if (mounted) {
        final didStrike = action.toString().startsWith('strike');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'dismiss'
                ? 'Report dismissed'
                : didStrike
                    ? 'Strike issued and content removed'
                    : 'Content removed and report resolved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadReports();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to resolve report'),
              backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  // ── ISSUE STRIKE TO A USER ──────────────────────────────────
  Future<void> _issueStrike(String userId) async {
    try {
      final result = await _client.rpc('issue_strike', params: {'p_user_id': userId});
      final info = Map<String, dynamic>.from(result);
      if (mounted && info['is_restricted'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User has reached 3 strikes and is now permanently restricted from chat.'),
            backgroundColor: Colors.deepOrange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('issueStrike error: $e');
    }
  }

  String _timeAgo(String dateStr) {
    final date = DateTime.parse(dateStr);
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildReportCard(Map<String, dynamic> report, bool isPending) {
    final type = report['report_type'] as String? ?? '';
    final reason = report['reason'] as String? ?? '';
    final createdAt = report['created_at'] as String? ?? '';
    final contentData = report['content_data'];
    final strikeInfo = report['strike_info'] as Map<String, dynamic>?;
    final strikeCount = strikeInfo?['strikes'] as int? ?? 0;
    final isRestricted = strikeInfo?['is_restricted'] as bool? ?? false;

    Color typeColor;
    IconData typeIcon;
    switch (type) {
      case 'post':
        typeColor = Colors.blue;
        typeIcon = Icons.article_outlined;
        break;
      case 'reply':
        typeColor = Colors.purple;
        typeIcon = Icons.reply_outlined;
        break;
      case 'church_message':
        typeColor = Colors.teal;
        typeIcon = Icons.chat_bubble_outline;
        break;
      case 'user':
        typeColor = Colors.orange;
        typeIcon = Icons.person_outline;
        break;
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.flag_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: isPending
            ? Border.all(color: Colors.orange.withOpacity(0.3))
            : Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(typeIcon, color: typeColor, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    type == 'church_message' ? 'CHAT MESSAGE' : type.toUpperCase(),
                    style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              if (!isPending)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('RESOLVED',
                      style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              if (strikeInfo != null && strikeCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isRestricted
                        ? Colors.red.withOpacity(0.15)
                        : Colors.deepOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.warning_amber_rounded,
                        color: isRestricted ? Colors.red : Colors.deepOrange, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      isRestricted ? 'RESTRICTED' : '$strikeCount/3 STRIKES',
                      style: TextStyle(
                        color: isRestricted ? Colors.red : Colors.deepOrange,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
              ],
              const Spacer(),
              Text(_timeAgo(createdAt), style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ]),
          ),

          // ── REASON ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('REASON', style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 0.8)),
              const SizedBox(height: 3),
              Text(reason, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ]),
          ),

          // ── REPORTED CONTENT ──────────────────────────
          if (contentData != null) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: _buildContentPreview(type, contentData),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: const Text('Content no longer exists (already deleted)',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
            ),
          ],

          // ── REVIEW BUTTON ─────────────────────────────
          if (isPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  onPressed: () => _resolveReport(report),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Review & Resolve', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            )
          else
            const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildContentPreview(String type, dynamic contentData) {
    if (type == 'post' || type == 'reply' || type == 'church_message') {
      if (contentData == null) {
        return const Text('Content deleted', style: TextStyle(color: Colors.grey, fontSize: 13));
      }
      final user = contentData['users'];
      final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown';
      final content = contentData['content'] as String? ?? '';
      final verseRef = contentData['verse_ref'] as String?;

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.person_outline, color: Colors.grey, size: 13),
          const SizedBox(width: 4),
          Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        if (verseRef != null) ...[
          const SizedBox(height: 4),
          Text(verseRef, style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 6),
        Text(content, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
      ]);
    }

    if (type == 'user') {
      final user = contentData['user'];
      final posts = contentData['posts'] as List? ?? [];
      final replies = contentData['replies'] as List? ?? [];
      final messages = contentData['messages'] as List? ?? [];
      final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown';

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.person_outline, color: Colors.orange, size: 13),
          const SizedBox(width: 4),
          Text(displayName,
              style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        if (posts.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('RECENT POSTS', style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          ...posts.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(p['content'] ?? '',
                style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2,
                overflow: TextOverflow.ellipsis),
          )),
        ],
        if (replies.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('RECENT REPLIES', style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          ...replies.map((r) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(r['content'] ?? '',
                style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2,
                overflow: TextOverflow.ellipsis),
          )),
        ],
        if (messages.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('RECENT CHAT MESSAGES', style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          ...messages.map((m) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(m['content'] ?? '',
                style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2,
                overflow: TextOverflow.ellipsis),
          )),
        ],
        if (posts.isEmpty && replies.isEmpty && messages.isEmpty)
          const Text('No posts, replies, or messages found',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
      ]);
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Reports',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadReports,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Pending (${_pending.length})'),
            Tab(text: 'Resolved (${_resolved.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : TabBarView(
              controller: _tabController,
              children: [
                _pending.isEmpty
                    ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
                        SizedBox(height: 16),
                        Text('No pending reports', style: TextStyle(color: Colors.grey)),
                      ]))
                    : RefreshIndicator(
                        onRefresh: _loadReports,
                        color: Colors.white,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _pending.length,
                          itemBuilder: (_, i) => _buildReportCard(_pending[i], true),
                        ),
                      ),
                _resolved.isEmpty
                    ? const Center(child: Text('No resolved reports',
                        style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _loadReports,
                        color: Colors.white,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _resolved.length,
                          itemBuilder: (_, i) => _buildReportCard(_resolved[i], false),
                        ),
                      ),
              ],
            ),
    );
  }
}