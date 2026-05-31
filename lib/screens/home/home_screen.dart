import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/home_service.dart';
import '../bible/bible_books_screen.dart';
import '../../services/bible_service.dart';
import '../auth/signup_screen.dart';
import '../ai/ai_chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _homeService = HomeService();

  Map<String, dynamic>? _profile;
  int _streak = 0;
  List<String> _daysRead = [];
  List<Map<String, dynamic>> _announcements = [];
  Map<String, String> _verseOfDay = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    // Update streak first (void — just triggers the server-side logic)
    await _homeService.updateStreak();

    // Then fetch all the data separately
    final profile = await _homeService.getUserProfile();
    print('Profile: $profile'); 
    final streak = await _homeService.getStreak();
    final daysRead = await _homeService.getDaysReadThisWeek();
    final announcements = await _homeService.getAnnouncements();
    final translationId = await BibleService().getUserTranslationId();
    final verse = await _homeService.getVerseOfTheDay(translationId);

    if (mounted) {
      setState(() {
        _profile = profile;
        _streak = streak;
        _daysRead = daysRead;
        _announcements = announcements;
        _verseOfDay = verse;
        _isLoading = false;
      });
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
    final dateStr = date.toUtc().toIso8601String().substring(0, 10);
    return _daysRead.contains(dateStr);
  }

  @override
  Widget build(BuildContext context) {
    final weekDays = _getWeekDays();
    final dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final displayName = _profile?['display_name'] ?? _profile?['username'] ?? 'Friend';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Passage',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.try_sms_star, color: Colors.white),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiChatScreen()),
              );
            }
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SignUpScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadHomeData,
                color: Colors.white,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),

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
                          // Streak badge
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(7, (index) {
                          final day = weekDays[index];
                          final isToday = day.day == DateTime.now().day &&
                              day.month == DateTime.now().month;
                          final wasRead = _wasReadOn(day);

                          return Column(
                            children: [
                              Text(
                                dayLabels[index],
                                style: TextStyle(
                                    color: isToday
                                      ? Colors.white
                                      : Colors.white,
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
                                          color: Colors.white,
                                          width: 1.5)
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${day.day}',
                                  style: TextStyle(
                                    color: wasRead ? Colors.black : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),

                      const SizedBox(height: 28),

                      // ── VERSE OF THE DAY ──────────────
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const BibleBooksScreen()),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.white12, Colors.white24],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
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
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '"${_verseOfDay['text'] ?? ''}"',
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
                                child: const Text(
                                  'Open Bible Reader →',
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
                                      color: Colors.white,
                                      fontSize: 13),
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
                                final community = a['communities'];
                                final user = a['users'];
                                final communityName =
                                    community?['name'] ?? 'Community';
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
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: a['source_type'] == 'church'
                                                  ? Colors.blue.withOpacity(0.15)
                                                  : Colors.white.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  a['source_type'] == 'church'
                                                      ? Icons.church_outlined
                                                      : Icons.people_outline,
                                                  color: a['source_type'] == 'church'
                                                      ? Colors.blue
                                                      : Colors.white,
                                                  size: 11,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  a['source_name'] ?? '',
                                                  style: TextStyle(
                                                    color: a['source_type'] == 'church'
                                                        ? Colors.blue
                                                        : Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            timeAgo,
                                            style: const TextStyle(
                                                color: Colors.grey, fontSize: 12),
                                          ),
                                        ],
                                      ),
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
                                      Text(
                                        '— $authorName',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
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