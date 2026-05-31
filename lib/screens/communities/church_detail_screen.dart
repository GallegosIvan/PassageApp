import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/church_service.dart';
import 'church_settings_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';

class ChurchDetailScreen extends StatefulWidget {
  final Map<String, dynamic> church;

  const ChurchDetailScreen({super.key, required this.church});

  @override
  State<ChurchDetailScreen> createState() => _ChurchDetailScreenState();
}

class _ChurchDetailScreenState extends State<ChurchDetailScreen> {
  final _churchService = ChurchService();
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _announcements = [];
  bool _isFollowing = false;
  bool _isCreator = false;
  bool _isAdmin = false;
  bool _isLoading = true;
  int _followerCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = _client.auth.currentUser?.id;
    final isCreator = widget.church['created_by'] == userId;

    final results = await Future.wait([
      _churchService.getChurchAnnouncements(widget.church['id']),
      _churchService.isFollowing(widget.church['id']),
      _churchService.isCoAdmin(widget.church['id']),
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
        // Admin if creator OR co-admin
        _isAdmin = isCreator || (results[2] as bool);
        _followerCount = (followers as List).length;
        _isLoading = false;
      });
    }
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

  void _showInviteSheet() {
    final inviteLink = _churchService.getInviteLink(widget.church['id']);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const Text('Invite to church',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Share this QR code or link at your church',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // QR Code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: inviteLink,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 20),

            // Invite link
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      inviteLink,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: inviteLink));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Link copied to clipboard'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Icon(Icons.copy,
                        color: Colors.white, size: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showAnnouncementSheet() {
    final controller = TextEditingController();
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
                  width: 40,
                  height: 4,
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
                'Visible to all followers on their home screen',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 6,
                maxLength: 500,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                onChanged: (_) => setSheetState(() {}),
                decoration: InputDecoration(
                  hintText:
                      'Share an update, event, or announcement...',
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
                  onPressed:
                      isPosting || controller.text.trim().isEmpty
                          ? null
                          : () async {
                              setSheetState(() => isPosting = true);
                              try {
                                // API CALL: ChurchService.createChurchAnnouncement → Supabase DB
                                await _churchService
                                    .createChurchAnnouncement(
                                  churchId: widget.church['id'],
                                  content: controller.text.trim(),
                                );
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  _loadData();
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Announcement posted!'),
                                      behavior:
                                          SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setSheetState(
                                    () => isPosting = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Failed to post announcement'),
                                      backgroundColor: Colors.red,
                                      behavior:
                                          SnackBarBehavior.floating,
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
              icon: const Icon(Icons.campaign_outlined, color: Colors.white),
              tooltip: 'Post announcement',
              onPressed: _showAnnouncementSheet,
            ),
          if (_isCreator || _isAdmin)
            IconButton(
              icon: const Icon(Icons.qr_code, color: Colors.white),
              onPressed: () => _showInviteSheet(),
            ),
          if (_isCreator || _isAdmin)
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () async {
                final updated = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ChurchSettingsScreen(
                      church: widget.church,
                      isCreator: _isCreator,
                    ),
                  ),
                );
                if (updated == true && mounted) {
                  Navigator.of(context).pop(true);
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: Colors.white,
              child: ListView(
                children: [
                  // ── CHURCH HEADER ─────────────────────────
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

                        // Follow button
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
                                _isFollowing
                                    ? 'Following'
                                    : 'Follow',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const Divider(color: Color(0xFF2A2A2A)),

                  // ── ANNOUNCEMENTS ─────────────────────────
                  Padding(
                    padding: const EdgeInsets.all(20),
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
                          ..._announcements.map((a) {
                            final user = a['users'];
                            final name = user?['display_name'] ??
                                user?['username'] ??
                                'Admin';
                            final timeAgo = _timeAgo(a['created_at']);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
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
                                        name,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                      const Spacer(),
                                      Text(
                                        timeAgo,
                                        style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 11),
                                      ),
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
                                                  style: TextStyle(
                                                      color:
                                                          Colors.white)),
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
                                                  onPressed: () async {
                                                    Navigator.pop(
                                                        context);
                                                    // API CALL: ChurchService.deleteChurchAnnouncement → Supabase DB
                                                    await _churchService
                                                        .deleteChurchAnnouncement(
                                                            a['id']);
                                                    _loadData();
                                                  },
                                                  child: const Text(
                                                      'Delete',
                                                      style: TextStyle(
                                                          color:
                                                              Colors.red)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          child: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.grey,
                                              size: 16),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}