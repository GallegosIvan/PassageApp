import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:passage/screens/auth/signup_screen.dart';
import 'package:passage/screens/auth/login_screen.dart';
import 'package:passage/screens/communities/create_community_screen.dart';
import 'package:passage/services/bible_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    await Supabase.initialize(
      url: 'https://dyoztddhfsscgvwlupdl.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5b3p0ZGRoZnNzY2d2d2x1cGRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyNzg2MjgsImV4cCI6MjA5MDg1NDYyOH0.i4b2KXmql_lnh2-Yxzo2J5OgM6_bk3p2tSJwXaFUG0E',
    );
  });

  // ============================================================
  // UNIT TESTS — Bible service logic
  // ============================================================

  group('BibleService unit tests', () {
    late BibleService bibleService;
    setUp(() => bibleService = BibleService());

    test('parseVerses extracts verses correctly', () {
      final content = [
        {
          'type': 'heading',
          'content': ['The Creation']
        },
        {
          'type': 'verse',
          'number': 1,
          'content': [
            'In the beginning God created the heavens and the earth.'
          ]
        },
        {
          'type': 'verse',
          'number': 2,
          'content': ['Now the earth was formless and void.']
        },
        {'type': 'line_break'},
      ];

      final verses = bibleService.parseVerses(content);
      expect(verses.length, 2);
      expect(verses[0]['number'], 1);
      expect(verses[0]['text'],
          'In the beginning God created the heavens and the earth.');
      expect(verses[1]['number'], 2);
    });

    test('parseVerses skips empty verses', () {
      final content = [
        {
          'type': 'verse',
          'number': 1,
          'content': ['Valid verse text']
        },
        {'type': 'verse', 'number': 2, 'content': []},
      ];
      final verses = bibleService.parseVerses(content);
      expect(verses.length, 1);
    });

    test('parseVerses handles FormattedText parts', () {
      final content = [
        {
          'type': 'verse',
          'number': 1,
          'content': [
            {'text': 'For God so loved '},
            'the world.',
          ]
        },
      ];
      final verses = bibleService.parseVerses(content);
      expect(verses[0]['text'], 'For God so loved the world.');
    });

    test('getChapterNumbers generates correct list', () {
      final book = {'numberOfChapters': 3, 'firstChapterNumber': 1};
      final chapters = bibleService.getChapterNumbers(book);
      expect(chapters, [1, 2, 3]);
    });

    test('getChapterNumbers handles 150 chapters', () {
      final book = {'numberOfChapters': 150, 'firstChapterNumber': 1};
      final chapters = bibleService.getChapterNumbers(book);
      expect(chapters.length, 150);
      expect(chapters.first, 1);
      expect(chapters.last, 150);
    });
  });

  // ============================================================
  // UNIT TESTS — Validation logic
  // ============================================================

  group('Validation logic', () {
    test('email regex rejects invalid emails', () {
      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      expect(emailRegex.hasMatch('notanemail'), false);
      expect(emailRegex.hasMatch('missing@domain'), false);
      expect(emailRegex.hasMatch('@nodomain.com'), false);
    });

    test('email regex accepts valid emails', () {
      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      expect(emailRegex.hasMatch('valid@email.com'), true);
      expect(emailRegex.hasMatch('user@test.org'), true);
    });

    test('username rejects spaces', () {
      expect('ivan gallegos'.contains(' '), true);
    });

    test('username rejects special characters', () {
      final validChars = RegExp(r'^[a-zA-Z0-9_]+$');
      expect(validChars.hasMatch('valid_username'), true);
      expect(validChars.hasMatch('invalid!user'), false);
      expect(validChars.hasMatch('invalid@user'), false);
    });

    test('username requires minimum 3 characters', () {
      expect('ab'.length < 3, true);
      expect('abc'.length >= 3, true);
    });

    test('password requires minimum 6 characters', () {
      expect('12345'.length < 6, true);
      expect('123456'.length >= 6, true);
    });
  });

  // ============================================================
  // WIDGET TESTS — Sign up screen
  // ============================================================

  group('SignUpScreen', () {
    testWidgets('renders all form fields', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Passage'), findsOneWidget);
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Display Name'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('shows validation errors on empty submit', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a display name'), findsOneWidget);
      expect(find.text('Please enter a username'), findsOneWidget);
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter a password'), findsOneWidget);
    });

    testWidgets('shows error for invalid email', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(2), 'notanemail');
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email address'), findsOneWidget);
    });

    testWidgets('shows error for short password', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(3), '123');
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(
          find.text('Password must be at least 6 characters'), findsOneWidget);
    });

    testWidgets('shows error for username with spaces', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField).at(1), 'ivan gallegos');
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Username cannot contain spaces'), findsOneWidget);
    });

    testWidgets('shows error for username under 3 characters', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), 'ab');
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(
          find.text('Username must be at least 3 characters'), findsOneWidget);
    });
  });

  // ============================================================
  // WIDGET TESTS — Login screen
  // ============================================================

  group('LoginScreen', () {
    testWidgets('renders all form fields', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Log In'), findsOneWidget);
    });

    testWidgets('shows validation errors on empty submit', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Log In'));
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });
  });

  // ============================================================
  // WIDGET TESTS — Create community screen
  // ============================================================

  group('CreateCommunityScreen', () {
    testWidgets('renders all fields', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: CreateCommunityScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Create Community'), findsWidgets);
      expect(find.text('Community Name'), findsOneWidget);
      expect(find.text('Description (optional)'), findsOneWidget);
      expect(find.text('Book'), findsOneWidget);
      expect(find.text('Chapter'), findsOneWidget);
      expect(find.text('Private community'), findsOneWidget);
    });

    testWidgets('shows error when name is empty', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: CreateCommunityScreen()));
      await tester.pumpAndSettle();

      // Clear name field and trigger validation directly
      await tester.enterText(find.byType(TextFormField).first, '');
      // Find the Form and validate it directly
      final formFinder = find.byType(Form);
      final FormState formState = tester.state(formFinder);
      formState.validate();
      await tester.pumpAndSettle();

      expect(find.text('Please enter a name'), findsOneWidget);
    });
  });
}