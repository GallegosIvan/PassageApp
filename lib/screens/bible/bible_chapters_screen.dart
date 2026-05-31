import 'package:flutter/material.dart';
import '../../services/bible_service.dart';
import '../../services/bible_interaction_service.dart';
import 'bible_reader_screen.dart';

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
  List<Map<String, dynamic>> _bookmarks = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBookmark();
  }

  Future<void> _loadBookmark() async {
    final bookmarks = await _interactionService.getBookmarks();
    if (mounted) setState(() => _bookmarks = bookmarks);
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(bookName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
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
          final bookmarkColor = isBookmarked
              ? (() {
                  final colorMap = {
                    'purple': Colors.white,
                    'blue': Colors.blue,
                    'green': Colors.green,
                  };
                  final bm = _bookmarks.firstWhere(
                    (b) => b['book_id'] == bookId && b['chapter'] == chapterNumber,
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
              // Reload bookmark when returning from reader
              _loadBookmark();
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
              child: Text(
                '$chapterNumber',
                style: TextStyle(
                  color: isBookmarked ? bookmarkColor! : Colors.white,
                  fontSize: 16,
                  fontWeight: isBookmarked ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}