import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/community_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/upgrade_sheet.dart';

// SECURITY FIX: _loadAllMembers previously used `users(display_name,
// username)` relational embedding, which relied on the users
// table's RLS SELECT policy — found to be `qual = true`, meaning
// any authenticated user could read any other user's full row,
// including email, strikes, is_restricted. That policy is now
// tightened to self-only. _loadAllMembers now fetches only
// public-safe fields via the get_public_profiles RPC instead,
// attached in the same 'users' key shape the old embed produced.

class CommunitySettingsScreen extends StatefulWidget {
  final Map<String, dynamic> community;
  final bool isCreator;

  const CommunitySettingsScreen({
    super.key,
    required this.community,
    required this.isCreator,
  });

  @override
  State<CommunitySettingsScreen> createState() =>
      _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState
    extends State<CommunitySettingsScreen> {
  final _communityService = CommunityService();
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final _addMemberController = TextEditingController();

  // Church communities don't always need a book — only required
  // if the community is marked as a Bible study. Non-church
  // communities always require a book. Chapter is no longer a
  // community-level field at all (it lives on individual posts).
  bool get _isChurchCommunity => widget.community['church_id'] != null;
  bool get _isBibleStudy => widget.community['is_bible_study'] == true;
  bool get _bookRequired => !_isChurchCommunity || _isBibleStudy;

  String? _selectedBook;
  bool _isPrivate = false;
  bool _isLoading = false;
  bool _isSaving = false;
  List<Map<String, dynamic>> _allMembers = [];
  bool _isLoadingMembers = false;

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
    _nameController =
        TextEditingController(text: widget.community['name'] ?? '');
    _descriptionController =
        TextEditingController(text: widget.community['description'] ?? '');
    _selectedBook = widget.community['book'];
    _isPrivate = widget.community['is_private'] ?? false;
    _loadAllMembers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addMemberController.dispose();
    super.dispose();
  }

