import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/church_service.dart';
import '../../services/community_service.dart';
import 'church_settings_screen.dart';
import 'community_detail_screen.dart';
import 'create_community_screen.dart';
import 'church_chat_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../widgets/restricted_dialog.dart';

class ChurchDetailScreen extends StatefulWidget {
  final Map<String, dynamic> church;

  const ChurchDetailScreen({super.key, required this.church});

  @override
  State<ChurchDetailScreen> createState() => _ChurchDetailScreenState();
}

class _ChurchDetailScreenState extends State<ChurchDetailScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _churchService = ChurchService();
  final _communityService = CommunityService();
  final _client = Supabase.instance.client;
  late TabController _tabController;
  RealtimeChannel? _communityChannel;

  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _churchCommunities = [];

  List<Map<String, dynamic>> get _bibleStudyCommunities =>
      _churchCommunities.where((c) => c['is_bible_study'] == true).toList();
  List<Map<String, dynamic>> get _groupChatCommunities =>
      _churchCommunities.where((c) => c['is_bible_study'] != true).toList();
  bool _isFollowing = false;
  bool _isCreator = false;
  bool _isAdmin = false;
  bool _isLoading = true;
  int _followerCount = 0;

  // For the Browse tab — every open community in this church,
  // marking which the user has already opted into joining.
  List<Map<String, dynamic>> _browsableCommunities = [];
  bool _isLoadingBrowsable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _subscribeToChurchCommunityChanges();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshChurchCommunities();
    }
  }

  Future<void> _refreshChurchCommunities() async {
    final communities = await _communityService.getChurchCommunities(widget.church['id']);
    if (mounted) setState(() => _churchCommunities = communities);
  }

  void _subscribeToChurchCommunityChanges() {
    _communityChannel = _client
        .channel('church_communities_${widget.church['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'communities',
          callback: (payload) {
            if (mounted) _refreshChurchCommunities();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'communities',
          callback: (payload) {
            if (mounted) _refreshChurchCommunities();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _communityChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _client.auth.currentUser?.id;
    final isCreator = widget.church['created_by'] == userId;

    final results = await Future.wait([
      _churchService.getChurchAnnouncements(widget.church['id']),
      _churchService.isFollowing(widget.church['id']),
      _churchService.isCoAdmin(widget.church['id']),
      _communityService.getChurchCommunities(widget.church['id']),
    ]);

    final followers = await _client
        .from('church_followers')
        .select('id')
        .eq('church_id', widget.church['id']);

    if (mounted) {
      setState(() {
        _announcements = results[0] as List<Map<String, dynamic>>;
        _isFollowing = results[1] as bool;
        _isCreator = isCreator;
        _isAdmin = isCreator || (results[2] as bool);
        _churchCommunities = results[3] as List<Map<String, dynamic>>;
        _followerCount = (followers as List).length;
        _isLoading = false;
      });
      _loadBrowsableCommunities();
    }
  }

  // ── BROWSE TAB: load + join ────────────────────────────────
  // Only fetched once the person follows the church (the RPC
  // itself also enforces this server-side).
  Future<void> _loadBrowsableCommunities() async {
    if (!_isFollowing) return;
    setState(() => _isLoadingBrowsable = true);
    final communities = await _communityService.getBrowsableChurchCommunities(widget.church['id']);
    if (mounted) {
      setState(() {
        _browsableCommunities = communities;
        _isLoadingBrowsable = false;
      });
    }
  }

  Future<void> _joinBrowsableCommunity(Map<String, dynamic> community) async {
    try {
      await _communityService.joinChurchCommunity(community['id'] as String);
      if (mounted) {
        setState(() {
          final index = _browsableCommunities.indexWhere((c) => c['id'] == community['id']);
          if (index != -1) _browsableCommunities[index]['is_member'] = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Joined ${community['name']}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to join'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showQrSheet() async {
    final token = await _churchService.getChurchQrToken(widget.church['id']);
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load QR code'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
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
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Church QR code',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                'Show this in person to anyone joining your church. There is no online invite link.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: token,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1A1A),
                      title: const Text('Regenerate QR code?',
                          style: TextStyle(color: Colors.white)),
                      content: const Text(
                        'The old QR code will stop working immediately. Anyone who scans it after this will not be able to join.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Regenerate', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    try {
                      await _churchService.regenerateChurchQrToken(widget.church['id']);
                      if (mounted) {
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('QR code regenerated'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to regenerate QR code'),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
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
      ),
    );
  }

  Future<void> _toggleFollow() async {
    try {
      if (_isFollowing) {
        await _churchService.unfollowChurch(widget.church['id']);
        setState(() {
          _isFollowing = false;
          _followerCount--;
        });
      } else {
        await _churchService.followChurch(widget.church['id']);
        setState(() {
          _isFollowing = true;
          _followerCount++;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update follow status'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAnnouncementSheet() {
    final controller = TextEditingController();
    bool isPosting = false;
    Uint8List? draftImageBytes;
    String? draftImageExtension;

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
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Post announcement',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                'Visible to all followers on their home screen',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),

              if (draftImageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          draftImageBytes!,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () => setSheetState(() {
                            draftImageBytes = null;
                            draftImageExtension = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              TextField(
                controller: controller,
                maxLines: 6,
                maxLength: 500,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                onChanged: (_) => setSheetState(() {}),
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

              if (draftImageBytes == null)
                TextButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                    if (picked == null) return;
                    final bytes = await picked.readAsBytes();
                    setSheetState(() {
                      draftImageBytes = bytes;
                      draftImageExtension = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
                    });
                  },
                  icon: const Icon(Icons.image_outlined, color: Colors.grey, size: 18),
                  label: const Text('Add photo', style: TextStyle(color: Colors.grey)),
                ),

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isPosting || (controller.text.trim().isEmpty && draftImageBytes == null)
                      ? null
                      : () async {
                          setSheetState(() => isPosting = true);
                          try {
                            String? imageUrl;
                            if (draftImageBytes != null) {
                              imageUrl = await _churchService.uploadAnnouncementImage(
                                churchId: widget.church['id'],
                                bytes: draftImageBytes!,
                                fileExtension: draftImageExtension ?? 'jpg',
                              );
                            }
                            await _churchService.createChurchAnnouncement(
                              churchId: widget.church['id'],
                              content: controller.text.trim(),
                              imageUrl: imageUrl,
                            );
                            if (mounted) {
                              Navigator.pop(ctx);
                              _loadData();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Announcement posted!'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            print('postAnnouncement error: $e');
                            setSheetState(() => isPosting = false);
                            if (mounted) {
                              final isRestricted = e.toString().contains('user_restricted');
                              if (isRestricted) {
                                Navigator.pop(ctx);
                                await RestrictedDialog.show(context);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Failed to post announcement'),
                                    backgroundColor: Colors.red,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
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
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2))
                      : const Text('Post',
                          style:
                              TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(String dateStr) {
    final date = DateTime.parse(dateStr);
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'now';
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
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.campaign_outlined,
                  color: Colors.white),
              tooltip: 'Post announcement',
              onPressed: _showAnnouncementSheet,
            ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              tooltip: 'Create church community',
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => CreateCommunityScreen(
                      churchId: widget.church['id'],
                    ),
                  ),
                );
                if (created == true && mounted) {
                  await _loadBrowsableCommunities();
                  _tabController.animateTo(1);
                }
              },
            ),
          if (_isCreator || _isAdmin)
            IconButton(
              icon: const Icon(Icons.qr_code, color: Colors.white),
              tooltip: 'Show QR code',
              onPressed: _showQrSheet,
            ),
          if (_isCreator || _isAdmin)
            IconButton(
              icon: const Icon(Icons.settings_outlined,
                  color: Colors.white),
              onPressed: () async {
                // Settings screen now reports back true whenever
                // ANYTHING changed in it — adding a follower,
                // adding/removing a co-admin, or saving general
                // settings — not just on explicit Save. This is
                // what fixes the stale follower count: previously
                // only _saveSettings's pop(true) triggered a
                // refresh, so adding a follower without touching
                // Save never updated this screen until you left
                // and came back through a different path.
                final updated = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ChurchSettingsScreen(
                      church: widget.church,
                      isCreator: _isCreator,
                    ),
                  ),
                );
                if (updated == true && mounted) {
                  _loadData();
                }
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Church'),
            Tab(text: 'Browse'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildChurchTab(),
                _buildBrowseTab(),
              ],
            ),
    );
  }

  // ── CHURCH TAB (existing page content, unchanged) ──────────
  Widget _buildChurchTab() {
    return RefreshIndicator(
              onRefresh: _loadData,
              color: Colors.white,
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.church_outlined,
                                  color: Colors.white, size: 32),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.church['name'] ?? '',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  if (widget.church['location'] !=
                                      null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                            Icons.location_on_outlined,
                                            color: Colors.grey,
                                            size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          widget.church['location'],
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    '$_followerCount followers',
                                    style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        if (widget.church['description'] != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            widget.church['description'],
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.5),
                          ),
                        ],

                        if (widget.church['website'] != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.link,
                                  color: Colors.grey, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                widget.church['website'],
                                style: const TextStyle(
                                    color: Colors.blue, fontSize: 13),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 16),

                        if (!_isCreator)
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _toggleFollow,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isFollowing
                                    ? Colors.transparent
                                    : Colors.white,
                                foregroundColor: _isFollowing
                                    ? Colors.white
                                    : Colors.black,
                                side: _isFollowing
                                    ? const BorderSide(
                                        color: Colors.white)
                                    : BorderSide.none,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                              child: Text(
                                _isFollowing ? 'Following' : 'Follow',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const Divider(color: Color(0xFF2A2A2A)),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.campaign_outlined,
                                color: Colors.grey, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Announcements',
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_announcements.isEmpty)
                          const Center(
                            child: Padding(
                              padding:
                                  EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No announcements yet',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                          ..._announcements.map((a) {
                            final user = a['users'];
                            final name = user?['display_name'] ??
                                user?['username'] ??
                                'Admin';
                            final timeAgo = _timeAgo(a['created_at']);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141414),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (a['image_url'] != null) ...[
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(
                                              a['image_url'],
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => Container(
                                                height: 100,
                                                alignment: Alignment.center,
                                                child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                        Text(
                                          a['content'] ?? '',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              height: 1.55),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1E1E1E),
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: Radius.circular(12),
                                        bottomRight: Radius.circular(12),
                                      ),
                                    ),
                                    child: Row(children: [
                                      const Icon(Icons.campaign_outlined, color: Colors.grey, size: 13),
                                      const SizedBox(width: 5),
                                      Text(name, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
                                      const Spacer(),
                                      Text(timeAgo, style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context),
                                                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                                                ),
                                                TextButton(
                                                  onPressed: () async {
                                                    Navigator.pop(context);
                                                    await _churchService.deleteChurchAnnouncement(a['id']);
                                                    _loadData();
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
                                  ),
                                ],
                              ),
                            );
                          }),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const Divider(color: Color(0xFF2A2A2A)),

                  if (_churchCommunities.isNotEmpty) ...[
                    if (_bibleStudyCommunities.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.menu_book_outlined,
                                    color: Colors.grey, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Bible Studies',
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._bibleStudyCommunities.map(_buildCommunityRow),
                          ],
                        ),
                      ),

                    if (_groupChatCommunities.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            20, _bibleStudyCommunities.isNotEmpty ? 24 : 20, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.chat_bubble_outline,
                                    color: Colors.grey, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Group Chats',
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._groupChatCommunities.map(_buildCommunityRow),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            );
  }

  // ── BROWSE TAB ──────────────────────────────────────────────
  // Every open (non-private) community in this church, with a
  // Join button for ones the person hasn't opted into yet.
  // Nothing here auto-joins anything — following the church only
  // grants visibility into this list, not membership.
  Widget _buildBrowseTab() {
    if (!_isFollowing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Follow this church to browse and join its communities and group chats.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isLoadingBrowsable) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_browsableCommunities.isEmpty) {
      return const Center(
        child: Text('No communities yet', style: TextStyle(color: Colors.grey)),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBrowsableCommunities,
      color: Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _browsableCommunities.length,
        itemBuilder: (context, index) {
          final community = _browsableCommunities[index];
          final isBibleStudy = community['is_bible_study'] == true;
          final isMember = community['is_member'] == true;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  isBibleStudy ? Icons.menu_book_outlined : Icons.chat_bubble_outline,
                  color: Colors.grey,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        community['name'] ?? '',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isBibleStudy ? (community['book'] ?? 'Bible study') : 'Group chat',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (isMember)
                  const Text('Joined', style: TextStyle(color: Colors.grey, fontSize: 12))
                else
                  ElevatedButton(
                    onPressed: () => _joinBrowsableCommunity(community),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Join', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCommunityRow(Map<String, dynamic> community) {
    final isBibleStudy = community['is_bible_study'] == true;
    return GestureDetector(
      onTap: () async {
        if (isBibleStudy) {
          Map<String, dynamic> freshCommunity = community;
          try {
            final result = await Supabase.instance.client
                .from('communities')
                .select()
                .eq('id', community['id'])
                .single();
            freshCommunity = {...Map<String, dynamic>.from(result), 'role': community['role']};
          } catch (e) {
            print('fetch fresh church community error: $e');
          }
          if (context.mounted) {
            final result = await Navigator.of(context).push<dynamic>(
              MaterialPageRoute(builder: (_) => CommunityDetailScreen(community: freshCommunity)),
            );
            if (result == 'left' && mounted) {
              await Future.wait([_refreshChurchCommunities(), _loadBrowsableCommunities()]);
              _tabController.animateTo(1);
            }
          }
        } else {
          Map<String, dynamic> freshCommunity = community;
          try {
            final result = await Supabase.instance.client
                .from('communities')
                .select()
                .eq('id', community['id'])
                .single();
            freshCommunity = {...Map<String, dynamic>.from(result), 'role': community['role']};
          } catch (e) {
            print('fetch fresh chat community error: $e');
          }
          if (context.mounted) {
            final result = await Navigator.of(context).push<dynamic>(
              MaterialPageRoute(builder: (_) => ChurchChatScreen(community: freshCommunity)),
            );
            if (result == 'left' && mounted) {
              await Future.wait([_refreshChurchCommunities(), _loadBrowsableCommunities()]);
              _tabController.animateTo(1);
            }
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isBibleStudy ? Icons.menu_book_outlined : Icons.chat_bubble_outline,
              color: Colors.grey,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    community['name'] ?? '',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isBibleStudy
                        ? (community['book'] ?? 'Bible study')
                        : 'Group chat',
                    style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
