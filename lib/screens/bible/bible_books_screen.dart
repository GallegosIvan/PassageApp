import 'package:flutter/material.dart';
import '../../services/bible_service.dart';
import '../../services/app_cache.dart';
import '../../services/bible_interaction_service.dart';
import 'bible_chapters_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BibleBooksScreen extends StatefulWidget {
  const BibleBooksScreen({super.key});

  @override
  State<BibleBooksScreen> createState() => _BibleBooksScreenState();
}

class _BibleBooksScreenState extends State<BibleBooksScreen> {
  final _bibleService = BibleService();
  final _interactionService = BibleInteractionService();
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _filteredBooks = [];
  List<Map<String, dynamic>> _translations = [];
  String _translationId = 'BSB';
  List<Map<String, dynamic>> _bookmarks = [];
  // Map of bookId -> number of chapters read
  Map<String, int> _readChapterCounts = {};
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

  bool _initialLoadDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBookmarks();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _loadData();
    } else {
      _refreshReadCounts();
    }
  }

  Future<void> _refreshReadCounts() async {
    if (!mounted) return;
    Map<String, int> readCounts;
    if (AppCache.instance.readChapters != null) {
      readCounts = {};
      for (final key in AppCache.instance.readChapters!) {
        final parts = key.split('_');
        if (parts.length == 2) {
          readCounts[parts[0]] = (readCounts[parts[0]] ?? 0) + 1;
        }
      }
    } else {
      readCounts = await _loadReadChapterCounts();
    }
    if (mounted) setState(() => _readChapterCounts = readCounts);
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
        if (AppCache.instance.preferredTranslation != null) {
          translationId = AppCache.instance.preferredTranslation!;
        } else {
          translationId = await _bibleService.getUserTranslationId();
          AppCache.instance.setPreferredTranslation(translationId);
        }
      } catch (e) {
        print('Translation fallback: $e');
      }

      if (!mounted) return;
      List<Map<String, dynamic>> books;
      final cachedBooks = AppCache.instance.getBooks(translationId);
      if (cachedBooks != null) {
        books = cachedBooks;
      } else {
        books = await _bibleService.getBooks(translationId);
        AppCache.instance.setBooks(translationId, books);
      }

      if (!mounted) return;
      final bookmarks = await _interactionService.getBookmarks();

      if (!mounted) return;
      Map<String, int> readCounts;
      if (AppCache.instance.readChapters != null) {
        // Build counts from cached read chapters
        readCounts = {};
        for (final key in AppCache.instance.readChapters!) {
          final parts = key.split('_');
          if (parts.length == 2) {
            readCounts[parts[0]] = (readCounts[parts[0]] ?? 0) + 1;
          }
        }
      } else {
        readCounts = await _loadReadChapterCounts();
      }

      if (!mounted) return;
      setState(() {
        _translationId = translationId;
        _books = books;
        _filteredBooks = books;
        _bookmarks = bookmarks;
        _readChapterCounts = readCounts;
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

  Future<Map<String, int>> _loadReadChapterCounts() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};
    try {
      final response = await _client
          .from('reading_history')
          .select('book_id')
          .eq('user_id', userId);
      final counts = <String, int>{};
      for (final row in response as List) {
        final bookId = row['book_id'] as String;
        counts[bookId] = (counts[bookId] ?? 0) + 1;
      }
      return counts;
    } catch (e) {
      print('loadReadChapterCounts error: $e');
      return {};
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

  bool _isBookFullyRead(Map<String, dynamic> book) {
    final bookId = book['id'] as String;
    final totalChapters = book['numberOfChapters'] as int;
    final readCount = _readChapterCounts[bookId] ?? 0;
    return readCount >= totalChapters;
  }

  // ── SHOW TRANSLATION PICKER ────────────────────────────────
  // Uses BibleService.getAvailableTranslations(), which filters
  // to complete 66-book Bibles only — no NT-only or partial
  // translations. Previously this fetched the unfiltered list
  // directly from the HelloAO API, which is why the picker was
  // still showing all 1000+ translations despite the filter
  // being added to the service. Now there's a single source of
  // truth for "what counts as a selectable translation."
  Future<void> _showTranslationPicker() async {
    if (_translations.isEmpty) {
      if (AppCache.instance.bibleTranslations != null) {
        _translations = AppCache.instance.bibleTranslations!;
      } else {
        setState(() => _isLoadingTranslations = true);
        try {
          _translations = await _bibleService.getAvailableTranslations();
          AppCache.instance.setBibleTranslations(_translations);
        } catch (e) {
          print('Failed to load translations: $e');
        }
        setState(() => _isLoadingTranslations = false);
      }
    }

    if (!mounted) return;

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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white24),
            child: const Text('Set as preferred',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (setAsPreferred == true) {
      await _bibleService.setUserTranslationId(newId);
      AppCache.instance.setPreferredTranslation(newId);
    } else {
      // Session only — update cache so returning to this screen keeps the choice
      AppCache.instance.setPreferredTranslation(newId);
    }

    AppCache.instance.invalidateBooks(newId);

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
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          GestureDetector(
            onTap: _isLoadingTranslations ? null : _showTranslationPicker,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.24)),
              ),
              child: _isLoadingTranslations
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Row(children: [
                      Text(_translationId,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down,
                          color: Colors.white, size: 18),
                    ]),
            ),
          ),
        ],
      ),
      body: Column(children: [
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withOpacity(0.5)),
                    ),
                    child: Row(children: [
                      Icon(Icons.bookmark, color: color, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${bookmark['book_name']} ${bookmark['chapter']}',
                        style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ]),
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
              prefixIcon: const Icon(Icons.search, color: Colors.white),
              filled: true,
              fillColor: Colors.black,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),

        // ── BOOKS LIST ────────────────────────────────────
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)))
                  : ListView.builder(
                      itemCount: _filteredBooks.length,
                      itemBuilder: (context, index) {
                        final book = _filteredBooks[index];
                        final bookId = book['id'] as String;
                        final isBookmarked =
                            _bookmarks.any((b) => b['book_id'] == bookId);
                        final isFullyRead = _isBookFullyRead(book);
                        final readCount =
                            _readChapterCounts[bookId] ?? 0;
                        final totalChapters =
                            book['numberOfChapters'] as int;

                        return ListTile(
                          title: Text(
                            book['name'] ?? '',
                            style: TextStyle(
                              color: isFullyRead
                                  ? Colors.green
                                  : Colors.white,
                              fontWeight: isFullyRead
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            isFullyRead
                                ? 'Completed ✓'
                                : readCount > 0
                                    ? '$readCount/$totalChapters chapters read'
                                    : '$totalChapters chapters',
                            style: TextStyle(
                              color: isFullyRead
                                  ? Colors.green.withOpacity(0.7)
                                  : readCount > 0
                                      ? Colors.white70
                                      : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          leading: isFullyRead
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green, size: 20)
                              : isBookmarked
                                  ? Icon(
                                      Icons.bookmark,
                                      color: colorMap[_bookmarks.firstWhere(
                                              (b) => b['book_id'] == bookId)[
                                          'color']] ??
                                          Colors.white,
                                      size: 20,
                                    )
                                  : readCount > 0
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            value: readCount / totalChapters,
                                            strokeWidth: 2.5,
                                            backgroundColor:
                                                Colors.white12,
                                            valueColor:
                                                const AlwaysStoppedAnimation<
                                                    Color>(Colors.green),
                                          ),
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
      ]),
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

class _TranslationPickerSheetState extends State<_TranslationPickerSheet> {
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
                  (t['id'] as String? ?? '').toLowerCase().contains(q))
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
      builder: (_, scrollController) => Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 16),
        const Text('Select Translation',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search translations...',
              hintStyle: const TextStyle(color: Colors.white),
              prefixIcon: const Icon(Icons.search, color: Colors.white),
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
              final language = t['languageEnglishName'] as String? ?? '';
              final isCurrent = id == widget.currentId;
              return ListTile(
                title: Text(name,
                    style: TextStyle(
                        color: isCurrent ? Colors.white : Colors.white70,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal)),
                subtitle: Text('$id • $language',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                trailing: isCurrent
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
                onTap: () => Navigator.pop(context, t),
              );
            },
          ),
        ),
      ]),
    );
  }
}