  // ── LOAD ALL MEMBERS (for the full roster list) ───────────
  // SECURITY FIX: see file header — switched from the users(...)
  // relational embed to fetching display info via the
  // get_public_profiles RPC.
  Future<void> _loadAllMembers() async {
    setState(() => _isLoadingMembers = true);
    try {
      final response = await Supabase.instance.client
          .from('community_members')
          .select('id, user_id, role, joined_at')
          .eq('community_id', widget.community['id'])
          .order('joined_at', ascending: true);

      final members = List<Map<String, dynamic>>.from(response);
      await _hydrateUsers(members, 'user_id');

      if (mounted) {
        setState(() {
          _allMembers = members;
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      print('loadAllMembers error: $e');
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  // ── HYDRATE USER DISPLAY INFO ──────────────────────────────
  // Fetches ONLY public-safe display fields (username,
  // display_name, avatar_url — never email/strikes/is_restricted)
  // via the get_public_profiles RPC, then attaches a 'users' key
  // to each row in the same shape the old `users(...)` embed
  // produced, so existing UI code in this file keeps reading
  // member['users']['display_name'] etc. unchanged.
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

  // ── REMOVE MEMBER FROM COMMUNITY ──────────────────────────
  // RPC-backed via CommunityService.removeCommunityMember — the
  // server verifies the caller is admin/co-admin and enforces
  // who a co-admin is allowed to remove. This is real enforcement,
  // not just hiding the menu item.
  Future<void> _removeMember(Map<String, dynamic> member) async {
    final user = member['users'];
    final displayName = user?['display_name'] ?? user?['username'] ?? 'this member';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Remove $displayName?', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'They will be removed from this community and will need to rejoin to participate again.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _communityService.removeCommunityMember(
        communityId: widget.community['id'],
        userId: member['user_id'],
      );
      if (mounted) {
        setState(() => _allMembers.removeWhere((m) => m['id'] == member['id']));
        _showSnackbar('$displayName removed from community');
      }
    } catch (e) {
      final message = e.toString();
      String displayMessage;
      if (message.contains('not_authorized')) {
        displayMessage = 'You don\'t have permission to remove this member';
      } else if (message.contains('cannot_remove_creator')) {
        displayMessage = 'The creator can\'t be removed — transfer ownership first';
      } else {
        displayMessage = 'Failed to remove member';
      }
      if (mounted) _showSnackbar(displayMessage, isError: true);
    }
  }

  // ── PROMOTE TO CO-ADMIN ────────────────────────────────────
  // RPC-backed via CommunityService.updateCommunityMemberRole —
  // the server verifies the caller is the admin (creator) and
  // blocks promoting a permanently restricted (three-strikes) user.
  Future<void> _promoteToCoAdmin(Map<String, dynamic> member) async {
    try {
      await _communityService.updateCommunityMemberRole(
        communityId: widget.community['id'],
        userId: member['user_id'],
        newRole: 'co-admin',
      );
      if (mounted) {
        _showSnackbar('Promoted to co-admin');
        await _loadAllMembers();
      }
    } catch (e) {
      final message = e.toString();
      if (message.contains('target_is_restricted')) {
        if (mounted) await _showRestrictedDialog();
        return;
      }
      final displayMessage = message.contains('not_authorized')
          ? 'Only the creator can promote members'
          : 'Failed to promote member';
      if (mounted) _showSnackbar(displayMessage, isError: true);
    }
  }

  // ── RESTRICTED USER DIALOG ──────────────────────────────────
  Future<void> _showRestrictedDialog() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Unable to promote',
            style: TextStyle(color: Colors.white)),
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

  // ── DEMOTE TO MEMBER ───────────────────────────────────────
  // RPC-backed via CommunityService.updateCommunityMemberRole —
  // the server verifies the caller is the admin (creator).
  Future<void> _demoteToMember(Map<String, dynamic> member) async {
    try {
      await _communityService.updateCommunityMemberRole(
        communityId: widget.community['id'],
        userId: member['user_id'],
        newRole: 'member',
      );
      if (mounted) {
        _showSnackbar('Removed as co-admin');
        await _loadAllMembers();
      }
    } catch (e) {
      final message = e.toString();
      final displayMessage = message.contains('not_authorized')
          ? 'Only the creator can demote co-admins'
          : 'Failed to update member';
      if (mounted) _showSnackbar(displayMessage, isError: true);
    }
  }

  // ── TRANSFER OWNERSHIP ─────────────────────────────────────
  Future<void> _transferOwnership(Map<String, dynamic> member) async {
    final user = member['users'];
    final displayName = user?['display_name'] ?? user?['username'] ?? 'this member';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Transfer ownership to $displayName?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          '$displayName will become the new creator of this community with full admin rights, including the ability to delete it. You will become a co-admin and lose creator privileges. This cannot be undone by you alone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Transfer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _communityService.transferCommunityOwnership(
        communityId: widget.community['id'],
        newOwnerId: member['user_id'],
      );

      final downgraded = result['downgraded_to_public'] == true;

      if (mounted) {
        _showSnackbar(downgraded
            ? 'Ownership transferred to $displayName. Since they don\'t have Pro, this community was switched to public.'
            : 'Ownership transferred to $displayName');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      final message = e.toString();
      if (message.contains('new_owner_is_restricted')) {
        if (mounted) await _showRestrictedDialog();
        return;
      }
      String displayMessage;
      if (message.contains('not_authorized')) {
        displayMessage = 'Only the creator can transfer ownership';
      } else if (message.contains('new_owner_not_a_member')) {
        displayMessage = 'That user must already be a member';
      } else {
        displayMessage = 'Failed to transfer ownership';
      }
      if (mounted) _showSnackbar(displayMessage, isError: true);
    }
  }

  // ── ROLE ACTION MENU ───────────────────────────────────────
  void _showMemberActions(Map<String, dynamic> member) {
    final user = member['users'];
    final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown';
    final role = member['role'] as String? ?? 'member';
    final isCreatorMember = member['user_id'] == widget.community['created_by'];

    if (isCreatorMember) return;

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
            Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(displayName,
                  style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            // Promote/demote are admin-only (creator-only) actions —
            // the RPC enforces this server-side, but we also only show
            // these options to the creator in the UI to avoid a
            // confusing "not_authorized" error on tap for a co-admin.
            if (widget.isCreator && role == 'member')
              ListTile(
                leading: const Icon(Icons.shield_outlined, color: Colors.white),
                title: const Text('Make co-admin', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _promoteToCoAdmin(member);
                },
              ),
            if (widget.isCreator && role == 'co-admin')
              ListTile(
                leading: const Icon(Icons.remove_moderator_outlined, color: Colors.orange),
                title: const Text('Remove as co-admin', style: TextStyle(color: Colors.orange)),
                onTap: () {
                  Navigator.pop(context);
                  _demoteToMember(member);
                },
              ),
            if (widget.isCreator)
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.red),
                title: const Text('Transfer ownership', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _transferOwnership(member);
                },
              ),
            // Remove from community is available to admin AND co-admin,
            // but the RPC server-side restricts co-admins to removing
            // only plain members, not other co-admins.
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: Colors.grey),
              title: const Text('Remove from community', style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                _removeMember(member);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    if (_bookRequired && _selectedBook == null) {
      _showSnackbar('Please select a book', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _communityService.updateCommunity(
        communityId: widget.community['id'],
        name: _nameController.text.trim(),
        book: _selectedBook,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        isPrivate: _isPrivate,
      );
      if (mounted) {
        _showSnackbar('Settings saved');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) _showSnackbar('Failed to save settings', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── ADD MEMBER TO PRIVATE SUB-GROUP BY USERNAME ────────────
  Future<void> _addMemberByUsername() async {
    final username = _addMemberController.text.trim();
    if (username.isEmpty) return;

    try {
      await _communityService.addMemberToPrivateCommunity(
        communityId: widget.community['id'],
        username: username,
      );
      _addMemberController.clear();
      await _loadAllMembers();
      if (mounted) _showSnackbar('@$username added to the group');
    } catch (e) {
      final message = e.toString();
      String displayMessage;
      if (message.contains('not_authorized')) {
        displayMessage = 'Only admins can add members';
      } else if (message.contains('user_not_found')) {
        displayMessage = 'User not found';
      } else if (message.contains('not_church_member')) {
        displayMessage = 'That user must follow the church first';
      } else {
        displayMessage = 'Failed to add member';
      }
      if (mounted) _showSnackbar(displayMessage, isError: true);
    }
  }

  Future<void> _deleteCommunity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete community?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently delete "${widget.community['name']}" and all its posts and replies. This cannot be undone.',
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
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _communityService.deleteCommunity(widget.community['id']);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        _showSnackbar('Community deleted');
      }
    } catch (e) {
      if (mounted) _showSnackbar('Failed to delete community', isError: true);
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
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Community Settings',
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
                    // ── GENERAL SETTINGS ──────────────────
                    _sectionLabel('General'),
                    const SizedBox(height: 12),

                    _buildLabel('Community Name', required: true),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Community name'),
                      validator: (val) =>
                          val == null || val.trim().isEmpty
                              ? 'Please enter a name'
                              : null,
                    ),

                    const SizedBox(height: 16),

                    _buildLabel('Description', required: false),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: _inputDecoration('Description (optional)'),
                    ),

                    const SizedBox(height: 16),

                    if (_bookRequired) ...[
                      _buildLabel('Book', required: true),
                      const SizedBox(height: 8),
                      _dropdown<String>(
                        value: _selectedBook,
                        hint: 'Select a book',
                        items: _books
                            .map((b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(b),
                                ))
                            .toList(),
                        onChanged: (val) => setState(() => _selectedBook = val),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Members reference a specific chapter when they post',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                    ] else if (_isChurchCommunity) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.grey, size: 16),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'This is a general church channel, not a Bible study community — no book or chapter required.',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Private toggle — for church communities this
                    // restricts the sub-group to QR/admin-add only
                    // (free). For non-church communities this is
                    // still the Pro-gated paywall feature.
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              color: Colors.grey, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isChurchCommunity ? 'Restrict this group' : 'Private community',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  _isChurchCommunity
                                      ? 'Only people who scan a QR code or are added by an admin can join'
                                      : 'Only invited members can join — Pro feature',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isPrivate,
                            onChanged: (val) async {
                              if (_isChurchCommunity) {
                                setState(() => _isPrivate = val);
                                return;
                              }
                              if (val) {
                                final isPro = await SubscriptionService().isPro();
                                if (isPro) {
                                  setState(() => _isPrivate = true);
                                } else {
                                  if (mounted) {
                                    final upgraded = await UpgradeSheet.show(context);
                                    if (upgraded == true && mounted) {
                                      setState(() => _isPrivate = true);
                                    }
                                  }
                                }
                              } else {
                                setState(() => _isPrivate = false);
                              }
                            },
                            activeColor: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── ADD MEMBER BY USERNAME (private church
                    // sub-groups only) ──────────────────────────
                    // Lets an admin add a specific church follower
                    // directly, without requiring a QR scan.
                    if (_isPrivate) ...[
                      _sectionLabel('Add Member'),
                      const SizedBox(height: 4),
                      const Text(
                        'Add someone directly by username, without requiring a QR scan.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _addMemberController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration('@username'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _addMemberByUsername,
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
                      const SizedBox(height: 16),
                    ],

                    const SizedBox(height: 16),

                    // ── MEMBERS ────────────────────────────
                    // This single list now covers everyone, including
                    // co-admins — there's no separate co-admins section
                    // anymore. Tap any non-creator member (if you're the
                    // creator or co-admin) to manage them via the action
                    // sheet, which calls the RPC-backed service methods
                    // above. Promote/demote/transfer only appear for the
                    // creator; remove-from-community is available to
                    // co-admins too (server-side limited to plain members).
                    _sectionLabel('Members'),
                    const SizedBox(height: 4),
                    const Text(
                      'View and manage everyone in this community.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    if (_isLoadingMembers)
                      const Center(child: CircularProgressIndicator(color: Colors.white))
                    else if (_allMembers.isEmpty)
                      const Text('No members yet', style: TextStyle(color: Colors.grey))
                    else
                      ..._allMembers.map((member) {
                        final user = member['users'];
                        final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown';
                        final username = user?['username'] ?? '';
                        final role = member['role'] as String? ?? 'member';
                        final isCurrentUser = member['user_id'] == currentUserId;
                        final isCreatorMember = member['user_id'] == widget.community['created_by'];
                        final canManage = (widget.isCreator || role == 'co-admin') &&
                            !isCurrentUser &&
                            !isCreatorMember;

                        String roleLabel;
                        Color roleColor;
                        if (isCreatorMember) {
                          roleLabel = 'Creator';
                          roleColor = Colors.amber;
                        } else if (role == 'co-admin') {
                          roleLabel = 'Co-admin';
                          roleColor = Colors.blueAccent;
                        } else {
                          roleLabel = 'Member';
                          roleColor = Colors.grey;
                        }

                        return GestureDetector(
                          onTap: canManage ? () => _showMemberActions(member) : null,
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
                                if (canManage)
                                  const Icon(Icons.more_vert, color: Colors.grey, size: 18),
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
                          onPressed: _deleteCommunity,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Delete Community',
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

  Widget _buildLabel(String text, {required bool required}) {
    return RichText(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500),
        children: required
            ? const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ]
            : null,
      ),
    );
  }

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: const TextStyle(color: Colors.grey)),
          dropdownColor: const Color(0xFF1A1A1A),
          isExpanded: true,
          style: const TextStyle(color: Colors.white),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
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
        borderSide: const BorderSide(color: Colors.white, width: 1),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}