import 'package:supabase_flutter/supabase_flutter.dart';
import 'church_service.dart';

// ============================================================
// HOME SERVICE
// Handles all Supabase calls for the home screen.
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;

class HomeService {
  final _client = Supabase.instance.client;

  // ── GET USER PROFILE ──────────────────────────────────────
  // API CALL: Supabase DB — fetches current user's profile
  Future<Map<String, dynamic>?> getUserProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final response = await _client
          .from('users')
          .select('username, display_name, avatar_url, denomination')
          .eq('id', userId)
          .single();
      return response;
    } catch (e) {
      print('getUserProfile error: $e');
      return null;
    }
  }

  // ── GET OR CREATE STREAK ──────────────────────────────────
  // API CALL: Supabase DB — fetches user's reading streak
  // Streak is tracked via a simple table we'll add
  Future<int> getStreak() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;

    try {
      final response = await _client
          .from('reading_streaks')
          .select('streak_count')
          .eq('user_id', userId)
          .maybeSingle();
      return response?['streak_count'] ?? 0;
    } catch (e) {
      print('getStreak error: $e');
      return 0;
    }
  }

  // ── UPDATE STREAK ─────────────────────────────────────────
  // API CALL: Supabase DB — called when user opens Bible reader
  Future<void> updateStreak() async {
    try {
      // API CALL: Supabase DB function — runs server-side via RPC
      await _client.rpc('update_user_streak');
    } catch (e) {
      print('updateStreak error: $e');
    }
  }

  // ── GET DAYS READ THIS WEEK ───────────────────────────────
  // API CALL: Supabase DB — returns list of dates read this week
  Future<List<String>> getDaysReadThisWeek() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final now = DateTime.now().toUtc();
      final weekStart =
          now.subtract(Duration(days: now.weekday % 7)).toIso8601String().substring(0, 10);

      final response = await _client
          .from('reading_days')
          .select('read_date')
          .eq('user_id', userId)
          .gte('read_date', weekStart);

      return List<String>.from(
          (response as List).map((r) => r['read_date'] as String));
    } catch (e) {
      print('getDaysReadThisWeek error: $e');
      return [];
    }
  }

  // ── GET ANNOUNCEMENTS ─────────────────────────────────────
  // API CALL: Supabase DB — fetches announcements from communities
  // the user belongs to, posted by admins only
  // API CALL: ChurchService.getHomeAnnouncements → Supabase DB
// Fetches announcements from both communities and churches
// in one sorted feed
  Future<List<Map<String, dynamic>>> getAnnouncements() async {
    return await ChurchService().getHomeAnnouncements();
  }

  // ── GET VERSE OF THE DAY ──────────────────────────────────
  // No API call — uses day of year to pick a consistent verse
  // Same verse all day for all users, changes at midnight
  Future<Map<String, String>> getVerseOfTheDay(String translationId) async {
    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year, 1, 1))
        .inDays + 1;

    try {
      // API CALL: Supabase DB — fetch today's verse reference
      final row = await _client
          .from('verses_of_day')
          .select('book_id, book_name, chapter, verse')
          .eq('day_of_year', dayOfYear)
          .single();

      final bookId = row['book_id'] as String;
      final bookName = row['book_name'] as String;
      final chapter = row['chapter'] as int;
      final verse = row['verse'] as int;

      // API CALL: Free Use Bible API — fetch the actual verse text
      final url =
          'https://bible.helloao.org/api/$translationId/$bookId/$chapter.json';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['chapter']['content'] as List<dynamic>;

        for (final item in content) {
          if (item is Map &&
              item['type'] == 'verse' &&
              item['number'] == verse) {
            final verseContent = item['content'] as List<dynamic>;
            final textBuffer = StringBuffer();
            for (final part in verseContent) {
              if (part is String) textBuffer.write(part);
              if (part is Map && part['text'] != null) {
                textBuffer.write(part['text']);
              }
            }
            return {
              'ref': '$bookName $chapter:$verse',
              'text': textBuffer.toString().trim(),
            };
          }
        }
      }
    } catch (e) {
      print('getVerseOfTheDay error: $e');
    }

    return {
      'ref': 'John 3:16',
      'text': 'For God so loved the world that He gave His one and only Son, that everyone who believes in Him shall not perish but have eternal life.',
    };
  }
}