import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../bible/bible_books_screen.dart';
import '../communities/communities_screen.dart';
import '../profile/profile_screen.dart';
import '../splash_screen.dart';
import '../guest_tab_placeholder.dart';
import '../../services/guest_session.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _connectivityTimer;
  bool _checkingConnectivity = false;

  List<Widget> get _screens => GuestSession.isGuest
      ? const [
          HomeScreen(),
          BibleBooksScreen(),
          GuestTabPlaceholder(featureName: 'Communities', icon: Icons.people_outline),
          GuestTabPlaceholder(featureName: 'Profile', icon: Icons.person_outline),
        ]
      : const [
          HomeScreen(),
          BibleBooksScreen(),
          CommunitiesScreen(),
          ProfileScreen(),
        ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Periodic check every 30 seconds while app is active
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnectivity(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivityTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkConnectivity();
    }
  }

  Future<void> _checkConnectivity() async {
    if (_checkingConnectivity || !mounted) return;
    _checkingConnectivity = true;
    try {
      final result = await InternetAddress.lookup('supabase.com')
          .timeout(const Duration(seconds: 5));
      if (result.isEmpty || result.first.rawAddress.isEmpty) {
        _redirectToNoInternet();
      }
    } catch (_) {
      _redirectToNoInternet();
    } finally {
      _checkingConnectivity = false;
    }
  }

  void _redirectToNoInternet() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const SplashScreen(showNoInternet: true),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: Colors.black,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        selectedIconTheme: const IconThemeData(color: Colors.white),
        unselectedIconTheme: const IconThemeData(color: Colors.white70),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            activeIcon: Icon(Icons.menu_book),
            label: 'Bible',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Communities',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
