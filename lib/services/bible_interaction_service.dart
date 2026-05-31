import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// BIBLE INTERACTION SERVICE
// Handles highlights, bookmarks, and sharing to communities.
// ============================================================

class BibleInteractionService {
  final _client = Supabase.instance.client;

  // ── HIGHLIGHTS ────────────────────────────────────────────

  // API CALL: Supabase DB — fetch all highlights for a chapter
  Future<List<Map<String, dynamic>>> getHighlightsForChapter({
    required String bookId,
    required int chapter,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('highlights')
          .select()
          .eq('user_id', userId)
          .eq('book_id', bookId)
          .eq('chapter', chapter);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getHighlightsForChapter error: $e');
      return [];
    }
  }

  // API CALL: Supabase DB — save or update a highlight
  Future<void> saveHighlight({
    required String bookId,
    required String bookName,
    required int chapter,
    required int verse,
    required String color,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    await _client.from('highlights').upsert({
      'user_id': userId,
      'book_id': bookId,
      'book_name': bookName,
      'chapter': chapter,
      'verse': verse,
      'color': color,
    });
  }

  // API CALL: Supabase DB — remove a highlight
  Future<void> removeHighlight({
    required String bookId,
    required int chapter,
    required int verse,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client
        .from('highlights')
        .delete()
        .eq('user_id', userId)
        .eq('book_id', bookId)
        .eq('chapter', chapter)
        .eq('verse', verse);
  }

  // ── BOOKMARKS ─────────────────────────────────────────────

  // API CALL: Supabase DB — get all user bookmarks (max 3)
  Future<List<Map<String, dynamic>>> getBookmarks() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('bookmarks')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getBookmarks error: $e');
      return [];
    }
  }

  // API CALL: Supabase DB — save bookmark in a color slot
  Future<void> saveBookmark({
    required String bookId,
    required String bookName,
    required int chapter,
    required String color,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    await _client.from('bookmarks').upsert({
      'user_id': userId,
      'book_id': bookId,
      'book_name': bookName,
      'chapter': chapter,
      'color': color,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // API CALL: Supabase DB — remove a bookmark by color slot
  Future<void> removeBookmark(String color) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client
        .from('bookmarks')
        .delete()
        .eq('user_id', userId)
        .eq('color', color);
  }

  // ── CHECK SUBSCRIPTION ────────────────────────────────────

  // API CALL: Supabase DB — checks if user has active paid plan
  // Used to gate the "Share to community" feature
  Future<bool> isPaidUser() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final response = await _client
          .from('subscriptions')
          .select('plan, status')
          .eq('user_id', userId)
          .single();
      
      print('Subscription: $response');

      final plan = response['plan'] as String;
      final status = response['status'] as String;
      return (plan == 'monthly' || plan == 'annual') && status == 'active';
    } catch (e) {
      return false;
    }
  }
}