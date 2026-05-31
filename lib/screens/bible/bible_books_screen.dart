import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/bible_service.dart';
import '../../services/bible_interaction_service.dart';
import 'bible_chapters_screen.dart';

class BibleBooksScreen extends StatefulWidget {
  const BibleBooksScreen({super.key});

  @override
  State<BibleBooksScreen> createState() => _BibleBooksScreenState();
}

class _BibleBooksScreenState extends State<BibleBooksScreen> {
  final _bibleService = BibleService();
  final _interactionService = BibleInteractionService();

  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _filteredBooks = [];
  List<Map<String, dynamic>> _translations = [];
  String _translationId = 'BSB';
  List<Map<String, dynamic>> _bookmarks = [];
  final colorMap = {
    'purple': Colors.white,
    'blue': Colors.blue,
    'green': Colors.green,
  };
  bool _isLoading = true;
  bool _isLoadingTranslations = false;
  String? _error;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterBooks);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBookmarks();
    if (_books.isEmpty) _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String translationId = 'BSB';
      try {
        translationId = await _bibleService.getUserTranslationId();
      } catch (e) {
        print('Translation fallback: $e');
      }

      if (!mounted) return;
      final books = await _bibleService.getBooks(translationId);

      if (!mounted) return;
      final bookmarks = await _interactionService.getBookmarks();

      if (!mounted) return;
      setState(() {
        _translationId = translationId;
        _books = books;
        _filteredBooks = books;
        _bookmarks = bookmarks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBookmarks() async {
    final bookmarks = await _interactionService.getBookmarks();
    if (mounted) setState(() => _bookmarks = bookmarks);
  }

  void _filterBooks() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredBooks = query.isEmpty
          ? _books
          : _books
              .where((b) =>
                  (b['name'] as String).toLowerCase().contains(query))
              .toList();
    });
  }

  // ── TRANSLATION PICKER ────────────────────────────────────
  Future<void> _showTranslationPicker() async {
    // API CALL: Free Use Bible API — fetch all available translations
    if (_translations.isEmpty) {
      setState(() => _isLoadingTranslations = true);
      try {
        final response = await http.get(
          Uri.parse(
              'https://bible.helloao.org/api/available_translations.json'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          _translations =
              List<Map<String, dynamic>>.from(data['translations']);
        }
      } catch (e) {
        print('Failed to load translations: $e');
      }
      setState(() => _isLoadingTranslations = false);
    }

    if (!mounted) return;

    // Show translation picker bottom sheet
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TranslationPickerSheet(
        translations: _translations,
        currentId: _translationId,
      ),
    );

    if (selected == null) return;
    final newId = selected['id'] as String;
    if (newId == _translationId) return;

    // Ask if user wants this as preferred translation
    if (!mounted) return;
    final setAsPreferred = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Set as preferred?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Do you want ${selected['name']} to be your default translation every time you open the app?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Just this session',
                style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white24,
            ),
            child: const Text('Set as preferred',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (setAsPreferred == true) {
      // API CALL: BibleService.setUserTranslationId → Supabase DB
      await _bibleService.setUserTranslationId(newId);
    }

    // Reload books with new translation
    setState(() {
      _translationId = newId;
      _isLoading = true;
    });

    try {
      final books = await _bibleService.getBooks(newId);
      setState(() {
        _books = books;
        _filteredBooks = books;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load books for this translation.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Bible',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Translation picker button
          GestureDetector(
            onTap: _isLoadingTranslations ? null : _showTranslationPicker,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withOpacity(0.24)),
              ),
              child: _isLoadingTranslations
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Row(
                      children: [
                        Text(
                          _translationId,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down,
                              color: Colors.white, size: 18),
                      ],
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── BOOKMARK BANNER ───────────────────────────────
          if (_bookmarks.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: _bookmarks.map((bookmark) {
                  final colorMap = {
                    'purple': Colors.white,
                    'blue': Colors.blue,
                    'green': Colors.green,
                  };
                  final color = colorMap[bookmark['color']] ?? Colors.white;
                  return GestureDetector(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BibleChaptersScreen(
                            translationId: _translationId,
                            book: _books.firstWhere(
                              (b) => b['id'] == bookmark['book_id'],
                              orElse: () => {
                                'id': bookmark['book_id'],
                                'name': bookmark['book_name'],
                                'numberOfChapters': 50,
                              },
                            ),
                          ),
                        ),
                      );
                      _loadData();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bookmark, color: color, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${bookmark['book_name']} ${bookmark['chapter']}',
                            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          // ── SEARCH BAR ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search books...',
                hintStyle: const TextStyle(color: Colors.white),
                prefixIcon: const Icon(Icons.search,
                  color: Colors.white),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // ── BOOKS LIST ────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white))
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style:
                                const TextStyle(color: Colors.red)))
                    : ListView.builder(
                        itemCount: _filteredBooks.length,
                        itemBuilder: (context, index) {
                          final book = _filteredBooks[index];
                          final isBookmarked =
                              _bookmarks.any((b) => b['book_id'] == book['id']);

                          return ListTile(
                            title: Text(
                              book['name'] ?? '',
                              style:
                                  const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              '${book['numberOfChapters']} chapters',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12),
                            ),
                            leading: _bookmarks.any((b) => b['book_id'] == book['id'])
                              ? Icon(
                                  Icons.bookmark,
                                  color: colorMap[_bookmarks.firstWhere(
                                      (b) => b['book_id'] == book['id'])['color']] ??
                                      Colors.white,
                                  size: 20,
                                )
                              : null,
                            trailing: const Icon(Icons.chevron_right,
                              color: Colors.white),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BibleChaptersScreen(
                                    translationId: _translationId,
                                    book: book,
                                  ),
                                ),
                              );
                              _loadData();
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TRANSLATION PICKER SHEET
// ============================================================

class _TranslationPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> translations;
  final String currentId;

  const _TranslationPickerSheet({
    required this.translations,
    required this.currentId,
  });

  @override
  State<_TranslationPickerSheet> createState() =>
      _TranslationPickerSheetState();
}

class _TranslationPickerSheetState
    extends State<_TranslationPickerSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.translations;
    _searchController.addListener(_filter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.translations
          : widget.translations
              .where((t) =>
                  (t['englishName'] as String? ?? '')
                      .toLowerCase()
                      .contains(q) ||
                  (t['id'] as String? ?? '')
                      .toLowerCase()
                      .contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Translation',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search translations...',
                hintStyle:
                  const TextStyle(color: Colors.white),
                prefixIcon: const Icon(Icons.search,
                  color: Colors.white),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                final t = _filtered[index];
                final id = t['id'] as String? ?? '';
                final name = t['englishName'] as String? ?? id;
                final language =
                    t['languageEnglishName'] as String? ?? '';
                final isCurrent = id == widget.currentId;

                return ListTile(
                  title: Text(
                    name,
                    style: TextStyle(
                      color:
                          isCurrent ? Colors.white : Colors.white70,
                      fontWeight: isCurrent
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '$id • $language',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 12),
                  ),
                  trailing: isCurrent
                      ? const Icon(Icons.check,
                          color: Colors.white)
                      : null,
                  onTap: () => Navigator.pop(context, t),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}