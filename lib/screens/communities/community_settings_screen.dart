import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/community_service.dart';
import '../../services/bible_interaction_service.dart';

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
  final _interactionService = BibleInteractionService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final _coAdminController = TextEditingController();

  String? _selectedBook;
  int? _selectedChapter;
  bool _isPrivate = false;
  bool _isLoading = false;
  bool _isSaving = false;
  List<Map<String, dynamic>> _members = [];

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

  final Map<String, int> _chapterCounts = {
    'Genesis': 50, 'Exodus': 40, 'Leviticus': 27, 'Numbers': 36,
    'Deuteronomy': 34, 'Joshua': 24, 'Judges': 21, 'Ruth': 4,
    '1 Samuel': 31, '2 Samuel': 24, '1 Kings': 22, '2 Kings': 25,
    '1 Chronicles': 29, '2 Chronicles': 36, 'Ezra': 10, 'Nehemiah': 13,
    'Esther': 10, 'Job': 42, 'Psalms': 150, 'Proverbs': 31,
    'Ecclesiastes': 12, 'Song of Solomon': 8, 'Isaiah': 66,
    'Jeremiah': 52, 'Lamentations': 5, 'Ezekiel': 48, 'Daniel': 12,
    'Hosea': 14, 'Joel': 3, 'Amos': 9, 'Obadiah': 1, 'Jonah': 4,
    'Micah': 7, 'Nahum': 3, 'Habakkuk': 3, 'Zephaniah': 3,
    'Haggai': 2, 'Zechariah': 14, 'Malachi': 4, 'Matthew': 28,
    'Mark': 16, 'Luke': 24, 'John': 21, 'Acts': 28, 'Romans': 16,
    '1 Corinthians': 16, '2 Corinthians': 13, 'Galatians': 6,
    'Ephesians': 6, 'Philippians': 4, 'Colossians': 4,
    '1 Thessalonians': 5, '2 Thessalonians': 3, '1 Timothy': 6,
    '2 Timothy': 4, 'Titus': 3, 'Philemon': 1, 'Hebrews': 13,
    'James': 5, '1 Peter': 5, '2 Peter': 3, '1 John': 5,
    '2 John': 1, '3 John': 1, 'Jude': 1, 'Revelation': 22,
  };

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.community['name'] ?? '');
    _descriptionController =
        TextEditingController(text: widget.community['description'] ?? '');
    _selectedBook = widget.community['book'];
    _selectedChapter = widget.community['chapter'];
    _isPrivate = widget.community['is_private'] ?? false;
    _loadMembers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _coAdminController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    final members = await _communityService
        .getCommunityMembers(widget.community['id']);
    if (mounted) setState(() {
      _members = members;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBook == null || _selectedChapter == null) {
      _showSnackbar('Please select a book and chapter', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      // API CALL: CommunityService.updateCommunity → Supabase DB
      await _communityService.updateCommunity(
        communityId: widget.community['id'],
        name: _nameController.text.trim(),
        book: _selectedBook!,
        chapter: _selectedChapter!,
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

  Future<void> _addCoAdmin() async {
    final username = _coAdminController.text.trim();
    if (username.isEmpty) return;

    try {
      // API CALL: CommunityService.addCoAdmin → Supabase DB
      await _communityService.addCoAdmin(
        communityId: widget.community['id'],
        username: username,
      );
      _coAdminController.clear();
      await _loadMembers();
      if (mounted) _showSnackbar('@$username is now a co-admin');
    } catch (e) {
      if (mounted) _showSnackbar(e.toString().replaceAll('Exception: ', ''),
          isError: true);
    }
  }

  Future<void> _removeCoAdmin(Map<String, dynamic> member) async {
    try {
      // API CALL: CommunityService.removeCoAdmin → Supabase DB
      await _communityService.removeCoAdmin(
        communityId: widget.community['id'],
        memberId: member['id'],
      );
      await _loadMembers();
      if (mounted) _showSnackbar('Co-admin removed');
    } catch (e) {
      if (mounted) _showSnackbar('Failed to remove co-admin', isError: true);
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
      // API CALL: CommunityService.deleteCommunity → Supabase DB
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
    final coAdmins = _members
        .where((m) => m['role'] == 'co-admin')
        .toList();

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

                    _buildLabel('Community Name'),
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

                    _buildLabel('Description'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: _inputDecoration('Description (optional)'),
                    ),

                    const SizedBox(height: 16),

                    _buildLabel('Book'),
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
                      onChanged: (val) => setState(() {
                        _selectedBook = val;
                        _selectedChapter = null;
                      }),
                    ),

                    const SizedBox(height: 16),

                    _buildLabel('Chapter'),
                    const SizedBox(height: 8),
                    _dropdown<int>(
                      value: _selectedChapter,
                      hint: _selectedBook == null
                          ? 'Select a book first'
                          : 'Select a chapter',
                      items: _selectedBook == null
                          ? []
                          : List.generate(
                              _chapterCounts[_selectedBook] ?? 50,
                              (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text('Chapter ${i + 1}'),
                              ),
                            ),
                      onChanged: _selectedBook == null
                          ? null
                          : (val) =>
                              setState(() => _selectedChapter = val),
                    ),

                    const SizedBox(height: 16),

                    // Private toggle
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
                          const Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('Private community',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500)),
                                Text('Only invited members can join',
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isPrivate,
                            onChanged: (val) async {
                              if (val) {
                                final isPaid = await _interactionService
                                    .isPaidUser();
                                if (isPaid) {
                                  setState(() => _isPrivate = true);
                                } else {
                                  if (mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        backgroundColor:
                                            const Color(0xFF1A1A1A),
                                        title: const Text(
                                            'Upgrade to Pro',
                                            style: TextStyle(
                                                color: Colors.white)),
                                        content: const Text(
                                          'Private communities require a Pro subscription.',
                                          style: TextStyle(
                                              color: Colors.grey),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('OK',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
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

                    const SizedBox(height: 32),

                    // ── CO-ADMINS ─────────────────────────
                    _sectionLabel('Co-admins'),
                    const SizedBox(height: 4),
                    const Text(
                      'Co-admins can post announcements and manage the community.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    // Add co-admin
                    if (widget.isCreator) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _coAdminController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration('@username'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _addCoAdmin,
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
                      const SizedBox(height: 12),
                    ],

                    // Co-admin list
                    if (coAdmins.isEmpty)
                      const Text('No co-admins yet',
                          style: TextStyle(color: Colors.grey))
                    else
                      ...coAdmins.map((member) {
                        final user = member['users'];
                        final displayName = user?['display_name'] ??
                            user?['username'] ??
                            'Unknown';
                        final username = user?['username'] ?? '';
                        final isCurrentUser =
                            member['user_id'] == currentUserId;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person_outline,
                                  color: Colors.grey, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(displayName,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500)),
                                    Text('@$username',
                                        style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (widget.isCreator && !isCurrentUser)
                                GestureDetector(
                                  onTap: () => _removeCoAdmin(member),
                                  child: const Icon(Icons.close,
                                      color: Colors.grey, size: 18),
                                ),
                            ],
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

  Widget _buildLabel(String text) {
    return Text(text,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500));
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