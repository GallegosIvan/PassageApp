import 'package:flutter/material.dart';
import '../../services/community_service.dart';
import '../../services/church_service.dart';
import 'community_detail_screen.dart';
import 'create_community_screen.dart';
import 'church_detail_screen.dart';
import 'create_church_screen.dart';
import 'qr_scan_screen.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen>
    with SingleTickerProviderStateMixin {
  final _communityService = CommunityService();
  final _churchService = ChurchService();
  late TabController _tabController;

  // My communities
  List<Map<String, dynamic>> _myCommunities = [];
  bool _isLoadingMine = true;

  // My churches
  List<Map<String, dynamic>> _followedChurches = [];
  bool _isLoadingMyChurches = true;

  // Discover — communities (churches are no longer discoverable —
  // joining a church only happens via in-person QR scan)
  List<Map<String, dynamic>> _discoverCommunities = [];
  bool _isLoadingDiscover = true;
  final _communitySearchController = TextEditingController();
  String? _filterBook;
  bool _showFilters = false;

  final List<String> _books = [
    'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy',
    'Joshua', 'Judges', 'Ruth', '1 Samuel', '2 Samuel', '1 Kings',
    '2 Kings', '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah',
    'Esther', 'Job', 'Psalms', 'Proverbs', 'Ecclesiastes',
    'Song of Solomon', 'Isaiah', 'Jeremiah', 'Lamentations', 'Ezekiel',
    'Daniel', 'Hosea', 'Joel', 'Amos', 'Obadiah', 'Jonah', 'Micah',
    'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai', 'Zechariah', 'Malachi',
    'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans',
    '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians',
    'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians',
    '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews', 'James',
    '1 Peter', '2 Peter', '1 John', '2 John', '3 John', 'Jude',
    'Revelation',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
    _communitySearchController.addListener(() {
      _loadDiscoverCommunities(query: _communitySearchController.text);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _communitySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadMyCommunities(),
      _loadFollowedChurches(),
      _loadDiscoverCommunities(),
    ]);
  }

  Future<void> _loadMyCommunities() async {
    if (!mounted) return;
    setState(() => _isLoadingMine = true);
    final communities = await _communityService.getMyCommunities();
    if (mounted) setState(() {
      _myCommunities = communities;
      _isLoadingMine = false;
    });
  }

  Future<void> _loadFollowedChurches() async {
    if (!mounted) return;
    setState(() => _isLoadingMyChurches = true);
    final churches = await _churchService.getFollowedChurches();
    if (mounted) setState(() {
      _followedChurches = churches;
      _isLoadingMyChurches = false;
    });
  }

  Future<void> _loadDiscoverCommunities({String? query}) async {
    if (!mounted) return;
    setState(() => _isLoadingDiscover = true);
    final communities = await _communityService.getDiscoverCommunities(
      searchQuery: query,
      filterBook: _filterBook,
    );
    if (mounted) setState(() {
      _discoverCommunities = communities;
      _isLoadingDiscover = false;
    });
  }

  Future<void> _joinCommunity(String communityId) async {
    try {
      await _communityService.joinCommunity(communityId);
      await _loadMyCommunities();
      await _loadDiscoverCommunities(query: _communitySearchController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Joined community!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to join community'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _unfollowChurch(Map<String, dynamic> church) async {
    try {
      await _churchService.unfollowChurch(church['id']);
      await _loadFollowedChurches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to leave church'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _filterBook = null;
    });
    _loadDiscoverCommunities(query: _communitySearchController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Communities',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () async {
              final choice = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: const Color(0xFF1A1A1A),
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
                      const Text('What would you like to create?',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      _CreateOption(
                        icon: Icons.people_outline,
                        title: 'Study Community',
                        subtitle: 'A group studying a specific book and chapter',
                        onTap: () => Navigator.pop(context, 'community'),
                      ),
                      const SizedBox(height: 12),
                      _CreateOption(
                        icon: Icons.church_outlined,
                        title: 'Church Profile',
                        subtitle: 'A church page with multiple communities',
                        onTap: () => Navigator.pop(context, 'church'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );

              if (choice == 'community') {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateCommunityScreen()),
                );
                _loadMyCommunities();
                _loadDiscoverCommunities();
              } else if (choice == 'church') {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateChurchScreen()),
                );
                _loadFollowedChurches();
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Theme(
            data: Theme.of(context).copyWith(
              tabBarTheme: const TabBarThemeData(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.white,
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(text: 'My Communities'),
                Tab(text: 'Discover'),
                Tab(text: 'My Churches'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── MY COMMUNITIES ────────────────────────────────
          _isLoadingMine
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _myCommunities.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.people_outline, color: Colors.grey, size: 48),
                          const SizedBox(height: 16),
                          const Text('No communities yet',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text('Join a community in the Discover tab',
                              style: TextStyle(color: Colors.grey, fontSize: 14)),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => _tabController.animateTo(1),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Discover'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadMyCommunities,
                      color: Colors.white,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _myCommunities.length,
                        itemBuilder: (context, index) {
                          final community = _myCommunities[index];
                          return _CommunityCard(
                            community: community,
                            isMember: true,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CommunityDetailScreen(community: community),
                                ),
                              );
                              _loadMyCommunities();
                            },
                          );
                        },
                      ),
                    ),

          // ── DISCOVER (communities only — no church discovery) ──
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _communitySearchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search communities...',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: Icon(
                        Icons.tune,
                        color: _filterBook != null ? Colors.white : Colors.grey,
                      ),
                      onPressed: () => setState(() => _showFilters = !_showFilters),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              if (_showFilters)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Filter by:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          const Spacer(),
                          if (_filterBook != null)
                            GestureDetector(
                              onTap: _clearFilters,
                              child: const Text('Clear', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _filterBook,
                            hint: const Text('Book', style: TextStyle(color: Colors.grey)),
                            dropdownColor: const Color(0xFF1A1A1A),
                            isExpanded: true,
                            style: const TextStyle(color: Colors.white),
                            items: _books.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                            onChanged: (val) {
                              setState(() => _filterBook = val);
                              _loadDiscoverCommunities(query: _communitySearchController.text);
                            },
                          ),
                        ),
                      ),
                      if (_filterBook != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              Chip(
                                label: Text(_filterBook!, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                backgroundColor: const Color(0xFF2A2A2A),
                                deleteIcon: const Icon(Icons.close, size: 14, color: Colors.grey),
                                onDeleted: () {
                                  setState(() => _filterBook = null);
                                  _loadDiscoverCommunities(query: _communitySearchController.text);
                                },
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoadingDiscover
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _discoverCommunities.isEmpty
                        ? const Center(child: Text('No communities found', style: TextStyle(color: Colors.grey)))
                        : RefreshIndicator(
                            onRefresh: () => _loadDiscoverCommunities(query: _communitySearchController.text),
                            color: Colors.white,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _discoverCommunities.length,
                              itemBuilder: (context, index) {
                                final community = _discoverCommunities[index];
                                return _CommunityCard(
                                  community: community,
                                  isMember: false,
                                  onJoin: () => _joinCommunity(community['id']),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),

          // ── MY CHURCHES ───────────────────────────────────
          // No public church discovery. Joining only happens via
          // in-person QR code scan.
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const QrScanScreen()),
                    ).then((_) => _loadFollowedChurches()),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan church QR code',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _isLoadingMyChurches
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _followedChurches.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.church_outlined, color: Colors.grey, size: 48),
                                const SizedBox(height: 16),
                                const Text('No churches yet',
                                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                const Text(
                                  'Scan a church\'s QR code in person to join',
                                  style: TextStyle(color: Colors.grey, fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadFollowedChurches,
                            color: Colors.white,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: _followedChurches.length,
                              itemBuilder: (context, index) {
                                final church = _followedChurches[index];
                                return _ChurchCard(
                                  church: church,
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => ChurchDetailScreen(church: church)),
                                    );
                                    _loadFollowedChurches();
                                  },
                                  onLeave: () => _unfollowChurch(church),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── COMMUNITY CARD ────────────────────────────────────────────
class _CommunityCard extends StatelessWidget {
  final Map<String, dynamic> community;
  final bool isMember;
  final VoidCallback? onTap;
  final VoidCallback? onJoin;

  const _CommunityCard({
    required this.community,
    required this.isMember,
    this.onTap,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final book = community['book'];
    final chapter = community['chapter'];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(community['name'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  if (book != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      chapter != null ? '$book $chapter' : book.toString(),
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                  if (community['description'] != null && community['description'].toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(community['description'],
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (community['role'] != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        community['role'] == 'admin' ? 'Admin' : 'Member',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isMember)
              ElevatedButton(
                onPressed: onJoin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Join', style: TextStyle(fontWeight: FontWeight.w600)),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

// ── CHURCH CARD (My Churches only — no follow/discover state) ──
class _ChurchCard extends StatelessWidget {
  final Map<String, dynamic> church;
  final VoidCallback onTap;
  final VoidCallback onLeave;

  const _ChurchCard({
    required this.church,
    required this.onTap,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final followerCount = (church['church_followers'] as List?)?.first?['count'] ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.church_outlined, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(church['name'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  if (church['location'] != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, color: Colors.grey, size: 12),
                        const SizedBox(width: 4),
                        Text(church['location'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text('$followerCount followers', style: const TextStyle(color: Colors.grey, fontSize: 12)),
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

// ── CREATE OPTION ─────────────────────────────────────────────
class _CreateOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CreateOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
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