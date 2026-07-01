import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// CHURCH SERVICE
// All Supabase calls for churches and church announcements.
//
// Churches are mandatory-private (no public discovery, no
// toggle). Joining only happens by scanning a church's QR
// code in person. This is a free trust/safety requirement,
// separate from the Pro-gated private-community feature.
//
// SECURITY FIX: getChurchAnnouncements, getHomeAnnouncements,
// and getChurchCoAdmins previously used `users(display_name,
// username)` relational embedding, which relied on the users
// table's RLS SELECT policy — found to be `qual = true`, meaning
// any authenticated user could read any other user's full row,
// including email, strikes, is_restricted. That policy is now
// tightened to self-only (auth.uid() = id). These methods now
// fetch only public-safe fields (username, display_name,
// avatar_url) via the get_public_profiles RPC instead, then
// attach them in the same 'users' key shape the old embed
// produced — so calling UI code keeps working unchanged.
// ============================================================

class ChurchService {
  final _client = Supabase.instance.client;

  // ── GET CHURCHES USER FOLLOWS ─────────────────────────────
  Future<List<Map<String, dynamic>>> getFollowedChurches() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('church_followers')
          .select('church_id')
          .eq('user_id', userId);

      if ((response as List).isEmpty) return [];

      final churchIds = response
          .map((f) => f['church_id'] as String)
          .toList();

      final churches = await _client
          .from('churches')
          .select('*, church_followers(count)')
          .inFilter('id', churchIds);

