import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/app_cache.dart';
import '../../services/home_service.dart';
import '../bible/bible_books_screen.dart';
import '../bible/bible_reader_screen.dart';
import 'reading_history_screen.dart';
import '../../services/bible_service.dart';
import '../auth/signup_screen.dart';
import '../ai/ai_chat_screen.dart';
import '../../widgets/ai_consent_dialog.dart';
import '../../widgets/guest_signup_sheet.dart';
import '../../services/guest_session.dart';
import '../../widgets/rate_us_dialog.dart';
import '../../widgets/strike_warning_dialog.dart';
import '../profile/appeal_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _homeService = HomeService();
  final _bibleService = BibleService();
  final _client = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  int _streak = 0;
  List<String> _daysRead = [];
  List<Map<String, dynamic>> _announcements = [];
  Map<String, dynamic> _verseOfDay = {};
  bool _isLoading = true;
  String? _error;
  bool _isRestricted = false;
  bool _isNavigatingToVerse = false;
  RealtimeChannel? _communityChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHomeData();
    _checkRestrictionStatus();
    _subscribeToCommunityChanges();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StrikeWarningDialog.checkAndShow(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_communityChannel != null) {
      Supabase.instance.client.removeChannel(_communityChannel!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppCache.instance.invalidateHomeData();
      _loadHomeData(forceRefresh: true);
    }
  }

  void _subscribeToCommunityChanges() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    _communityChannel = _client
        .channel('home_community_changes_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            AppCache.instance.invalidateHomeData();
            _loadHomeData(forceRefresh: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'communities',
          callback: (_) {
            AppCache.instance.invalidateHomeData();
            _loadHomeData(forceRefresh: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'communities',
          callback: (_) {
            AppCache.instance.invalidateHomeData();
            _loadHomeData(forceRefresh: true);
          },
        )
        .subscribe();
  }

  // ── CHECK RESTRICTION STATUS ───────────────────────────────
  Future<void> _checkRestrictionStatus() async {
    try {
      final result = await _client.rpc('get_my_restriction_status');
      if (result != null && mounted) {
        final info = Map<String, dynamic>.from(result);
        setState(() => _isRestricted = info['is_restricted'] == true);
      }
    } catch (e) {
      print('checkRestrictionStatus error: $e');
    }
  }

  Future<void> _loadHomeData({bool forceRefresh = false}) async {
    if (!mounted) return;

    // If we have cached home data, show it instantly then refresh in background
    final cached = AppCache.instance.homeData;
    if (cached != null && !forceRefresh) {
      setState(() {
        _profile = cached['profile'] as Map<String, dynamic>?;
        _streak = cached['streak'] as int;
        _daysRead = List<String>.from(cached['daysRead'] as List);
        _announcements = List<Map<String, dynamic>>.from(cached['announcements'] as List);
        _verseOfDay = cached['verseOfDay'] as Map<String, dynamic>;
        _isLoading = false;
      });
      // Fetch fresh data silently in background
      _fetchAndCacheHomeData(showLoading: false);
      return;
    }

    // First open — show spinner and wait
    setState(() { _isLoading = true; _error = null; });
    await _fetchAndCacheHomeData(showLoading: true);
  }

  Future<void> _fetchAndCacheHomeData({required bool showLoading}) async {
    try {
      await _homeService.updateStreak();

      final results = await Future.wait([
        _homeService.getUserProfile(),
        _homeService.getStreak(),
        _homeService.getDaysReadThisWeek(),
        _homeService.getAnnouncements(),
        _bibleService.getUserTranslationId(),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final streak = results[1] as int;
      final daysRead = List<String>.from(results[2] as List);
      final announcements = List<Map<String, dynamic>>.from(results[3] as List);
      final translationId = results[4] as String;
      final verse = await _homeService.getVerseOfTheDay(translationId);

      AppCache.instance.setStreakCount(streak);
      AppCache.instance.setHomeData(
        profile: profile,
        streak: streak,
        daysRead: daysRead,
        announcements: announcements,
        verseOfDay: verse,
      );
      if (AppCache.instance.preferredTranslation == null) {
        AppCache.instance.setPreferredTranslation(translationId);
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _streak = streak;
          _daysRead = daysRead;
          _announcements = announcements;
          _verseOfDay = verse;
          _isLoading = false;
        });

        if (streak == 3 || streak == 7 || streak == 30 || streak == 100) {
          RateUsDialog.maybeShow(context);
        }
      }
    } catch (e) {
      print('loadHomeData error: $e');
      if (showLoading && mounted) {
        setState(() {
          _error = 'Could not load your home screen. Please check your connection.';
          _isLoading = false;
        });
      }
    }
  }


  // ── OPEN VERSE OF THE DAY ───────────────────────────────────
  // Navigates directly to the exact book/chapter the verse of the
  // day is from, rather than just opening the book list (which
  // duplicated the existing Bible tab and made this button
  // pointless). Needs one extra lookup for totalChapters since
  // that's required by BibleReaderScreen but isn't part of the
  // verse-of-day data itself.
  Future<void> _openVerseOfDay() async {
    final bookId = _verseOfDay['bookId'] as String?;
    final bookName = _verseOfDay['bookName'] as String?;
    final chapter = _verseOfDay['chapter'] as int?;

    if (bookId == null || bookName == null || chapter == null) {
      // Data not loaded yet or fallback shape missing — fall back
      // to the book list rather than doing nothing.
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BibleBooksScreen()),
      );
      return;
    }

    setState(() => _isNavigatingToVerse = true);
    try {
      final translationId = await _bibleService.getUserTranslationId();
      final books = await _bibleService.getBooks(translationId);
      final book = books.firstWhere(
        (b) => (b['id'] as String).toUpperCase() == bookId.toUpperCase(),
        orElse: () => <String, dynamic>{},
      );

      if (book.isEmpty) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BibleBooksScreen()),
          );
        }
        return;
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BibleReaderScreen(
              translationId: translationId,
              bookId: book['id'] as String,
              bookName: book['name'] as String,
              chapterNumber: chapter,
              totalChapters: book['numberOfChapters'] as int,
            ),
          ),
        );
      }
    } catch (e) {
      print('openVerseOfDay error: $e');
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BibleBooksScreen()),
        );
      }
    } finally {
      if (mounted) setState(() => _isNavigatingToVerse = false);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  List<DateTime> _getWeekDays() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday % 7));
    return List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
  }

  bool _wasReadOn(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return _daysRead.contains('$y-$m-$d');
  }

  @override
  Widget build(BuildContext context) {
    final weekDays = _getWeekDays();
    final dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final displayName =
        _profile?['display_name'] ?? _profile?['username'] ?? 'Friend';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Passage',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.try_sms_star, color: Colors.white),
            onPressed: () async {
              if (GuestSession.isGuest) {
                GuestSignUpSheet.show(context);
                return;
              }
              final allowed = await AiConsentDialog.requestConsent(context);
              if (allowed && context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiChatScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off,
                            color: Colors.white54, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loadHomeData,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      AppCache.instance.invalidateHomeData();
      AppCache.instance.invalidateHomeData();
      await _loadHomeData(forceRefresh: true);
                      await _checkRestrictionStatus();
                    },
                    color: Colors.white,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),

                          // ── RESTRICTED STATUS BANNER ──────
                          if (_isRestricted) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.red.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.block,
                                          color: Colors.red, size: 20),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Chat access restricted',
                                              style: TextStyle(
                                                color: Colors.red,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'You can no longer post or reply in communities or churches. This is permanent. All other features remain available.',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 38,
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => const AppealScreen()),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(color: Colors.white24),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: const Text('Appeal this restriction', style: TextStyle(fontSize: 13)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // ── TOP ROW: Greeting + Streak ────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getGreeting(),
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 14),
                                  ),
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    const Text('🔥',
                                        style: TextStyle(fontSize: 18)),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$_streak',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // ── WEEKLY CALENDAR STRIP ─────────
                          // Tappable — opens the full reading
                          // history screen (every day read since
                          // account creation, grouped by month).
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const ReadingHistoryScreen()),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(7, (index) {
                                final day = weekDays[index];
                                final isToday =
                                    day.day == DateTime.now().day &&
                                        day.month == DateTime.now().month;
                                final wasRead = _wasReadOn(day);
                                return Column(
                                  children: [
                                    Text(
                                      dayLabels[index],
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: isToday
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: wasRead
                                            ? Colors.white
                                            : isToday
                                                ? Colors.white.withOpacity(0.3)
                                                : Colors.black,
                                        shape: BoxShape.circle,
                                        border: isToday
                                            ? Border.all(
                                                color: Colors.white, width: 1.5)
                                            : null,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${day.day}',
                                        style: TextStyle(
                                          color: wasRead
                                              ? Colors.black
                                              : Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── VERSE OF THE DAY ──────────────
                          // Now navigates directly to the exact
                          // book/chapter the verse is from, instead
                          // of just opening the book list (which
                          // made this button redundant with the
                          // existing Bible tab).
                          GestureDetector(
                            onTap: _isNavigatingToVerse ? null : _openVerseOfDay,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.white12, Colors.white24],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(children: [
                                    Icon(Icons.menu_book_rounded,
                                        color: Colors.white, size: 16),
                                    SizedBox(width: 6),
                                    Text(
                                      'VERSE OF THE DAY',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ]),
                                  const SizedBox(height: 12),
                                  Text(
                                    '"${(_verseOfDay['text'] ?? '').toString().replaceAll('?', '? ').replaceAll(';', '; ').replaceAll(':', ': ').replaceAll('.', '. ').replaceAll('!', '! ').replaceAll(',', ', ').replaceAll('  ', ' ').trim()}"',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      height: 1.5,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '— ${_verseOfDay['ref'] ?? ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: _isNavigatingToVerse
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                color: Colors.white, strokeWidth: 2),
                                          )
                                        : const Text(
                                            'Read this verse →',
                                            style: TextStyle(
                                                color: Colors.white, fontSize: 12),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── ANNOUNCEMENTS ─────────────────
                          const Text(
                            'Announcements',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),

                          _announcements.isEmpty
                              ? Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Column(
                                    children: [
                                      Icon(Icons.church_outlined,
                                          color: Colors.white, size: 32),
                                      SizedBox(height: 10),
                                      Text(
                                        'No announcements yet',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Join a community to see announcements from church admins here.',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _announcements.length,
                                  itemBuilder: (context, index) {
                                    final a = _announcements[index];
                                    final user = a['users'];
                                    final authorName =
                                        user?['display_name'] ?? 'Admin';
                                    final createdAt =
                                        DateTime.parse(a['created_at']);
                                    final timeAgo = _timeAgo(createdAt);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: a['source_type'] ==
                                                        'church'
                                                    ? Colors.blue
                                                        .withOpacity(0.15)
                                                    : Colors.white
                                                        .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Row(children: [
                                                Icon(
                                                  a['source_type'] == 'church'
                                                      ? Icons.church_outlined
                                                      : Icons.people_outline,
                                                  color:
                                                      a['source_type'] == 'church'
                                                          ? Colors.blue
                                                          : Colors.white,
                                                  size: 11,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  a['source_name'] ?? '',
                                                  style: TextStyle(
                                                    color: a['source_type'] ==
                                                            'church'
                                                        ? Colors.blue
                                                        : Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ]),
                                            ),
                                            const Spacer(),
                                            Text(timeAgo,
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12)),
                                          ]),
                                          const SizedBox(height: 10),
                                          Text(
                                            a['content'] ?? '',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              height: 1.5,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text('— $authorName',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12)),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}