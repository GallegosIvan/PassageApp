import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// CHURCH SERVICE
// All Supabase calls for churches and church announcements.
// ============================================================

class ChurchService {
  final _client = Supabase.instance.client;

  // ── GET ALL CHURCHES ──────────────────────────────────────
  // API CALL: Supabase DB — fetch all churches with follower count
  // ── GET ALL CHURCHES (excluding ones user follows) ────────
  Future<List<Map<String, dynamic>>> getChurches({
    String? searchQuery,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      // Get churches user already follows
      final follows = await _client
          .from('church_followers')
          .select('church_id')
          .eq('user_id', userId);

      final followedIds = (follows as List)
          .map((f) => f['church_id'] as String)
          .toList();

      var query = _client
          .from('churches')
          .select('*, church_followers(count)');

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.ilike('name', '%$searchQuery%');
      }

      final response = await query.order('created_at', ascending: false);
      final all = List<Map<String, dynamic>>.from(response);

      // Filter out churches user already follows
      if (followedIds.isEmpty) return all;
      return all.where((c) => !followedIds.contains(c['id'])).toList();
    } catch (e) {
      print('getChurches error: $e');
      return [];
    }
  }

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

      // API CALL: Supabase DB — fetch full church data for followed churches
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
  // API CALL: Supabase DB — follow a church
  Future<void> followChurch(String churchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    await _client.from('church_followers').insert({
      'church_id': churchId,
      'user_id': userId,
    });
  }

  // ── UNFOLLOW CHURCH ───────────────────────────────────────
  // API CALL: Supabase DB — unfollow a church
  Future<void> unfollowChurch(String churchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client
        .from('church_followers')
        .delete()
        .eq('church_id', churchId)
        .eq('user_id', userId);
  }

  // ── CHECK IF FOLLOWING ────────────────────────────────────
  // API CALL: Supabase DB — check if user follows a church
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
  // API CALL: Supabase DB — create a new church profile
  Future<Map<String, dynamic>> createChurch({
    required String name,
    String? description,
    String? location,
    String? website,
    bool isPrivate = false,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    final response = await _client.from('churches').insert({
      'created_by': userId,
      'name': name,
      'description': description,
      'location': location,
      'website': website,
      'is_private': isPrivate,
    }).select().single();

    // Auto-follow the church you just created
    await followChurch(response['id']);

    return Map<String, dynamic>.from(response);
  }

  // ── GET CHURCH ANNOUNCEMENTS ──────────────────────────────
  // API CALL: Supabase DB — fetch announcements for a church
  Future<List<Map<String, dynamic>>> getChurchAnnouncements(
      String churchId) async {
    try {
      final response = await _client
          .from('church_announcements')
          .select('''
            id,
            content,
            created_at,
            users(display_name, username)
          ''')
          .eq('church_id', churchId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getChurchAnnouncements error: $e');
      return [];
    }
  }

  // ── CREATE CHURCH ANNOUNCEMENT ────────────────────────────
  // API CALL: Supabase DB — post an announcement to a church
  Future<void> createChurchAnnouncement({
    required String churchId,
    required String content,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    await _client.from('church_announcements').insert({
      'church_id': churchId,
      'user_id': userId,
      'content': content,
    });
  }

  // ── DELETE CHURCH ANNOUNCEMENT ────────────────────────────
  // API CALL: Supabase DB — delete a church announcement
  Future<void> deleteChurchAnnouncement(String announcementId) async {
    await _client
        .from('church_announcements')
        .delete()
        .eq('id', announcementId);
  }

  // ── GET ALL ANNOUNCEMENTS FOR HOME FEED ───────────────────
  // API CALL: Supabase DB — fetch announcements from both
  // communities the user has joined AND churches they follow
  Future<List<Map<String, dynamic>>> getHomeAnnouncements() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      // Community announcements
      final communityMemberships = await _client
          .from('community_members')
          .select('community_id')
          .eq('user_id', userId);

      final communityIds = (communityMemberships as List)
          .map((m) => m['community_id'] as String)
          .toList();

      // Church announcements
      final churchFollows = await _client
          .from('church_followers')
          .select('church_id')
          .eq('user_id', userId);

      final churchIds = (churchFollows as List)
          .map((f) => f['church_id'] as String)
          .toList();

      final List<Map<String, dynamic>> all = [];

      // Fetch community announcements
      if (communityIds.isNotEmpty) {
        final commAnnouncements = await _client
            .from('announcements')
            .select('''
              id,
              content,
              created_at,
              community_id,
              communities(name),
              users(display_name, username)
            ''')
            .inFilter('community_id', communityIds)
            .order('created_at', ascending: false)
            .limit(20);

        all.addAll(
          (commAnnouncements as List).map((a) => {
            ...Map<String, dynamic>.from(a),
            'source_type': 'community',
            'source_name': a['communities']?['name'] ?? 'Community',
          }),
        );
      }

      // Fetch church announcements
      if (churchIds.isNotEmpty) {
        final churchAnnouncements = await _client
            .from('church_announcements')
            .select('''
              id,
              content,
              created_at,
              church_id,
              churches(name),
              users(display_name, username)
            ''')
            .inFilter('church_id', churchIds)
            .order('created_at', ascending: false)
            .limit(20);

        all.addAll(
          (churchAnnouncements as List).map((a) => {
            ...Map<String, dynamic>.from(a),
            'source_type': 'church',
            'source_name': a['churches']?['name'] ?? 'Church',
          }),
        );
      }

      // Sort combined list by created_at descending
      all.sort((a, b) => DateTime.parse(b['created_at'])
          .compareTo(DateTime.parse(a['created_at'])));

      return all;
    } catch (e) {
      print('getHomeAnnouncements error: $e');
      return [];
    }
  }

  // ── GET CHURCH CO-ADMINS ──────────────────────────────────
  // API CALL: Supabase DB — fetch all co-admins of a church
  Future<List<Map<String, dynamic>>> getChurchCoAdmins(
      String churchId) async {
    try {
      final response = await _client
          .from('church_members')
          .select('''
            id,
            role,
            added_at,
            user_id,
            users(username, display_name)
          ''')
          .eq('church_id', churchId)
          .order('added_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('getChurchCoAdmins error: $e');
      return [];
    }
  }

  // ── ADD CHURCH CO-ADMIN ───────────────────────────────────
  // API CALL: Supabase DB — add a co-admin to a church
  Future<void> addChurchCoAdmin({
    required String churchId,
    required String username,
  }) async {
    final userResponse = await _client
        .from('users')
        .select('id')
        .eq('username', username.toLowerCase().trim())
        .maybeSingle();

    if (userResponse == null) throw Exception('User not found');

    final userId = userResponse['id'] as String;

    final existing = await _client
        .from('church_members')
        .select('id')
        .eq('church_id', churchId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) throw Exception('User is already a co-admin');

    await _client.from('church_members').insert({
      'church_id': churchId,
      'user_id': userId,
      'role': 'co-admin',
    });
  }

  // ── REMOVE CHURCH CO-ADMIN ────────────────────────────────
  // API CALL: Supabase DB — remove a co-admin from a church
  Future<void> removeChurchCoAdmin(String memberId) async {
    await _client
        .from('church_members')
        .delete()
        .eq('id', memberId);
  }

  // ── UPDATE CHURCH ─────────────────────────────────────────
  // API CALL: Supabase DB — update church settings
  Future<void> updateChurch({
    required String churchId,
    required String name,
    String? description,
    String? location,
    String? website,
    bool isPrivate = false,
  }) async {
    await _client.from('churches').update({
      'name': name,
      'description': description,
      'location': location,
      'website': website,
      'is_private': isPrivate,
    }).eq('id', churchId);
  }

  // ── DELETE CHURCH ─────────────────────────────────────────
  // API CALL: Supabase DB — permanently delete a church
  Future<void> deleteChurch(String churchId) async {
    await _client
        .from('churches')
        .delete()
        .eq('id', churchId);
  }

  // ── CHECK IF CO-ADMIN ─────────────────────────────────────
  // API CALL: Supabase DB — check if user is co-admin of a church
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

  // Generate a unique invite link for a church
  String getInviteLink(String churchId) {
    return 'https://passageapp.com/church/$churchId';
  }

  // API CALL: Supabase DB — check if current user has active paid plan
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

  // API CALL: Supabase DB — check if a specific user has active paid plan
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
}