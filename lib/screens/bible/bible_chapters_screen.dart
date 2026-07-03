import 'package:flutter/material.dart';
import '../../services/bible_service.dart';
import '../../services/app_cache.dart';
import '../../services/bible_interaction_service.dart';
import 'bible_reader_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BibleChaptersScreen extends StatefulWidget {
  final String translationId;
  final Map<String, dynamic> book;

  const BibleChaptersScreen({
    super.key,
    required this.translationId,
    required this.book,
  });

  @override
  State<BibleChaptersScreen> createState() => _BibleChaptersScreenState();
}

class _BibleChaptersScreenState extends State<BibleChaptersScreen> {
  final _interactionService = BibleInteractionService();
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _bookmarks = [];
  Set<int> _readChapters = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    final bookmarks = await _interactionService.getBookmarks();
    Set<int> readChapters;
    final bookId = widget.book['id'] as String;
    if (AppCache.instance.readChapters != null) {
      readChapters = AppCache.instance.readChapters!
          .where((k) => k.startsWith('${bookId}_'))
          .map((k) => int.tryParse(k.split('_').last) ?? 0)
          .where((c) => c > 0)
          .toSet();
    } else {
      readChapters = await _loadReadChapters();
    }
    if (mounted) {
      setState(() {
        _bookmarks = bookmarks;
        _readChapters = readChapters;
      });
    }
  }

  Future<Set<int>> _loadReadChapters() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};
    try {
      final response = await _client
          .from('reading_history')
          .select('chapter')
          .eq('user_id', userId)
          .eq('book_id', widget.book['id'] as String);
      return (response as List).map((r) => r['chapter'] as int).toSet();
    } catch (e) {
      print('loadReadChapters error: $e');
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final bibleService = BibleService();
    final chapters = bibleService.getChapterNumbers(widget.book);
    final bookName = widget.book['name'] ?? '';
    final bookId = widget.book['id'] as String;
    final bookmarkedChapters = _bookmarks
        .where((b) => b['book_id'] == bookId)
        .map((b) => b['chapter'] as int)
        .toList();

    final allRead = chapters.isNotEmpty &&
        chapters.every((c) => _readChapters.contains(c));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Text(bookName,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            if (allRead) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
            ],
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1,
        ),
        itemCount: chapters.length,
        itemBuilder: (context, index) {
          final chapterNumber = chapters[index];
          final isBookmarked = bookmarkedChapters.contains(chapterNumber);
          final isRead = _readChapters.contains(chapterNumber);

          final colorMap = {
            'purple': Colors.white,
            'blue': Colors.blue,
            'green': Colors.green,
          };

          final bookmarkColor = isBookmarked
              ? (() {
                  final bm = _bookmarks.firstWhere(
                    (b) =>
                        b['book_id'] == bookId &&
                        b['chapter'] == chapterNumber,
                    orElse: () => {'color': 'purple'},
                  );
                  return colorMap[bm['color']] ?? Colors.white;
                })()
              : null;

          return GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BibleReaderScreen(
                    translationId: widget.translationId,
                    bookId: bookId,
                    bookName: bookName,
                    chapterNumber: chapterNumber,
                    totalChapters: chapters.length,
                  ),
                ),
              );
              _loadData();
            },
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: isBookmarked
                    ? Border.all(color: bookmarkColor!, width: 1.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: Stack(
                children: [
                  // Chapter number — centered
                  Center(
                    child: Text(
                      '$chapterNumber',
                      style: TextStyle(
                        color: isBookmarked ? bookmarkColor! : Colors.white,
                        fontSize: 16,
                        fontWeight: isBookmarked
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  // Green checkmark in bottom-right corner if read
                  if (isRead)
                    const Positioned(
                      bottom: 4,
                      right: 4,
                      child: Icon(
                        Icons.check,
                        size: 11,
                        color: Colors.green,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}