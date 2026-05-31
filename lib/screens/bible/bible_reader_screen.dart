import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/bible_service.dart';
import '../../services/bible_interaction_service.dart';
import '../communities/community_detail_screen.dart';
import '../../services/community_service.dart';

class BibleReaderScreen extends StatefulWidget {
  final String translationId;
  final String bookId;
  final String bookName;
  final int chapterNumber;
  final int totalChapters;

  const BibleReaderScreen({
    super.key,
    required this.translationId,
    required this.bookId,
    required this.bookName,
    required this.chapterNumber,
    required this.totalChapters,
  });

  @override
  State<BibleReaderScreen> createState() => _BibleReaderScreenState();
}

class _BibleReaderScreenState extends State<BibleReaderScreen> {
  final _bibleService = BibleService();
  final _interactionService = BibleInteractionService();

  List<Map<String, dynamic>> _verses = [];
  List<Map<String, dynamic>> _annotations = [];
  List<Map<String, dynamic>> _highlights = [];
  bool _isLoading = true;
  bool _isPaidUser = false;
  String? _error;
  List<Map<String, dynamic>> _bookmarks = [];

  @override
  void initState() {
    super.initState();
    _loadChapter();
  }

  Future<void> _loadChapter() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // API CALL: BibleService.getChapter → Free Use Bible API
      final chapterData = await _bibleService.getChapter(
        widget.translationId,
        widget.bookId,
        widget.chapterNumber,
      );

      final content = chapterData['chapter']['content'] as List<dynamic>;
      final verses = _bibleService.parseVerses(content);

      // API CALL: BibleService.getAnnotationsForChapter → Supabase DB
      final annotations = await _bibleService.getAnnotationsForChapter(
        book: widget.bookName,
        chapter: widget.chapterNumber,
      );

      // API CALL: BibleInteractionService.getHighlightsForChapter → Supabase DB
      final highlights = await _interactionService.getHighlightsForChapter(
        bookId: widget.bookId,
        chapter: widget.chapterNumber,
      );

      final bookmarks = await _interactionService.getBookmarks();
      setState(() => _bookmarks = bookmarks);

      // API CALL: BibleInteractionService.isPaidUser → Supabase DB
      final isPaid = await _interactionService.isPaidUser();

