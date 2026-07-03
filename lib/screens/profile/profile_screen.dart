import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/app_cache.dart';
import '../auth/landing_screen.dart';
import 'settings_screen.dart';
import '../../widgets/upgrade_sheet.dart';
import 'manage_subscription_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _subscription;
  int _streak = 0;
  bool _isLoading = true;
  String? _error;
  bool _isEditingName = false;
  bool _isSaving = false;
  late TextEditingController _displayNameController;

  static const List<String> _denominations = [
    'Non-denominational',
    'Baptist',
    'Catholic',
    'Methodist',
    'Lutheran',
    'Presbyterian',
    'Pentecostal',
    'Anglican / Episcopal',
    'Eastern Orthodox',
    'Seventh-day Adventist',
    'Church of Christ',
    'Assembly of God',
    'Reformed / Calvinist',
    'Evangelical',
    'Charismatic',
    'Mennonite',
    'Quaker',
    'Salvation Army',
    'Christian Reformed',
    'Other',
    'Prefer not to say',
  ];

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile({bool forceRefresh = false}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    // Show cached data instantly then refresh in background
    final cached = AppCache.instance.profileData;
    if (cached != null && !forceRefresh) {
      if (mounted) setState(() {
        _profile = cached['profile'] as Map<String, dynamic>;
        _subscription = cached['subscription'] as Map<String, dynamic>?;
        _streak = cached['streak'] as int? ?? 0;
        _displayNameController.text =
            (_profile?['display_name'] ?? _profile?['username'] ?? '').toString();
        _isLoading = false;
      });
      _fetchProfile(userId, showLoading: false);
      return;
    }

    if (mounted) setState(() { _isLoading = true; _error = null; });
    await _fetchProfile(userId, showLoading: true);
  }

  Future<void> _fetchProfile(String userId, {required bool showLoading}) async {
    try {
      final results = await Future.wait([
        _client
            .from('users')
            .select('username, display_name, email, avatar_url, denomination, created_at')
            .eq('id', userId)
            .single(),
        _client
            .from('subscriptions')
            .select('plan, status')
            .eq('user_id', userId)
            .maybeSingle(),
        _client
            .from('reading_streaks')
            .select('streak_count')
            .eq('user_id', userId)
            .maybeSingle(),
      ]);

      final profile = results[0] as Map<String, dynamic>;
      final subscription = results[1] as Map<String, dynamic>?;
      final streakData = results[2] as Map<String, dynamic>?;
      final streak = streakData?['streak_count'] as int? ?? 0;

      AppCache.instance.setProfileData({
        'profile': profile,
        'subscription': subscription,
        'streak': streak,
      });

      if (mounted) {
        setState(() {
          _profile = profile;
          _subscription = subscription;
          _streak = streak;
          _displayNameController.text =
              profile['display_name'] ?? profile['username'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('loadProfile error: \$e');
      if (showLoading && mounted) setState(() {
        _error = 'Could not load your profile. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveDisplayName() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    final newName = _displayNameController.text.trim();
    if (newName.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await _client
          .from('users')
          .update({'display_name': newName}).eq('id', userId);
      if (mounted) {
        setState(() {
          _profile?['display_name'] = newName;
          _isEditingName = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Name updated'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update name'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveDenomination(String? denomination) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _client
          .from('users')
          .update({'denomination': denomination}).eq('id', userId);
      if (mounted) {
        setState(() => _profile?['denomination'] = denomination);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Denomination updated'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update denomination'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _planLabel() {
    final plan = _subscription?['plan'] as String? ?? 'free';
    final status = _subscription?['status'] as String? ?? '';
    if (plan == 'monthly' && status == 'active') return 'Pro — Monthly';
    if (plan == 'annual' && status == 'active') return 'Pro — Annual';
    return 'Free';
  }

  bool _isPaid() {
    final plan = _subscription?['plan'] as String? ?? 'free';
    final status = _subscription?['status'] as String? ?? '';
    return (plan == 'monthly' || plan == 'annual') && status == 'active';
  }

  String _memberSince() {
    final createdAt = _profile?['created_at'] as String?;
    if (createdAt == null) return '';
    final date = DateTime.parse(createdAt);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return 'Member since ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final displayName =
        _profile?['display_name'] ?? _profile?['username'] ?? 'User';
    final username = _profile?['username'] ?? '';
    final denomination = _profile?['denomination'] as String?;
    final initials = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : 'U';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        title: const Text('Profile',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              AppCache.instance.clear();
              await _client.auth.signOut();
              // Routes to LandingScreen, not directly to
              // SignUpScreen — logging out should land someone
              // back at the choice between Log In and Create
              // Account, not funnel them straight into account
              // creation as if they had no account at all.
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LandingScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off, color: Colors.white54, size: 48),
                        const SizedBox(height: 16),
                        Text(_error!,
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loadProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
              onRefresh: () async { AppCache.instance.invalidateProfileData(); await _loadProfile(forceRefresh: true); },
              color: Colors.white,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_isEditingName) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _displayNameController,
                                        autofocus: true,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ),
                                    if (_isSaving)
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2),
                                      )
                                    else ...[
                                      GestureDetector(
                                        onTap: _saveDisplayName,
                                        child: const Icon(Icons.check,
                                            color: Colors.white, size: 20),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => setState(
                                            () => _isEditingName = false),
                                        child: const Icon(Icons.close,
                                            color: Colors.grey, size: 20),
                                      ),
                                    ],
                                  ],
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => setState(
                                          () => _isEditingName = true),
                                      child: const Icon(Icons.edit_outlined,
                                          color: Colors.grey, size: 16),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text('@$username',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(_memberSince(),
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Day Streak',
                                    style:
                                        TextStyle(color: Colors.grey, fontSize: 12)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      '$_streak',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('🔥', style: TextStyle(fontSize: 20)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _streak == 1 ? '1 day in a row' : '$_streak days in a row',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Plan',
                                    style:
                                        TextStyle(color: Colors.grey, fontSize: 12)),
                                const SizedBox(height: 8),
                                Text(
                                  _isPaid() ? 'Pro' : 'Free',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _isPaid() ? 'Full access' : '2,000 tokens/day',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    GestureDetector(
                      onTap: () {
                        final searchController = TextEditingController();
                        List<String> filtered = List.from(_denominations)..sort();

                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: const Color(0xFF1A1A1A),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          builder: (ctx) => StatefulBuilder(
                            builder: (ctx, setSheetState) => SizedBox(
                              height: MediaQuery.of(context).size.height * 0.75,
                              child: Column(
                                children: [
                                  const SizedBox(height: 12),
                                  Container(
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('Select Denomination',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: TextField(
                                      controller: searchController,
                                      autofocus: true,
                                      style: const TextStyle(color: Colors.white),
                                      onChanged: (query) {
                                        setSheetState(() {
                                          filtered = (_denominations..sort())
                                              .where((d) => d
                                                  .toLowerCase()
                                                  .contains(query.toLowerCase()))
                                              .toList();
                                        });
                                      },
                                      decoration: InputDecoration(
                                        hintText: 'Search...',
                                        hintStyle: const TextStyle(color: Colors.grey),
                                        prefixIcon:
                                            const Icon(Icons.search, color: Colors.grey),
                                        filled: true,
                                        fillColor: Colors.black,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: filtered.length,
                                      itemBuilder: (_, index) {
                                        final item = filtered[index];
                                        final isSelected = item == denomination;
                                        return ListTile(
                                          title: Text(
                                            item,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.white70,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          trailing: isSelected
                                              ? const Icon(Icons.check,
                                                  color: Colors.white, size: 18)
                                              : null,
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            _saveDenomination(item);
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.church_outlined, color: Colors.grey, size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Denomination',
                                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  const SizedBox(height: 2),
                                  Text(
                                    denomination ?? 'Select denomination',
                                    style: TextStyle(
                                      color: denomination != null
                                          ? Colors.white
                                          : Colors.white54,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    _sectionLabel('Subscription'),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isPaid()
                              ? Colors.white.withOpacity(0.2)
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _isPaid() ? Colors.white : Colors.white12,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _isPaid()
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  color: _isPaid() ? Colors.black : Colors.grey,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _planLabel(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16),
                                    ),
                                    Text(
                                      _isPaid()
                                          ? '50,000 AI tokens/day · Private communities'
                                          : 'Upgrade for more AI tokens and premium features',
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: () async {
                                if (_isPaid()) {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const ManageSubscriptionScreen()),
                                  );
                                  _loadProfile();
                                } else {
                                  final upgraded = await UpgradeSheet.show(context);
                                  if (upgraded == true && mounted) {
                                    _loadProfile();
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _isPaid() ? const Color(0xFF2A2A2A) : Colors.white,
                                foregroundColor:
                                    _isPaid() ? Colors.white : Colors.black,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(
                                _isPaid() ? 'Manage subscription' : 'Upgrade to Pro',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
          color: Colors.grey,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _StatCard({
    required this.label,
    required this.value,
    this.valueColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}