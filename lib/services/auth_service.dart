import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// AUTH SERVICE
// All Supabase API calls for authentication live here.
// No UI logic — just data calls.
// ============================================================

class AuthService {
  final _client = Supabase.instance.client;

  // ── SIGN UP ──────────────────────────────────────────────
  // API CALL: Supabase Auth — creates a new auth user
  // Then updates the auto-created users row with username + display_name
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    // VALIDATION: username uniqueness checked at DB level via unique constraint
    // If duplicate, Supabase throws a PostgrestException which we catch in the UI

    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    if (response.user != null) {
      // API CALL: Supabase DB — update the users row created by our trigger
      await _client.from('users').update({
        'username': username.trim().toLowerCase(),
        'display_name': displayName.trim(),
      }).eq('id', response.user!.id);
    }

    return response;
  }

  // ── LOG IN ───────────────────────────────────────────────
  // API CALL: Supabase Auth — signs in with email + password
  Future<AuthResponse> logIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // ── LOG OUT ──────────────────────────────────────────────
  // API CALL: Supabase Auth — signs out current user
  Future<void> logOut() async {
    await _client.auth.signOut();
  }

  // ── CURRENT USER ─────────────────────────────────────────
  // Returns the currently logged in user, or null if not logged in
  User? get currentUser => _client.auth.currentUser;

  // ── AUTH STATE STREAM ────────────────────────────────────
  // Stream that emits whenever auth state changes (login, logout, token refresh)
  // Used in main.dart to decide which screen to show
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
}