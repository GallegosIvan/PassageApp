import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// AI SERVICE
// Handles all communication with the bible-ai Edge Function.
// The Anthropic API key never touches Flutter code.
// ============================================================

class AiService {
  final _client = Supabase.instance.client;

  // ── START NEW CONVERSATION ────────────────────────────────
  // API CALL: Supabase DB — creates a new conversation record
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
  // API CALL: Supabase DB — fetch all conversations for the user
  Future<List<Map<String, dynamic>>> getConversations() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('ai_conversations')
          .select('id, title, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getConversations error: $e');
      return [];
    }
  }

  // ── GET MESSAGES FOR CONVERSATION ────────────────────────
  // API CALL: Supabase DB — fetch all messages in a conversation
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
  // API CALL: Supabase DB — delete a conversation and its messages
  Future<void> deleteConversation(String conversationId) async {
    await _client
        .from('ai_conversations')
        .delete()
        .eq('id', conversationId);
  }

  // ── SEND MESSAGE ──────────────────────────────────────────
  // API CALL: Supabase Edge Function (bible-ai)
  // Sends messages to Claude via Edge Function.
  // Returns the assistant response and token usage info.
  Future<Map<String, dynamic>> sendMessage({
    required List<Map<String, String>> messages,
    required String conversationId,
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) throw Exception('Not logged in');

    try {
      final response = await _client.functions.invoke(
        'bible-ai',
        body: {
          'messages': messages,
          'conversation_id': conversationId,
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
          );
        }
        throw Exception(error);
      }

      if (response.status != 200) {
        throw Exception('Failed to get AI response: ${response.status}');
      }

      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      if (e is AiLimitException) rethrow;
      rethrow;
    }
  }

  // ── GET TOKEN USAGE ───────────────────────────────────────
  // API CALL: Supabase DB function — get today's token usage
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
// Thrown when a free user hits their daily token budget
// ============================================================
class AiLimitException implements Exception {
  final int tokensUsed;
  final int tokensRemaining;
  final int dailyLimit;

  AiLimitException({
    required this.tokensUsed,
    required this.tokensRemaining,
    required this.dailyLimit,
  });

  @override
  String toString() =>
      'Daily token limit reached. Used $tokensUsed of $dailyLimit tokens today.';
}