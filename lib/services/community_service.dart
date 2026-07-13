import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// COMMUNITY SERVICE
// All Supabase calls for communities, posts, and replies.
//
// Book/chapter model: non-church communities always require a
// book (chosen at creation) but NOT a chapter — chapter is now
// specified per-post instead, so one community can cover an
// entire book without fragmenting into per-chapter groups.
// Church communities only require a book if explicitly marked
// as a Bible study community (is_bible_study), and are always
// free + exempt from the Pro paywall and the 5-private-community
// limit entirely.
//
// Church sub-group privacy: a church community can be marked
// is_private to restrict it to specific people within the
// church (e.g. a parents-only or youth-only chat). This is a
// DIFFERENT meaning of is_private than for standalone
// communities (which gates on the Pro paywall) — for church
// sub-groups, privacy is free and enforced via QR scan or
// admin-add, never a paywall.
//
// Member management (add/remove co-admin, remove member) is
// RPC-backed (remove_community_member, update_community_member_role,
// transfer_community_ownership) — these RPCs verify the caller's
// role server-side. Never write directly to community_members
// for role changes or removing another user; RLS does not permit
// it and never should, since client-side gating alone was the
// exact bug pattern this app's RLS audit was built around fixing.
//
// User display data (getCommunityAnnouncements, getCommunityMembers)
// previously used `users(display_name, username)` relational
// embedding. That relied on the users table's RLS SELECT policy,
// which was found to be `qual = true` — any authenticated user
// could read ANY other user's full row, including email, strikes,
// is_restricted. That policy is now tightened to self-only
// (auth.uid() = id), so these two methods now fetch only the
// non-sensitive public fields (username, display_name, avatar_url)
// via the get_public_profiles RPC instead, then attach them in the
// same 'users' key shape the old embed produced — so calling UI
// code reading row['users']['display_name'] keeps working unchanged.
//
// All join/leave operations (joinCommunity, leaveCommunity) are
// now RPC-backed (join_community, leave_community) rather than
// raw client-side inserts/deletes, consistent with the rest of
// this app's join-related logic.
// ============================================================

class CommunityService {
  final _client = Supabase.instance.client;

  // ── MY COMMUNITIES ────────────────────────────────────────
  // Fetches communities the user has joined (excludes church-only)
  Future<List<Map<String, dynamic>>> getMyCommunities() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('community_members')
          .select('''
            community_id,
            role,
            joined_at,
            communities(
              id,
              name,
              book,
              description,
              is_private,
              church_id,
              is_bible_study,
              created_at,
              created_by
            )
          ''')
          .eq('user_id', userId)
          .order('joined_at', ascending: false);

