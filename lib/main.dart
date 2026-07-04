import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/splash_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/subscription_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/communities/community_detail_screen.dart';
import 'screens/communities/church_detail_screen.dart';
import 'screens/communities/church_chat_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _handleNotificationTap(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'] as String?;
  final communityId = data['community_id'] as String?;
  final churchId = data['church_id'] as String?;
  final postId = data['post_id'] as String?;

  final nav = navigatorKey.currentState;
  if (nav == null) return;

  if ((type == 'reply' || type == 'announcement') && communityId != null) {
    try {
      final result = await Supabase.instance.client
          .from('communities')
          .select()
          .eq('id', communityId)
          .single();
      nav.push(MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(
          community: Map<String, dynamic>.from(result),
          initialPostId: type == 'reply' ? postId : null,
        ),
      ));
    } catch (e) {
      print('notification nav community error: $e');
    }
  } else if (type == 'church_message' && communityId != null) {
    try {
      final result = await Supabase.instance.client
          .from('communities')
          .select()
          .eq('id', communityId)
          .single();
      nav.push(MaterialPageRoute(
        builder: (_) => ChurchChatScreen(community: Map<String, dynamic>.from(result)),
      ));
    } catch (e) {
      print('notification nav church chat error: $e');
    }
  } else if (type == 'church_message' && churchId != null) {
    // fallback if community_id not in payload — open church detail
    try {
      final result = await Supabase.instance.client
          .from('churches')
          .select('*, church_followers(count)')
          .eq('id', churchId)
          .single();
      nav.push(MaterialPageRoute(
        builder: (_) => ChurchDetailScreen(church: Map<String, dynamic>.from(result)),
      ));
    } catch (e) {
      print('notification nav church error: $e');
    }
  }
}

// ============================================================
// MAIN.DART
// Initializes Supabase and RevenueCat, then launches the app.
// All API keys are loaded from .env — never hardcoded.
// ============================================================

Future<void> initializeRevenueCat() async {
  if (kIsWeb) return;
  final apiKey = dotenv.get('REVENUECAT_API_KEY');
  final config = PurchasesConfiguration(apiKey);
  await Purchases.configure(config);
  
  // Set the app user ID to match Supabase user ID
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId != null) {
    await Purchases.logIn(userId);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.get('SUPABASE_URL'),
    anonKey: dotenv.get('SUPABASE_ANON_KEY'),
  );

  // Don't await — run in background so app launches immediately
Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
).then((_) async {
  try {
    await FirebaseMessaging.instance.requestPermission();
    final fcmToken = await FirebaseMessaging.instance.getToken();
    print('FCM Token: $fcmToken');
    if (fcmToken != null) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client
            .from('users')
            .update({'fcm_token': fcmToken})
            .eq('id', userId);
      }
    }

    // Show banners/badges/sound even when app is in the foreground (iOS)
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Background → foreground: user taps notification while app is running
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Cold start: user taps notification to launch app from killed state
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // Wait for splash screen + auth navigation to complete before pushing
      await Future.delayed(const Duration(seconds: 4));
      await _handleNotificationTap(initialMessage);
    }
  } catch (e) {
    print('Firebase background init error: $e');
  }
}).catchError((e) {
  print('Firebase init error: $e');
});

  await initializeRevenueCat();

  // Sync subscription status on launch so Supabase reflects
  // the current RevenueCat state (handles renewals, cancellations)
  if (!kIsWeb) {
    try {
      await SubscriptionService().syncSubscription();
    } catch (e) {
      print('syncSubscription on launch error: $e');
    }
  }

  runApp(const PassageApp());
}

class PassageApp extends StatelessWidget {
  const PassageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Passage',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData.dark().copyWith(
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          background: Colors.black,
          surface: Colors.black,
          onBackground: Colors.white,
          onSurface: Colors.white,
          primary: Colors.white,
          onPrimary: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20),
        ),
        textTheme: ThemeData.dark()
            .textTheme
            .apply(bodyColor: Colors.white, displayColor: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: MaterialStatePropertyAll(Colors.white),
            backgroundColor: MaterialStateProperty.resolveWith((states) =>
                states.contains(MaterialState.disabled)
                    ? Colors.grey
                    : Colors.white24),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: MaterialStateProperty.resolveWith((states) =>
                states.contains(MaterialState.disabled)
                    ? Colors.grey
                    : Colors.white),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          fillColor: Colors.black,
          filled: true,
          hintStyle: TextStyle(color: Colors.white),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
