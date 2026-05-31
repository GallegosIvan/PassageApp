import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/church_service.dart';

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
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  late final TextEditingController _websiteController;
  late bool _isPrivate;
  final _coAdminController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  List<Map<String, dynamic>> _coAdmins = [];
  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _filteredFollowers = [];
  bool _showFollowerSuggestions = false;

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
    _loadFollowers();
    _coAdminController.addListener(() {
      final query = _coAdminController.text.toLowerCase().trim();
      setState(() {
        if (query.isEmpty) {
          _showFollowerSuggestions = false;
          _filteredFollowers = [];
        } else {
          _showFollowerSuggestions = true;
          _filteredFollowers = _followers.where((f) {
            final username = (f['username'] as String? ?? '').toLowerCase();
            final displayName = (f['display_name'] as String? ?? '').toLowerCase();
            return username.contains(query) || displayName.contains(query);
          }).toList();
        }
      });
    });
    _isPrivate = widget.church['is_private'] ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    _coAdminController.dispose();
    super.dispose();
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

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    // If trying to save as private, verify the creator has a paid plan
    if (_isPrivate) {
      final creatorId = widget.church['created_by'] as String;
      final creatorIsPaid = await _churchService.isUserPaid(creatorId);
      if (!creatorIsPaid) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text('Upgrade required',
                  style: TextStyle(color: Colors.white)),
              content: const Text(
                'The church owner must have an active Pro subscription to make this church private.',
                style: TextStyle(color: Colors.grey),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      // API CALL: ChurchService.updateChurch → Supabase DB
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

  Future<void> _loadFollowers() async {
    try {
      // API CALL: Supabase DB — get all church followers with user info
      final response = await Supabase.instance.client
          .from('church_followers')
          .select('user_id, users(username, display_name)')
          .eq('church_id', widget.church['id']);

      if (mounted) {
        setState(() {
          _followers = List<Map<String, dynamic>>.from(
            response.map((f) => {
              'user_id': f['user_id'],
              ...Map<String, dynamic>.from(f['users'] ?? {}),
            }),
          );
        });
      }
    } catch (e) {
      print('loadFollowers error: $e');
    }
  }

  Future<void> _addCoAdmin() async {
    final username = _coAdminController.text.trim();
    if (username.isEmpty) return;

    try {
      // API CALL: ChurchService.addChurchCoAdmin → Supabase DB
      await _churchService.addChurchCoAdmin(
        churchId: widget.church['id'],
        username: username,
      );
      _coAdminController.clear();
      await _loadCoAdmins();
      if (mounted) _showSnackbar('@$username is now a co-admin');
    } catch (e) {
      if (mounted) {
        _showSnackbar(
            e.toString().replaceAll('Exception: ', ''),
            isError: true);
      }
    }
  }

  Future<void> _removeCoAdmin(String memberId) async {
    try {
      // API CALL: ChurchService.removeChurchCoAdmin → Supabase DB
      await _churchService.removeChurchCoAdmin(memberId);
      await _loadCoAdmins();
      if (mounted) _showSnackbar('Co-admin removed');
    } catch (e) {
      if (mounted) _showSnackbar('Failed to remove co-admin', isError: true);
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

    return Scaffold(
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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline, color: Colors.grey, size: 20),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Private church',
                                    style: TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.w500)),
                                Text('Only people with the invite link can join',
                                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isPrivate,
                            onChanged: (val) async {
                              if (val) {
                                final isPaid = await ChurchService().isPaidUser();
                                if (isPaid) {
                                  setState(() => _isPrivate = true);
                                } else {
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      backgroundColor: const Color(0xFF1A1A1A),
                                      title: const Text('Upgrade to Pro',
                                          style: TextStyle(color: Colors.white)),
                                      content: const Text(
                                        'Private churches are a Pro feature.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('OK',
                                              style: TextStyle(color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                  );
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
                      'Co-admins can post and delete announcements.',
                      style:
                          TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    if (widget.isCreator) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _coAdminController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _inputDecoration('@username or name'),
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
                          if (_showFollowerSuggestions && _filteredFollowers.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.1)),
                              ),
                              child: Column(
                                children: _filteredFollowers.take(5).map((f) {
                                  final username = f['username'] as String? ?? '';
                                  final displayName =
                                      f['display_name'] as String? ?? username;
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
                                      _coAdminController.text = username;
                                      setState(() => _showFollowerSuggestions = false);
                                      _addCoAdmin();
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (_coAdmins.isEmpty)
                      const Text('No co-admins yet',
                          style: TextStyle(color: Colors.grey))
                    else
                      ..._coAdmins.map((member) {
                        final user = member['users'];
                        final displayName =
                            user?['display_name'] ??
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
                                            fontWeight:
                                                FontWeight.w500)),
                                    Text('@$username',
                                        style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (widget.isCreator && !isCurrentUser)
                                GestureDetector(
                                  onTap: () =>
                                      _removeCoAdmin(member['id']),
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