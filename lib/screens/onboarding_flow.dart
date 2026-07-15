import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home/main_screen.dart';
import '../widgets/upgrade_sheet.dart';

// ============================================================
// ONBOARDING FLOW
// 6 screens shown once on first launch, never again.
// Strict black/white to match the existing app style.
// No gradients, no color, no illustrations that look like
// stock art — just clean type and iconography.
//
// Screen order:
//   0 — Welcome
//   1 — Bible reading
//   2 — AI Bible assistant
//   3 — Communities & churches
//   4 — Go Pro
//   5 — Permissions / get started
// ============================================================

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _pageController = PageController();
  int _currentPage = 0;
  static const int _totalPages = 6;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _markOnboardingComplete() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete_$userId', true);
    // Also write to server so reinstalls don't re-show onboarding
    try {
      await Supabase.instance.client
          .from('users')
          .update({'has_completed_onboarding': true})
          .eq('id', userId);
    } catch (e) {
      print('markOnboardingComplete server error: $e');
    }
  }

  void _next() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _skip() {
    _pageController.animateToPage(
      _totalPages - 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    await _markOnboardingComplete();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // ── SKIP BUTTON (hidden on last two screens) ──
              Align(
                alignment: Alignment.topRight,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _currentPage < 4 ? 1.0 : 0.0,
                  child: TextButton(
                    onPressed: _currentPage < 4 ? _skip : null,
                    child: const Text('Skip',
                        style: TextStyle(color: Colors.white54, fontSize: 14)),
                  ),
                ),
              ),

              // ── PAGES ────────────────────────────────────
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  children: [
                    _WelcomePage(onNext: _next),
                    _BibleReadingPage(onNext: _next),
                    _AIAssistantPage(onNext: _next),
                    _CommunitiesPage(onNext: _next),
                    _ProPage(onNext: _next, onStartTrial: () async {
                      final upgraded = await UpgradeSheet.show(context);
                      if (upgraded == true && mounted) {
                        _next();
                      }
                    }),
                    _PermissionsPage(onFinish: _finish),
                  ],
                ),
              ),

              // ── PAGE DOTS ─────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_totalPages, (i) {
                    final isActive = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white : Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SCREEN 1 — WELCOME
