import 'package:flutter/material.dart';
import '../../services/community_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/upgrade_sheet.dart';

class CreateCommunityScreen extends StatefulWidget {
  final String? churchId; // if set, creates a church-only community

  const CreateCommunityScreen({super.key, this.churchId});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _communityService = CommunityService();
  final _subscriptionService = SubscriptionService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedBook;
  bool _isPrivate = false;
  bool _isBibleStudy = false; // church-only toggle
  bool _isLoading = false;

  bool get _isChurchCommunity => widget.churchId != null;

  // Book is required for: every non-church community, and for
  // church communities explicitly marked as Bible study.
  bool get _bookRequired => !_isChurchCommunity || _isBibleStudy;

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
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    if (_bookRequired && _selectedBook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a book'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _communityService.createCommunity(
        name: _nameController.text.trim(),
        book: _selectedBook,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        isPrivate: _isPrivate,
        churchId: widget.churchId,
        isBibleStudy: _isChurchCommunity ? _isBibleStudy : false,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Community created!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString();
        if (message.contains('private_limit_reached')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'You\'ve reached the limit of 5 private communities on the Pro plan.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (message.contains('paid_required')) {
          setState(() => _isLoading = false);
          await UpgradeSheet.show(context);
          return;
        } else if (message.contains('book_required')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a book'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create community: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onPrivateToggled(bool val) async {
    // Church sub-groups: privacy is free, no paywall — just a
    // restriction on who can join (QR scan or admin-add only).
    if (_isChurchCommunity) {
      setState(() => _isPrivate = val);
      return;
    }

    // Non-church communities: privacy is a Pro-gated feature,
    // same as before.
    if (val) {
      final isPro = await _subscriptionService.isPro();
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          _isChurchCommunity ? 'Create Church Community' : 'Create Community',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── CHURCH COMMUNITY NOTICE ───────────────────
              if (_isChurchCommunity) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.church_outlined,
                          color: Colors.grey, size: 18),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This community will only be visible to members of your church — it won\'t appear in Discover. It\'s free and doesn\'t count toward your private community limit.',
                          style:
                              TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ── NAME ──────────────────────────────────────
              _buildLabel('Community Name', required: true),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(_isChurchCommunity
                    ? 'e.g. Youth Group or John 3 Study'
                    : 'e.g. John 3 Study Group'),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Please enter a name'
                    : null,
              ),

              const SizedBox(height: 20),

              // ── DESCRIPTION ───────────────────────────────
              _buildLabel('Description', required: false),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration:
                    _inputDecoration('What is this community about?'),
              ),

              const SizedBox(height: 20),

              // ── BIBLE STUDY TOGGLE (church communities only) ──
              if (_isChurchCommunity) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book_outlined,
                          color: Colors.grey, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('This is a Bible study community',
                                style: TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.w500)),
                            Text('Turn on if this group studies a specific book of the Bible',
                                style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isBibleStudy,
                        onChanged: (val) => setState(() {
                          _isBibleStudy = val;
                          if (!val) _selectedBook = null;
                        }),
                        activeColor: Colors.white,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ── BOOK PICKER (only when required) ──────────
              if (_bookRequired) ...[
                _buildLabel('Book', required: true),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedBook,
                      hint: const Text('Select a book',
                          style: TextStyle(color: Colors.grey)),
                      dropdownColor: const Color(0xFF1A1A1A),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white),
                      items: _books
                          .map((b) => DropdownMenuItem<String>(
                                value: b,
                                child: Text(b),
                              ))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedBook = val),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isChurchCommunity
                      ? 'Members will reference a specific chapter when posting'
                      : 'Members will reference a specific chapter when posting — no need to make a new community per chapter',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 20),
              ],

              // ── PRIVATE TOGGLE ─────────────────────────────
              // For church communities: free sub-group restriction
              // (QR scan or admin-add to join). For non-church
              // communities: Pro-gated paywall feature, unchanged.
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
                      onChanged: _onPrivateToggled,
                      activeColor: Colors.white,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // ── CREATE BUTTON ─────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _create,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2))
                      : const Text('Create Community',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
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