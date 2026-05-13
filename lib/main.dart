import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/signup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://dyoztddhfsscgvwlupdl.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5b3p0ZGRoZnNzY2d2d2x1cGRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyNzg2MjgsImV4cCI6MjA5MDg1NDYyOH0.i4b2KXmql_lnh2-Yxzo2J5OgM6_bk3p2tSJwXaFUG0E',
  );

  runApp(const PassageApp());
}

class PassageApp extends StatelessWidget {
  const PassageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Passage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B4FCF)),
        useMaterial3: true,
      ),
      home: const SignUpScreen(),
    );
  }
}