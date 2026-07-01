import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/landing_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_feedback_screen.dart';
import 'admin_restricted_users_screen.dart';
import 'admin_appeals_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _client = Supabase.instance.client;
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isChangingPassword = false;
  bool _showPasswordSection = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isAdmin = false;
  bool _isRestricted = false;

  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoadingBlocked = true;

  static const _privacyPolicyUrl =
      'https://app.termly.io/policy-viewer/policy.html?policyUUID=854856e5-3d43-46ed-b024-b04e84d58d67';
  static const _termsUrl =
      'https://app.termly.io/policy-viewer/policy.html?policyUUID=ee043960-b26b-47a2-9e42-d5be53fdf766';

  @override
  void initState() {
    super.initState();
    _checkIfAdmin();
    _loadBlockedUsers();
    _checkRestrictionStatus();
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _checkIfAdmin() async {
    try {
      final result = await _client.rpc('is_admin');
      if (mounted) setState(() => _isAdmin = result as bool? ?? false);
    } catch (e) {
      print('checkIfAdmin error: $e');
    }
  }

  Future<void> _checkRestrictionStatus() async {
    try {
      final result = await _client.rpc('get_my_restriction_status');
      if (result != null && mounted) {
        final info = Map<String, dynamic>.from(result);
        setState(() => _isRestricted = info['is_restricted'] == true);
      }
    } catch (e) {
      print('checkRestrictionStatus error: $e');
    }
  }

  Future<void> _loadBlockedUsers() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final blocked = await _client
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', userId);

      final ids = (blocked as List).map((r) => r['blocked_id'] as String).toList();

      if (ids.isEmpty) {
        if (mounted) setState(() { _blockedUsers = []; _isLoadingBlocked = false; });
        return;
      }

      final profiles = await _client.rpc('get_public_profiles', params: {'p_user_ids': ids});
      final profileList = List<Map<String, dynamic>>.from(profiles);
      final profileMap = {for (final p in profileList) p['id'] as String: p};

      final result = ids.map((id) {
        final user = profileMap[id] ?? {'id': id, 'display_name': 'Unknown', 'username': 'Unknown'};
        return {'blocked_id': id, 'users': user};
      }).toList();

      if (mounted) {
        setState(() {
          _blockedUsers = result;
          _isLoadingBlocked = false;
        });
      }
    } catch (e) {
      print('loadBlockedUsers error: $e');
      if (mounted) setState(() => _isLoadingBlocked = false);
    }
  }

  Future<void> _unblockUser(String blockedId, String displayName) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client
          .from('blocked_users')
          .delete()
          .eq('blocker_id', userId)
          .eq('blocked_id', blockedId);
      if (mounted) {
        setState(() => _blockedUsers.removeWhere((u) => u['blocked_id'] == blockedId));
        _showSnackbar('$displayName has been unblocked');
      }
    } catch (e) {
      if (mounted) _showSnackbar('Failed to unblock user', isError: true);
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) _showSnackbar('Could not open link', isError: true);
    }
  }

  Future<void> _changePassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty) {
      _showSnackbar('Please enter a new password', isError: true);
      return;
    }
    if (newPassword.length < 6) {
      _showSnackbar('Password must be at least 6 characters', isError: true);
      return;
    }
    if (newPassword != confirmPassword) {
      _showSnackbar('Passwords do not match', isError: true);
      return;
    }

    setState(() => _isChangingPassword = true);
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      if (mounted) {
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        setState(() => _showPasswordSection = false);
        _showSnackbar('Password updated successfully');
      }
    } catch (e) {
      if (mounted) _showSnackbar('Failed to update password', isError: true);
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete account?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete your account, all your data, highlights, notes, and communities. This cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _client.rpc('delete_own_account');
      await _client.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LandingScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) _showSnackbar('Failed to delete account', isError: true);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _client.auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            if (_isRestricted) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.block, color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Chat access restricted',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'You have permanently lost the ability to post or reply in communities and churches due to repeated violations of our guidelines. This restriction is permanent and applies regardless of subscription status.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            _sectionLabel('Account'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.email_outlined, color: Colors.grey, size: 18),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Email', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(email, style: const TextStyle(color: Colors.white, fontSize: 14)),
                ])),
              ]),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _showPasswordSection = !_showPasswordSection),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.lock_outline, color: Colors.grey, size: 18),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Change password',
                      style: TextStyle(color: Colors.white, fontSize: 14))),
                  Icon(
                    _showPasswordSection ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                  ),
                ]),
              ),
            ),
            if (_showPasswordSection) ...[
              const SizedBox(height: 12),
              _PasswordField(
                controller: _newPasswordController,
                hint: 'New password',
                obscure: _obscureNew,
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
              ),
              const SizedBox(height: 8),
              _PasswordField(
                controller: _confirmPasswordController,
                hint: 'Confirm new password',
                obscure: _obscureConfirm,
                onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isChangingPassword ? null : _changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isChangingPassword
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text('Update password',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],

            const SizedBox(height: 24),

            _sectionLabel('Notifications'),
            const SizedBox(height: 12),
            _ToggleRow(icon: Icons.notifications_outlined, label: 'New replies to my posts', value: true, onChanged: (_) {}),
            const SizedBox(height: 8),
            _ToggleRow(icon: Icons.campaign_outlined, label: 'Community announcements', value: true, onChanged: (_) {}),
            const SizedBox(height: 8),
            _ToggleRow(icon: Icons.local_fire_department_outlined, label: 'Daily streak reminder', value: true, onChanged: (_) {}),

            const SizedBox(height: 24),

            _sectionLabel('Blocked Users'),
            const SizedBox(height: 12),
            if (_isLoadingBlocked)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (_blockedUsers.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(children: [
                  Icon(Icons.block_outlined, color: Colors.grey, size: 18),
                  SizedBox(width: 12),
                  Text('No blocked users', style: TextStyle(color: Colors.grey, fontSize: 14)),
                ]),
              )
            else
              ...(_blockedUsers.map((entry) {
                final user = entry['users'];
                final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown';
                final blockedId = entry['blocked_id'] as String;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.person_outline, color: Colors.grey, size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(displayName,
                        style: const TextStyle(color: Colors.white, fontSize: 14))),
                    TextButton(
                      onPressed: () => _unblockUser(blockedId, displayName),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        backgroundColor: Colors.white12,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Unblock', style: TextStyle(fontSize: 12)),
                    ),
                  ]),
                );
              })),

            const SizedBox(height: 24),

            _sectionLabel('Legal'),
            const SizedBox(height: 12),
            _InfoTile(
              icon: Icons.description_outlined,
              label: 'Terms of Service',
              onTap: () => _launchUrl(_termsUrl),
            ),
            const SizedBox(height: 8),
            _InfoTile(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              onTap: () => _launchUrl(_privacyPolicyUrl),
            ),

            const SizedBox(height: 24),

            _sectionLabel('About'),
            const SizedBox(height: 12),
            _InfoTile(icon: Icons.info_outline, label: 'Version', value: '1.0.0'),

            const SizedBox(height: 24),

            if (_isAdmin) ...[
              _sectionLabel('Admin'),
              const SizedBox(height: 12),
              _InfoTile(
                icon: Icons.admin_panel_settings_outlined,
                label: 'View Reports',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminReportsScreen()),
                ),
              ),
              const SizedBox(height: 8),
              _InfoTile(
                icon: Icons.feedback_outlined,
                label: 'View Feedback',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminFeedbackScreen()),
                ),
              ),
              const SizedBox(height: 8),
              _InfoTile(
                icon: Icons.block,
                label: 'Restricted Users',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminRestrictedUsersScreen()),
                ),
              ),
              const SizedBox(height: 8),
              _InfoTile(
                icon: Icons.gavel_outlined,
                label: 'Restriction Appeals',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminAppealsScreen()),
                ),
              ),
              const SizedBox(height: 24),
            ],

            _sectionLabel('Danger zone'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _deleteAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Delete account',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
          color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;

  const _PasswordField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey, size: 18,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class _ToggleRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ToggleRow> createState() => _ToggleRowState();
}

class _ToggleRowState extends State<_ToggleRow> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(widget.icon, color: Colors.grey, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(widget.label,
            style: const TextStyle(color: Colors.white, fontSize: 14))),
        Switch(
          value: _value,
          onChanged: (val) {
            setState(() => _value = val);
            widget.onChanged(val);
          },
          activeColor: Colors.white,
        ),
      ]),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  const _InfoTile({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.grey, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 14))),
          if (value != null)
            Text(value!, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          if (onTap != null)
            const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        ]),
      ),
    );
  }
}