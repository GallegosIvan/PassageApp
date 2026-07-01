import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import 'landing_screen.dart';
import '../home/main_screen.dart';
import '../onboarding_flow.dart';
import '../terms_gate_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  final _authService = AuthService();
  final _client = Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      String email = _emailController.text.trim();

      if (!email.contains('@')) {
        try {
          final result = await _client.rpc('get_email_by_username', params: {
            'p_username': email,
          });
          if (result == null) {
            if (mounted) _showSnackbar('No account found with that username.', isError: true);
            setState(() => _isLoading = false);
            return;
          }
          email = result as String;
        } catch (e) {
          if (mounted) _showSnackbar('Something went wrong. Please try again.', isError: true);
          setState(() => _isLoading = false);
          return;
        }
      }

      await _authService.logIn(
        email: email,
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;

      // ── TERMS CHECK ───────────────────────────────────────
      // Always check server — catches terms updates even for
      // existing users who previously accepted an older version.
      bool hasAcceptedTerms = false;
      try {
        final result = await _client.rpc('has_accepted_current_terms');
        hasAcceptedTerms = result as bool? ?? false;
      } catch (e) {
        print('has_accepted_current_terms error: $e');
        hasAcceptedTerms = true; // fail open — don't block login on RPC error
      }

      if (!mounted) return;

      if (!hasAcceptedTerms) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TermsGateScreen(
              nextScreen: const _PostTermsRedirect(),
            ),
          ),
        );
        return;
      }

      if (!mounted) return;

      // ── ONBOARDING CHECK ──────────────────────────────────
      final prefs = await SharedPreferences.getInstance();
      final userId = _client.auth.currentUser?.id ?? '';
      bool onboardingComplete = prefs.getBool('onboarding_complete_$userId') ?? false;

      if (!onboardingComplete && userId.isNotEmpty) {
        try {
          final result = await _client
              .from('users')
              .select('has_completed_onboarding')
              .eq('id', userId)
              .single();
          onboardingComplete = result['has_completed_onboarding'] as bool? ?? false;
          if (onboardingComplete) {
            await prefs.setBool('onboarding_complete_$userId', true);
          }
        } catch (e) {
          print('onboarding server check error: $e');
        }
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => onboardingComplete
              ? const MainScreen()
              : const OnboardingFlow(),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) _showSnackbar(e.message, isError: true);
    } catch (e) {
      if (mounted) _showSnackbar('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackbar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LandingScreen()),
            );
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Column(
                    children: [
                      Container(
                        child: Image.asset('assets/icon/icon.png', width: 120, height: 120),
                      ),
                      const SizedBox(height: 16),
                      const Text('Passage',
                          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Study together. Grow together.',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                const Text('Welcome back',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),
                _buildLabel('Email or username'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _emailController,
                  hint: 'Email or username',
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Please enter your email or username';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _buildLabel('Password'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _passwordController,
                  hint: 'Your password',
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white, size: 20),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Please enter your password';
                    return null;
                  },
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Log In',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.black,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

class _PostTermsRedirect extends StatefulWidget {
  const _PostTermsRedirect();

  @override
  State<_PostTermsRedirect> createState() => _PostTermsRedirectState();
}

class _PostTermsRedirectState extends State<_PostTermsRedirect> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id ?? '';
    final prefs = await SharedPreferences.getInstance();
    bool onboardingComplete = prefs.getBool('onboarding_complete_$userId') ?? false;

    if (!onboardingComplete && userId.isNotEmpty) {
      try {
        final result = await client
            .from('users')
            .select('has_completed_onboarding')
            .eq('id', userId)
            .single();
        onboardingComplete = result['has_completed_onboarding'] as bool? ?? false;
        if (onboardingComplete) {
          await prefs.setBool('onboarding_complete_$userId', true);
        }
      } catch (e) {
        print('onboarding server check error: $e');
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => onboardingComplete ? const MainScreen() : const OnboardingFlow(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}