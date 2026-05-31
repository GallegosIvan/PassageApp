import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// BIBLE SERVICE
// Uses the Free Use Bible API by AO Lab — bible.helloao.org
// No API key required. Free for commercial use.
// Docs: https://bible.helloao.org/docs/reference/
// ============================================================

class BibleService {
  static const String _baseUrl = 'https://bible.helloao.org/api';

  final _client = Supabase.instance.client;

  // ── GET USER'S PREFERRED TRANSLATION ─────────────────────
  // API CALL: Supabase DB — reads preferred_bible_id from users table
  // Returns 'BSB' (Berean Standard Bible) as the default
  Future<String> getUserTranslationId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'BSB';

    try {
      final response = await _client
          .from('users')
          .select('preferred_bible_id')
          .eq('id', userId)
          .single();

      return response['preferred_bible_id'] ?? 'BSB';
    } catch (e) {
      print('getUserTranslationId error: $e');
      return 'BSB';
    }
  }

  // ── UPDATE USER'S PREFERRED TRANSLATION ──────────────────
  // API CALL: Supabase DB — saves the user's chosen translation
  Future<void> setUserTranslationId(String translationId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client
        .from('users')
        .update({'preferred_bible_id': translationId})
        .eq('id', userId);
  }

  // ── GET ALL AVAILABLE TRANSLATIONS ───────────────────────
  // API CALL: Free Use Bible API
  // Endpoint: GET /api/available_translations.json
  // Returns list of all 1000+ translations available
  Future<List<Map<String, dynamic>>> getAvailableTranslations() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/available_translations.json'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['translations']);
    }
    throw Exception('Failed to load translations');
  }

  // ── GET ALL BOOKS FOR A TRANSLATION ──────────────────────
  // API CALL: Free Use Bible API
  // Endpoint: GET /api/{translation}/books.json
  // e.g. GET /api/BSB/books.json
  Future<List<Map<String, dynamic>>> getBooks(String translationId) async {
    final url = '$_baseUrl/$translationId/books.json';
    print('Books URL: $url');
  
    final response = await http.get(Uri.parse(url));
    print('Books status: ${response.statusCode}');
    print('Books response start: ${response.body.substring(0, 100)}');
  
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['books']);
    }
    throw Exception('Failed to load books');
  }

  // ── GET A FULL CHAPTER ────────────────────────────────────
  // API CALL: Free Use Bible API
  // Endpoint: GET /api/{translation}/{book}/{chapter}.json
  // e.g. GET /api/BSB/GEN/1.json
  //
  // The response contains a chapter.content array with mixed types:
  //   { type: 'heading', content: [...] }
  //   { type: 'verse', number: 1, content: [...] }
  //   { type: 'line_break' }
  //
  // This method returns the raw response so screens can use
  // both parseVerses() and access metadata like next/prev chapter links.
  Future<Map<String, dynamic>> getChapter(
    String translationId, String bookId, int chapterNumber) async {
  final url = '$_baseUrl/$translationId/$bookId/$chapterNumber.json';
  print('Fetching: $url');
  
  try {
    final response = await http.get(Uri.parse(url));
    print('Status code: ${response.statusCode}');
    print('Response body: ${response.body.substring(0, 200)}');
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load chapter: ${response.statusCode}');
  } catch (e) {
    print('Error: $e');
    rethrow;
  }
}

  // ── PARSE VERSES FROM CHAPTER CONTENT ────────────────────
  // The API returns content as a mixed array of headings, verses, line breaks.
  // This helper extracts just the verses with clean readable text.
  //
  // Input: chapter['chapter']['content'] from getChapter()
  // Output: [ { 'number': 1, 'text': 'In the beginning...' }, ... ]
  List<Map<String, dynamic>> parseVerses(List<dynamic> content) {
  final verses = <Map<String, dynamic>>[];

  for (final item in content) {
    if (item is! Map) continue;
    if (item['type'] != 'verse') continue;

    final verseContent = item['content'];
    if (verseContent is! List) continue;

    final textBuffer = StringBuffer();

    for (final part in verseContent) {
      if (part is String) {
        textBuffer.write(part);
      } else if (part is Map) {
        if (part['text'] != null) {
          textBuffer.write(part['text']);
        }
      }
    }

    final text = textBuffer.toString().trim();
    if (text.isEmpty) continue;

    verses.add({
      'number': item['number'] ?? verses.length + 1,
      'text': text,
    });
  }

  return verses;
  }


  // ── GET CHAPTER NUMBERS FOR A BOOK ───────────────────────
  // The books endpoint includes numberOfChapters and firstChapterNumber
  // so we can generate chapter numbers without an extra API call.
  // Returns: [1, 2, 3, ..., n]
  List<int> getChapterNumbers(Map<String, dynamic> book) {
    final count = book['numberOfChapters'] as int;
    final first = (book['firstChapterNumber'] as int?) ?? 1;
    return List.generate(count, (i) => first + i);
  }

  // ── SAVE ANNOTATION ───────────────────────────────────────
  // API CALL: Supabase DB
  // Upserts an annotation — updates if one exists for this verse,
  // inserts a new one if not.
  Future<void> saveAnnotation({
    required String book,
    required int chapter,
    required int verseStart,
    int? verseEnd,
    required String note,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      print('Saving annotation for user: $userId, book: $book, chapter: $chapter, verse: $verseStart');

      final existing = await _client
          .from('annotations')
          .select('id')
          .eq('user_id', userId)
          .eq('book', book)
          .eq('chapter', chapter)
          .eq('verse_start', verseStart)
          .maybeSingle();

      print('Existing annotation: $existing');

      if (existing != null) {
        await _client
            .from('annotations')
            .update({'note': note})
            .eq('id', existing['id']);
        print('Updated annotation');
      } else {
        await _client.from('annotations').insert({
          'user_id': userId,
          'book': book,
          'chapter': chapter,
          'verse_start': verseStart,
          'verse_end': verseEnd,
          'note': note,
          'shared': false,
        });
        print('Inserted annotation');
      }
    } catch (e, st) {
      print('saveAnnotation error: $e');
      print('saveAnnotation stack: $st');
      rethrow;
    }
  }

  // ── GET USER ANNOTATIONS FOR A CHAPTER ───────────────────
  // API CALL: Supabase DB — fetches all annotations for a chapter
  Future<List<Map<String, dynamic>>> getAnnotationsForChapter({
    required String book,
    required int chapter,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('annotations')
          .select()
          .eq('user_id', userId)
          .eq('book', book)
          .eq('chapter', chapter)
          .order('verse_start');

      return List<Map<String, dynamic>>.from(response);
    } catch (e, st) {
      print('BibleService.getAnnotationsForChapter failed: $e');
      print(st);
      return [];
    }
  }

  // ── DELETE ANNOTATION ─────────────────────────────────────
  // API CALL: Supabase DB — deletes an annotation by its id
  Future<void> deleteAnnotation(String annotationId) async {
    await _client.from('annotations').delete().eq('id', annotationId);
  }
}