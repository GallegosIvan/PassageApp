import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// APP CACHE
// Singleton that holds frequently accessed data in memory.
// Screens read from cache first — only fetch from Supabase
// when cache is empty or explicitly invalidated.
//
// Cache is cleared on logout so the next user starts fresh.
// ============================================================

class AppCache {
  AppCache._();
  static final AppCache instance = AppCache._();

  final _client = Supabase.instance.client;

  // ── USER ──────────────────────────────────────────────────
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;
  void setCurrentUser(Map<String, dynamic> user) => _currentUser = user;

  // ── COMMUNITIES ───────────────────────────────────────────
  List<Map<String, dynamic>>? _myCommunities;
  List<Map<String, dynamic>>? get myCommunities => _myCommunities;
  void setMyCommunities(List<Map<String, dynamic>> c) => _myCommunities = c;
  void addCommunity(Map<String, dynamic> c) {
    _myCommunities ??= [];
    _myCommunities!.removeWhere((e) => e['id'] == c['id']);
    _myCommunities!.insert(0, c);
  }
  void removeCommunity(String id) =>
      _myCommunities?.removeWhere((e) => e['id'] == id);
  void invalidateCommunities() => _myCommunities = null;

  // ── CHURCHES ─────────────────────────────────────────────
  List<Map<String, dynamic>>? _myChurches;
  List<Map<String, dynamic>>? get myChurches => _myChurches;
  void setMyChurches(List<Map<String, dynamic>> c) => _myChurches = c;
  void addChurch(Map<String, dynamic> c) {
    _myChurches ??= [];
    _myChurches!.removeWhere((e) => e['id'] == c['id']);
    _myChurches!.insert(0, c);
  }
  void removeChurch(String id) =>
      _myChurches?.removeWhere((e) => e['id'] == id);
  void invalidateChurches() => _myChurches = null;

  // ── READING STREAK ────────────────────────────────────────
  int? _streakCount;
  int? get streakCount => _streakCount;
  void setStreakCount(int count) => _streakCount = count;
  void invalidateStreak() => _streakCount = null;

  // ── READING HISTORY ───────────────────────────────────────
  Set<String>? _readChapters; // "BookId_chapter" keys
  Set<String>? get readChapters => _readChapters;
  void setReadChapters(Set<String> chapters) => _readChapters = chapters;
  void markChapterRead(String bookId, int chapter) {
    _readChapters?.add('${bookId}_$chapter');
  }
  void removeChapterRead(String bookId, int chapter) {
    _readChapters?.remove('${bookId}_$chapter');
  }
  void invalidateReadHistory() => _readChapters = null;

  // ── BIBLE TRANSLATIONS ────────────────────────────────────
  // Cache the list of available translations (rarely changes)
  List<Map<String, dynamic>>? _bibleTranslations;
  List<Map<String, dynamic>>? get bibleTranslations => _bibleTranslations;
  void setBibleTranslations(List<Map<String, dynamic>> t) =>
      _bibleTranslations = t;

  // ── PREFERRED TRANSLATION ─────────────────────────────────
  String? _preferredTranslation;
  String? get preferredTranslation => _preferredTranslation;
  void setPreferredTranslation(String t) => _preferredTranslation = t;

  // ── BIBLE BOOKS ───────────────────────────────────────────
  // Cache books per translation
  final Map<String, List<Map<String, dynamic>>> _booksByTranslation = {};
  List<Map<String, dynamic>>? getBooks(String translationId) =>
      _booksByTranslation[translationId];
  void setBooks(String translationId, List<Map<String, dynamic>> books) =>
      _booksByTranslation[translationId] = books;
  void invalidateBooks(String translationId) => _booksByTranslation.remove(translationId);

  // ── BIBLE CHAPTERS ────────────────────────────────────────
  // Cache chapters per book
  final Map<String, List<Map<String, dynamic>>> _chaptersByBook = {};
  List<Map<String, dynamic>>? getChapters(String bookId) =>
      _chaptersByBook[bookId];
  void setChapters(String bookId, List<Map<String, dynamic>> chapters) =>
      _chaptersByBook[bookId] = chapters;

