import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import 'landing_screen.dart';

// ============================================================
// SIGN UP SCREEN
// ============================================================

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // Form key used to trigger validation across all fields at once
  final _formKey = GlobalKey<FormState>();

  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  final _authService = AuthService();

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── SIGN UP HANDLER ───────────────────────────────────────
  Future<void> _handleSignUp() async {
    // VALIDATION: triggers all field validators before proceeding
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // API CALL: AuthService.signUp → Supabase Auth + Supabase DB
      await _authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        username: _usernameController.text.trim(),
        displayName: _displayNameController.text.trim(),
      );

      // Only record terms server-side if we have a live session
      // (email verification disabled). With verification on,
      // there's no session here yet — login_screen.dart handles
      // the terms check after they verify and log in.
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        try {
          await Supabase.instance.client.rpc('accept_terms');
        } catch (e) {
          print('accept_terms after signup error: $e');
        }
      }

      if (mounted) {
        _showSnackbar(
          'Account created! Please check your email to verify.',
          isError: false,
        );
      }
    } on AuthException catch (e) {
      // Supabase auth errors (wrong format, email taken, weak password)
      if (mounted) _showSnackbar(e.message, isError: true);
    } on PostgrestException catch (e) {
      // DB errors — most likely duplicate username (unique constraint)
      if (mounted) {
        final msg = e.message.contains('username')
            ? 'That username is already taken. Please choose another.'
            : 'Something went wrong. Please try again.';
        _showSnackbar(msg, isError: true);
      }
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
                const SizedBox(height: 0),

                // ── LOGO + TITLE ──────────────────────────
                Center(
                  child: Column(
                    children: [
                      Container(
                        child: Image.asset('assets/icon/icon.png', width: 120, height: 120),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Passage',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Study together. Grow together.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                const Text(
                  'Create your account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 24),

                // ── DISPLAY NAME ──────────────────────────
                _buildLabel('Display Name'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _displayNameController,
                  hint: 'e.g. John Smith',
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a display name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                const Text(
                  'Shown publicly. Others can share the same name.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),

                const SizedBox(height: 20),

                // ── USERNAME ──────────────────────────────
                _buildLabel('Username'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _usernameController,
                  hint: 'e.g. Smith123',
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a username';
                    }
                    if (val.trim().length < 3) {
                      return 'Username must be at least 3 characters';
                    }
                    if (val.contains(' ')) {
                      return 'Username cannot contain spaces';
                    }
                    final validChars = RegExp(r'^[a-zA-Z0-9_]+$');
                    if (!validChars.hasMatch(val.trim())) {
                      return 'Only letters, numbers, and underscores allowed';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                const Text(
                  'Unique handle. No two users can share this.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),

                const SizedBox(height: 20),

                // ── EMAIL ─────────────────────────────────
                _buildLabel('Email'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _emailController,
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                    if (!emailRegex.hasMatch(val.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // ── PASSWORD ──────────────────────────────
                _buildLabel('Password'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _passwordController,
                  hint: 'At least 6 characters',
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return 'Please enter a password';
                    }
                    if (val.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 36),

                // ── SUBMIT BUTTON ─────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Create Account',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.white, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}