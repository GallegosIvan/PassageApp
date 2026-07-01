import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../services/subscription_service.dart';

// ============================================================
// MANAGE SUBSCRIPTION SCREEN
// Shows current plan, renewal date, plan switching,
// and cancel option that opens Apple/Google's native flow.
// ============================================================

class ManageSubscriptionScreen extends StatefulWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  State<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState extends State<ManageSubscriptionScreen> {
  final _subscriptionService = SubscriptionService();
  CustomerInfo? _customerInfo;
  bool _isLoading = true;
  bool _isSwitching = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    setState(() => _isLoading = true);
    final info = await _subscriptionService.getCustomerInfo();
    if (mounted) {
      setState(() {
        _customerInfo = info;
        _isLoading = false;
      });
    }
  }

  String _currentPlan() {
    final entitlement = _customerInfo?.entitlements.active['Passage Pro'];
    if (entitlement == null) return 'free';
    return entitlement.productIdentifier.contains('annual')
        ? 'annual'
        : 'monthly';
  }

  String _expirationDate() {
    final entitlement = _customerInfo?.entitlements.active['Passage Pro'];
    if (entitlement?.expirationDate == null) return '';
    final date = DateTime.parse(entitlement!.expirationDate!);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _switchPlan(String targetPlan) async {
    setState(() => _isSwitching = true);
    try {
      final success = await _subscriptionService.switchPlan(targetPlan);
      if (mounted) {
        if (success) {
          await _loadInfo();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Switched to ${targetPlan == 'annual' ? 'Annual' : 'Monthly'} plan'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not switch plan. Please try again.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Cancel subscription?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'You\'ll be taken to your device\'s subscription settings to cancel. Your access continues until the end of your current billing period.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Continue', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _subscriptionService.openManageSubscriptions(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPlan = _currentPlan();
    final expirationDate = _expirationDate();
    final isAnnual = currentPlan == 'annual';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Manage Subscription',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── CURRENT PLAN ──────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.star_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Current Plan',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isAnnual ? 'Pro — Annual' : 'Pro — Monthly',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isAnnual
                              ? '\$99.99 / year'
                              : '\$11.99 / month',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 14),
                        ),
                        if (expirationDate.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Renews $expirationDate',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── SWITCH PLAN ───────────────────────────
                  _sectionLabel('Switch Plan'),
                  const SizedBox(height: 12),

                  if (isAnnual)
                    _PlanOption(
                      label: 'Monthly',
                      price: '\$11.99 / month',
                      description: 'Billed monthly, cancel anytime',
                      isCurrentPlan: false,
                      isLoading: _isSwitching,
                      onTap: () => _switchPlan('monthly'),
                    )
                  else
                    _PlanOption(
                      label: 'Annual',
                      price: '\$99.99 / year',
                      description: 'Save 30% vs monthly — \$8.33/mo',
                      isCurrentPlan: false,
                      isLoading: _isSwitching,
                      onTap: () => _switchPlan('annual'),
                    ),

                  const SizedBox(height: 24),

                  // ── DANGER ZONE ───────────────────────────
                  _sectionLabel('Danger zone'),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _cancel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel subscription',
                          style:
                              TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Center(
                    child: Text(
                      'Cancelling keeps your access until the end of\nyour current billing period.',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 12),
                      textAlign: TextAlign.center,
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
          color: Colors.grey,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2),
    );
  }
}

// ── PLAN OPTION ───────────────────────────────────────────────
class _PlanOption extends StatelessWidget {
  final String label;
  final String price;
  final String description;
  final bool isCurrentPlan;
  final bool isLoading;
  final VoidCallback onTap;

  const _PlanOption({
    required this.label,
    required this.price,
    required this.description,
    required this.isCurrentPlan,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isCurrentPlan ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrentPlan
                ? Colors.white.withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(price,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            if (isCurrentPlan)
              const Icon(Icons.check_circle,
                  color: Colors.white, size: 20)
            else if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            else
              const Icon(Icons.arrow_forward_ios,
                  color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }
}