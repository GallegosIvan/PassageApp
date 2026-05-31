import 'package:flutter/material.dart';
import '../../services/community_service.dart';
import '../../services/bible_interaction_service.dart';


class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _communityService = CommunityService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _interactionService = BibleInteractionService();

  String? _selectedBook;
  int? _selectedChapter;
  bool _isPrivate = false;
  bool _isLoading = false;

  // Full list of Bible books with chapter counts
  final List<Map<String, dynamic>> _books = [
    {'name': 'Genesis', 'chapters': 50},
    {'name': 'Exodus', 'chapters': 40},
    {'name': 'Leviticus', 'chapters': 27},
    {'name': 'Numbers', 'chapters': 36},
    {'name': 'Deuteronomy', 'chapters': 34},
    {'name': 'Joshua', 'chapters': 24},
    {'name': 'Judges', 'chapters': 21},
    {'name': 'Ruth', 'chapters': 4},
    {'name': '1 Samuel', 'chapters': 31},
    {'name': '2 Samuel', 'chapters': 24},
    {'name': '1 Kings', 'chapters': 22},
    {'name': '2 Kings', 'chapters': 25},
    {'name': '1 Chronicles', 'chapters': 29},
    {'name': '2 Chronicles', 'chapters': 36},
    {'name': 'Ezra', 'chapters': 10},
    {'name': 'Nehemiah', 'chapters': 13},
    {'name': 'Esther', 'chapters': 10},
    {'name': 'Job', 'chapters': 42},
    {'name': 'Psalms', 'chapters': 150},
    {'name': 'Proverbs', 'chapters': 31},
    {'name': 'Ecclesiastes', 'chapters': 12},
    {'name': 'Song of Solomon', 'chapters': 8},
    {'name': 'Isaiah', 'chapters': 66},
    {'name': 'Jeremiah', 'chapters': 52},
    {'name': 'Lamentations', 'chapters': 5},
    {'name': 'Ezekiel', 'chapters': 48},
    {'name': 'Daniel', 'chapters': 12},
    {'name': 'Hosea', 'chapters': 14},
    {'name': 'Joel', 'chapters': 3},
    {'name': 'Amos', 'chapters': 9},
    {'name': 'Obadiah', 'chapters': 1},
    {'name': 'Jonah', 'chapters': 4},
    {'name': 'Micah', 'chapters': 7},
    {'name': 'Nahum', 'chapters': 3},
    {'name': 'Habakkuk', 'chapters': 3},
    {'name': 'Zephaniah', 'chapters': 3},
    {'name': 'Haggai', 'chapters': 2},
    {'name': 'Zechariah', 'chapters': 14},
    {'name': 'Malachi', 'chapters': 4},
    {'name': 'Matthew', 'chapters': 28},
    {'name': 'Mark', 'chapters': 16},
    {'name': 'Luke', 'chapters': 24},
    {'name': 'John', 'chapters': 21},
    {'name': 'Acts', 'chapters': 28},
    {'name': 'Romans', 'chapters': 16},
    {'name': '1 Corinthians', 'chapters': 16},
    {'name': '2 Corinthians', 'chapters': 13},
    {'name': 'Galatians', 'chapters': 6},
    {'name': 'Ephesians', 'chapters': 6},
    {'name': 'Philippians', 'chapters': 4},
    {'name': 'Colossians', 'chapters': 4},
    {'name': '1 Thessalonians', 'chapters': 5},
    {'name': '2 Thessalonians', 'chapters': 3},
    {'name': '1 Timothy', 'chapters': 6},
    {'name': '2 Timothy', 'chapters': 4},
    {'name': 'Titus', 'chapters': 3},
    {'name': 'Philemon', 'chapters': 1},
    {'name': 'Hebrews', 'chapters': 13},
    {'name': 'James', 'chapters': 5},
    {'name': '1 Peter', 'chapters': 5},
    {'name': '2 Peter', 'chapters': 3},
    {'name': '1 John', 'chapters': 5},
    {'name': '2 John', 'chapters': 1},
    {'name': '3 John', 'chapters': 1},
    {'name': 'Jude', 'chapters': 1},
    {'name': 'Revelation', 'chapters': 22},
  ];

  int _chapterCount() {
    if (_selectedBook == null) return 0;
    return _books.firstWhere(
        (b) => b['name'] == _selectedBook)['chapters'] as int;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    // VALIDATION: check all fields
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBook == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a book'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selectedChapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a chapter'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // API CALL: CommunityService.createCommunity → Supabase DB
      await _communityService.createCommunity(
        name: _nameController.text.trim(),
        book: _selectedBook!,
        chapter: _selectedChapter!,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        isPrivate: _isPrivate,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Community created!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create community: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Create Community',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── NAME ──────────────────────────────────────
              _buildLabel('Community Name'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('e.g. John 3 Study Group'),
                // VALIDATION: must not be empty
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Please enter a name'
                    : null,
              ),

              const SizedBox(height: 20),

              // ── DESCRIPTION ───────────────────────────────
              _buildLabel('Description (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: _inputDecoration(
                    'What is this community about?'),
              ),

              const SizedBox(height: 20),

              // ── BOOK PICKER ───────────────────────────────
              _buildLabel('Book'),
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
                              value: b['name'] as String,
                              child: Text(b['name'] as String),
                            ))
                        .toList(),
                    onChanged: (val) => setState(() {
                      _selectedBook = val;
                      _selectedChapter = null;
                    }),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── CHAPTER PICKER ────────────────────────────
              _buildLabel('Chapter'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedChapter,
                    hint: Text(
                      _selectedBook == null
                          ? 'Select a book first'
                          : 'Select a chapter',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    dropdownColor: const Color(0xFF1A1A1A),
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white),
                    items: _selectedBook == null
                        ? []
                        : List.generate(
                            _chapterCount(),
                            (i) => DropdownMenuItem<int>(
                              value: i + 1,
                              child: Text('Chapter ${i + 1}'),
                            ),
                          ),
                    onChanged: _selectedBook == null
                        ? null
                        : (val) => setState(() => _selectedChapter = val),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── PRIVATE TOGGLE ────────────────────────────
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Private community',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500)),
                          Text('Only invited members can join',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isPrivate,
                      onChanged: (val) async {
                        if (val) {
                          final isPaid = await _interactionService.isPaidUser();
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
                                  'Private communities are a Pro feature. Upgrade to create private groups for your church or study group.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Maybe later',
                                        style: TextStyle(color: Colors.grey)),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                    ),
                                    child: const Text('Upgrade'),
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

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500),
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
        borderSide:
            const BorderSide(color: Colors.white, width: 1),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}