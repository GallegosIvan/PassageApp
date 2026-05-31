import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:passage/main.dart' as app;
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// PASSAGE APP — INTEGRATION TESTS
// Run with: flutter test integration_test/app_test.dart -d emulator-5554
// Uses real test account: test@test.com / testtest
// ============================================================

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testEmail = 'test@test.com';
  const testPassword = 'testtest';

  // Helper to launch app and wait for it to settle
  Future<void> launchApp(WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  // Helper to sign out via Supabase after app is initialized
  Future<void> signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }

  // Helper to sign in via Supabase after app is initialized
  Future<void> signIn() async {
    await Supabase.instance.client.auth.signInWithPassword(
      email: testEmail,
      password: testPassword,
    );
  }

  // Helper to navigate to login screen from sign up
  Future<void> goToLogin(WidgetTester tester) async {
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
  }

  // Helper to log in through the UI
  Future<void> loginViaUI(WidgetTester tester) async {
    await goToLogin(tester);
    await tester.enterText(find.byType(TextFormField).at(0), testEmail);
    await tester.enterText(find.byType(TextFormField).at(1), testPassword);
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  // ============================================================
  // AUTH TESTS
  // ============================================================

  group('Authentication', () {
    testWidgets('app launches and shows splash screen', (tester) async {
      await launchApp(tester);
      await signOut();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Passage'), findsWidgets);
      expect(find.text('Study together. Grow together.'), findsOneWidget);
    });

    testWidgets('navigates to sign up when not logged in', (tester) async {
      await launchApp(tester);
      await signOut();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Create your account'), findsOneWidget);
    });

    testWidgets('can navigate to login screen', (tester) async {
      await launchApp(tester);
      await signOut();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('shows validation error for empty email on login',
        (tester) async {
      await launchApp(tester);
      await signOut();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await goToLogin(tester);
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email'), findsOneWidget);
    });

    testWidgets('can log in with valid credentials', (tester) async {
      await launchApp(tester);
      await signOut();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await loginViaUI(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Bible'), findsOneWidget);
      expect(find.text('Communities'), findsOneWidget);
    });

    testWidgets('shows error for wrong password', (tester) async {
      await launchApp(tester);
      await signOut();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await goToLogin(tester);
      await tester.enterText(find.byType(TextFormField).at(0), testEmail);
      await tester.enterText(
          find.byType(TextFormField).at(1), 'wrongpassword');
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Still on login screen
      expect(find.text('Log In'), findsOneWidget);
    });
  });

  // ============================================================
  // HOME SCREEN TESTS
  // ============================================================

  group('Home screen', () {
    testWidgets('shows greeting after login', (tester) async {
      await launchApp(tester);
      await signOut();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await loginViaUI(tester);

      final hasGreeting =
          find.text('Good morning').evaluate().isNotEmpty ||
          find.text('Good afternoon').evaluate().isNotEmpty ||
          find.text('Good evening').evaluate().isNotEmpty;
      expect(hasGreeting, isTrue);
    });

    testWidgets('shows verse of the day', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('VERSE OF THE DAY'), findsOneWidget);
      expect(find.text('Open Bible Reader →'), findsOneWidget);
    });

    testWidgets('shows bottom navigation with 4 tabs', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Bible'), findsOneWidget);
      expect(find.text('Communities'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('verse of day taps open bible reader', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Open Bible Reader →'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Bible'), findsOneWidget);
    });
  });

  // ============================================================
  // BIBLE READER TESTS
  // ============================================================

  group('Bible reader', () {
    testWidgets('can navigate to bible tab', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Bible'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Genesis'), findsOneWidget);
      expect(find.text('BSB'), findsOneWidget);
    });

    testWidgets('can open a book and see chapters', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Bible'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('Genesis'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('can open a chapter and read verses', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Bible'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('Genesis'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('Genesis 1'), findsOneWidget);
      expect(find.textContaining('In the beginning'), findsOneWidget);
    });

    testWidgets('can navigate to next chapter', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Bible'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('Genesis'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('Genesis 2'), findsOneWidget);
    });

    testWidgets('prev chapter disabled on chapter 1', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Bible'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('Genesis'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final prevButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(prevButton.onPressed, isNull);
    });

    testWidgets('search filters book list', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Bible'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.enterText(find.byType(TextField).first, 'John');
      await tester.pumpAndSettle();

      expect(find.text('John'), findsOneWidget);
      expect(find.text('Genesis'), findsNothing);
    });

    testWidgets('tapping verse shows action sheet', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Bible'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('Genesis'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.textContaining('In the beginning'));
      await tester.pumpAndSettle();

      expect(find.text('Highlight'), findsOneWidget);
      expect(find.text('Add Note'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('bookmark button shows bookmark sheet', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Bible'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('Genesis'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.byIcon(Icons.bookmark_border).first);
      await tester.pumpAndSettle();

      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.text('Bookmark 1'), findsOneWidget);
      expect(find.text('Bookmark 2'), findsOneWidget);
      expect(find.text('Bookmark 3'), findsOneWidget);
    });
  });

  // ============================================================
  // COMMUNITIES TESTS
  // ============================================================

  group('Communities', () {
    testWidgets('can navigate to communities tab', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('My Communities'), findsOneWidget);
      expect(find.text('Discover'), findsOneWidget);
    });

    testWidgets('can switch to discover tab', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('can open create community screen', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Create Community'), findsWidgets);
      expect(find.text('Community Name'), findsOneWidget);
    });

    testWidgets('create community validates empty name', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final formFinder = find.byType(Form);
      final FormState formState = tester.state(formFinder);
      formState.validate();
      await tester.pumpAndSettle();

      expect(find.text('Please enter a name'), findsOneWidget);
    });
  });

  // ============================================================
  // LOGOUT TEST
  // ============================================================

  group('Logout', () {
    testWidgets('can log out from home screen', (tester) async {
      await launchApp(tester);
      await signIn();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Create your account'), findsOneWidget);
    });
  });
}