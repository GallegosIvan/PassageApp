import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// COMMUNITY SERVICE
// All Supabase calls for communities, posts, and replies.
// ============================================================

class CommunityService {
  final _client = Supabase.instance.client;

  // ── MY COMMUNITIES ────────────────────────────────────────
  // API CALL: Supabase DB — fetch communities the user has joined
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
              chapter,
              description,
              is_private,
              created_at
            )
          ''')
          .eq('user_id', userId)
          .order('joined_at', ascending: false);

      return List<Map<String, dynamic>>.from(
        response.map((m) => {
          ...Map<String, dynamic>.from(m['communities']),
          'role': m['role'],
        }),
      );
    } catch (e) {
      print('getMyCommunities error: $e');
      return [];
    }
  }

  // ── DISCOVER COMMUNITIES ──────────────────────────────────
  // API CALL: Supabase DB — fetch public communities the user hasn't joined
  Future<List<Map<String, dynamic>>> getDiscoverCommunities({
    String? searchQuery,
    String? filterBook,
    int? filterChapter,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final memberships = await _client
          .from('community_members')
          .select('community_id')
          .eq('user_id', userId);

      final joinedIds = (memberships as List)
          .map((m) => m['community_id'] as String)
          .toList();

      var query = _client
          .from('communities')
          .select()
          .eq('is_private', false);

      if (joinedIds.isNotEmpty) {
        query = query.not('id', 'in', '(${joinedIds.join(',')})');
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.ilike('name', '%$searchQuery%');
      }

      if (filterBook != null) {
        query = query.eq('book', filterBook);
      }

      if (filterChapter != null) {
        query = query.eq('chapter', filterChapter);
      }

      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getDiscoverCommunities error: $e');
      return [];
    }
  }

  // ── JOIN COMMUNITY ────────────────────────────────────────
  // API CALL: Supabase DB — join a community
  Future<void> joinCommunity(String communityId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    await _client.from('community_members').insert({
      'community_id': communityId,
      'user_id': userId,
      'role': 'member',
    });
  }

  // ── LEAVE COMMUNITY ───────────────────────────────────────
  // API CALL: Supabase DB — leave a community
  Future<void> leaveCommunity(String communityId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client
        .from('community_members')
        .delete()
        .eq('community_id', communityId)
        .eq('user_id', userId);
  }

  // ── CREATE COMMUNITY ──────────────────────────────────────
  // API CALL: Supabase DB — create a new community
  // Creator is automatically added as admin via DB trigger
  Future<Map<String, dynamic>> createCommunity({
    required String name,
    required String book,
    required int chapter,
    String? description,
    bool isPrivate = false,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    // API CALL: Supabase DB function — validates subscription server-side
    final communityId = await _client.rpc('create_community', params: {
      'p_name': name,
      'p_book': book,
      'p_chapter': chapter,
      'p_description': description ?? '',
      'p_is_private': isPrivate,
    });

    return {
      'id': communityId,
      'name': name,
      'book': book,
      'chapter': chapter,
      'is_private': isPrivate,
    };
  }

  // ── GET MEMBER COUNT ──────────────────────────────────────
  // API CALL: Supabase DB — get number of members in a community
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

  // API CALL: Supabase DB — create an announcement (admin only)
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

  // API CALL: Supabase DB — delete an announcement (admin only)
  Future<void> deleteAnnouncement(String announcementId) async {
    await _client
        .from('announcements')
        .delete()
        .eq('id', announcementId);
  }

  // API CALL: Supabase DB — get announcements for a community
  Future<List<Map<String, dynamic>>> getCommunityAnnouncements(
      String communityId) async {
    try {
      final response = await _client
          .from('announcements')
          .select('''
            id,
            content,
            created_at,
            users(display_name, username)
          ''')
          .eq('community_id', communityId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getCommunityAnnouncements error: $e');
      return [];
    }
  }

  // ── GET COMMUNITY MEMBERS ─────────────────────────────────
  // API CALL: Supabase DB — fetch all members with their roles
  Future<List<Map<String, dynamic>>> getCommunityMembers(
      String communityId) async {
    try {
      final response = await _client
          .from('community_members')
          .select('''
            id,
            role,
            joined_at,
            user_id,
            users(username, display_name)
          ''')
          .eq('community_id', communityId)
          .order('joined_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getCommunityMembers error: $e');
      return [];
    }
  }

  // ── ADD CO-ADMIN ──────────────────────────────────────────
  // API CALL: Supabase DB — promote a member to co-admin
  Future<void> addCoAdmin({
    required String communityId,
    required String username,
  }) async {
    // Find user by username
    final userResponse = await _client
        .from('users')
        .select('id')
        .eq('username', username.toLowerCase().trim())
        .maybeSingle();

    if (userResponse == null) throw Exception('User not found');

    final userId = userResponse['id'] as String;

    // Check if already a member
    final existing = await _client
        .from('community_members')
        .select('id, role')
        .eq('community_id', communityId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      if (existing['role'] == 'admin' || existing['role'] == 'co-admin') {
        throw Exception('User is already an admin');
      }
      // Update existing member to co-admin
      await _client
          .from('community_members')
          .update({'role': 'co-admin'})
          .eq('id', existing['id']);
    } else {
      // Add as co-admin
      await _client.from('community_members').insert({
        'community_id': communityId,
        'user_id': userId,
        'role': 'co-admin',
      });
    }
  }

  // ── REMOVE CO-ADMIN ───────────────────────────────────────
  // API CALL: Supabase DB — demote co-admin back to member
  Future<void> removeCoAdmin({
    required String communityId,
    required String memberId,
  }) async {
    await _client
        .from('community_members')
        .update({'role': 'member'})
        .eq('id', memberId);
  }

  // ── UPDATE COMMUNITY ──────────────────────────────────────
  // API CALL: Supabase DB — update community settings
  Future<void> updateCommunity({
    required String communityId,
    required String name,
    required String book,
    required int chapter,
    String? description,
    required bool isPrivate,
  }) async {
    await _client.from('communities').update({
      'name': name,
      'book': book,
      'chapter': chapter,
      'description': description,
      'is_private': isPrivate,
    }).eq('id', communityId);
  }

  // ── DELETE COMMUNITY ──────────────────────────────────────
  // API CALL: Supabase DB — permanently delete a community
  Future<void> deleteCommunity(String communityId) async {
    await _client
        .from('communities')
        .delete()
        .eq('id', communityId);
  }

  // ── SHARE VERSE TO COMMUNITY ──────────────────────────────
  // API CALL: Supabase DB — post a verse as a community post
  Future<void> shareVerseToCommunity({
    required String communityId,
    required String verseRef,
    required String verseText,
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
    });
  }

  // API CALL: Supabase DB — fetch communities user belongs to for sharing
  Future<List<Map<String, dynamic>>> getMyCommunitiesForSharing() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('community_members')
          .select('community_id, communities(id, name, book, chapter)')
          .eq('user_id', userId)
          .order('joined_at', ascending: false);

      return List<Map<String, dynamic>>.from(
        response.map((m) => Map<String, dynamic>.from(m['communities'])),
      );
    } catch (e) {
      print('getMyCommunitiesForSharing error: $e');
      return [];
    }
  }
}