// ============================================================
class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    const SizedBox(height: 48),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24, width: 1),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.menu_book_outlined,
                          color: Colors.white, size: 48),
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      'Passage',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your Bible. Your community.\nYour study companion.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 18,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: _PrimaryButton(label: 'Get started', onTap: onNext),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SCREEN 2 — BIBLE READING
// ============================================================
class _BibleReadingPage extends StatelessWidget {
  final VoidCallback onNext;
  const _BibleReadingPage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),
                    const _ScreenLabel('Bible reading'),
                    const SizedBox(height: 24),
                    const Text(
                      'Read at your own pace.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Choose from hundreds of complete Bible translations. Highlight verses, add notes, and track your reading — your progress stays with you.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: const [
                        _FeatureChip(icon: Icons.translate_outlined, label: 'Hundreds of translations'),
                        _FeatureChip(icon: Icons.highlight_outlined, label: 'Highlights & notes'),
                        _FeatureChip(icon: Icons.local_fire_department_outlined, label: 'Reading streaks'),
                        _FeatureChip(icon: Icons.calendar_today_outlined, label: 'Calendar history'),
                      ],
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: _PrimaryButton(label: 'Continue', onTap: onNext),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SCREEN 3 — AI BIBLE ASSISTANT
// ============================================================
class _AIAssistantPage extends StatelessWidget {
  final VoidCallback onNext;
  const _AIAssistantPage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),
                    const _ScreenLabel('AI assistant'),
                    const SizedBox(height: 24),
                    const Text(
                      'Ask anything about the Bible.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Get instant answers to your questions, navigate to any verse by asking, and use your voice so you can study hands-free.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 40),
                    _MockChatBubble(
                      isUser: true,
                      text: 'What does Romans 8:28 mean?',
                    ),
                    const SizedBox(height: 10),
                    _MockChatBubble(
                      isUser: false,
                      text: '"And we know that in all things God works for the good of those who love him..." Paul is saying that God uses every circumstance — even suffering — purposefully.',
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: _PrimaryButton(label: 'Continue', onTap: onNext),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SCREEN 4 — COMMUNITIES & CHURCHES
// ============================================================
class _CommunitiesPage extends StatelessWidget {
  final VoidCallback onNext;
  const _CommunitiesPage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),
                    const _ScreenLabel('Communities & churches'),
                    const SizedBox(height: 24),
                    const Text(
                      'Study together.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Join public Bible study communities or follow your church. Inside a church, you choose which group chats and studies you join — nothing is forced on you.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _InfoRow(
                      icon: Icons.people_outline,
                      title: 'Public study communities',
                      subtitle: 'Find groups studying the same book as you',
                    ),
                    const SizedBox(height: 16),
                    _InfoRow(
                      icon: Icons.church_outlined,
                      title: 'Private churches',
                      subtitle: 'Join in person by scanning a QR code — no open search',
                    ),
                    const SizedBox(height: 16),
                    _InfoRow(
                      icon: Icons.chat_bubble_outline,
                      title: 'Opt-in group chats',
                      subtitle: 'Browse your church\'s groups and join only what you want',
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: _PrimaryButton(label: 'Continue', onTap: onNext),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SCREEN 5 — GO PRO
// ============================================================
class _ProPage extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onStartTrial;
  const _ProPage({required this.onNext, required this.onStartTrial});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),
                    const _ScreenLabel('Passage Pro'),
                    const SizedBox(height: 20),
                    const Text(
                      'Go deeper.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Everything in the free plan, plus:',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                    const SizedBox(height: 28),
                    _ProFeatureRow(
                      icon: Icons.auto_awesome_outlined,
                      title: '50,000 AI tokens per day',
                      subtitle: 'vs 2,000 on free',
                    ),
                    const SizedBox(height: 14),
                    _ProFeatureRow(
                      icon: Icons.quiz_outlined,
                      title: '8 quizzes per day',
                      subtitle: 'vs 3 on free',
                    ),
                    const SizedBox(height: 14),
                    _ProFeatureRow(
                      icon: Icons.history_outlined,
                      title: 'Unlimited conversation history',
                      subtitle: 'vs 5 saved on free',
                    ),
                    const SizedBox(height: 14),
                    _ProFeatureRow(
                      icon: Icons.lock_open_outlined,
                      title: 'Private study communities',
                      subtitle: 'Up to 5 invite-only groups',
                    ),
                    const SizedBox(height: 14),
                    _ProFeatureRow(
                      icon: Icons.church_outlined,
                      title: 'Create up to 3 churches',
                      subtitle: 'Free plan: 1 church',
                    ),
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '\$99.99 / year',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '\$8.33/mo · or \$11.99/mo billed monthly',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '7-day free trial — cancel any time',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      _PrimaryButton(label: 'Start free trial', onTap: onStartTrial),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: onNext,
                          child: const Text(
                            'Maybe later',
                            style: TextStyle(color: Colors.white38, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SCREEN 6 — PERMISSIONS / GET STARTED
// ============================================================
class _PermissionsPage extends StatelessWidget {
  final VoidCallback onFinish;
  const _PermissionsPage({required this.onFinish});

  Future<void> _requestPermissions(BuildContext context) async {
    await Permission.camera.request();
    await Permission.microphone.request();
    onFinish();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 48),
                    const _ScreenLabel('One last thing'),
                    const SizedBox(height: 24),
                    const Text(
                      'Two quick permissions.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Passage works better with access to your camera and microphone. We\'ll ask now so the prompts don\'t interrupt you mid-study.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 40),
                    _PermissionRow(
                      icon: Icons.qr_code_scanner_outlined,
                      title: 'Camera',
                      subtitle: 'Scan QR codes to join a church in person',
                    ),
                    const SizedBox(height: 20),
                    _PermissionRow(
                      icon: Icons.mic_outlined,
                      title: 'Microphone',
                      subtitle: 'Use your voice with the AI Bible assistant',
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                    children: [
                      _PrimaryButton(
                        label: 'Allow & get started',
                        onTap: () => _requestPermissions(context),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: onFinish,
                          child: const Text(
                            'Skip for now',
                            style: TextStyle(color: Colors.white38, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SHARED COMPONENTS
// ============================================================

class _ScreenLabel extends StatelessWidget {
  final String text;
  const _ScreenLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProFeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _ProFeatureRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
        const Icon(Icons.check, color: Colors.white38, size: 16),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _PermissionRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 14, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MockChatBubble extends StatelessWidget {
  final bool isUser;
  final String text;
  const _MockChatBubble({required this.isUser, required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? Colors.white.withOpacity(0.12) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: isUser
              ? Border.all(color: Colors.white.withOpacity(0.15))
              : null,
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
        ),
      ),
    );
  }
}