import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/guest_session.dart';

// ============================================================
// TERMS OF SERVICE / PRIVACY POLICY GATE
// Shown once, before SignUpScreen or LoginScreen — gates ALL
// access to the app, not just account creation. A user who
// declines cannot reach the login screen either, since both
// paths require an account that requires Terms acceptance.
//
// Decline behavior:
//   - Mobile (iOS/Android): closes the app via SystemNavigator.pop()
//   - Web: cannot force-close a browser tab, so instead shows a
//     blocked state with no way forward — same effective result
//     (no access), just no fake "app closed" pretense on a
//     platform where that's not actually possible.
//
// Once accepted, sets terms_accepted = true in SharedPreferences
// so this screen is never shown again unless you bump
// _currentTermsVersion below (e.g. after a real Terms update).
// ============================================================

class TermsGateScreen extends StatefulWidget {
  final Widget nextScreen;
  final bool isGuestMode;

  const TermsGateScreen({super.key, required this.nextScreen, this.isGuestMode = false});

  // Terms re-prompting is now handled automatically via the
  // sync-terms-version Edge Function which checks Termly's API
  // for policy update dates. No manual version bumping needed.

  @override
  State<TermsGateScreen> createState() => _TermsGateScreenState();
}

class _TermsGateScreenState extends State<TermsGateScreen> {
  bool _hasDeclined = false;
  bool _isProcessing = false;

  Future<void> _accept() async {
    setState(() => _isProcessing = true);

    // If a session already exists (existing account going through
    // the gate after a terms update, or post-login), record
    // acceptance server-side right now — this is the real,
    // permanent record. If no session exists yet (brand new
    // signup, no account created yet), this call will fail
    // harmlessly, and signup_screen.dart records it instead, the
    // moment the account is actually created.
    if (widget.isGuestMode) {
      await GuestSession.start();
    } else {
      try {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          await Supabase.instance.client.rpc('accept_terms');
        }
      } catch (e) {
        print('accept_terms error: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('terms_accepted', true);


    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => widget.nextScreen),
    );
  }

  void _decline() {
    if (kIsWeb) {
      // Can't actually close a browser tab from JS/Dart in a way
      // that's reliable or not blocked by the browser — so we
      // just show the blocked state instead of pretending to exit.
      setState(() => _hasDeclined = true);
    } else {
      // Real app close on mobile.
      SystemNavigator.pop();
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasDeclined) {
      return _DeclinedBlockScreen(onReconsider: () => setState(() => _hasDeclined = false));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),

              const Icon(Icons.description_outlined, color: Colors.white, size: 48),

              const SizedBox(height: 24),

              const Text(
                'Before you continue',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              const Text(
                'Please read and accept our Terms of Service and Privacy Policy to use Passage. You can\'t create an account or sign in until you accept.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 28),

              // ── LINKS ───────────────────────────────────
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _LinkRow(
                      icon: Icons.gavel_outlined,
                      label: 'Terms of Service',
                      onTap: () => _openUrl(
                          'https://app.termly.io/policy-viewer/policy.html?policyUUID=ee043960-b26b-47a2-9e42-d5be53fdf766'),
                    ),
                    Divider(color: Colors.white.withOpacity(0.1), height: 1),
                    _LinkRow(
                      icon: Icons.lock_outline,
                      label: 'Privacy Policy',
                      onTap: () => _openUrl(
                          'https://app.termly.io/policy-viewer/policy.html?policyUUID=854856e5-3d43-46ed-b024-b04e84d58d67'),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 3),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2),
                        )
                      : const Text(
                          'I agree, continue',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: _isProcessing ? null : _decline,
                  child: const Text(
                    'Decline',
                    style: TextStyle(color: Colors.white38, fontSize: 15),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── DECLINED BLOCK STATE (web only) ───────────────────────────
// A dead end on purpose — no skip, no way to reach the rest of
// the app. The only way out is to come back and accept, or
// actually close the tab themselves (which we can't do for them).
class _DeclinedBlockScreen extends StatelessWidget {
  final VoidCallback onReconsider;
  const _DeclinedBlockScreen({required this.onReconsider});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, color: Colors.white24, size: 48),
              const SizedBox(height: 24),
              const Text(
                'You can\'t use Passage without accepting our Terms of Service and Privacy Policy.',
                style: TextStyle(color: Colors.white54, fontSize: 16, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              TextButton(
                onPressed: onReconsider,
                child: const Text(
                  'Go back',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LinkRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            const Icon(Icons.open_in_new, color: Colors.white38, size: 16),
          ],
        ),
      ),
    );
  }
}