import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================
// SUBSCRIPTION SERVICE
// RevenueCat is the client-side source of truth for purchase
// state. Supabase subscriptions table is kept in sync via a
// server-side Edge Function (sync-subscription) that calls
// RevenueCat's server-to-server API — the client never writes
// to the subscriptions table directly, preventing bypass.
// ============================================================

class SubscriptionService {
  final _client = Supabase.instance.client;

  // ── CHECK IF USER HAS ACTIVE PRO SUBSCRIPTION ────────────
  // Checks RevenueCat directly — source of truth for purchases.
  Future<bool> isPro() async {
    if (kIsWeb) return false;
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return customerInfo.entitlements.active.containsKey('Passage Pro');
    } catch (e) {
      print('isPro error: $e');
      return false;
    }
  }

  // ── SYNC SUBSCRIPTION TO SUPABASE ─────────────────────────
  // Calls the server-side Edge Function which validates against
  // RevenueCat's API before writing to the subscriptions table.
  // The client never writes subscription data directly.
  Future<void> syncSubscription() async {
    if (kIsWeb) return;
    final session = _client.auth.currentSession;
    if (session == null) return;

    try {
      await _client.functions.invoke(
        'sync-subscription',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
    } catch (e) {
      print('syncSubscription error: $e');
    }
  }

  // ── GET CUSTOMER INFO ─────────────────────────────────────
  Future<CustomerInfo?> getCustomerInfo() async {
    if (kIsWeb) return null;
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      print('getCustomerInfo error: $e');
      return null;
    }
  }

  // ── CHECK TRIAL ELIGIBILITY ────────────────────────────────
Future<bool> isTrialEligible() async {
  if (kIsWeb) return false;
  try {
    final offerings = await Purchases.getOfferings();
    final package = offerings.current?.annual ?? offerings.current?.monthly;
    if (package == null) {
      print('isTrialEligible: no package found, returning true');
      return true;
    }

    final eligibility = await Purchases.checkTrialOrIntroductoryPriceEligibility(
      [package.storeProduct.identifier],
    );
    final result = eligibility[package.storeProduct.identifier];
    print('isTrialEligible: status = ${result?.status}');
    return result?.status == IntroEligibilityStatus.introEligibilityStatusEligible;
  } catch (e) {
    print('isTrialEligible error: $e');
    return true;
  }
}
  // ── PURCHASE MONTHLY PLAN ─────────────────────────────────
  Future<bool> purchaseMonthly() async {
    if (kIsWeb) return false;
    return await _purchase('monthly');
  }

  // ── PURCHASE ANNUAL PLAN ──────────────────────────────────
  Future<bool> purchaseAnnual() async {
    if (kIsWeb) return false;
    return await _purchase('yearly');
  }

  // ── SWITCH PLAN ───────────────────────────────────────────
  Future<bool> switchPlan(String targetPlan) async {
    if (kIsWeb) return false;
    return await _purchase(targetPlan == 'annual' ? 'yearly' : 'monthly');
  }

  // ── RESTORE PURCHASES ─────────────────────────────────────
  Future<bool> restorePurchases() async {
    if (kIsWeb) return false;
    try {
      final customerInfo = await Purchases.restorePurchases();
      final hasPro = customerInfo.entitlements.active.containsKey('Passage Pro');
      if (hasPro) await syncSubscription();
      return hasPro;
    } catch (e) {
      print('restorePurchases error: $e');
      return false;
    }
  }

  // ── OPEN MANAGE SUBSCRIPTIONS ─────────────────────────────
  Future<void> openManageSubscriptions(BuildContext context) async {
    if (kIsWeb) return;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final url = Uri.parse(
      isIOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // ── INTERNAL PURCHASE HANDLER ─────────────────────────────
  Future<bool> _purchase(String productId) async {
    if (kIsWeb) return false;
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) throw Exception('No offerings available');

      Package? package;
      if (productId == 'monthly') {
        package = current.monthly;
      } else if (productId == 'yearly') {
        package = current.annual;
      }

      if (package == null) throw Exception('Package not found: $productId');

      await Purchases.purchasePackage(package!);
      final customerInfo = await Purchases.getCustomerInfo();
      final hasPro =
          customerInfo.entitlements.all.containsKey('Passage Pro') &&
              customerInfo.entitlements.all['Passage Pro']!.isActive;
      if (hasPro) await syncSubscription();
      return hasPro;
    } catch (e) {
      print('purchase error: $e');
      return false;
    }
  }
}