  // ── HIGHLIGHTS & BOOKMARKS ────────────────────────────────
  List<Map<String, dynamic>>? _highlights;
  List<Map<String, dynamic>>? get highlights => _highlights;
  void setHighlights(List<Map<String, dynamic>> h) => _highlights = h;
  void addHighlight(Map<String, dynamic> h) {
    _highlights ??= [];
    _highlights!.removeWhere((e) => e['id'] == h['id']);
    _highlights!.add(h);
  }
  void removeHighlight(String id) =>
      _highlights?.removeWhere((e) => e['id'] == id);
  void invalidateHighlights() => _highlights = null;

  // ── COMMUNITY POSTS ───────────────────────────────────────
  // Cache posts per community
  final Map<String, List<Map<String, dynamic>>> _postsByCommunity = {};
  List<Map<String, dynamic>>? getPosts(String communityId) =>
      _postsByCommunity[communityId];
  void setPosts(String communityId, List<Map<String, dynamic>> posts) =>
      _postsByCommunity[communityId] = posts;
  void invalidatePosts(String communityId) =>
      _postsByCommunity.remove(communityId);

  // ── CHURCH MESSAGES ───────────────────────────────────────
  // Cache messages per community
  final Map<String, List<Map<String, dynamic>>> _messagesByCommunity = {};
  List<Map<String, dynamic>>? getMessages(String communityId) =>
      _messagesByCommunity[communityId];
  void setMessages(String communityId, List<Map<String, dynamic>> messages) =>
      _messagesByCommunity[communityId] = messages;
  void addMessage(String communityId, Map<String, dynamic> message) {
    _messagesByCommunity[communityId] ??= [];
    _messagesByCommunity[communityId]!.add(message);
  }
  void invalidateMessages(String communityId) =>
      _messagesByCommunity.remove(communityId);

  // ── BLOCKED USERS ─────────────────────────────────────────
  Set<String>? _blockedUserIds;
  Set<String>? get blockedUserIds => _blockedUserIds;
  void setBlockedUserIds(Set<String> ids) => _blockedUserIds = ids;
  void addBlockedUser(String id) {
    _blockedUserIds ??= {};
    _blockedUserIds!.add(id);
  }
  void removeBlockedUser(String id) => _blockedUserIds?.remove(id);
  void invalidateBlockedUsers() => _blockedUserIds = null;

  // ── AI CONVERSATIONS ─────────────────────────────────────────
  List<Map<String, dynamic>>? _aiConversations;
  List<Map<String, dynamic>>? get aiConversations => _aiConversations;
  void setAiConversations(List<Map<String, dynamic>> c) => _aiConversations = c;
  void invalidateAiConversations() => _aiConversations = null;

  // ── PROFILE DATA ─────────────────────────────────────────────
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? get profileData => _profileData;
  void setProfileData(Map<String, dynamic> data) => _profileData = data;
  void invalidateProfileData() => _profileData = null;

  // ── HOME SCREEN DATA ─────────────────────────────────────────
  Map<String, dynamic>? _homeData;
  Map<String, dynamic>? get homeData => _homeData;
  void setHomeData({
    required Map<String, dynamic>? profile,
    required int streak,
    required List<String> daysRead,
    required List<Map<String, dynamic>> announcements,
    required Map<String, dynamic> verseOfDay,
  }) {
    _homeData = {
      'profile': profile,
      'streak': streak,
      'daysRead': daysRead,
      'announcements': announcements,
      'verseOfDay': verseOfDay,
    };
  }
  void invalidateHomeData() => _homeData = null;

  // ── CLEAR ALL (on logout) ─────────────────────────────────
  void clear() {
    _currentUser = null;
    _myCommunities = null;
    _myChurches = null;
    _streakCount = null;
    _homeData = null;
    _profileData = null;
    _aiConversations = null;
    _readChapters = null;
    _bibleTranslations = null;
    _preferredTranslation = null;
    _booksByTranslation.clear();
    _chaptersByBook.clear();
    _highlights = null;
    _postsByCommunity.clear();
    _messagesByCommunity.clear();
    _blockedUserIds = null;
  }
}