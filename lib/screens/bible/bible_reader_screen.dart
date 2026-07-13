import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:convert';
import '../../services/bible_service.dart';
import '../../services/app_cache.dart';
import '../../services/bible_interaction_service.dart';
import '../../services/subscription_service.dart';
import '../communities/community_detail_screen.dart';
import '../../services/community_service.dart';
import '../../widgets/upgrade_sheet.dart';
import '../../widgets/restricted_dialog.dart';
import '../../widgets/rate_us_dialog.dart';
import '../../widgets/ai_consent_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final _subscriptionService = SubscriptionService();
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _verses = [];
  List<Map<String, dynamic>> _annotations = [];
  List<Map<String, dynamic>> _highlights = [];
  bool _isLoading = true;
  bool _isPaidUser = false;
  String? _error;
  List<Map<String, dynamic>> _bookmarks = [];

  bool _isRead = false;
  Timer? _readTimer;

  int? _currentChapterOverride;
  int get _currentChapter => _currentChapterOverride ?? widget.chapterNumber;
  bool _slideFromRight = true;

  @override
  void initState() {
    super.initState();
    _loadChapter();
    _startReadTimer();
  }

  @override
  void dispose() {
    _readTimer?.cancel();
    super.dispose();
  }

  void _startReadTimer() {
    _readTimer = Timer(const Duration(seconds: 90), () {
      if (mounted && !_isRead) {
        _markAsRead();
      }
    });
  }

  Future<void> _markAsRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client.from('reading_history').upsert({
        'user_id': userId,
        'book_id': widget.bookId,
        'book_name': widget.bookName,
        'chapter': _currentChapter,
        'read_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,book_id,chapter');
      AppCache.instance.markChapterRead(widget.bookId, _currentChapter);
      if (mounted) {
        setState(() => _isRead = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.bookName} ${_currentChapter} marked as read'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('markAsRead error: $e');
    }
  }

  Future<void> _toggleRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    if (_isRead) {
      try {
        await _client
            .from('reading_history')
            .delete()
            .eq('user_id', userId)
            .eq('book_id', widget.bookId)
            .eq('chapter', _currentChapter);
        AppCache.instance.invalidateReadHistory();
        if (mounted) setState(() => _isRead = false);
      } catch (e) {
        print('unmarkAsRead error: $e');
      }
    } else {
      _readTimer?.cancel();
      await _markAsRead();
    }
  }

  Future<void> _checkIfRead() async {
    final cacheKey = '\${widget.bookId}_\${_currentChapter}';
    if (AppCache.instance.readChapters != null) {
      if (mounted) setState(() => _isRead = AppCache.instance.readChapters!.contains(cacheKey));
      return;
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final results = await _client
          .from('reading_history')
          .select('id')
          .eq('user_id', userId)
          .eq('book_id', widget.bookId)
          .eq('chapter', _currentChapter)
          .limit(1);
      if (mounted) setState(() => _isRead = (results as List).isNotEmpty);
    } catch (e) {
      print('checkIfRead error: \$e');
    }
  }

  Future<void> _loadChapter() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final chapterData = await _bibleService.getChapter(
        widget.translationId,
        widget.bookId,
        _currentChapter,
      );
      final content = chapterData['chapter']['content'] as List<dynamic>;
      final verses = _bibleService.parseVerses(content);
      final annotations = await _bibleService.getAnnotationsForChapter(
        book: widget.bookName,
        chapter: _currentChapter,
      );
      final highlights = await _interactionService.getHighlightsForChapter(
        bookId: widget.bookId,
        chapter: _currentChapter,
      );
      final bookmarks = await _interactionService.getBookmarks();
      final isPaid = await _interactionService.isPaidUser();
      await _checkIfRead();
      setState(() {
        _verses = verses;
        _annotations = annotations;
        _highlights = highlights;
        _bookmarks = bookmarks;
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
      chapter: _currentChapter,
    );
    final highlights = await _interactionService.getHighlightsForChapter(
      bookId: widget.bookId,
      chapter: _currentChapter,
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
      case 'yellow': return Colors.yellow.withOpacity(0.3);
      case 'green': return Colors.green.withOpacity(0.3);
      case 'pink': return Colors.pink.withOpacity(0.3);
      case 'purple': return Colors.white.withOpacity(0.3);
      default: return Colors.yellow.withOpacity(0.3);
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
        verseRef: '${widget.bookName} ${_currentChapter}:$verseNumber',
        bookId: widget.bookId,
        bookName: widget.bookName,
        chapter: _currentChapter,
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
    _readTimer?.cancel();
    setState(() {
      _slideFromRight = chapterNumber > _currentChapter;
      _currentChapterOverride = chapterNumber;
      _isRead = false;
      _verses = [];
      _annotations = [];
      _highlights = [];
      _isLoading = true;
      _error = null;
    });
    _loadChapter();
    _startReadTimer();
  }

  void _showBookmarkSheet() {
    final colors = ['purple', 'blue', 'green'];
    final colorValues = {'purple': Colors.white, 'blue': Colors.blue, 'green': Colors.green};
    final colorLabels = {'purple': 'Bookmark 1', 'blue': 'Bookmark 2', 'green': 'Bookmark 3'};
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
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Bookmarks', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Tap a slot to bookmark this chapter', style: TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(height: 20),
            ...colors.map((color) {
              final existing = _bookmarks.firstWhere((b) => b['color'] == color, orElse: () => {});
              final isThisChapter = existing.isNotEmpty && existing['book_id'] == widget.bookId && existing['chapter'] == _currentChapter;
              final isOtherChapter = existing.isNotEmpty && !isThisChapter;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  tileColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(existing.isNotEmpty ? Icons.bookmark : Icons.bookmark_border, color: colorValues[color]),
                  title: Text(colorLabels[color]!, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    isThisChapter ? '${widget.bookName} ${_currentChapter} — tap to remove'
                        : isOtherChapter ? '${existing['book_name']} ${existing['chapter']} — tap to replace'
                        : 'Empty slot',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    if (isThisChapter) {
                      await _interactionService.removeBookmark(color);
                    } else {
                      await _interactionService.saveBookmark(bookId: widget.bookId, bookName: widget.bookName, chapter: _currentChapter, color: color);
                    }
                    final bookmarks = await _interactionService.getBookmarks();
                    if (mounted) setState(() => _bookmarks = bookmarks);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(isThisChapter ? 'Bookmark removed' : '${widget.bookName} ${_currentChapter} bookmarked'),
                        backgroundColor: isThisChapter ? Colors.grey[700] : colorValues[color],
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ));
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

  Future<void> _showQuizSheet() async {
    final allowed = await AiConsentDialog.requestConsent(context);
    if (!allowed || !mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuizSheet(
        bookName: widget.bookName,
        chapterNumber: _currentChapter,
        translationId: widget.translationId,
        verseCount: _verses.length,
        isPaidUser: _isPaidUser,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('${widget.bookName} ${_currentChapter}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text(widget.translationId, style: const TextStyle(color: Colors.white, fontSize: 13))),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) {
          final incoming = animation.status == AnimationStatus.dismissed ||
              animation.status == AnimationStatus.forward;
          final beginOffset = _slideFromRight
              ? (incoming ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0))
              : (incoming ? const Offset(-1.0, 0.0) : const Offset(1.0, 0.0));
          return SlideTransition(
            position: Tween<Offset>(begin: beginOffset, end: Offset.zero)
                .animate(animation),
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_currentChapter),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _error != null
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadChapter, child: const Text('Retry')),
                    ]))
                  : Column(children: [
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
                              color: highlight != null ? _highlightColor(highlight['color'] as String) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: hasNote ? Border.all(color: Colors.white.withOpacity(0.4), width: 1) : null,
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              SizedBox(width: 28, child: Text('$verseNumber', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                (verse['text'] ?? '').toString()
                                  .replaceAll('?', '? ')
                                  .replaceAll('!', '! ')
                                  .replaceAll(',', ', ')
                                  .replaceAll('  ', ' ')
                                  .replaceAll('.', '. ')
                                  .replaceAll(';', '; ')
                                  .replaceAll(':', ': ')
                                  .trim(),
                                style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                              )),
                              if (hasNote) const Padding(padding: EdgeInsets.only(left: 8, top: 2), child: Icon(Icons.bookmark, color: Colors.white, size: 16)),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(color: Colors.black, border: Border(top: BorderSide(color: Colors.white10))),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      if (_currentChapter > 1)
                       TextButton.icon(
                        onPressed: () => _navigateToChapter(_currentChapter - 1),
                        icon: const Icon(Icons.chevron_left, color: Colors.white, size: 24),
                        label: const Text('Prev', style: TextStyle(color: Colors.white, fontSize: 12)),
                       )
                      else
                       const SizedBox(width: 72),
                      IconButton(onPressed: _showQuizSheet, tooltip: 'Quiz me', icon: const Icon(Icons.quiz_outlined, color: Colors.white, size: 22)),
                      Flexible(
                       child: Text('Ch ${_currentChapter}/${widget.totalChapters}', 
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                       ),
                      ),
                      IconButton(
                        onPressed: _toggleRead,
                        tooltip: _isRead ? 'Mark as unread' : 'Mark as read',
                        icon: Icon(_isRead ? Icons.check_circle : Icons.check_circle_outline, color: _isRead ? Colors.green : Colors.white54, size: 22),
                      ),
                      IconButton(
                        onPressed: _showBookmarkSheet,
                        icon: Icon(
                          _bookmarks.any((b) => b['book_id'] == widget.bookId && b['chapter'] == _currentChapter) ? Icons.bookmark : Icons.bookmark_border,
                          color: Colors.white, size: 22,
                        ),
                      ),
                      if (_currentChapter < widget.totalChapters)
                       TextButton.icon(
                        onPressed: () => _navigateToChapter(_currentChapter + 1),
                        icon: const Text('Next', style: TextStyle(color: Colors.white, fontSize: 12)),
                        label: const Icon(Icons.chevron_right, color: Colors.white, size: 24),
                       )
                      else
                        const SizedBox(width: 72),
                    ]),
                  ),
                ]),
        ),
      ),
    );
  }
}