      return List<Map<String, dynamic>>.from(
        response
            .where((m) => m['communities']['church_id'] == null)
            .map((m) => {
                  ...Map<String, dynamic>.from(m['communities']),
                  'role': m['role'],
                }),
      );
    } catch (e) {
      print('getMyCommunities error: $e');
      return [];
    }
  }

  // ── CHURCH COMMUNITIES (joined only, for the main tab) ────
  // RPC-backed via get_joined_church_communities — only returns
  // communities the caller has actually joined (or every
  // sub-group automatically for the creator/co-admin). This is
  // DIFFERENT from getBrowsableChurchCommunities below, which
  // intentionally shows every open community regardless of
  // membership, for the Browse tab where people opt in.
  Future<List<Map<String, dynamic>>> getChurchCommunities(
      String churchId) async {
    try {
      final response = await _client.rpc('get_joined_church_communities', params: {
        'p_church_id': churchId,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getChurchCommunities error: $e');
      return [];
    }
  }

  // ── DISCOVER COMMUNITIES ──────────────────────────────────
  // Only shows public communities that are NOT church-only.
  // Filters by book only now — chapter filtering moved to the
  // post level, since communities cover whole books.
  // Confirmed: excludes private communities (is_private = false)
  // and church-linked communities (church_id is null) server-side,
  // before results ever reach the client — no leak here.
  Future<List<Map<String, dynamic>>> getDiscoverCommunities({
    String? searchQuery,
    String? filterBook,
  }) async {
    final userId = _client.auth.currentUser?.id;

    try {
      List<String> joinedIds = [];
      if (userId != null) {
        final memberships = await _client
            .from('community_members')
            .select('community_id')
            .eq('user_id', userId);
        joinedIds = (memberships as List)
            .map((m) => m['community_id'] as String)
            .toList();
      }

      var query = _client
          .from('communities')
          .select()
          .eq('is_private', false)
          .isFilter('church_id', null); // exclude church-only communities

      if (joinedIds.isNotEmpty) {
        query = query.not('id', 'in', '(${joinedIds.join(',')})');
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.ilike('name', '%$searchQuery%');
      }

      if (filterBook != null) {
        query = query.eq('book', filterBook);
      }

      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getDiscoverCommunities error: $e');
      return [];
    }
  }

  // ── BROWSE CHURCH COMMUNITIES (joined + unjoined) ─────────
  // RPC-backed via get_browsable_church_communities. Lists every
  // open (non-private) community in a church, marking which the
  // caller has already joined. Caller must already follow the
  // church. For the "browse all groups" tab where people opt in
  // to specific group chats / Bible studies rather than being
  // auto-joined to everything just for following the church.
  Future<List<Map<String, dynamic>>> getBrowsableChurchCommunities(String churchId) async {
    try {
      final response = await _client.rpc('get_browsable_church_communities', params: {
        'p_church_id': churchId,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getBrowsableChurchCommunities error: $e');
      return [];
    }
  }

  // ── JOIN CHURCH COMMUNITY (open, non-private only) ────────
  // RPC-backed via join_church_community. Caller must already
  // follow the parent church. Private sub-groups are NOT
  // joinable through this — those stay QR/admin-add only.
  Future<void> joinChurchCommunity(String communityId) async {
    try {
      await _client.rpc('join_church_community', params: {
        'p_community_id': communityId,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('community_is_private')) {
        throw Exception('community_is_private');
      }
      if (message.contains('not_church_follower')) {
        throw Exception('not_church_follower');
      }
      if (message.contains('not_a_church_community')) {
        throw Exception('not_a_church_community');
      }
      rethrow;
    }
  }

  // ── JOIN COMMUNITY ────────────────────────────────────────
  // RPC-backed via join_community. For non-church (public,
  // Discover-listed) communities only — the RPC itself now
  // rejects private or church-linked communities server-side,
  // closing a gap that previously only existed as a client-side
  // filter in the Discover tab.
  Future<void> joinCommunity(String communityId) async {
    try {
      await _client.rpc('join_community', params: {
        'p_community_id': communityId,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('community_is_private')) {
        throw Exception('community_is_private');
      }
      if (message.contains('church_community_requires_church_join')) {
        throw Exception('church_community_requires_church_join');
      }
      if (message.contains('community_not_found')) {
        throw Exception('community_not_found');
      }
      rethrow;
    }
  }

  // ── JOIN PRIVATE CHURCH SUB-GROUP BY QR TOKEN ─────────────
  // Throws 'invalid_token' or 'not_church_member' on failure.
  // Caller must already follow the parent church — a sub-group
  // QR code can never be used as a backdoor into a church
  // someone hasn't actually joined.
  Future<Map<String, dynamic>> joinCommunityByQrToken(String token) async {
    try {
      final result = await _client.rpc('join_community_by_qr_token', params: {
        'p_token': token,
      });
      return Map<String, dynamic>.from(result);
    } catch (e) {
      final message = e.toString();
      if (message.contains('invalid_token')) {
        throw Exception('invalid_token');
      }
      if (message.contains('not_church_member')) {
        throw Exception('not_church_member');
      }
      rethrow;
    }
  }

  // ── ADMIN: ADD MEMBER TO PRIVATE SUB-GROUP BY USERNAME ────
  // Server-side checks: caller must be admin/co-admin of the
  // community, and the target must already follow the parent
  // church. Lets an admin skip the QR flow when they already
  // know exactly who belongs in the group.
  Future<void> addMemberToPrivateCommunity({
    required String communityId,
    required String username,
  }) async {
    try {
      await _client.rpc('add_member_to_private_community', params: {
        'p_community_id': communityId,
        'p_username': username,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('not_authorized')) {
        throw Exception('not_authorized');
      }
      if (message.contains('user_not_found')) {
        throw Exception('user_not_found');
      }
      if (message.contains('not_church_member')) {
        throw Exception('not_church_member');
      }
      rethrow;
    }
  }

  // ── GET SUB-GROUP QR TOKEN ─────────────────────────────────
  // For displaying a private church sub-group's QR code to admins.
  Future<String?> getSubGroupQrToken(String communityId) async {
    try {
      final response = await _client
          .from('communities')
          .select('sub_group_qr_token')
          .eq('id', communityId)
          .maybeSingle();
      return response?['sub_group_qr_token'] as String?;
    } catch (e) {
      print('getSubGroupQrToken error: $e');
      return null;
    }
  }

  // ── LEAVE COMMUNITY ───────────────────────────────────────
  // RPC-backed via leave_community. Self-only, same as before —
  // the creator cannot leave their own community through this
  // path (use transferCommunityOwnership or deleteCommunity).
  Future<void> leaveCommunity(String communityId) async {
    try {
      await _client.rpc('leave_community', params: {
        'p_community_id': communityId,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('creator_cannot_leave')) {
        throw Exception('creator_cannot_leave');
      }
      rethrow;
    }
  }

  // ── CREATE COMMUNITY ──────────────────────────────────────
  // Uses RPC to enforce: book requirement, paid plan check, and
  // private-community limit — all server-side, unbypassable.
  // Church communities are exempt from the Pro/limit checks
  // entirely (enforced inside the RPC itself). isPrivate for a
  // church community means "restricted sub-group" (free), not
  // the Pro paywall meaning it has for standalone communities.
  Future<Map<String, dynamic>> createCommunity({
    required String name,
    String? book,
    String? description,
    bool isPrivate = false,
    String? churchId,
    bool isBibleStudy = false,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    try {
      final communityId = await _client.rpc('create_community', params: {
        'p_name': name,
        'p_book': book,
        'p_description': description ?? '',
        'p_is_private': isPrivate,
        'p_church_id': churchId,
        'p_is_bible_study': isBibleStudy,
      });

      return {
        'id': communityId,
        'name': name,
        'book': book,
        'is_private': isPrivate,
        'church_id': churchId,
        'is_bible_study': isBibleStudy,
      };
    } catch (e) {
      final message = e.toString();
      if (message.contains('private_limit_reached')) {
        throw Exception('private_limit_reached');
      }
      if (message.contains('paid_required')) {
        throw Exception('paid_required');
      }
      if (message.contains('book_required')) {
        throw Exception('book_required');
      }
      if (message.contains('not_authorized')) {
        throw Exception('not_authorized');
      }
      rethrow;
    }
  }

  // ── GET MEMBER COUNT ──────────────────────────────────────
  Future<int> getMemberCount(String communityId) async {
    try {
      final response = await _client
          .from('community_members')
          .select('id')
          .eq('community_id', communityId);
      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  // ── ANNOUNCEMENTS ─────────────────────────────────────────

  Future<void> createAnnouncement({
    required String communityId,
    required String content,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    await _client.from('announcements').insert({
      'community_id': communityId,
      'user_id': userId,
      'content': content,
    });
  }

  Future<void> deleteAnnouncement(String announcementId) async {
    await _client
        .from('announcements')
        .delete()
        .eq('id', announcementId);
  }

  // ── GET COMMUNITY ANNOUNCEMENTS ───────────────────────────
  // SECURITY FIX: previously used `users(display_name, username)`
  // relational embedding, which relied on the users table's
  // overly permissive RLS SELECT policy (qual = true). Now fetches
  // only public-safe fields via get_public_profiles RPC. See file
  // header comment for full context.
  Future<List<Map<String, dynamic>>> getCommunityAnnouncements(
      String communityId) async {
    try {
      final response = await _client
          .from('announcements')
          .select('id, content, created_at, user_id')
          .eq('community_id', communityId)
          .order('created_at', ascending: false);

      final announcements = List<Map<String, dynamic>>.from(response);
      await _hydrateUsers(announcements, 'user_id');
      return announcements;
    } catch (e) {
      print('getCommunityAnnouncements error: $e');
      return [];
    }
  }

  // ── GET COMMUNITY MEMBERS ─────────────────────────────────
  // SECURITY FIX: same as getCommunityAnnouncements above —
  // switched from the users(...) embed to the hydration pattern.
  Future<List<Map<String, dynamic>>> getCommunityMembers(
      String communityId) async {
    try {
      final response = await _client
          .from('community_members')
          .select('id, role, joined_at, user_id')
          .eq('community_id', communityId)
          .order('joined_at', ascending: true);

      final members = List<Map<String, dynamic>>.from(response);
      await _hydrateUsers(members, 'user_id');
      return members;
    } catch (e) {
      print('getCommunityMembers error: $e');
      return [];
    }
  }

  // ── HYDRATE USER DISPLAY INFO ──────────────────────────────
  // Fetches ONLY public-safe display fields (username,
  // display_name, avatar_url — never email/strikes/is_restricted)
  // via the get_public_profiles RPC, then attaches a 'users' key
  // to each row in the same shape the old `users(...)` embed
  // produced, so existing UI code reading row['users']['display_name']
  // keeps working unchanged without touching every screen.
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

  // ── REMOVE MEMBER FROM COMMUNITY ──────────────────────────
  // RPC-backed. Caller must be admin or co-admin server-side.
  // Co-admins may only remove plain members (not other co-admins
  // or the admin) — enforced inside the RPC, not just hidden in
  // the UI. The creator can never be removed through this path;
  // use transferCommunityOwnership first.
  Future<void> removeCommunityMember({
    required String communityId,
    required String userId,
  }) async {
    try {
      await _client.rpc('remove_community_member', params: {
        'p_community_id': communityId,
        'p_user_id': userId,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('not_authorized')) {
        throw Exception('not_authorized');
      }
      if (message.contains('cannot_remove_self')) {
        throw Exception('cannot_remove_self');
      }
      if (message.contains('cannot_remove_creator')) {
        throw Exception('cannot_remove_creator');
      }
      if (message.contains('target_not_a_member')) {
        throw Exception('target_not_a_member');
      }
      rethrow;
    }
  }

  // ── UPDATE COMMUNITY MEMBER ROLE (promote/demote co-admin) ──
  // RPC-backed. Caller must be the admin (creator) server-side.
  // newRole must be 'member' or 'co-admin' — cannot be used to
  // grant 'admin' (use transferCommunityOwnership for that) and
  // cannot touch the admin's own role.
  Future<void> updateCommunityMemberRole({
    required String communityId,
    required String userId,
    required String newRole,
  }) async {
    try {
      await _client.rpc('update_community_member_role', params: {
        'p_community_id': communityId,
        'p_user_id': userId,
        'p_new_role': newRole,
      });
    } catch (e) {
      final message = e.toString();
      if (message.contains('not_authorized')) {
        throw Exception('not_authorized');
      }
      if (message.contains('cannot_change_own_role')) {
        throw Exception('cannot_change_own_role');
      }
      if (message.contains('invalid_role')) {
        throw Exception('invalid_role');
      }
      if (message.contains('target_not_a_member')) {
        throw Exception('target_not_a_member');
      }
      if (message.contains('cannot_change_admin_role')) {
        throw Exception('cannot_change_admin_role');
      }
      if (message.contains('target_is_restricted')) {
        throw Exception('target_is_restricted');
      }
      rethrow;
    }
  }

  // ── TRANSFER COMMUNITY OWNERSHIP ──────────────────────────
  // RPC-backed. Caller must be the current creator server-side.
  // New owner must already be a member and must not be a
  // permanently restricted (three-strikes) user. If the
  // community is private and the new owner isn't Pro, it is
  // automatically downgraded to public.
  Future<Map<String, dynamic>> transferCommunityOwnership({
    required String communityId,
    required String newOwnerId,
  }) async {
    try {
      final result = await _client.rpc('transfer_community_ownership', params: {
        'p_community_id': communityId,
        'p_new_owner_id': newOwnerId,
      });
      return Map<String, dynamic>.from(result);
    } catch (e) {
      final message = e.toString();
      if (message.contains('not_authorized')) {
        throw Exception('not_authorized');
      }
      if (message.contains('new_owner_not_a_member')) {
        throw Exception('new_owner_not_a_member');
      }
      if (message.contains('new_owner_is_restricted')) {
        throw Exception('new_owner_is_restricted');
      }
      rethrow;
    }
  }

  // ── UPDATE COMMUNITY ──────────────────────────────────────
  // Book can be updated (e.g. switching study focus), but chapter
  // is no longer a community-level field at all.
  Future<void> updateCommunity({
    required String communityId,
    required String name,
    String? book,
    String? description,
    required bool isPrivate,
  }) async {
    await _client.from('communities').update({
      'name': name,
      'book': book,
      'description': description,
      'is_private': isPrivate,
    }).eq('id', communityId);
  }

  // ── DELETE COMMUNITY ──────────────────────────────────────
  Future<void> deleteCommunity(String communityId) async {
    await _client
        .from('communities')
        .delete()
        .eq('id', communityId);
  }

  // ── SHARE VERSE TO COMMUNITY ──────────────────────────────
  // Now requires a chapter explicitly, matching the post-level
  // chapter requirement for study communities.
  Future<void> shareVerseToCommunity({
    required String communityId,
    required String verseRef,
    required String verseText,
    required int chapter,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    final content = comment != null && comment.isNotEmpty
        ? '$comment\n\n"$verseText"'
        : '"$verseText"';

    await _client.from('posts').insert({
      'community_id': communityId,
      'user_id': userId,
      'verse_ref': verseRef,
      'content': content,
      'chapter': chapter,
    });
  }

  // ── GET COMMUNITIES FOR SHARING ───────────────────────────
  Future<List<Map<String, dynamic>>> getMyCommunitiesForSharing() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('community_members')
          .select('community_id, communities(id, name, book, church_id, is_bible_study, churches(name))')
          .eq('user_id', userId)
          .order('joined_at', ascending: false);

      return List<Map<String, dynamic>>.from(
        response
            .where((m) => m['communities'] != null)
            .map((m) => Map<String, dynamic>.from(m['communities'])),
      );
    } catch (e) {
      print('getMyCommunitiesForSharing error: $e');
      return [];
    }
  }

  Future<void> shareVerseToGroupChat({
    required String communityId,
    required String verseRef,
    required String verseText,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');
    final content = comment != null && comment.isNotEmpty
        ? '$comment\n\n"$verseText"\n— $verseRef'
        : '"$verseText"\n— $verseRef';
    await _client.from('church_messages').insert({
      'community_id': communityId,
      'user_id': userId,
      'content': content,
    });
  }

  // ── REGENERATE SUB-GROUP QR TOKEN ─────────────────────────
  Future<void> regenerateSubGroupQrToken(String communityId) async {
    try {
      await _client.rpc('regenerate_sub_group_qr_token', params: {
        'p_community_id': communityId,
      });
    } catch (e) {
      print('regenerateSubGroupQrToken error: $e');
      rethrow;
    }
  }
}