import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// CHURCH CHAT SERVICE
// All Supabase calls for the linear group-chat model used by
// general (non-Bible-study) church communities. Separate from
// CommunityService since this is a distinct data model
// (church_messages table, not posts/replies).
//
// Photo posting: admin-only — either the specific community's
// admin/co-admin, OR the parent church's admin/co-admin (church
// admins automatically have full access to every sub-group in
// their own church, including posting images).
//
// SECURITY FIX: getMessages previously used `users(display_name,
// username)` relational embedding, which relied on the users
// table's RLS SELECT policy — found to be `qual = true`, meaning
// any authenticated user could read any other user's full row,
// including email, strikes, is_restricted. That policy is now
// tightened to self-only. getMessages now fetches only public-safe
// fields via the get_public_profiles RPC instead.
// ============================================================

class ChurchChatService {
  final _client = Supabase.instance.client;

  // ── GET MESSAGES ──────────────────────────────────────────
  // Resolves reply_to references locally so the UI can show a
  // quoted preview without a second round trip per message.
  Future<List<Map<String, dynamic>>> getMessages(String communityId) async {
    try {
      final response = await _client
          .from('church_messages')
          .select('id, content, image_url, created_at, user_id, reply_to_id')
          .eq('community_id', communityId)
          .order('created_at', ascending: true);

      final messages = List<Map<String, dynamic>>.from(response);
      await _hydrateUsers(messages, 'user_id');

      final byId = {for (var m in messages) m['id']: m};
      for (var m in messages) {
        if (m['reply_to_id'] != null) {
          m['reply_to'] = byId[m['reply_to_id']];
        }
      }
      return messages;
    } catch (e) {
      print('getMessages error: $e');
      return [];
    }
  }

  // ── HYDRATE USER DISPLAY INFO ──────────────────────────────
  // Fetches ONLY public-safe display fields (username,
  // display_name, avatar_url — never email/strikes/is_restricted)
  // via the get_public_profiles RPC, then attaches a 'users' key
  // to each row in the same shape the old `users(...)` embed
  // produced, so existing UI code keeps working unchanged.
  Future<void> _hydrateUsers(List<Map<String, dynamic>> rows, String idField) async {
    final ids = rows
        .map((r) => r[idField] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
      final profiles = await _client.rpc('get_public_profiles', params: {'p_user_ids': ids});
      final profileMap = {
        for (final p in List<Map<String, dynamic>>.from(profiles)) p['id'] as String: p
      };
      for (final row in rows) {
        final id = row[idField] as String?;
        row['users'] = id != null ? profileMap[id] : null;
      }
    } catch (e) {
      print('_hydrateUsers error: $e');
    }
  }

  // ── SEND MESSAGE ───────────────────────────────────────────
  // Throws 'user_restricted' (via the underlying trigger) if the
  // sender is permanently restricted from chat. Open to any
  // member — not admin-gated, unlike church announcements.
  Future<void> sendMessage({
    required String communityId,
    required String content,
    String? replyToId,
    String? imageUrl,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    await _client.from('church_messages').insert({
      'community_id': communityId,
      'user_id': userId,
      'content': content,
      'reply_to_id': replyToId,
      'image_url': imageUrl,
    });
  }

  // ── UPLOAD CHAT IMAGE ───────────────────────────────────────
  // Admin-only (enforced server-side by storage policy — this
  // call will fail with a permissions error for non-admins
  // regardless of UI gating). Path is communityId/timestamp.ext
  // so storage policies can check community membership from the
  // path itself. Takes raw bytes rather than a File — File has no
  // real filesystem backing on Flutter Web, so byte-based upload
  // is required for cross-platform compatibility.
  Future<String> uploadChatImageBytes({
    required String communityId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final fileName = '$communityId/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

    await _client.storage.from('church-chat-images').uploadBinary(fileName, bytes);

    return _client.storage.from('church-chat-images').getPublicUrl(fileName);
  }

  // ── DELETE MESSAGE ─────────────────────────────────────────
  // RLS allows this only for the message's own sender or a
  // community admin/co-admin — enforced server-side regardless
  // of what this client call attempts.
  Future<void> deleteMessage(String messageId) async {
    await _client.from('church_messages').delete().eq('id', messageId);
  }

  // ── CHECK IF ADMIN (community-level OR church-level) ───────
  // Returns true if the caller is admin/co-admin of this specific
  // community, OR creator/co-admin of the parent church — church
  // admins automatically have full admin rights in every sub-group
  // within their church, including photo-posting.
  Future<bool> isCommunityAdmin(String communityId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final response = await _client
          .from('community_members')
          .select('role')
          .eq('community_id', communityId)
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null &&
          (response['role'] == 'admin' || response['role'] == 'co-admin')) {
        return true;
      }

      // Not a community-level admin — check church-level admin status
      final community = await _client
          .from('communities')
          .select('church_id')
          .eq('id', communityId)
          .maybeSingle();

      final churchId = community?['church_id'] as String?;
      if (churchId == null) return false;

      final church = await _client
          .from('churches')
          .select('created_by')
          .eq('id', churchId)
          .maybeSingle();

      if (church?['created_by'] == userId) return true;

      final churchMember = await _client
          .from('church_members')
          .select('role')
          .eq('church_id', churchId)
          .eq('user_id', userId)
          .maybeSingle();

      return churchMember?['role'] == 'co-admin';
    } catch (e) {
      print('isCommunityAdmin error: $e');
      return false;
    }
  }
}