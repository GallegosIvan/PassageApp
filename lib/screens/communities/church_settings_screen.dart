import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/church_service.dart';

// SECURITY NOTE: church_followers/church_members display data is
// fetched via RPCs that return only public-safe fields (username,
// display_name) — get_church_followers for the unified Members
// list and search_users_by_username for the Add Follower
// autocomplete — never a raw `users(...)` relational embed, which
// would expose every field including email/strikes/is_restricted
// under the table's now-tightened self-only RLS SELECT policy.

class ChurchSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> church;
  final bool isCreator;

  const ChurchSettingsScreen({
    super.key,
    required this.church,
    required this.isCreator,
  });

  @override
  State<ChurchSettingsScreen> createState() =>
      _ChurchSettingsScreenState();
}

class _ChurchSettingsScreenState extends State<ChurchSettingsScreen> {
  final _churchService = ChurchService();
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  late final TextEditingController _websiteController;
  final _addFollowerController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  List<Map<String, dynamic>> _coAdmins = [];
  bool _showAddFollowerSuggestions = false;
  List<Map<String, dynamic>> _filteredForAddFollower = [];
  // Tracks whether anything changed in this screen (follower
  // added, co-admin added/removed, kicked, banned) so
  // ChurchDetailScreen knows to refresh its follower count when
  // this screen closes — even if the person never tapped Save.
  bool _didMakeChanges = false;