      return List<Map<String, dynamic>>.from(churches);
    } catch (e) {
      print('getFollowedChurches error: $e');
      return [];
    }
  }

  // ── FOLLOW CHURCH ─────────────────────────────────────────
  // RPC-backed via follow_church — checks church_bans server-side
  // (SECURITY DEFINER bypasses the admin-only SELECT policy on
  // church_bans, so this works correctly even though the calling
  // user themselves isn't allowed to read that table directly).
  // This is the one function every join path funnels through
  // (QR scan confirmation, etc), so this is where a ban actually
  // gets enforced.
  Future<void> followChurch(String churchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    try {
      await _client.rpc('follow_church', params: {'p_church_id': churchId});
    } catch (e) {
      final message = e.toString();
      if (message.contains('user_is_banned')) {
        throw Exception('user_is_banned');
      }
      rethrow;
    }
  }

  // ── UNFOLLOW CHURCH ───────────────────────────────────────
  // RPC-backed via unfollow_church. Self-only, same as before —
  // the creator cannot unfollow their own church through this
  // path (use deleteChurch instead).
  Future<void> unfollowChurch(String churchId) async {
    try {
      await _client.rpc('unfollow_church', params: {'p_church_id': churchId});
    } catch (e) {
      final message = e.toString();
      if (message.contains('creator_cannot_unfollow')) {
        throw Exception('creator_cannot_unfollow');
      }
      rethrow;
    }
  }

  // ── CHECK IF FOLLOWING ────────────────────────────────────
  Future<bool> isFollowing(String churchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final response = await _client
          .from('church_followers')
          .select('id')
          .eq('church_id', churchId)
          .eq('user_id', userId)
          .maybeSingle();
      return response != null;
    } catch (e) {
      return false;
    }
  }

  // ── CREATE CHURCH ─────────────────────────────────────────
  // API CALL: Supabase DB — create a new church profile.
  // Always private. No public discovery. Joining only happens
  // via in-person QR scan (see getChurchByQrToken below).
  Future<Map<String, dynamic>> createChurch({
    required String name,
    String? description,
    String? location,
    String? website,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    try {
      final response = await _client.from('churches').insert({
        'created_by': userId,
        'name': name,
        'description': description,
        'location': location,
        'website': website,
        'is_private': true,
      }).select().single();

      await followChurch(response['id']);
      return Map<String, dynamic>.from(response);
    } catch (e) {
      if (e.toString().contains('church_limit_reached')) {
        throw Exception('church_limit_reached');
      }
      rethrow;
    }
  }

  // ── GET QR JOIN TOKEN ──────────────────────────────────────
  // Returns the church's permanent QR token. Render this as a QR
  // code for admins to display/print and show to people in person.
  Future<String?> getChurchQrToken(String churchId) async {
    try {
      final response = await _client
          .from('churches')
          .select('qr_token')
          .eq('id', churchId)
          .maybeSingle();
      return response?['qr_token'] as String?;
    } catch (e) {
      print('getChurchQrToken error: $e');
      return null;
    }
  }

  // ── REGENERATE QR TOKEN ────────────────────────────────────
  // Admin-only. Invalidates the old QR code (old printed/displayed
  // codes stop working) and generates a new one.
  Future<String> regenerateChurchQrToken(String churchId) async {
    final newToken = await _client.rpc('regenerate_church_qr_token', params: {
      'p_church_id': churchId,
    });
    return newToken as String;
  }

  // ── LOOKUP CHURCH BY QR TOKEN ──────────────────────────────
  // RPC-backed via get_church_by_qr_token. Called after scanning
  // a QR code, before joining — shows the church's info on a
  // confirmation screen first.
  Future<Map<String, dynamic>?> getChurchByQrToken(String token) async {
    try {
      final response = await _client.rpc('get_church_by_qr_token', params: {
        'p_token': token,
      });
      final results = List<Map<String, dynamic>>.from(response);
      return results.isEmpty ? null : results.first;
    } catch (e) {
      print('getChurchByQrToken error: $e');
      return null;
    }
  }

  // ── GET CHURCH ANNOUNCEMENTS ──────────────────────────────
  // image_url is church-announcement-only — community-level
  // announcements never support photos.
  // SECURITY FIX: see file header — switched from users(...)
  // embed to the hydration pattern.
  Future<List<Map<String, dynamic>>> getChurchAnnouncements(
      String churchId) async {
    try {
      final response = await _client
          .from('church_announcements')
          .select('id, content, image_url, created_at, user_id')
          .eq('church_id', churchId)
          .order('created_at', ascending: false);

      final announcements = List<Map<String, dynamic>>.from(response);
      await _hydrateUsers(announcements, 'user_id');
      return announcements;
    } catch (e) {
      print('getChurchAnnouncements error: $e');
      return [];
    }
  }

  // ── CREATE CHURCH ANNOUNCEMENT ────────────────────────────
  // imageUrl is optional. Photo support is intentionally
  // church-announcement-only — community-level announcements
  // (createAnnouncement, elsewhere) never accept an image.
  Future<void> createChurchAnnouncement({
    required String churchId,
    required String content,
    String? imageUrl,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    await _client.from('church_announcements').insert({
      'church_id': churchId,
      'user_id': userId,
      'content': content,
      'image_url': imageUrl,
    });
  }

  // ── UPLOAD ANNOUNCEMENT IMAGE ─────────────────────────────
  // Admin-only — enforced server-side by the storage policy
  // (church creator or church-level co-admin), regardless of
  // UI gating. Reuses the same church-chat-images bucket, with
  // a churchId-based path so the storage policy can verify
  // admin status from the path itself.
  Future<String> uploadAnnouncementImage({
    required String churchId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final fileName = '$churchId/announcement_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    await _client.storage.from('church-chat-images').uploadBinary(fileName, bytes);
    return _client.storage.from('church-chat-images').getPublicUrl(fileName);
  }

  // ── DELETE CHURCH ANNOUNCEMENT ────────────────────────────
  Future<void> deleteChurchAnnouncement(String announcementId) async {
    await _client
        .from('church_announcements')
        .delete()
        .eq('id', announcementId);
  }

  // ── GET ALL ANNOUNCEMENTS FOR HOME FEED ───────────────────
  // SECURITY FIX: see file header — both branches switched from
  // users(...) embed to the hydration pattern. communities(name)
  // and churches(name) embeds are untouched — those are different
  // tables with their own RLS, not the users table.
  Future<List<Map<String, dynamic>>> getHomeAnnouncements() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final communityMemberships = await _client
          .from('community_members')
          .select('community_id')
          .eq('user_id', userId);

      final communityIds = (communityMemberships as List)
          .map((m) => m['community_id'] as String)
          .toList();

      final churchFollows = await _client
          .from('church_followers')
          .select('church_id')
          .eq('user_id', userId);

      final churchIds = (churchFollows as List)
          .map((f) => f['church_id'] as String)
          .toList();

      final List<Map<String, dynamic>> all = [];

      if (communityIds.isNotEmpty) {
        final commAnnouncements = await _client
            .from('announcements')
            .select('id, content, created_at, community_id, user_id, communities(name)')
            .inFilter('community_id', communityIds)
            .order('created_at', ascending: false)
            .limit(20);

        final commList = List<Map<String, dynamic>>.from(commAnnouncements);
        await _hydrateUsers(commList, 'user_id');

        all.addAll(
          commList.map((a) => {
            ...a,
            'source_type': 'community',
            'source_name': a['communities']?['name'] ?? 'Community',
          }),
        );
      }

      if (churchIds.isNotEmpty) {
        final churchAnnouncements = await _client
            .from('church_announcements')
            .select('id, content, created_at, church_id, user_id, churches(name)')
            .inFilter('church_id', churchIds)
            .order('created_at', ascending: false)
            .limit(20);

        final churchList = List<Map<String, dynamic>>.from(churchAnnouncements);
        await _hydrateUsers(churchList, 'user_id');

        all.addAll(
          churchList.map((a) => {
            ...a,
            'source_type': 'church',
            'source_name': a['churches']?['name'] ?? 'Church',
          }),
        );
      }

      all.sort((a, b) => DateTime.parse(b['created_at'])
          .compareTo(DateTime.parse(a['created_at'])));

      return all;
    } catch (e) {
      print('getHomeAnnouncements error: $e');
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

  // ── GET CHURCH CO-ADMINS ──────────────────────────────────
  // SECURITY FIX: see file header — switched from users(...)
  // embed to the hydration pattern.
  Future<List<Map<String, dynamic>>> getChurchCoAdmins(
      String churchId) async {
    try {
      final response = await _client
          .from('church_members')
          .select('id, role, added_at, user_id')
          .eq('church_id', churchId)
          .order('added_at', ascending: true);

      final members = List<Map<String, dynamic>>.from(response);
      await _hydrateUsers(members, 'user_id');
      return members;
    } catch (e) {
      print('getChurchCoAdmins error: $e');
      return [];
    }
  }

  // ── GET CHURCH FOLLOWERS (full roster) ────────────────────
  // RPC-backed via get_church_followers — admin/co-admin only.
  // Returns every follower with their role (co-admin or null),
  // for the members list screen. Public-safe fields only.
  Future<List<Map<String, dynamic>>> getChurchFollowers(String churchId) async {
    try {
      final response = await _client.rpc('get_church_followers', params: {
        'p_church_id': churchId,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getChurchFollowers error: $e');
      return [];
    }
  }

  // ── REMOVE CHURCH FOLLOWER (KICK) ─────────────────────────
  // RPC-backed via remove_church_follower. They CAN rejoin later
  // through any normal path — this is reversible, unlike a ban.
  // Caller must be admin/co-admin server-side. Cannot remove the
  // creator.
  Future<void> removeChurchFollower({
    required String churchId,
    required String userId,
  }) async {
    try {
      await _client.rpc('remove_church_follower', params: {
        'p_church_id': churchId,
        'p_user_id': userId,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('not_authorized')) {
        throw Exception('not_authorized');
      }
      if (message.contains('cannot_remove_creator')) {
        throw Exception('cannot_remove_creator');
      }
      rethrow;
    }
  }

  // ── BAN CHURCH FOLLOWER ────────────────────────────────────
  // RPC-backed via ban_church_follower. Removes them AND records
  // a permanent ban — they cannot rejoin this church again
  // through any path (QR, admin-add) unless explicitly unbanned.
  // Caller must be admin/co-admin server-side. Cannot ban the
  // creator.
  Future<void> banChurchFollower({
    required String churchId,
    required String userId,
  }) async {
    try {
      await _client.rpc('ban_church_follower', params: {
        'p_church_id': churchId,
        'p_user_id': userId,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('not_authorized')) {
        throw Exception('not_authorized');
      }
      if (message.contains('cannot_ban_creator')) {
        throw Exception('cannot_ban_creator');
      }
      rethrow;
    }
  }

  // ── UNBAN CHURCH FOLLOWER ──────────────────────────────────
  // RPC-backed via unban_church_follower. Reverses a ban,
  // allowing the person to rejoin again through normal paths.
  Future<void> unbanChurchFollower({
    required String churchId,
    required String userId,
  }) async {
    try {
      await _client.rpc('unban_church_follower', params: {
        'p_church_id': churchId,
        'p_user_id': userId,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('not_authorized')) {
        throw Exception('not_authorized');
      }
      rethrow;
    }
  }

  // ── GET CHURCH BANS ────────────────────────────────────────
  // RPC-backed via get_church_bans. Lists everyone currently
  // banned from this church, for review/unban.
  Future<List<Map<String, dynamic>>> getChurchBans(String churchId) async {
    try {
      final response = await _client.rpc('get_church_bans', params: {
        'p_church_id': churchId,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getChurchBans error: $e');
      return [];
    }
  }

  // ── SEARCH USERS BY USERNAME ──────────────────────────────
  // RPC-backed via search_users_by_username — for autocomplete
  // when adding someone who is NOT yet a follower/co-admin.
  // Returns public-safe fields only, capped at 10 results.
  Future<List<Map<String, dynamic>>> searchUsersByUsername(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final response = await _client.rpc('search_users_by_username', params: {
        'p_query': query,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('searchUsersByUsername error: $e');
      return [];
    }
  }

  // ── ADD FOLLOWER BY USERNAME ──────────────────────────────
  // RPC-backed via add_church_follower_by_username — lets the
  // creator or a co-admin add a known person directly as a
  // follower of the church, without requiring a QR scan. The
  // server verifies the caller's role before doing anything.
  Future<void> addFollowerByUsername({
    required String churchId,
    required String username,
  }) async {
    final cleanUsername = username.trim().replaceFirst(RegExp(r'^@'), '');
    try {
      await _client.rpc('add_church_follower_by_username', params: {
        'p_church_id': churchId,
        'p_username': cleanUsername,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('not_authorized')) {
        throw Exception('Only the creator or a co-admin can add followers');
      }
      if (message.contains('user_not_found')) {
        throw Exception('User not found');
      }
      if (message.contains('already_following')) {
        throw Exception('That user already follows this church');
      }
      rethrow;
    }
  }

  // ── ADD CHURCH CO-ADMIN ───────────────────────────────────
  // RPC-backed via add_church_co_admin — the server verifies the
  // caller is the church's creator before inserting anything.
  Future<void> addChurchCoAdmin({
    required String churchId,
    required String username,
  }) async {
    final cleanUsername = username.trim().replaceFirst(RegExp(r'^@'), '');
    try {
      await _client.rpc('add_church_co_admin', params: {
        'p_church_id': churchId,
        'p_username': cleanUsername,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('not_authorized')) {
        throw Exception('Only the church creator can add co-admins');
      }
      if (message.contains('user_not_found')) {
        throw Exception('User not found');
      }
      if (message.contains('already_co_admin')) {
        throw Exception('User is already a co-admin');
      }
      if (message.contains('target_is_restricted')) {
        throw Exception('target_is_restricted');
      }
      rethrow;
    }
  }

  // ── REMOVE CHURCH CO-ADMIN ────────────────────────────────
  // RPC-backed via remove_church_co_admin — the server verifies
  // the caller is the church's creator and scopes the delete to
  // this specific church, rather than deleting by member id alone.
  Future<void> removeChurchCoAdmin({
    required String churchId,
    required String memberId,
  }) async {
    try {
      await _client.rpc('remove_church_co_admin', params: {
        'p_church_id': churchId,
        'p_member_id': memberId,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('not_authorized')) {
        throw Exception('Only the church creator can remove co-admins');
      }
      rethrow;
    }
  }

  // ── UPDATE CHURCH ─────────────────────────────────────────
  // API CALL: Supabase DB — update church settings.
  // is_private is always true and is no longer a setting that
  // can be changed.
  Future<void> updateChurch({
    required String churchId,
    required String name,
    String? description,
    String? location,
    String? website,
  }) async {
    await _client.from('churches').update({
      'name': name,
      'description': description,
      'location': location,
      'website': website,
    }).eq('id', churchId);
  }

  // ── DELETE CHURCH ─────────────────────────────────────────
  Future<void> deleteChurch(String churchId) async {
    await _client
        .from('churches')
        .delete()
        .eq('id', churchId);
  }

  // ── CHECK IF CO-ADMIN ─────────────────────────────────────
  Future<bool> isCoAdmin(String churchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final response = await _client
          .from('church_members')
          .select('id')
          .eq('church_id', churchId)
          .eq('user_id', userId)
          .maybeSingle();
      return response != null;
    } catch (e) {
      return false;
    }
  }

  // ── PAID STATUS CHECKS ─────────────────────────────────────
  // Unrelated to church privacy — used for unlocking Pro features
  // elsewhere in the app (e.g. private communities, quiz limits).
  Future<bool> isPaidUser() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final response = await _client
          .from('subscriptions')
          .select('plan, status')
          .eq('user_id', userId)
          .single();

      final plan = response['plan'] as String;
      final status = response['status'] as String;
      return (plan == 'monthly' || plan == 'annual') && status == 'active';
    } catch (e) {
      return false;
    }
  }

  Future<bool> isUserPaid(String userId) async {
    try {
      final response = await _client
          .from('subscriptions')
          .select('plan, status')
          .eq('user_id', userId)
          .single();

      final plan = response['plan'] as String;
      final status = response['status'] as String;
      return (plan == 'monthly' || plan == 'annual') && status == 'active';
    } catch (e) {
      return false;
    }
  }

  // ── CHURCH CREATION LIMIT ──────────────────────────────────
  // 1 free / 3 Pro churches. Unrelated to privacy — every church
  // is private regardless of subscription tier.
  Future<Map<String, dynamic>> checkChurchLimit() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {'allowed': false, 'churches_created': 0, 'limit': 1};

    try {
      final isPaid = await isPaidUser();
      final result = await _client.rpc('check_church_creation_limit', params: {
        'p_user_id': userId,
        'p_is_paid': isPaid,
      });
      return Map<String, dynamic>.from(result);
    } catch (e) {
      print('checkChurchLimit error: $e');
      return {'allowed': false, 'churches_created': 0, 'limit': 1};
    }
  }
}