// ============================================================
// QUIZ SHEET
// ============================================================
class _QuizSheet extends StatefulWidget {
  final String bookName;
  final int chapterNumber;
  final String translationId;
  final int verseCount;
  final bool isPaidUser;

  const _QuizSheet({
    required this.bookName,
    required this.chapterNumber,
    required this.translationId,
    required this.verseCount,
    required this.isPaidUser,
  });

  @override
  State<_QuizSheet> createState() => _QuizSheetState();
}

class _QuizSheetState extends State<_QuizSheet> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _questions = [];
  int _currentIndex = 0;
  int? _selectedAnswer;
  bool _answered = false;
  int _score = 0;
  bool _isLoading = true;
  bool _isFinished = false;
  String? _error;
  int _quizzesRemaining = 0;
  int _dailyLimit = 0;
  // Track answers for resume: list of selected answer indices (-1 = unanswered)
  List<int> _userAnswers = [];

  @override
  void initState() {
    super.initState();
    _initQuiz();
  }

  Future<void> _initQuiz() async {
    // Try to load saved state first
    final saved = await _loadSavedState();
    if (saved) return;
    // No saved state — generate new quiz (counts against daily limit)
    await _generateQuiz();
  }

  // ── SAVE STATE ─────────────────────────────────────────────
  Future<void> _saveState() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || _questions.isEmpty) return;
    try {
      await _client.from('quiz_state').upsert({
        'user_id': userId,
        'book_name': widget.bookName,
        'chapter': widget.chapterNumber,
        'questions_json': jsonEncode(_questions),
        'current_index': _currentIndex,
        'score': _score,
        'answers': _userAnswers,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,book_name,chapter');
    } catch (e) {
      print('saveState error: $e');
    }
  }

  // ── LOAD SAVED STATE ───────────────────────────────────────
  Future<bool> _loadSavedState() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final result = await _client
          .from('quiz_state')
          .select()
          .eq('user_id', userId)
          .eq('book_name', widget.bookName)
          .eq('chapter', widget.chapterNumber)
          .maybeSingle();

      if (result == null) return false;

      final questions = List<Map<String, dynamic>>.from(
          (jsonDecode(result['questions_json'] as String) as List)
              .map((e) => Map<String, dynamic>.from(e)));

      if (questions.isEmpty) return false;

      final answers = List<int>.from(result['answers'] as List? ?? []);

      // Pad answers list if needed
      while (answers.length < questions.length) answers.add(-1);

      final currentIndex = result['current_index'] as int? ?? 0;
      final score = result['score'] as int? ?? 0;

      // Fetch remaining quizzes without consuming one
      final quizzesRemaining = await _fetchQuizzesRemaining();

      if (mounted) {
        setState(() {
          _questions = questions;
          _currentIndex = currentIndex;
          _score = score;
          _userAnswers = answers;
          _quizzesRemaining = quizzesRemaining;
          _dailyLimit = widget.isPaidUser ? 8 : 3;
          // Restore answered state for current question
          if (currentIndex < answers.length && answers[currentIndex] != -1) {
            _selectedAnswer = answers[currentIndex];
            _answered = true;
          }
          _isLoading = false;
        });
      }
      return true;
    } catch (e) {
      print('loadSavedState error: $e');
      return false;
    }
  }

  // ── CLEAR SAVED STATE ──────────────────────────────────────
  Future<void> _clearSavedState() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client
          .from('quiz_state')
          .delete()
          .eq('user_id', userId)
          .eq('book_name', widget.bookName)
          .eq('chapter', widget.chapterNumber);
    } catch (e) {
      print('clearSavedState error: $e');
    }
  }

  // ── FETCH REMAINING WITHOUT CONSUMING ─────────────────────
  Future<int> _fetchQuizzesRemaining() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;
    try {
      final result = await _client
          .from('quiz_usage')
          .select('quiz_count')
          .eq('user_id', userId)
          .eq('quiz_date', DateTime.now().toIso8601String().substring(0, 10))
          .maybeSingle();
      final used = result?['quiz_count'] as int? ?? 0;
      final limit = widget.isPaidUser ? 8 : 3;
      return (limit - used).clamp(0, limit);
    } catch (e) {
      return 0;
    }
  }

  // ── GENERATE QUIZ ──────────────────────────────────────────
  Future<void> _generateQuiz() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final session = _client.auth.currentSession;
      if (session == null) throw Exception('Not logged in');

      final response = await _client.functions.invoke(
        'bible-quiz',
        body: {
          'book_name': widget.bookName,
          'chapter': widget.chapterNumber,
          'translation_id': widget.translationId,
          'verse_count': widget.verseCount,
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      if (response.data == null) throw Exception('No response from quiz service');

      if (response.data['error'] != null) {
        final error = response.data['error'] as String;
        if (error == 'quiz_limit_reached') {
          setState(() {
            _error = 'limit_reached';
            _quizzesRemaining = 0;
            _dailyLimit = widget.isPaidUser ? 8 : 3;
            _isLoading = false;
          });
          return;
        }
        throw Exception(error);
      }

      String raw = response.data['questions_json'] as String;
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();

      final parsed = _parseJson(raw);
      if (parsed.isEmpty) throw Exception('Could not parse quiz');

      final quizzesRemaining = response.data['quizzes_remaining'] as int? ?? 0;
      final dailyLimit = response.data['daily_limit'] as int? ?? (widget.isPaidUser ? 8 : 3);

      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        await _client.from('quiz_results').insert({
          'user_id': userId,
          'book_name': widget.bookName,
          'chapter': widget.chapterNumber,
          'question_count': parsed.length,
          'score': 0,
          'completed': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // Initialize answers list
      final answers = List<int>.filled(parsed.length, -1);

      if (mounted) {
        setState(() {
          _questions = parsed;
          _userAnswers = answers;
          _quizzesRemaining = quizzesRemaining;
          _dailyLimit = dailyLimit;
          _isLoading = false;
        });
        // Save initial state
        await _saveState();
      }
    } on FunctionException catch (e) {
      if (mounted) {
        final data = e.details;
        final isLimit = data is Map && data['error'] == 'quiz_limit_reached';
        setState(() {
          _error = isLimit ? 'limit_reached' : 'Failed to generate quiz. Please try again.';
          _dailyLimit = widget.isPaidUser ? 8 : 3;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to generate quiz. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _parseJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return List<Map<String, dynamic>>.from(
          (decoded as List).map((e) => Map<String, dynamic>.from(e)));
    } catch (_) {
      return [];
    }
  }

  void _selectAnswer(int index) {
    if (_answered) return;
    final correct = _questions[_currentIndex]['correct'] as int;
    setState(() {
      _selectedAnswer = index;
      _answered = true;
      if (index == correct) _score++;
      _userAnswers[_currentIndex] = index;
    });
    _saveState();
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        // Restore answer if already answered
        final saved = _userAnswers[_currentIndex];
        if (saved != -1) {
          _selectedAnswer = saved;
          _answered = true;
        } else {
          _selectedAnswer = null;
          _answered = false;
        }
      });
      _saveState();
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final userId = _client.auth.currentUser?.id;
    if (userId != null) {
      try {
        await _client
            .from('quiz_results')
            .update({'score': _score, 'completed': true})
            .eq('user_id', userId)
            .eq('book_name', widget.bookName)
            .eq('chapter', widget.chapterNumber)
            .eq('completed', false)
            .order('created_at', ascending: false)
            .limit(1);
      } catch (e) {
        print('saveQuizResult error: $e');
      }
    }
    // Clear saved state since quiz is complete
    await _clearSavedState();
    if (mounted) setState(() => _isFinished = true);

    // Positive-moment rate prompt trigger: a good score is a
    // genuine moment of satisfaction, exactly when platform
    // guidance says to ask. RateUsDialog silently no-ops if the
    // user isn't eligible (too new, recently prompted, etc).
    final percentage = _questions.isEmpty ? 0 : (_score / _questions.length * 100).round();
    if (percentage >= 70 && mounted) {
      RateUsDialog.maybeShow(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Icon(Icons.quiz_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${widget.bookName} ${widget.chapterNumber} Quiz',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              // ── QUIZ COUNTER ────────────────────────────
              if (!_isLoading && _error != 'limit_reached')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _quizzesRemaining <= 1 ? Colors.red.withOpacity(0.2) : Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                    border: _quizzesRemaining <= 1
                        ? Border.all(color: Colors.red.withOpacity(0.4))
                        : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.quiz_outlined,
                        size: 12,
                        color: _quizzesRemaining <= 1 ? Colors.red : Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      '$_quizzesRemaining left today',
                      style: TextStyle(
                          color: _quizzesRemaining <= 1 ? Colors.red : Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Generating quiz...', style: TextStyle(color: Colors.grey)),
                  ]))
                : _error != null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: _error == 'limit_reached'
                            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Icon(Icons.lock_outline, color: Colors.white54, size: 48),
                                const SizedBox(height: 16),
                                const Text('Daily quiz limit reached',
                                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                Text(
                                  widget.isPaidUser
                                      ? 'You\'ve used all $_dailyLimit quizzes for today. Your limit resets at midnight.'
                                      : 'You\'ve used all $_dailyLimit free quizzes for today. Upgrade to Pro for 8 quizzes per day.',
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: widget.isPaidUser
                                      ? ElevatedButton(
                                          onPressed: () => Navigator.pop(context),
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor: Colors.black,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                          child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w600)),
                                        )
                                      : ElevatedButton(
                                          onPressed: () { Navigator.pop(context); UpgradeSheet.show(context); },
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor: Colors.black,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                          child: const Text('Study more with Pro', style: TextStyle(fontWeight: FontWeight.w600)),
                                        ),
                                ),
                              ])
                            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text(_error!, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _generateQuiz,
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                                  child: const Text('Try again'),
                                ),
                              ]),
                      ))
                    : _isFinished
                        ? _buildResults()
                        : _buildQuestion(scrollController),
          ),
        ]),
      ),
    );
  }

  Widget _buildQuestion(ScrollController scrollController) {
    final q = _questions[_currentIndex];
    final options = List<String>.from(q['options'] as List);
    final correct = q['correct'] as int;

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Question ${_currentIndex + 1} of ${_questions.length}',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text('Score: $_score/${_currentIndex + (_answered ? 1 : 0)}',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_currentIndex + 1) / _questions.length,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 3,
          ),
        ),
        const SizedBox(height: 20),
        Text(q['question'] as String,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, height: 1.4)),
        const SizedBox(height: 20),
        ...options.asMap().entries.map((entry) {
          final i = entry.key;
          final option = entry.value;
          Color bgColor = const Color(0xFF1E1E1E);
          Color borderColor = Colors.transparent;
          Color textColor = Colors.white;

          if (_answered) {
            if (i == correct) { bgColor = Colors.green.withOpacity(0.2); borderColor = Colors.green; }
            else if (i == _selectedAnswer && i != correct) { bgColor = Colors.red.withOpacity(0.2); borderColor = Colors.red; textColor = Colors.red; }
          } else if (_selectedAnswer == i) {
            borderColor = Colors.white;
          }

          return GestureDetector(
            onTap: () => _selectAnswer(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor, width: 1.5)),
              child: Row(children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text(['A','B','C','D'][i], style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(option, style: TextStyle(color: textColor, fontSize: 14))),
                if (_answered && i == correct) const Icon(Icons.check_circle, color: Colors.green, size: 20),
                if (_answered && i == _selectedAnswer && i != correct) const Icon(Icons.cancel, color: Colors.red, size: 20),
              ]),
            ),
          );
        }),
        if (_answered) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Explanation',
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(q['explanation'] as String,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _nextQuestion,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(
                _currentIndex < _questions.length - 1 ? 'Next question' : 'See results',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildResults() {
    final percentage = _questions.isEmpty ? 0 : (_score / _questions.length * 100).round();
    String message;
    Color messageColor;
    if (percentage >= 80) { message = 'Excellent! You know this chapter well.'; messageColor = Colors.green; }
    else if (percentage >= 60) { message = 'Good effort! Re-reading may help.'; messageColor = Colors.orange; }
    else { message = 'Keep studying — you\'ll get there!'; messageColor = Colors.red; }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.emoji_events_outlined, color: Colors.white, size: 48),
        const SizedBox(height: 16),
        Text('$percentage%', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
        Text('$_score out of ${_questions.length} correct', style: const TextStyle(color: Colors.grey, fontSize: 16)),
        const SizedBox(height: 12),
        Text(message, style: TextStyle(color: messageColor, fontSize: 14, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
        const SizedBox(height: 32),
        if (!widget.isPaidUser) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
            child: Column(children: [
              const Text('Get 8 quizzes per day with Pro',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('More quizzes, longer chapters, and full quiz history.',
                  style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () { Navigator.pop(context); UpgradeSheet.show(context); },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Study more with Pro', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _currentIndex = 0; _selectedAnswer = null; _answered = false;
                  _score = 0; _isFinished = false; _questions = []; _userAnswers = []; _isLoading = true;
                });
                _generateQuiz();
              },
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Try again'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ============================================================
// VERSE ACTIONS BOTTOM SHEET
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
    _noteController = TextEditingController(text: widget.existingAnnotation?['note'] ?? '');
    _shareController = TextEditingController(text: '${widget.verseRef}\n\n"${widget.verse['text']}"');
    _selectedHighlightColor = widget.existingHighlight?['color'] ?? 'yellow';
  }

  @override
  void dispose() {
    _noteController.dispose();
    _shareController.dispose();
    super.dispose();
  }

  Future<void> _saveHighlight(String color) async {
    try {
      await widget.interactionService.saveHighlight(bookId: widget.bookId, bookName: widget.bookName, chapter: widget.chapter, verse: widget.verseNumber, color: color);
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save highlight'), backgroundColor: Colors.red));
    }
  }

  Future<void> _removeHighlight() async {
    try {
      await widget.interactionService.removeHighlight(bookId: widget.bookId, chapter: widget.chapter, verse: widget.verseNumber);
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove highlight'), backgroundColor: Colors.red));
    }
  }

  Future<void> _saveNote() async {
    if (_noteController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await widget.bibleService.saveAnnotation(book: widget.bookName, chapter: widget.chapter, verseStart: widget.verseNumber, note: _noteController.text.trim());
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save note'), backgroundColor: Colors.red));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete note'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── SHARE OUTSIDE THE APP ──────────────────────────────────
  // Opens the native OS share sheet (Messages, Instagram, etc.).
  // Free for everyone, unconditionally — this is a growth/marketing
  // channel (every share carries the app's name to a non-user),
  // not a feature to monetize. Includes the user's existing note
  // on this verse if one exists, since that's the whole point of
  // sharing what stood out to them, not just the raw text.
  //
  // TODO before launch: once there's a live App Store listing or
  // landing page, replace the text-only attribution below with a
  // real clickable link (e.g. https://apps.apple.com/app/id6782405746)
  // — a working link converts to downloads far better than text
  // alone, but a dead/non-existent link pre-launch would actively
  // hurt trust at the moment someone's curious enough to click.
  Future<void> _shareOutsideApp() async {
    final note = widget.existingAnnotation?['note'] as String?;

    final buffer = StringBuffer();
    buffer.writeln('"${widget.verse['text']}"');
    buffer.writeln('— ${widget.verseRef}');
    if (note != null && note.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('My note: $note');
    }
    buffer.writeln();
    buffer.writeln('Shared with Passage: Bible Study');

    await Share.share(
      buffer.toString(),
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Text(widget.verseRef, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('"${widget.verse['text']}"', style: const TextStyle(color: Colors.white, fontSize: 13, fontStyle: FontStyle.italic), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        if (!_showNoteInput && !_showShareInput) ...[
          const Text('Highlight', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Row(children: [
            ..._highlightColors.entries.map((entry) {
              final isSelected = _selectedHighlightColor == entry.key && widget.existingHighlight != null;
              return GestureDetector(
                onTap: () => _saveHighlight(entry.key),
                child: Container(
                  width: 36, height: 36,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: entry.value.withOpacity(0.7),
                    shape: BoxShape.circle,
                    border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                  ),
                  child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                ),
              );
            }),
            if (widget.existingHighlight != null)
              GestureDetector(
                onTap: _removeHighlight,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: const Color(0xFF2A2A3E), shape: BoxShape.circle, border: Border.all(color: Colors.white)),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
          ]),
          const SizedBox(height: 20),
          const Divider(color: Color(0xFF2A2A3E)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _ActionButton(icon: Icons.edit_note_rounded, label: widget.existingAnnotation != null ? 'Edit Note' : 'Add Note', onTap: () => setState(() => _showNoteInput = true))),
            const SizedBox(width: 10),
            Expanded(child: _ActionButton(
              icon: Icons.people_rounded, label: 'Community',
              onTap: () => setState(() => _showShareInput = true),
            )),
            const SizedBox(width: 10),
            Expanded(child: _ActionButton(icon: Icons.ios_share_rounded, label: 'Share Outside', onTap: () async {
              Navigator.of(context).pop();
              await Future.delayed(const Duration(milliseconds: 300));
              await _shareOutsideApp();
            })),
          ]),
        ],
        if (_showNoteInput) ...[
          const Text('Your note', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController, maxLines: 4, autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Write your thoughts...', hintStyle: const TextStyle(color: Colors.white),
              filled: true, fillColor: Colors.black,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white, width: 1.5)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextButton(onPressed: () => setState(() => _showNoteInput = false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF9090A0))))),
            if (widget.existingAnnotation != null) ...[
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: _isSaving ? null : _deleteNote,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Delete'),
              )),
            ],
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: _isSaving ? null : _saveNote,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) : const Text('Save'),
            )),
          ]),
        ],
        if (_showShareInput) ...[
          const Text('Share to community', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Post this verse to one of your communities.', style: TextStyle(color: Color(0xFF9090A0), fontSize: 12)),
          const SizedBox(height: 12),
          _ShareToCommunitySheet(
            verse: widget.verse, verseRef: widget.verseRef, bookName: widget.bookName, chapter: widget.chapter, communityService: CommunityService(),
            onDone: () { Navigator.pop(context); widget.onChanged(); },
            onCancel: () => setState(() => _showShareInput = false),
          ),
        ],
      ]),
    );
  }
}