  // Full member roster + ban list, replacing the old
  // co-admin-only list — same unified pattern as
  // CommunitySettingsScreen's single Members section.
  List<Map<String, dynamic>> _allMembers = [];
  List<Map<String, dynamic>> _bans = [];
  bool _isLoadingMembers = false;
  bool _showingBans = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.church['name'] ?? '');
    _descriptionController =
        TextEditingController(text: widget.church['description'] ?? '');
    _locationController =
        TextEditingController(text: widget.church['location'] ?? '');
    _websiteController =
        TextEditingController(text: widget.church['website'] ?? '');
    _loadCoAdmins();
    _loadAllMembers();
    _addFollowerController.addListener(_onAddFollowerQueryChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    _addFollowerController.dispose();
    super.dispose();
  }

  // ── ADD FOLLOWER AUTOCOMPLETE ──────────────────────────────
  // Searches ALL users (not just existing followers) so the
  // creator can find someone who isn't a follower yet — the
  // whole point of this feature. Debounced lightly by only
  // searching on every change (no separate timer needed since
  // typing speed naturally throttles this enough for a 10-result
  // RPC call).
  Future<void> _onAddFollowerQueryChanged() async {
    final query = _addFollowerController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _showAddFollowerSuggestions = false;
        _filteredForAddFollower = [];
      });
      return;
    }
    final results = await _churchService.searchUsersByUsername(query);
    if (mounted) {
      setState(() {
        _showAddFollowerSuggestions = true;
        _filteredForAddFollower = results;
      });
    }
  }

  Future<void> _loadCoAdmins() async {
    setState(() => _isLoading = true);
    final coAdmins =
        await _churchService.getChurchCoAdmins(widget.church['id']);
    if (mounted) setState(() {
      _coAdmins = coAdmins;
      _isLoading = false;
    });
  }

  // ── LOAD ALL MEMBERS (full roster for the Members section) ──
  // RPC-backed via getChurchFollowers — returns every follower
  // with their role (co-admin or null), public-safe fields only.
  Future<void> _loadAllMembers() async {
    setState(() => _isLoadingMembers = true);
    final members = await _churchService.getChurchFollowers(widget.church['id']);
    if (mounted) {
      setState(() {
        _allMembers = members;
        _isLoadingMembers = false;
      });
    }
  }

  Future<void> _loadBans() async {
    setState(() => _isLoadingMembers = true);
    final bans = await _churchService.getChurchBans(widget.church['id']);
    if (mounted) {
      setState(() {
        _bans = bans;
        _isLoadingMembers = false;
      });
    }
  }

  // ── PROMOTE TO CO-ADMIN ────────────────────────────────────
  Future<void> _promoteMemberToCoAdmin(Map<String, dynamic> member) async {
    final username = member['username'] as String? ?? '';
    try {
      await _churchService.addChurchCoAdmin(
        churchId: widget.church['id'],
        username: username,
      );
      _didMakeChanges = true;
      await _loadAllMembers();
      await _loadCoAdmins();
      if (mounted) _showSnackbar('@$username is now a co-admin');
    } catch (e) {
      final message = e.toString();
      if (message.contains('target_is_restricted')) {
        await _showRestrictedDialog();
        return;
      }
      if (mounted) {
        _showSnackbar(message.replaceAll('Exception: ', ''), isError: true);
      }
    }
  }

  // ── DEMOTE TO REGULAR FOLLOWER ─────────────────────────────
  Future<void> _demoteMemberToFollower(Map<String, dynamic> member) async {
    final match = _coAdmins.firstWhere(
      (c) => c['user_id'] == member['user_id'],
      orElse: () => <String, dynamic>{},
    );
    if (match.isEmpty) {
      if (mounted) _showSnackbar('Could not find co-admin record', isError: true);
      return;
    }
    try {
      await _churchService.removeChurchCoAdmin(
        churchId: widget.church['id'],
        memberId: match['id'] as String,
      );
      _didMakeChanges = true;
      await _loadAllMembers();
      await _loadCoAdmins();
      if (mounted) _showSnackbar('Removed as co-admin');
    } catch (e) {
      if (mounted) _showSnackbar('Failed to update member', isError: true);
    }
  }

  // ── KICK (reversible) ──────────────────────────────────────
  Future<void> _kickMember(Map<String, dynamic> member) async {
    final displayName = member['display_name'] as String? ?? member['username'] as String? ?? 'this person';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Remove $displayName?', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'They will be removed from this church and will need to be re-added or scan the QR code to rejoin.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _churchService.removeChurchFollower(
        churchId: widget.church['id'],
        userId: member['user_id'] as String,
      );
      _didMakeChanges = true;
      setState(() => _allMembers.removeWhere((m) => m['user_id'] == member['user_id']));
      await _loadCoAdmins();
      if (mounted) _showSnackbar('$displayName removed');
    } catch (e) {
      final message = e.toString();
      final display = message.contains('cannot_remove_creator')
          ? 'The creator can\'t be removed'
          : 'Failed to remove';
      if (mounted) _showSnackbar(display, isError: true);
    }
  }

  // ── BAN (permanent) ────────────────────────────────────────
  Future<void> _banMember(Map<String, dynamic> member) async {
    final displayName = member['display_name'] as String? ?? member['username'] as String? ?? 'this person';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Ban $displayName?', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'They will be permanently removed and will NOT be able to rejoin this church again — not by QR code, not by being re-added. This can be reversed later from Banned Users.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ban', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _churchService.banChurchFollower(
        churchId: widget.church['id'],
        userId: member['user_id'] as String,
      );
      _didMakeChanges = true;
      setState(() => _allMembers.removeWhere((m) => m['user_id'] == member['user_id']));
      await _loadCoAdmins();
      if (mounted) _showSnackbar('$displayName banned');
    } catch (e) {
      final message = e.toString();
      final display = message.contains('cannot_ban_creator')
          ? 'The creator can\'t be banned'
          : 'Failed to ban';
      if (mounted) _showSnackbar(display, isError: true);
    }
  }

  // ── UNBAN ───────────────────────────────────────────────────
  Future<void> _unbanMember(Map<String, dynamic> banRecord) async {
    final displayName = banRecord['display_name'] as String? ?? banRecord['username'] as String? ?? 'this person';
    try {
      await _churchService.unbanChurchFollower(
        churchId: widget.church['id'],
        userId: banRecord['user_id'] as String,
      );
      _didMakeChanges = true;
      setState(() => _bans.removeWhere((b) => b['user_id'] == banRecord['user_id']));
      if (mounted) _showSnackbar('$displayName unbanned');
    } catch (e) {
      if (mounted) _showSnackbar('Failed to unban', isError: true);
    }
  }

  Future<void> _showRestrictedDialog() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Unable to promote', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This user is unable to be promoted due to a violation of our Terms of Service.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── MEMBER ACTION MENU ──────────────────────────────────────
  void _showMemberActionsSheet(Map<String, dynamic> member) {
    final isCreatorMember = member['user_id'] == widget.church['created_by'];
    if (isCreatorMember) return;

    final role = member['role'] as String?;
    final isCoAdmin = role == 'co-admin';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            if (!isCoAdmin)
              ListTile(
                leading: const Icon(Icons.shield_outlined, color: Colors.white),
                title: const Text('Make co-admin', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _promoteMemberToCoAdmin(member);
                },
              ),
            if (isCoAdmin)
              ListTile(
                leading: const Icon(Icons.remove_moderator_outlined, color: Colors.orange),
                title: const Text('Remove as co-admin', style: TextStyle(color: Colors.orange)),
                onTap: () {
                  Navigator.pop(context);
                  _demoteMemberToFollower(member);
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: Colors.orange),
              title: const Text('Remove (kick)', style: TextStyle(color: Colors.orange)),
              onTap: () {
                Navigator.pop(context);
                _kickMember(member);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text('Ban permanently', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _banMember(member);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // API CALL: ChurchService.updateChurch → Supabase DB
      // Privacy is no longer a setting here — every church is
      // private and joins only happen via in-person QR scan.
      await _churchService.updateChurch(
        churchId: widget.church['id'],
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        website: _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
      );
      if (mounted) {
        _showSnackbar('Settings saved');
        _didMakeChanges = true;
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) _showSnackbar('Failed to save settings', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── ADD FOLLOWER BY USERNAME ────────────────────────────────
  // RPC-backed via ChurchService.addFollowerByUsername — lets the
  // creator (or a co-admin, enforced server-side even though this
  // screen only exposes the field to widget.isCreator) add a known
  // person directly as a follower, skipping the QR scan entirely.
  Future<void> _addFollowerByUsername() async {
    final username = _addFollowerController.text.trim();
    if (username.isEmpty) return;

    try {
      await _churchService.addFollowerByUsername(
        churchId: widget.church['id'],
        username: username,
      );
      _addFollowerController.clear();
      await _loadAllMembers();
      _didMakeChanges = true;
      if (mounted) _showSnackbar('@$username now follows this church');
    } catch (e) {
      if (mounted) {
        _showSnackbar(
            e.toString().replaceAll('Exception: ', ''),
            isError: true);
      }
    }
  }

  Future<void> _deleteChurch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete church?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently delete "${widget.church['name']}" and all its announcements. This cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // API CALL: ChurchService.deleteChurch → Supabase DB
      await _churchService.deleteChurch(widget.church['id']);
      if (mounted) {
        // The church no longer exists, so this needs to pop back
        // past this screen AND ChurchDetailScreen at once — set
        // _didMakeChanges first in case anything checks it, then
        // allow this specific pop sequence through directly rather
        // than going through the PopScope handler (which only
        // pops one route at a time).
        _didMakeChanges = true;
        Navigator.of(context).popUntil((route) => route.isFirst);
        _showSnackbar('Church deleted');
      }
    } catch (e) {
      if (mounted) _showSnackbar('Failed to delete church', isError: true);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        Supabase.instance.client.auth.currentUser?.id;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Catches the back button (app bar arrow), hardware back,
        // and swipe-back gesture — anything that didn't go through
        // an explicit Navigator.pop(true) call already (those set
        // _didMakeChanges before popping, so this stays consistent
        // either way).
        Navigator.of(context).pop(_didMakeChanges);
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Church Settings',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── GENERAL ───────────────────────────
                    _sectionLabel('General'),
                    const SizedBox(height: 12),

                    _buildLabel('Church Name'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Church name'),
                      validator: (val) =>
                          val == null || val.trim().isEmpty
                              ? 'Please enter a church name'
                              : null,
                    ),

                    const SizedBox(height: 16),

                    _buildLabel('Description'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration:
                          _inputDecoration('Description (optional)'),
                    ),

                    const SizedBox(height: 16),

                    _buildLabel('Location'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _locationController,
                      style: const TextStyle(color: Colors.white),
                      decoration:
                          _inputDecoration('e.g. Dallas, TX (optional)'),
                    ),

                    const SizedBox(height: 16),

                    _buildLabel('Website'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _websiteController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.url,
                      decoration: _inputDecoration(
                          'e.g. https://mychurch.com (optional)'),
                    ),

                    const SizedBox(height: 16),

                    // ── PRIVACY NOTICE (no longer a toggle) ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.qr_code_2, color: Colors.grey, size: 20),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Joins by QR code only',
                                    style: TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.w500)),
                                Text(
                                  'This is permanent for every church. Find your QR code from the church page.',
                                  style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── ADD FOLLOWER BY USERNAME ──────────
                    // Lets the creator add a known person directly
                    // as a follower, without requiring them to scan
                    // the church's QR code.
                    _sectionLabel('Add Follower'),
                    const SizedBox(height: 4),
                    const Text(
                      'Add someone directly by username, instead of having them scan your QR code.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    if (widget.isCreator) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _addFollowerController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration('@username'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _addFollowerByUsername,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                      if (_showAddFollowerSuggestions && _filteredForAddFollower.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Column(
                            children: _filteredForAddFollower.take(5).map((u) {
                              final username = u['username'] as String? ?? '';
                              final displayName =
                                  u['display_name'] as String? ?? username;
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.person_outline,
                                    color: Colors.grey, size: 18),
                                title: Text(displayName,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                subtitle: Text('@$username',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                                onTap: () {
                                  _addFollowerController.text = username;
                                  setState(() => _showAddFollowerSuggestions = false);
                                  _addFollowerByUsername();
                                },
                              );
                            }).toList(),
                          ),
                        ),
                    ],

                    const SizedBox(height: 32),

                    // ── MEMBERS ────────────────────────────
                    // Unified roster — every follower, with role
                    // shown (Creator / Co-admin / Follower). Tap
                    // any non-creator member (if you're the
                    // creator) to promote, demote, kick, or ban.
                    // Same pattern as CommunitySettingsScreen's
                    // single Members section.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionLabel(_showingBans ? 'Banned Users' : 'Members'),
                        if (widget.isCreator)
                          GestureDetector(
                            onTap: () {
                              setState(() => _showingBans = !_showingBans);
                              if (_showingBans) {
                                _loadBans();
                              } else {
                                _loadAllMembers();
                              }
                            },
                            child: Text(
                              _showingBans ? 'View members' : 'View banned users',
                              style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _showingBans
                          ? 'People who can never rejoin this church unless unbanned.'
                          : 'View and manage everyone following this church.',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    if (_isLoadingMembers)
                      const Center(child: CircularProgressIndicator(color: Colors.white))
                    else if (_showingBans)
                      if (_bans.isEmpty)
                        const Text('No banned users', style: TextStyle(color: Colors.grey))
                      else
                        ..._bans.map((ban) {
                          final displayName = ban['display_name'] as String? ?? ban['username'] as String? ?? 'Unknown';
                          final username = ban['username'] as String? ?? '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.block, color: Colors.red, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                      Text('@$username', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _unbanMember(ban),
                                  child: const Text('Unban', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                        })
                    else if (_allMembers.isEmpty)
                      const Text('No members yet', style: TextStyle(color: Colors.grey))
                    else
                      ..._allMembers.map((member) {
                        final displayName = member['display_name'] as String? ?? member['username'] as String? ?? 'Unknown';
                        final username = member['username'] as String? ?? '';
                        final role = member['role'] as String?;
                        final isCurrentUser = member['user_id'] == currentUserId;
                        final isCreatorMember = member['user_id'] == widget.church['created_by'];
                        final canManage = widget.isCreator && !isCurrentUser && !isCreatorMember;

                        String roleLabel;
                        Color roleColor;
                        if (isCreatorMember) {
                          roleLabel = 'Creator';
                          roleColor = Colors.amber;
                        } else if (role == 'co-admin') {
                          roleLabel = 'Co-admin';
                          roleColor = Colors.blueAccent;
                        } else {
                          roleLabel = 'Follower';
                          roleColor = Colors.grey;
                        }

                        return GestureDetector(
                          onTap: canManage ? () => _showMemberActionsSheet(member) : null,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person_outline, color: Colors.grey, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(displayName,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: roleColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(roleLabel,
                                              style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.w600)),
                                        ),
                                      ]),
                                      Text('@$username', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                if (canManage) const Icon(Icons.more_vert, color: Colors.grey, size: 18),
                              ],
                            ),
                          ),
                        );
                      }),

                    const SizedBox(height: 32),

                    // ── DANGER ZONE ───────────────────────
                    if (widget.isCreator) ...[
                      _sectionLabel('Danger zone'),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _deleteChurch,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.red,
                            side:
                                const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                          ),
                          child: const Text('Delete Church',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
          color: Colors.grey,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500));
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: Colors.white, width: 1),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}