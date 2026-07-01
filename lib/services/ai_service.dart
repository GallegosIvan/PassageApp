import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// AI SERVICE
// Handles all communication with the bible-ai Edge Function.
// The Anthropic API key never touches Flutter code.
// ============================================================

class AiService {
  final _client = Supabase.instance.client;

  // ── START NEW CONVERSATION ────────────────────────────────
  Future<String> startConversation(String title) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    final response = await _client
        .from('ai_conversations')
        .insert({
          'user_id': userId,
          'title': title,
        })
        .select()
        .single();

    return response['id'] as String;
  }

  // ── GET CONVERSATIONS ─────────────────────────────────────
  Future<List<Map<String, dynamic>>> getConversations({bool isPaid = false}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      var query = _client
          .from('ai_conversations')
          .select('id, title, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      // Free users only see their 5 most recent conversations
      if (!isPaid) {
        query = query.limit(5);
      }

      final response = await query;
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getConversations error: $e');
      return [];
    }
  }

  // ── GET MESSAGES FOR CONVERSATION ────────────────────────
  Future<List<Map<String, dynamic>>> getMessages(
      String conversationId) async {
    try {
      final response = await _client
          .from('ai_messages')
          .select('id, role, content, created_at')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getMessages error: $e');
      return [];
    }
  }

  // ── DELETE CONVERSATION ───────────────────────────────────
  Future<void> deleteConversation(String conversationId) async {
    await _client
        .from('ai_conversations')
        .delete()
        .eq('id', conversationId);
  }

  Future<void> updateConversationTitle(String conversationId, String title) async {
    try {
      await _client
          .from('ai_conversations')
          .update({'title': title})
          .eq('id', conversationId);
    } catch (e) {
      print('updateConversationTitle error: $e');
    }
  }

  // ── SEND MESSAGE ──────────────────────────────────────────
  Future<Map<String, dynamic>> sendMessage({
    required List<Map<String, String>> messages,
    required String conversationId,
    String translationId = 'BSB',
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) throw Exception('Not logged in');

    try {
      final response = await _client.functions.invoke(
        'bible-ai',
        body: {
          'messages': messages,
          'conversation_id': conversationId,
          'translation_id': translationId,
        },
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      if (response.data is Map && response.data['error'] != null) {
        final error = response.data['error'] as String;
        if (error == 'daily_limit_reached') {
          throw AiLimitException(
            tokensUsed: response.data['tokens_used'] as int? ?? 0,
            tokensRemaining: response.data['tokens_remaining'] as int? ?? 0,
            dailyLimit: response.data['daily_limit'] as int? ?? 2000,
            isPaid: response.data['paid'] as bool? ?? false,
          );
        }
        throw Exception(error);
      }

      return Map<String, dynamic>.from(response.data);
    } on FunctionException catch (e) {
      // Supabase throws FunctionException for non-200 responses
      // Parse the body to check if it's a daily limit error
      final data = e.details;
      if (data is Map && data['error'] == 'daily_limit_reached') {
        throw AiLimitException(
          tokensUsed: data['tokens_used'] as int? ?? 0,
          tokensRemaining: data['tokens_remaining'] as int? ?? 0,
          dailyLimit: data['daily_limit'] as int? ?? 2000,
          isPaid: data['paid'] as bool? ?? false,
        );
      }
      rethrow;
    } catch (e) {
      if (e is AiLimitException) rethrow;
      rethrow;
    }
  }

  // ── GET TOKEN USAGE ───────────────────────────────────────
  Future<Map<String, dynamic>> getTokenUsage() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};

    try {
      final response = await _client.rpc(
        'get_ai_usage_today',
        params: {'p_user_id': userId},
      );
      return Map<String, dynamic>.from(response);
    } catch (e) {
      print('getTokenUsage error: $e');
      return {};
    }
  }
}

// ============================================================
// AI LIMIT EXCEPTION
// Thrown when a user hits their daily token budget
// ============================================================
class AiLimitException implements Exception {
  final int tokensUsed;
  final int tokensRemaining;
  final int dailyLimit;
  final bool isPaid;

  AiLimitException({
    required this.tokensUsed,
    required this.tokensRemaining,
    required this.dailyLimit,
    required this.isPaid,
  });

  @override
  String toString() =>
      'Daily token limit reached. Used $tokensUsed of $dailyLimit tokens today.';
}