// ── ACTION BUTTON ─────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPro;

  const _ActionButton({required this.icon, required this.label, required this.onTap, this.isPro = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(icon, color: Colors.white, size: 22),
            if (isPro) Positioned(top: -4, right: -8, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
              child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
            )),
          ]),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      ),
    );
  }
}

// ── SHARE TO COMMUNITY SHEET ──────────────────────────────────
class _ShareToCommunitySheet extends StatefulWidget {
  final Map<String, dynamic> verse;
  final String verseRef;
  final String bookName;
  final int chapter;
  final CommunityService communityService;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  const _ShareToCommunitySheet({required this.verse, required this.verseRef, required this.bookName, required this.chapter, required this.communityService, required this.onDone, required this.onCancel});

  @override
  State<_ShareToCommunitySheet> createState() => _ShareToCommunitySheetState();
}

class _ShareToCommunitySheetState extends State<_ShareToCommunitySheet> {
  List<Map<String, dynamic>> _communities = [];
  List<Map<String, dynamic>> _filtered = [];
  Map<String, dynamic>? _selectedCommunity;
  final _commentController = TextEditingController();
  final _searchController = TextEditingController();
  bool _isLoading = true;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _loadCommunities();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _commentController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _communities
          : _communities.where((c) {
              final name = (c['name'] as String? ?? '').toLowerCase();
              final church = (c['churches']?['name'] as String? ?? '').toLowerCase();
              final book = (c['book'] as String? ?? '').toLowerCase();
              return name.contains(q) || church.contains(q) || book.contains(q);
            }).toList();
    });
  }

  Future<void> _loadCommunities() async {
    final communities = await widget.communityService.getMyCommunitiesForSharing();
    if (mounted) setState(() { _communities = communities; _filtered = communities; _isLoading = false; });
  }

  // ── CHECK BOOK MATCH ────────────────────────────────────────
  // Communities have a `book` field (e.g. "Numbers"). If the verse
  // being shared is from a different book, this isn't blocked —
  // cross-references and tangents are normal, valuable discussion
  // — but the sharer gets a confirmation step so it's a deliberate
  // choice, not an accident.
  bool _isBookMismatch() {
    final communityBook = _selectedCommunity?['book'] as String?;
    if (communityBook == null) return false; // no book set (general church channel) — no mismatch concept applies
    return communityBook.toLowerCase().trim() != widget.bookName.toLowerCase().trim();
  }

  Future<bool> _confirmMismatch() async {
    final communityBook = _selectedCommunity?['book'] as String?;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Different book', style: TextStyle(color: Colors.white)),
        content: Text(
          'This community is focused on $communityBook, but you\'re sharing a verse from ${widget.bookName}. Share anyway?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Share anyway', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  bool _isGroupChat(Map<String, dynamic> community) =>
      community['church_id'] != null && community['is_bible_study'] != true;

  Future<void> _share() async {
    if (_selectedCommunity == null) return;

    if (!_isGroupChat(_selectedCommunity!) && _isBookMismatch()) {
      final proceed = await _confirmMismatch();
      if (!proceed) return;
    }

    setState(() => _isPosting = true);
    try {
      if (_isGroupChat(_selectedCommunity!)) {
        await widget.communityService.shareVerseToGroupChat(
          communityId: _selectedCommunity!['id'],
          verseRef: widget.verseRef,
          verseText: widget.verse['text'] ?? '',
          comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
        );
      } else {
        await widget.communityService.shareVerseToCommunity(
          communityId: _selectedCommunity!['id'], verseRef: widget.verseRef,
          verseText: widget.verse['text'] ?? '',
          chapter: widget.chapter,
          comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
        );
      }
      widget.onDone();
    } catch (e) {
      if (mounted) {
        final isRestricted = e.toString().contains('user_restricted');
        if (isRestricted) {
          await RestrictedDialog.show(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to share verse'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF5B4FCF)));
    if (_communities.isEmpty) return Column(children: [
      const Text('You have not joined any communities yet.', style: TextStyle(color: Color(0xFF9090A0), fontSize: 13)),
      const SizedBox(height: 10),
      TextButton(onPressed: widget.onCancel, child: const Text('Cancel', style: TextStyle(color: Color(0xFF9090A0)))),
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search communities...', hintStyle: const TextStyle(color: Color(0xFF9090A0)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF9090A0), size: 20),
          filled: true, fillColor: const Color(0xFF0F0F1A),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      const SizedBox(height: 8),
      Container(
        constraints: const BoxConstraints(maxHeight: 180),
        decoration: BoxDecoration(color: const Color(0xFF0F0F1A), borderRadius: BorderRadius.circular(12)),
        child: _filtered.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No communities found', style: TextStyle(color: Color(0xFF9090A0), fontSize: 13)),
              )
            : ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _filtered.length,
                itemBuilder: (context, i) {
                  final c = _filtered[i];
                  final isChurch = c['church_id'] != null;
                  final churchName = c['churches']?['name'] as String?;
                  final isChat = isChurch && c['is_bible_study'] != true;
                  final String subtitle;
                  if (isChat) {
                    subtitle = churchName != null ? '$churchName · Group Chat' : 'Group Chat';
                  } else if (isChurch && churchName != null) {
                    subtitle = c['book'] != null ? '$churchName · ${c['book']}' : churchName;
                  } else {
                    subtitle = c['book'] as String? ?? '';
                  }
                  final selected = _selectedCommunity?['id'] == c['id'];
                  return InkWell(
                    onTap: () => setState(() => _selectedCommunity = c),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white12 : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c['name'] ?? '', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(subtitle, style: const TextStyle(color: Color(0xFF9090A0), fontSize: 12)),
                          ],
                        ])),
                        if (selected) const Icon(Icons.check, color: Colors.white, size: 16),
                      ]),
                    ),
                  );
                },
              ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _commentController, maxLines: 3, style: const TextStyle(color: Colors.white),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        decoration: InputDecoration(
          hintText: 'Add a comment (optional)', hintStyle: const TextStyle(color: Color(0xFF9090A0)),
          filled: true, fillColor: const Color(0xFF0F0F1A),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5B4FCF), width: 1.5)),
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextButton(onPressed: widget.onCancel, child: const Text('Cancel', style: TextStyle(color: Color(0xFF9090A0))))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton(
          onPressed: _isPosting || _selectedCommunity == null ? null : _share,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5B4FCF), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: _isPosting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Share'),
        )),
      ]),
    ]);
  }
}