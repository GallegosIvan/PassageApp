import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/community_service.dart';
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

  bool _showSearch = false;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredPosts = [];
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _announcements = [];
  bool _isAdmin = false;
  bool _isLoading = true;
  bool _isPosting = false;
  bool _showPostInput = false;
  bool _isCreator = false;
  int _memberCount = 0;
  String? _currentUserId;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _currentUserId = _client.auth.currentUser?.id;
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
    _channel?.unsubscribe();
    super.dispose();
    _searchController.dispose();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    try {
      // API CALL: Supabase DB — fetch posts with author info
      final response = await _client
          .from('posts')
          .select('''
            id,
            content,
            verse_ref,
            created_at,
            user_id,
            users(display_name, username, avatar_url)
          ''')
          .eq('community_id', widget.community['id'])
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _posts = List<Map<String, dynamic>>.from(response);
          _filteredPosts = _posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('loadPosts error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMemberCount() async {
    final count = await _communityService
        .getMemberCount(widget.community['id']);
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
          return content.contains(q) ||
              verseRef.contains(q) ||
              displayName.contains(q) ||
              username.contains(q);
        }).toList();
      }
    });
  }

  // ── REALTIME ──────────────────────────────────────────────
  // API CALL: Supabase Realtime — listen for new posts
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
    if (mounted) {
      setState(() =>
          _isCreator = widget.community['created_by'] == userId);
    }
  }

  Future<void> _submitPost() async {
    // VALIDATION: post must not be empty
    if (_postController.text.trim().isEmpty) return;

    setState(() => _isPosting = true);

    try {
      // API CALL: Supabase DB — create a new post
      await _client.from('posts').insert({
        'community_id': widget.community['id'],
        'user_id': _currentUserId,
        'content': _postController.text.trim(),
        'verse_ref': _verseRefController.text.trim().isEmpty
            ? null
            : _verseRefController.text.trim(),
      });

      _postController.clear();
      _verseRefController.clear();
      setState(() => _showPostInput = false);
      await _loadPosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to post. Please try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      // API CALL: Supabase DB — delete a post
      await _client.from('posts').delete().eq('id', postId);
      await _loadPosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete post.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.community['name'] ?? '',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            Text(
              '${widget.community['book']} ${widget.community['chapter']} • $_memberCount members',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
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
                  MaterialPageRoute(
                    builder: (_) => CommunitySettingsScreen(
                      community: widget.community,
                      isCreator: _isCreator,
                    ),
                  ),
                );
                if (updated == true && mounted) {
                  Navigator.of(context).pop(true);
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () =>
                setState(() => _showPostInput = !_showPostInput),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              setState(() => _showSearch = !_showSearch);
              if (!_showSearch) {
                _searchController.clear();
                _filteredPosts = _posts;
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── POST INPUT ────────────────────────────────────
          if (_showPostInput)
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1A1A1A),
              child: Column(
                children: [
                  TextField(
                    controller: _verseRefController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Verse reference (e.g. John 3:16)',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.black,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _postController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Share your interpretation...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.black,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => setState(
                              () => _showPostInput = false),
                          child: const Text('Cancel',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isPosting ? null : _submitPost,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _isPosting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.black,
                                      strokeWidth: 2))
                              : const Text('Post'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          if (_announcements.isNotEmpty)
            Container(
              color: const Color(0xFF1A1A1A),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.campaign_outlined,
                          color: Colors.grey, size: 16),
                      SizedBox(width: 6),
                      Text('Announcements',
                          style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._announcements.map((a) {
                    final user = a['users'];
                    final name =
                        user?['display_name'] ?? user?['username'] ?? 'Admin';
                    final createdAt = DateTime.parse(a['created_at']);
                    final timeAgo = _timeAgo(a['created_at']);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.campaign_outlined,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 6),
                              Text(name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const Spacer(),
                              Text(timeAgo,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                              if (_isAdmin) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      backgroundColor:
                                          const Color(0xFF1A1A1A),
                                      title: const Text(
                                          'Delete announcement?',
                                          style:
                                              TextStyle(color: Colors.white)),
                                      content: const Text(
                                          'This cannot be undone.',
                                          style:
                                              TextStyle(color: Colors.grey)),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Cancel',
                                              style: TextStyle(
                                                  color: Colors.grey)),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            Navigator.pop(context);
                                            // API CALL: CommunityService.deleteAnnouncement → Supabase DB
                                            await _communityService
                                                .deleteAnnouncement(a['id']);
                                            _loadAnnouncements();
                                          },
                                          child: const Text('Delete',
                                              style: TextStyle(
                                                  color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(Icons.delete_outline,
                                      color: Colors.grey, size: 16),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            a['content'] ?? '',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.5),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  const Divider(color: Color(0xFF2A2A2A)),
                ],
              ),
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
                  hintText: 'Search posts...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () {
                      setState(() {
                        _showSearch = false;
                        _filteredPosts = _posts;
                      });
                      _searchController.clear();
                    },
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),
          // ── POSTS LIST ────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Colors.white))
                    :_filteredPosts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.chat_bubble_outline,
                                  color: Colors.grey, size: 48),
                              const SizedBox(height: 16),
                              Text(
                                _showSearch
                                    ? 'No posts match your search'
                                    : 'No posts yet',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              if (!_showSearch)
                                const Text(
                                  'Be the first to share an interpretation',
                                  style: TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                            ],
                          ),
                        )
                    : RefreshIndicator(
                        onRefresh: _loadPosts,
                        color: Colors.white,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredPosts.length,
                          itemBuilder: (context, index) {
                            final post = _filteredPosts[index];
                            final user = post['users'];
                            final displayName =
                                user?['display_name'] ??
                                    user?['username'] ??
                                    'Unknown';
                            final isOwner =
                                post['user_id'] == _currentUserId;

                            return GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => _ReplyScreen(
                                    post: post,
                                    communityId:
                                        widget.community['id'],
                                  ),
                                ),
                              ),
                              child: Container(
                                margin:
                                    const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1A),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          displayName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _timeAgo(post['created_at']),
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12),
                                        ),
                                        if (isOwner) ...[
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => showDialog(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                backgroundColor:
                                                    const Color(
                                                        0xFF1A1A1A),
                                                title: const Text(
                                                    'Delete post?',
                                                    style: TextStyle(
                                                        color: Colors
                                                            .white)),
                                                content: const Text(
                                                    'This cannot be undone.',
                                                    style: TextStyle(
                                                        color:
                                                            Colors.grey)),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context),
                                                    child: const Text(
                                                        'Cancel',
                                                        style: TextStyle(
                                                            color: Colors
                                                                .grey)),
                                                  ),
                                                  TextButton(
                                                    onPressed: () {
                                                      Navigator.pop(
                                                          context);
                                                      _deletePost(
                                                          post['id']);
                                                    },
                                                    child: const Text(
                                                        'Delete',
                                                        style: TextStyle(
                                                            color: Colors
                                                                .red)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            child: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.grey,
                                                size: 18),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (post['verse_ref'] != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        post['verse_ref'],
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(
                                      post['content'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Row(
                                      children: [
                                        Icon(Icons.chat_bubble_outline,
                                            color: Colors.grey,
                                            size: 14),
                                        SizedBox(width: 4),
                                        Text('Reply',
                                            style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
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
      setState(() => _isAdmin =
          response['role'] == 'admin' || response['role'] == 'co-admin');
    }
  } catch (e) {
    print('checkIfAdmin error: $e');
  }
}

Future<void> _loadAnnouncements() async {
  // API CALL: CommunityService.getCommunityAnnouncements → Supabase DB
  final announcements = await _communityService
      .getCommunityAnnouncements(widget.community['id']);
  if (mounted) setState(() => _announcements = announcements);
}

void _showAnnouncementSheet() {
  final controller = TextEditingController();
  int charCount = 0;
  bool isPosting = false;

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1A1A1A),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Post announcement',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Visible to all community members on their home screen',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 6,
              maxLength: 500,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onChanged: (val) =>
                  setSheetState(() => charCount = val.length),
              decoration: InputDecoration(
                hintText: 'Share an update, event, or announcement...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.black,
                counterStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Colors.white, width: 1),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: isPosting
                    ? null
                    : () async {
                        setSheetState(() => isPosting = true);
                        try {
                          print('Posting announcement to: ${widget.community['id']}');
                          print('User id: ${_client.auth.currentUser?.id}');
                          print('Is admin: $_isAdmin');
                          // API CALL: CommunityService.createAnnouncement → Supabase DB
                          await _communityService.createAnnouncement(
                            communityId: widget.community['id'],
                            content: controller.text.trim(),
                          );
                          if (mounted) {
                            Navigator.pop(ctx);
                            _loadAnnouncements();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Announcement posted!'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          setSheetState(() => isPosting = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to post announcement'),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: isPosting
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2))
                    : const Text('Post',
                        style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

// ============================================================
// REPLY SCREEN
// ============================================================
class _ReplyScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final String communityId;

  const _ReplyScreen({required this.post, required this.communityId});

  @override
  State<_ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<_ReplyScreen> {
  final _client = Supabase.instance.client;
  final _replyController = TextEditingController();
  List<Map<String, dynamic>> _replies = [];
  bool _isLoading = true;
  bool _isPosting = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = _client.auth.currentUser?.id;
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
      // API CALL: Supabase DB — fetch replies with author info
      final response = await _client
          .from('replies')
          .select('''
            id,
            content,
            created_at,
            user_id,
            users(display_name, username)
          ''')
          .eq('post_id', widget.post['id'])
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _replies = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('loadReplies error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitReply() async {
    // VALIDATION: reply must not be empty
    if (_replyController.text.trim().isEmpty) return;

    setState(() => _isPosting = true);

    try {
      // API CALL: Supabase DB — create a new reply
      await _client.from('replies').insert({
        'post_id': widget.post['id'],
        'user_id': _currentUserId,
        'content': _replyController.text.trim(),
      });

      _replyController.clear();
      await _loadReplies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to reply. Please try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _deleteReply(String replyId) async {
    try {
      // API CALL: Supabase DB — delete a reply
      await _client.from('replies').delete().eq('id', replyId);
      await _loadReplies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete reply.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
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

  @override
  Widget build(BuildContext context) {
    final user = widget.post['users'];
    final displayName =
        user?['display_name'] ?? user?['username'] ?? 'Unknown';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Thread',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // ── ORIGINAL POST ─────────────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
                if (widget.post['verse_ref'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.post['verse_ref'],
                    style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  widget.post['content'] ?? '',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, height: 1.5),
                ),
              ],
            ),
          ),

          // ── REPLIES ───────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white))
                : _replies.isEmpty
                    ? const Center(
                        child: Text('No replies yet',
                            style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        itemCount: _replies.length,
                        itemBuilder: (context, index) {
                          final reply = _replies[index];
                          final replyUser = reply['users'];
                          final replyName =
                              replyUser?['display_name'] ??
                                  replyUser?['username'] ??
                                  'Unknown';
                          final isOwner =
                              reply['user_id'] == _currentUserId;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      replyName,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _timeAgo(reply['created_at']),
                                      style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11),
                                    ),
                                    if (isOwner) ...[
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => _deleteReply(
                                            reply['id']),
                                        child: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.grey,
                                            size: 16),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  reply['content'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      height: 1.4),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // ── REPLY INPUT ───────────────────────────────────
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            color: const Color(0xFF1A1A1A),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Write a reply...',
                      hintStyle:
                          const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.black,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _isPosting ? null : _submitReply,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: _isPosting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.black, strokeWidth: 2))
                        : const Icon(Icons.send,
                            color: Colors.black, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}