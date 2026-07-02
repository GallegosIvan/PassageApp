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

// ============================================================
// MAIN.DART
// Initializes Supabase and RevenueCat, then launches the app.
// All API keys are loaded from .env — never hardcoded.
// ============================================================

Future<void> initializeRevenueCat() async {
  if (kIsWeb) return;
  final apiKey = dotenv.get('REVENUECAT_API_KEY');
  await Purchases.configure(PurchasesConfiguration(apiKey));
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
