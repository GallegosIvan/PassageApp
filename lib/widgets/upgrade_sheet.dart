import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subscription_service.dart';

class UpgradeSheet extends StatefulWidget {
  const UpgradeSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const UpgradeSheet(),
    );
  }

  @override
  State<UpgradeSheet> createState() => _UpgradeSheetState();
}

class _UpgradeSheetState extends State<UpgradeSheet> {
  final _subscriptionService = SubscriptionService();
  final _client = Supabase.instance.client;
  bool _isLoading = false;
  bool _isRestoring = false;
  String? _errorMessage;
  String _selectedPlan = 'annual';
  bool _isTrialEligible = true;
  bool _isRestricted = false;

  @override
  void initState() {
    super.initState();
    _checkTrialEligibility();
    _checkRestrictionStatus();
  }

  Future<void> _checkTrialEligibility() async {
    final eligible = await _subscriptionService.isTrialEligible();
    if (mounted) setState(() => _isTrialEligible = eligible);
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

  Future<void> _purchase() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = _selectedPlan == 'annual'
          ? await _subscriptionService.purchaseAnnual()
          : await _subscriptionService.purchaseMonthly();

      if (mounted) {
        if (success) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Welcome to Passage Pro!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          setState(() => _errorMessage = 'Purchase could not be completed.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _isRestoring = true;
      _errorMessage = null;
    });

    try {
      final success = await _subscriptionService.restorePurchases();
      if (mounted) {
        if (success) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Purchase restored successfully!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          setState(() => _errorMessage = 'No previous purchases found.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not restore purchases. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 20),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white54, size: 22),
                    ),
                  ),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    'Passage Pro',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Deepen your Bible study with full access',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (_isRestricted) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.block, color: Colors.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your account is permanently restricted from posting or replying in communities due to repeated violations. Subscribing to Pro will not lift this restriction — you will still be unable to post, reply, or share verses to community, even as a paying subscriber.',
                          style: TextStyle(
                            color: Colors.red.shade100,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _FeatureRow(
                    icon: Icons.auto_awesome,
                    title: '50,000 AI tokens per day',
                    subtitle: 'vs 2,000 on the free plan',
                  ),
                  const SizedBox(height: 12),
                  _FeatureRow(
                    icon: Icons.history,
                    title: 'Unlimited AI conversation history',
                    subtitle: 'vs 5 saved AI conversations on the free plan',
                  ),
                  const SizedBox(height: 12),
                  _FeatureRow(
                    icon: Icons.quiz_outlined,
                    title: '8 quizzes per day',
                    subtitle: 'vs 3 on the free plan',
                  ),
                  const SizedBox(height: 12),
                  _FeatureRow(
                    icon: Icons.lock_open,
                    title: 'Create private study communities',
                    subtitle: 'Up to 5 invite-only study groups — separate from churches',
                  ),
                  const SizedBox(height: 12),
                  _FeatureRow(
                    icon: Icons.church_outlined,
                    title: 'Create up to 3 churches',
                    subtitle: 'All churches are free and private — join only by QR code',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _PlanCard(
                      label: 'Annual',
                      price: '\$99.99',
                      period: '/year',
                      badge: 'Best value',
                      subtext: '\$8.33/mo',
                      isSelected: _selectedPlan == 'annual',
                      onTap: () => setState(() => _selectedPlan = 'annual'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PlanCard(
                      label: 'Monthly',
                      price: '\$11.99',
                      period: '/mo',
                      badge: null,
                      subtext: 'Billed monthly',
                      isSelected: _selectedPlan == 'monthly',
                      onTap: () => setState(() => _selectedPlan = 'monthly'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 24, right: 24),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _purchase,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isTrialEligible
                              ? 'Start 7-day free trial'
                              : 'Subscribe now',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _isRestoring ? null : _restore,
                  child: Text(
                    _isRestoring ? 'Restoring...' : 'Restore purchases',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                const Text('·', style: TextStyle(color: Colors.white24)),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text(
                    'Terms',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                const Text('·', style: TextStyle(color: Colors.white24)),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://app.termly.io/policy-viewer/policy.html?policyUUID=854856e5-3d43-46ed-b024-b04e84d58d67'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text(
                    'Privacy',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isUnavailable;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isUnavailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final dimColor = isUnavailable ? Colors.white38 : Colors.white;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: dimColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: dimColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  decoration: isUnavailable ? TextDecoration.lineThrough : null,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: isUnavailable ? Colors.red.shade200 : Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Icon(
          isUnavailable ? Icons.block : Icons.check_circle,
          color: isUnavailable ? Colors.red.shade300 : Colors.green,
          size: 18,
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String label;
  final String price;
  final String period;
  final String? badge;
  final String subtext;
  final bool isSelected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.label,
    required this.price,
    required this.period,
    required this.badge,
    required this.subtext,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white24,
            width: isSelected ? 2 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  period,
                  style: TextStyle(
                    color: isSelected ? Colors.black54 : Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtext,
              style: TextStyle(
                color: isSelected ? Colors.black54 : Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}