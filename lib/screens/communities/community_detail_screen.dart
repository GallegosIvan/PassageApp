import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/community_service.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/restricted_dialog.dart';
import 'community_settings_screen.dart';

class CommunityDetailScreen extends StatefulWidget {
  final Map<String, dynamic> community;

  const CommunityDetailScreen({super.key, required this.community});

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  final _communityService = CommunityService();
  final _client = Supabase.instance.client;
  final _postController = TextEditingController();
  final _verseRefController = TextEditingController();
  final _searchController = TextEditingController();
  final _chapterController = TextEditingController();

  bool _showSearch = false;
  List<Map<String, dynamic>> _filteredPosts = [];
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _announcements = [];
  Set<String> _blockedUserIds = {};
  bool _isAdmin = false;
  bool _isLoading = true;
  bool _isPosting = false;
  bool _showPostInput = false;
  bool _isCreator = false;
  int _memberCount = 0;
  String? _currentUserId;
  RealtimeChannel? _channel;

  bool get _isChurchCommunity => widget.community['church_id'] != null;
  bool get _isBibleStudy => widget.community['is_bible_study'] == true;
  bool get _chapterRequired => !_isChurchCommunity || _isBibleStudy;

  @override
  void initState() {
    super.initState();
    _currentUserId = _client.auth.currentUser?.id;
    _loadBlockedUsers();
    _loadPosts();
    _loadAnnouncements();
    _checkIfAdmin();
    _checkIfCreator();
    _loadMemberCount();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _postController.dispose();
    _verseRefController.dispose();
    _searchController.dispose();
    _chapterController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadBlockedUsers() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await _client
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', userId);
      final ids = (response as List).map((r) => r['blocked_id'] as String).toSet();
      if (mounted) setState(() => _blockedUserIds = ids);
    } catch (e) {
      print('loadBlockedUsers error: $e');
    }
  }

  Future<void> _blockUser(String targetUserId, String displayName) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client.from('blocked_users').insert({
        'blocker_id': userId,
        'blocked_id': targetUserId,
      });
      if (mounted) {
        setState(() => _blockedUserIds.add(targetUserId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayName has been blocked'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to block user'),
              backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _unblockUser(String targetUserId, String displayName) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client.from('blocked_users').delete()
          .eq('blocker_id', userId).eq('blocked_id', targetUserId);
      if (mounted) {
        setState(() => _blockedUserIds.remove(targetUserId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayName has been unblocked'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      print('unblockUser error: $e');
    }
  }

  void _showPostOptions(Map<String, dynamic> post) {
    final postUserId = post['user_id'] as String?;
    final user = post['users'];
    final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown';
    final isOwner = postUserId == _currentUserId;
    final isBlocked = postUserId != null && _blockedUserIds.contains(postUserId);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete post', style: TextStyle(color: Colors.red)),
                onTap: () { Navigator.pop(context); _confirmDeletePost(post['id']); },
              ),
            if (!isOwner) ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.white),
                title: const Text('Report post', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  ReportSheet.show(context, type: ReportType.post, targetId: post['id'], targetUserId: postUserId);
                },
              ),
              if (postUserId != null)
                ListTile(
                  leading: Icon(isBlocked ? Icons.person_add_outlined : Icons.block_outlined,
                      color: isBlocked ? Colors.white : Colors.orange),
                  title: Text(isBlocked ? 'Unblock $displayName' : 'Block $displayName',
                      style: TextStyle(color: isBlocked ? Colors.white : Colors.orange)),
                  onTap: () {
                    Navigator.pop(context);
                    if (isBlocked) _unblockUser(postUserId, displayName);
                    else _confirmBlockUser(postUserId, displayName);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmDeletePost(String postId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete post?', style: TextStyle(color: Colors.white)),
        content: const Text('This cannot be undone.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () { Navigator.pop(context); _deletePost(postId); },
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _confirmBlockUser(String targetUserId, String displayName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Block $displayName?', style: const TextStyle(color: Colors.white)),
        content: Text('You will no longer see posts or replies from $displayName. They will not be notified.',
            style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () { Navigator.pop(context); _blockUser(targetUserId, displayName); },
              child: const Text('Block', style: TextStyle(color: Colors.orange))),
        ],
      ),
    );
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    try {
      final response = await _client
          .from('posts')
          .select('id, content, verse_ref, chapter, created_at, user_id')
          .eq('community_id', widget.community['id'])
          .order('created_at', ascending: false);

      final posts = List<Map<String, dynamic>>.from(response);
      await _hydrateUsers(posts, 'user_id');

      if (mounted) {
        setState(() {
          _posts = posts;
          _filteredPosts = _posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('loadPosts error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load posts. Pull down to retry.'),
              backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _hydrateUsers(List<Map<String, dynamic>> rows, String idField) async {
    final ids = rows.map((r) => r[idField] as String?).whereType<String>().toSet().toList();
    if (ids.isEmpty) return;
    try {
      final profiles = await _client.rpc('get_public_profiles', params: {'p_user_ids': ids});
      final profileMap = {for (final p in List<Map<String, dynamic>>.from(profiles)) p['id'] as String: p};
      for (final row in rows) {
        final id = row[idField] as String?;
        row['users'] = id != null ? profileMap[id] : null;
      }
    } catch (e) {
      print('_hydrateUsers error: $e');
    }
  }

  Future<void> _loadMemberCount() async {
    final count = await _communityService.getMemberCount(widget.community['id']);
    if (mounted) setState(() => _memberCount = count);
  }

  void _filterPosts(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredPosts = _posts;
      } else {
        _filteredPosts = _posts.where((post) {
          final content = (post['content'] as String? ?? '').toLowerCase();
          final verseRef = (post['verse_ref'] as String? ?? '').toLowerCase();
          final user = post['users'];
          final displayName = (user?['display_name'] as String? ?? '').toLowerCase();
          final username = (user?['username'] as String? ?? '').toLowerCase();
          final q = query.toLowerCase();
          return content.contains(q) || verseRef.contains(q) || displayName.contains(q) || username.contains(q);
        }).toList();
      }
    });
  }

  void _subscribeToRealtime() {
    _channel = _client
        .channel('community_${widget.community['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'community_id',
            value: widget.community['id'],
          ),
          callback: (payload) => _loadPosts(),
        )
        .subscribe();
  }

  void _checkIfCreator() {
    final userId = _client.auth.currentUser?.id;
    if (mounted) setState(() => _isCreator = widget.community['created_by'] == userId);
  }

  Future<void> _submitPost() async {
    if (_postController.text.trim().isEmpty) return;

    int? chapter;
    if (_chapterRequired) {
      if (_chapterController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a chapter'),
              backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
        return;
      }
      chapter = int.tryParse(_chapterController.text.trim());
      if (chapter == null || chapter <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid chapter number'),
              backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
        return;
      }
    }

    setState(() => _isPosting = true);
    try {
      await _client.from('posts').insert({
        'community_id': widget.community['id'],
        'user_id': _currentUserId,
        'content': _postController.text.trim(),
        'verse_ref': _verseRefController.text.trim().isEmpty ? null : _verseRefController.text.trim(),
        'chapter': chapter,
      });
      _postController.clear();
      _verseRefController.clear();
      _chapterController.clear();
      setState(() => _showPostInput = false);
      await _loadPosts();
    } catch (e) {
      if (mounted) {
        final isRestricted = e.toString().contains('user_restricted');
        if (isRestricted) {
          await RestrictedDialog.show(context);
        } else if (e.toString().contains('chapter_required')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A chapter reference is required for this community'),
                backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to post. Please try again.'),
                backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      await _client.from('posts').delete().eq('id', postId);
      await _loadPosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete post.'),
              backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
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

  String _buildSubtitle() {
    final book = widget.community['book'];
    if (book != null) return '$book • $_memberCount members';
    return '$_memberCount members';
  }

  // ── SUB-GROUP QR SHEET ─────────────────────────────────────
  // Shown to admins of private church sub-groups so they can
  // invite people by showing them a QR code to scan. Same pattern
  // as _showQrSheet in ChurchDetailScreen.
  Future<void> _showSubGroupQrSheet() async {
    final token = await _communityService.getSubGroupQrToken(widget.community['id']);
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load QR code'),
              backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Group QR code',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Show this to invite people to this private group.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: token, version: QrVersions.auto, size: 220, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Regenerate QR code?', style: TextStyle(color: Colors.white)),
                    content: const Text('The old code stops working immediately. Anyone who scans it after this will not be able to join.',
                        style: TextStyle(color: Colors.grey)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
                      TextButton(onPressed: () => Navigator.pop(context, true),
                          child: const Text('Regenerate', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await _communityService.regenerateSubGroupQrToken(widget.community['id']);
                    if (mounted) {
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('QR code regenerated'), behavior: SnackBarBehavior.floating),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to regenerate'),
                            backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.refresh, color: Colors.grey, size: 18),
              label: const Text('Regenerate code', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkIfAdmin() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await _client
          .from('community_members')
          .select('role')
          .eq('community_id', widget.community['id'])
          .eq('user_id', userId)
          .single();
      if (mounted) {
        setState(() => _isAdmin = response['role'] == 'admin' || response['role'] == 'co-admin');
      }
    } catch (e) {
      print('checkIfAdmin error: $e');
    }
  }

  Future<void> _loadAnnouncements() async {
    final announcements = await _communityService.getCommunityAnnouncements(widget.community['id']);
    if (mounted) setState(() => _announcements = announcements);
  }

  void _showAnnouncementSheet() {
    final controller = TextEditingController();
    bool isPosting = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Post announcement',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Visible to all community members on their home screen',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: controller, maxLines: 6, maxLength: 500, autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Share an update, event, or announcement...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true, fillColor: Colors.black,
                counterStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white, width: 1)),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: isPosting ? null : () async {
                  setSheetState(() => isPosting = true);
                  try {
                    await _communityService.createAnnouncement(
                      communityId: widget.community['id'],
                      content: controller.text.trim(),
                    );
                    if (mounted) {
                      Navigator.pop(ctx);
                      _loadAnnouncements();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Announcement posted!'), behavior: SnackBarBehavior.floating),
                      );
                    }
                  } catch (e) {
                    setSheetState(() => isPosting = false);
                    if (mounted) {
                      final isRestricted = e.toString().contains('user_restricted');
                      if (isRestricted) {
                        Navigator.pop(ctx);
                        await RestrictedDialog.show(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to post announcement'),
                              backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
                        );
                      }
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isPosting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('Post', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.community['name'] ?? '',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          Text(_buildSubtitle(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.campaign_outlined, color: Colors.white),
              tooltip: 'Post announcement',
              onPressed: _showAnnouncementSheet,
            ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () async {
                final updated = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => CommunitySettingsScreen(
                    community: widget.community, isCreator: _isCreator)),
                );
                if (updated == true && mounted) Navigator.of(context).pop(true);
              },
            ),
          // QR button — only for private church sub-groups, admin only
          if (_isAdmin && widget.community['is_private'] == true && widget.community['church_id'] != null)
            IconButton(
              icon: const Icon(Icons.qr_code, color: Colors.white),
              tooltip: 'Show QR code',
              onPressed: _showSubGroupQrSheet,
            ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () => setState(() => _showPostInput = !_showPostInput),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              setState(() => _showSearch = !_showSearch);
              if (!_showSearch) { _searchController.clear(); _filteredPosts = _posts; }
            },
          ),
        ],
      ),
      body: Column(children: [
        if (_showPostInput)
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1A1A1A),
            child: Column(children: [
              if (_chapterRequired) ...[
                Row(children: [
                  Expanded(flex: 2, child: TextField(
                    controller: _verseRefController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Verse ref (optional)', hintStyle: const TextStyle(color: Colors.grey),
                      filled: true, fillColor: Colors.black,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(flex: 1, child: TextField(
                    controller: _chapterController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ch. *', hintStyle: const TextStyle(color: Colors.grey),
                      filled: true, fillColor: Colors.black,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  )),
                ]),
                const SizedBox(height: 10),
              ] else
                TextField(
                  controller: _verseRefController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Reference (optional)', hintStyle: const TextStyle(color: Colors.grey),
                    filled: true, fillColor: Colors.black,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              if (!_chapterRequired) const SizedBox(height: 10),
              TextField(
                controller: _postController,
                style: const TextStyle(color: Colors.white),
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Share your interpretation... *', hintStyle: const TextStyle(color: Colors.grey),
                  filled: true, fillColor: Colors.black,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextButton(
                  onPressed: () => setState(() => _showPostInput = false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                )),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton(
                  onPressed: _isPosting ? null : _submitPost,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isPosting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text('Post'),
                )),
              ]),
            ]),
          ),

        if (_announcements.isNotEmpty)
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.campaign_outlined, color: Colors.grey, size: 16),
                SizedBox(width: 6),
                Text('Announcements', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              ]),
              const SizedBox(height: 8),
              ..._announcements.map((a) {
                final user = a['users'];
                final name = user?['display_name'] ?? user?['username'] ?? 'Admin';
                final timeAgo = _timeAgo(a['created_at']);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.campaign_outlined, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      const Spacer(),
                      Text(timeAgo, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      if (_isAdmin) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              title: const Text('Delete announcement?', style: TextStyle(color: Colors.white)),
                              content: const Text('This cannot be undone.', style: TextStyle(color: Colors.grey)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
                                TextButton(
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    await _communityService.deleteAnnouncement(a['id']);
                                    _loadAnnouncements();
                                  },
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.grey, size: 16),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 8),
                    Text(a['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                  ]),
                );
              }),
              const SizedBox(height: 4),
              const Divider(color: Color(0xFF2A2A2A)),
            ]),
          ),

        if (_showSearch)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            color: Colors.black,
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onChanged: _filterPosts,
              decoration: InputDecoration(
                hintText: 'Search posts...', hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () {
                    setState(() { _showSearch = false; _filteredPosts = _posts; });
                    _searchController.clear();
                  },
                ),
                filled: true, fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _filteredPosts.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 48),
                      const SizedBox(height: 16),
                      Text(_showSearch ? 'No posts match your search' : 'No posts yet',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (!_showSearch)
                        const Text('Be the first to share an interpretation',
                            style: TextStyle(color: Colors.grey, fontSize: 14)),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _loadPosts,
                      color: Colors.white,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredPosts.length,
                        itemBuilder: (context, index) {
                          final post = _filteredPosts[index];
                          final postUserId = post['user_id'] as String?;
                          if (postUserId != null && _blockedUserIds.contains(postUserId)) {
                            return const SizedBox.shrink();
                          }
                          final user = post['users'];
                          final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown';
                          final chapter = post['chapter'];
                          final book = widget.community['book'];

                          return GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => _ReplyScreen(
                                post: post, communityId: widget.community['id'], blockedUserIds: _blockedUserIds)),
                            ),
                            onLongPress: () => _showPostOptions(post),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                  if (chapter != null && book != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text('$book $chapter', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                    ),
                                  ],
                                  const Spacer(),
                                  Text(_timeAgo(post['created_at']), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  const SizedBox(width: 4),
                                  GestureDetector(onTap: () => _showPostOptions(post),
                                      child: const Icon(Icons.more_horiz, color: Colors.grey, size: 18)),
                                ]),
                                if (post['verse_ref'] != null) ...[
                                  const SizedBox(height: 6),
                                  Text(post['verse_ref'], style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
                                ],
                                const SizedBox(height: 8),
                                Text(post['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5)),
                                const SizedBox(height: 10),
                                const Row(children: [
                                  Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 14),
                                  SizedBox(width: 4),
                                  Text('Reply', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                ]),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ============================================================
// REPLY SCREEN
// ============================================================
class _ReplyScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final String communityId;
  final Set<String> blockedUserIds;

  const _ReplyScreen({required this.post, required this.communityId, required this.blockedUserIds});

  @override
  State<_ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<_ReplyScreen> {
  final _client = Supabase.instance.client;
  final _replyController = TextEditingController();
  List<Map<String, dynamic>> _replies = [];
  late Set<String> _blockedUserIds;
  bool _isLoading = true;
  bool _isPosting = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = _client.auth.currentUser?.id;
    _blockedUserIds = Set.from(widget.blockedUserIds);
    _loadReplies();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadReplies() async {
    setState(() => _isLoading = true);
    try {
      final response = await _client
          .from('replies')
          .select('id, content, created_at, user_id')
          .eq('post_id', widget.post['id'])
          .order('created_at', ascending: true);

      final replies = List<Map<String, dynamic>>.from(response);
      await _hydrateUsers(replies, 'user_id');

      if (mounted) setState(() { _replies = replies; _isLoading = false; });
    } catch (e) {
      print('loadReplies error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _hydrateUsers(List<Map<String, dynamic>> rows, String idField) async {
    final ids = rows.map((r) => r[idField] as String?).whereType<String>().toSet().toList();
    if (ids.isEmpty) return;
    try {
      final profiles = await _client.rpc('get_public_profiles', params: {'p_user_ids': ids});
      final profileMap = {for (final p in List<Map<String, dynamic>>.from(profiles)) p['id'] as String: p};
      for (final row in rows) {
        final id = row[idField] as String?;
        row['users'] = id != null ? profileMap[id] : null;
      }
    } catch (e) {
      print('_hydrateUsers error: $e');
    }
  }

  Future<void> _submitReply() async {
    if (_replyController.text.trim().isEmpty) return;
    setState(() => _isPosting = true);
    try {
      await _client.from('replies').insert({
        'post_id': widget.post['id'],
        'user_id': _currentUserId,
        'content': _replyController.text.trim(),
      });
      _replyController.clear();
      await _loadReplies();
    } catch (e) {
      if (mounted) {
        final isRestricted = e.toString().contains('user_restricted');
        if (isRestricted) {
          await RestrictedDialog.show(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to reply. Please try again.'),
                backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _deleteReply(String replyId) async {
    try {
      await _client.from('replies').delete().eq('id', replyId);
      await _loadReplies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete reply.'),
              backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showReplyOptions(Map<String, dynamic> reply) {
    final replyUserId = reply['user_id'] as String?;
    final user = reply['users'];
    final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown';
    final isOwner = replyUserId == _currentUserId;
    final isBlocked = replyUserId != null && _blockedUserIds.contains(replyUserId);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          if (isOwner)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete reply', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); _deleteReply(reply['id']); },
            ),
          if (!isOwner) ...[
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.white),
              title: const Text('Report reply', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                ReportSheet.show(context, type: ReportType.reply, targetId: reply['id'], targetUserId: replyUserId);
              },
            ),
            if (replyUserId != null)
              ListTile(
                leading: Icon(isBlocked ? Icons.person_add_outlined : Icons.block_outlined,
                    color: isBlocked ? Colors.white : Colors.orange),
                title: Text(isBlocked ? 'Unblock $displayName' : 'Block $displayName',
                    style: TextStyle(color: isBlocked ? Colors.white : Colors.orange)),
                onTap: () async {
                  Navigator.pop(context);
                  final userId = _client.auth.currentUser?.id;
                  if (userId == null) return;
                  if (isBlocked) {
                    await _client.from('blocked_users').delete()
                        .eq('blocker_id', userId).eq('blocked_id', replyUserId);
                    if (mounted) setState(() => _blockedUserIds.remove(replyUserId));
                  } else {
                    await _client.from('blocked_users').insert({'blocker_id': userId, 'blocked_id': replyUserId});
                    if (mounted) setState(() => _blockedUserIds.add(replyUserId));
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isBlocked ? '$displayName unblocked' : '$displayName blocked'),
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
              ),
          ],
        ]),
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
    final user = widget.post['users'];
    final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Thread', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            if (widget.post['verse_ref'] != null) ...[
              const SizedBox(height: 4),
              Text(widget.post['verse_ref'], style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 8),
            Text(widget.post['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5)),
          ]),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _replies.isEmpty
                  ? const Center(child: Text('No replies yet', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _replies.length,
                      itemBuilder: (context, index) {
                        final reply = _replies[index];
                        final replyUserId = reply['user_id'] as String?;
                        if (replyUserId != null && _blockedUserIds.contains(replyUserId)) {
                          return const SizedBox.shrink();
                        }
                        final replyUser = reply['users'];
                        final replyName = replyUser?['display_name'] ?? replyUser?['username'] ?? 'Unknown';

                        return GestureDetector(
                          onLongPress: () => _showReplyOptions(reply),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(replyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                const Spacer(),
                                Text(_timeAgo(reply['created_at']), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                const SizedBox(width: 4),
                                GestureDetector(onTap: () => _showReplyOptions(reply),
                                    child: const Icon(Icons.more_horiz, color: Colors.grey, size: 16)),
                              ]),
                              const SizedBox(height: 6),
                              Text(reply['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
        Container(
          padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 12),
          color: const Color(0xFF1A1A1A),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _replyController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Write a reply...', hintStyle: const TextStyle(color: Colors.grey),
                filled: true, fillColor: Colors.black,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            )),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _isPosting ? null : _submitReply,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: _isPosting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Icon(Icons.send, color: Colors.black, size: 18),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}