      setState(() {
        _verses = verses;
        _annotations = annotations;
        _highlights = highlights;
        _isPaidUser = isPaid;
        _isLoading = false;
      });
    } catch (e, st) {
      print('loadChapter error: $e\n$st');
      setState(() {
        _error = 'Failed to load chapter. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshData() async {
    final annotations = await _bibleService.getAnnotationsForChapter(
      book: widget.bookName,
      chapter: widget.chapterNumber,
    );
    final highlights = await _interactionService.getHighlightsForChapter(
      bookId: widget.bookId,
      chapter: widget.chapterNumber,
    );
    if (mounted) {
      setState(() {
        _annotations = annotations;
        _highlights = highlights;
      });
    }
  }

  bool _hasAnnotation(int verseNumber) =>
      _annotations.any((a) => a['verse_start'] == verseNumber);

  Map<String, dynamic>? _getAnnotation(int verseNumber) {
    try {
      return _annotations.firstWhere((a) => a['verse_start'] == verseNumber);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _getHighlight(int verseNumber) {
    try {
      return _highlights.firstWhere((h) => h['verse'] == verseNumber);
    } catch (_) {
      return null;
    }
  }

  Color _highlightColor(String color) {
    switch (color) {
      case 'yellow':
        return Colors.yellow.withOpacity(0.3);
      case 'green':
        return Colors.green.withOpacity(0.3);
      case 'pink':
        return Colors.pink.withOpacity(0.3);
      case 'purple':
        return Colors.white.withOpacity(0.3);
      default:
        return Colors.yellow.withOpacity(0.3);
    }
  }

  void _onVerseTap(Map<String, dynamic> verse) {
    final verseNumber = verse['number'] as int;
    final existing = _getAnnotation(verseNumber);
    final highlight = _getHighlight(verseNumber);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => _VerseActionsSheet(
        verse: verse,
        verseRef:
            '${widget.bookName} ${widget.chapterNumber}:$verseNumber',
        bookId: widget.bookId,
        bookName: widget.bookName,
        chapter: widget.chapterNumber,
        verseNumber: verseNumber,
        existingAnnotation: existing,
        existingHighlight: highlight,
        bibleService: _bibleService,
        interactionService: _interactionService,
        isPaidUser: _isPaidUser,
        onChanged: _refreshData,
      ),
    );
  }

  void _navigateToChapter(int chapterNumber) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BibleReaderScreen(
          translationId: widget.translationId,
          bookId: widget.bookId,
          bookName: widget.bookName,
          chapterNumber: chapterNumber,
          totalChapters: widget.totalChapters,
        ),
      ),
    );
  }

  void _showBookmarkSheet() {
    final colors = ['purple', 'blue', 'green'];
    final colorValues = {
      'purple': Colors.white,
      'blue': Colors.blue,
      'green': Colors.green,
    };
    final colorLabels = {
      'purple': 'Bookmark 1',
      'blue': 'Bookmark 2',
      'green': 'Bookmark 3',
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Bookmarks',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Tap a slot to bookmark this chapter',
              style: TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(height: 20),
            ...colors.map((color) {
              final existing = _bookmarks.firstWhere(
                (b) => b['color'] == color,
                orElse: () => {},
              );
              final isThisChapter = existing.isNotEmpty &&
                  existing['book_id'] == widget.bookId &&
                  existing['chapter'] == widget.chapterNumber;
              final isOtherChapter = existing.isNotEmpty && !isThisChapter;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                  tileColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  leading: Icon(
                    existing.isNotEmpty ? Icons.bookmark : Icons.bookmark_border,
                    color: colorValues[color],
                  ),
                  title: Text(
                    colorLabels[color]!,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                  isThisChapter
                    ? '${widget.bookName} ${widget.chapterNumber} — tap to remove'
                    : isOtherChapter
                      ? '${existing['book_name']} ${existing['chapter']} — tap to replace'
                      : 'Empty slot',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    if (isThisChapter) {
                      await _interactionService.removeBookmark(color);
                    } else {
                      await _interactionService.saveBookmark(
                        bookId: widget.bookId,
                        bookName: widget.bookName,
                        chapter: widget.chapterNumber,
                        color: color,
                      );
                    }
                    final bookmarks = await _interactionService.getBookmarks();
                    if (mounted) setState(() => _bookmarks = bookmarks);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isThisChapter
                              ? 'Bookmark removed'
                              : '${widget.bookName} ${widget.chapterNumber} bookmarked'),
                          backgroundColor: isThisChapter
                              ? Colors.grey[700]
                              : colorValues[color],
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    }
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          '${widget.bookName} ${widget.chapterNumber}',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                widget.translationId,
                style: const TextStyle(
                  color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _loadChapter,
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // ── VERSE LIST ────────────────────────
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        itemCount: _verses.length,
                        itemBuilder: (context, index) {
                          final verse = _verses[index];
                          final verseNumber = verse['number'] as int;
                          final hasNote = _hasAnnotation(verseNumber);
                          final highlight = _getHighlight(verseNumber);

                          return GestureDetector(
                            onTap: () => _onVerseTap(verse),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: highlight != null
                                    ? _highlightColor(
                                        highlight['color'] as String)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: hasNote
                                    ? Border.all(
                                        color: Colors.white.withOpacity(0.4),
                                        width: 1)
                                    : null,
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '$verseNumber',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      verse['text'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        height: 1.6,
                                      ),
                                    ),
                                  ),
                                  if (hasNote)
                                    const Padding(
                                      padding: EdgeInsets.only(
                                          left: 8, top: 2),
                                      child: Icon(Icons.bookmark,
                                          color: Colors.white,
                                          size: 16),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // ── BOTTOM CONTROL BAR ────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: const Border(
                          top: BorderSide(
                              color: Colors.black54, width: 1),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          // Previous chapter
                          TextButton.icon(
                            onPressed: widget.chapterNumber > 1
                                ? () => _navigateToChapter(
                                    widget.chapterNumber - 1)
                                : null,
                            icon: Icon(
                              Icons.chevron_left,
                                color: widget.chapterNumber > 1
                                  ? Colors.white
                                  : Colors.white,
                              size: 28,
                            ),
                            label: Text(
                              "Previous", 
                              style: TextStyle(
                                fontSize: 12, 
                                color: widget.chapterNumber > 1 ? Colors.white : Colors.white),
                            ),
                          ),

                          // Book + chapter indicator
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Text(
                              //   widget.bookName,
                              //   style: const TextStyle(
                              //     color: Colors.white,
                              //     fontSize: 13,
                              //     fontWeight: FontWeight.w600,
                              //   ),
                              // ),
                              Text(
                                'Chapter ${widget.chapterNumber} of ${widget.totalChapters}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),

                          // Bookmark button
                          IconButton(
                            onPressed: () => _showBookmarkSheet(),
                            icon: Icon(
                              _bookmarks.any((b) =>
                                  b['book_id'] == widget.bookId &&
                                  b['chapter'] == widget.chapterNumber)
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              color: _bookmarks.any((b) =>
                                  b['book_id'] == widget.bookId &&
                                  b['chapter'] == widget.chapterNumber)
                                  ? Colors.white
                                  : Colors.white,
                              size: 24,
                            ),
                          ),

                          // Next chapter
                          TextButton(
                            onPressed: widget.chapterNumber <
                                    widget.totalChapters
                                ? () => _navigateToChapter(
                                    widget.chapterNumber + 1)
                                : null,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "Next", 
                                  style: TextStyle(
                                    fontSize: 12, 
                                    color: widget.chapterNumber < widget.totalChapters ? Colors.white : Colors.white),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                    color: widget.chapterNumber <
                                        widget.totalChapters
                                      ? Colors.white
                                      : Colors.white,
                                  size: 28,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ============================================================
// VERSE ACTIONS BOTTOM SHEET
// Shows highlight, note, copy, and share options on verse tap
// ============================================================

class _VerseActionsSheet extends StatefulWidget {
  final Map<String, dynamic> verse;
  final String verseRef;
  final String bookId;
  final String bookName;
  final int chapter;
  final int verseNumber;
  final Map<String, dynamic>? existingAnnotation;
  final Map<String, dynamic>? existingHighlight;
  final BibleService bibleService;
  final BibleInteractionService interactionService;
  final bool isPaidUser;
  final VoidCallback onChanged;

  const _VerseActionsSheet({
    required this.verse,
    required this.verseRef,
    required this.bookId,
    required this.bookName,
    required this.chapter,
    required this.verseNumber,
    required this.existingAnnotation,
    required this.existingHighlight,
    required this.bibleService,
    required this.interactionService,
    required this.isPaidUser,
    required this.onChanged,
  });

  @override
  State<_VerseActionsSheet> createState() => _VerseActionsSheetState();
}

class _VerseActionsSheetState extends State<_VerseActionsSheet> {
  bool _showNoteInput = false;
  bool _showShareInput = false;
  late final TextEditingController _noteController;
  late final TextEditingController _shareController;
  String _selectedHighlightColor = 'yellow';
  bool _isSaving = false;

  final _highlightColors = {
    'yellow': Colors.yellow,
    'green': Colors.green,
    'pink': Colors.pink,
    'purple': Colors.white,
  };

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(
        text: widget.existingAnnotation?['note'] ?? '');
    _shareController = TextEditingController(
        text: '${widget.verseRef}\n\n"${widget.verse['text']}"');
    _selectedHighlightColor =
        widget.existingHighlight?['color'] ?? 'yellow';
  }

  @override
  void dispose() {
    _noteController.dispose();
    _shareController.dispose();
    super.dispose();
  }

  Future<void> _saveHighlight(String color) async {
    try {
      // API CALL: BibleInteractionService.saveHighlight → Supabase DB
      await widget.interactionService.saveHighlight(
        bookId: widget.bookId,
        bookName: widget.bookName,
        chapter: widget.chapter,
        verse: widget.verseNumber,
        color: color,
      );
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to save highlight'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removeHighlight() async {
    try {
      // API CALL: BibleInteractionService.removeHighlight → Supabase DB
      await widget.interactionService.removeHighlight(
        bookId: widget.bookId,
        chapter: widget.chapter,
        verse: widget.verseNumber,
      );
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to remove highlight'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveNote() async {
    // VALIDATION: don't save empty note
    if (_noteController.text.trim().isEmpty) return;

    setState(() => _isSaving = true);
    try {
      // API CALL: BibleService.saveAnnotation → Supabase DB
      await widget.bibleService.saveAnnotation(
        book: widget.bookName,
        chapter: widget.chapter,
        verseStart: widget.verseNumber,
        note: _noteController.text.trim(),
      );
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to save note'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteNote() async {
    final annotationId = widget.existingAnnotation?['id'] as String?;
    if (annotationId == null) return;

    setState(() => _isSaving = true);
    try {
      await widget.bibleService.deleteAnnotation(annotationId);
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to delete note'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _copyVerse() {
    // Copy verse text to clipboard
    Clipboard.setData(ClipboardData(
        text: '${widget.verseRef}\n"${widget.verse['text']}"'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Verse copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
              child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Verse reference
          Text(
            widget.verseRef,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),

          // Verse text preview
          Text(
            '"${widget.verse['text']}"',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),

          // ── HIGHLIGHT COLORS ──────────────────────────
          if (!_showNoteInput && !_showShareInput) ...[
            const Text('Highlight',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Row(
              children: [
                ..._highlightColors.entries.map((entry) {
                  final isSelected =
                      _selectedHighlightColor == entry.key &&
                          widget.existingHighlight != null;
                  return GestureDetector(
                    onTap: () => _saveHighlight(entry.key),
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: entry.value.withOpacity(0.7),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: Colors.white, width: 2)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }),
                if (widget.existingHighlight != null)
                  GestureDetector(
                    onTap: _removeHighlight,
                    child: Container(
                      width: 36,
                      height: 36,
                        decoration: BoxDecoration(
                        color: const Color(0xFF2A2A3E),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white),
                        ),
                        child: const Icon(Icons.close,
                          color: Colors.white, size: 18),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(color: Color(0xFF2A2A3E)),
            const SizedBox(height: 12),

            // ── ACTION BUTTONS ────────────────────────
            Row(
              children: [
                // Note button
                Expanded(
                  child: _ActionButton(
                    icon: Icons.edit_note_rounded,
                    label: widget.existingAnnotation != null
                        ? 'Edit Note'
                        : 'Add Note',
                    onTap: () =>
                        setState(() => _showNoteInput = true),
                  ),
                ),
                const SizedBox(width: 10),
                // Copy button
                Expanded(
                  child: _ActionButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: _copyVerse,
                  ),
                ),
                const SizedBox(width: 10),
                // Share to community button (paid only)
                Expanded(
                  child: _ActionButton(
                    icon: Icons.people_rounded,
                    label: 'Share',
                    isPro: !widget.isPaidUser,
                    onTap: widget.isPaidUser
                        ? () => setState(
                            () => _showShareInput = true)
                        : () {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Upgrade to Pro to share verses to communities'),
                                backgroundColor:
                                    Color(0xFF424242),
                              ),
                            );
                          },
                  ),
                ),
              ],
            ),
          ],

          // ── NOTE INPUT ────────────────────────────────
          if (_showNoteInput) ...[
            const Text('Your note',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 4,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Write your thoughts...',
                hintStyle:
                  const TextStyle(color: Colors.white),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Colors.white, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _showNoteInput = false),
                    child: const Text('Cancel',
                        style: TextStyle(color: Color(0xFF9090A0))),
                  ),
                ),
                if (widget.existingAnnotation != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _deleteNote,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Delete'),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveNote,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.black, strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],

          // ── SHARE TO COMMUNITY (paid) ─────────────────
          if (_showShareInput) ...[
            const Text('Share to community',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Post this verse to one of your communities.',
              style: TextStyle(color: Color(0xFF9090A0), fontSize: 12),
            ),
            const SizedBox(height: 12),

            // Community picker
            _ShareToCommunitySheet(
              verse: widget.verse,
              verseRef: widget.verseRef,
              communityService: CommunityService(),
              onDone: () {
                Navigator.pop(context);
                widget.onChanged();
              },
              onCancel: () => setState(() => _showShareInput = false),
            ),
          ],
        ],
      ),
    );
  }
}

// ── REUSABLE ACTION BUTTON ────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPro;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPro = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                if (isPro)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('PRO',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SHARE TO COMMUNITY SHEET
// Lets paid users pick a community and share a verse as a post
// ============================================================
class _ShareToCommunitySheet extends StatefulWidget {
  final Map<String, dynamic> verse;
  final String verseRef;
  final CommunityService communityService;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  const _ShareToCommunitySheet({
    required this.verse,
    required this.verseRef,
    required this.communityService,
    required this.onDone,
    required this.onCancel,
  });

  @override
  State<_ShareToCommunitySheet> createState() =>
      _ShareToCommunitySheetState();
}

class _ShareToCommunitySheetState extends State<_ShareToCommunitySheet> {
  List<Map<String, dynamic>> _communities = [];
  Map<String, dynamic>? _selectedCommunity;
  final _commentController = TextEditingController();
  bool _isLoading = true;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _loadCommunities();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadCommunities() async {
    // API CALL: CommunityService.getMyCommunitiesForSharing → Supabase DB
    final communities =
        await widget.communityService.getMyCommunitiesForSharing();
    if (mounted) setState(() {
      _communities = communities;
      _isLoading = false;
    });
  }

  Future<void> _share() async {
    if (_selectedCommunity == null) return;
    setState(() => _isPosting = true);

    try {
      // API CALL: CommunityService.shareVerseToCommunity → Supabase DB
      await widget.communityService.shareVerseToCommunity(
        communityId: _selectedCommunity!['id'],
        verseRef: widget.verseRef,
        verseText: widget.verse['text'] ?? '',
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );
      widget.onDone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to share verse'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF5B4FCF)),
      );
    }

    if (_communities.isEmpty) {
      return Column(
        children: [
          const Text(
            'You have not joined any communities yet.',
            style: TextStyle(color: Color(0xFF9090A0), fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: widget.onCancel,
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF9090A0))),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Community picker
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F1A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Map<String, dynamic>>(
              value: _selectedCommunity,
              hint: const Text('Select a community',
                  style: TextStyle(color: Color(0xFF9090A0))),
              dropdownColor: const Color(0xFF1C1C2E),
              isExpanded: true,
              style: const TextStyle(color: Colors.white),
              items: _communities
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(
                          '${c['name']} — ${c['book']} ${c['chapter']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (val) =>
                  setState(() => _selectedCommunity = val),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Optional comment
        TextField(
          controller: _commentController,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Add a comment (optional)',
            hintStyle: const TextStyle(color: Color(0xFF9090A0)),
            filled: true,
            fillColor: const Color(0xFF0F0F1A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Color(0xFF5B4FCF), width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel',
                    style: TextStyle(color: Color(0xFF9090A0))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed:
                    _isPosting || _selectedCommunity == null
                        ? null
                        : _share,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B4FCF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isPosting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Share'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}