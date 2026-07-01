import 'package:flutter/material.dart';
import '../../services/church_service.dart';

class CreateChurchScreen extends StatefulWidget {
  const CreateChurchScreen({super.key});

  @override
  State<CreateChurchScreen> createState() => _CreateChurchScreenState();
}

class _CreateChurchScreenState extends State<CreateChurchScreen> {
  final _churchService = ChurchService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _websiteController = TextEditingController();
  bool _isLoading = false;
  bool _confirmed = false;
  Map<String, dynamic>? _limitInfo;

  @override
  void initState() {
    super.initState();
    _checkLimit();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _checkLimit() async {
    final info = await _churchService.checkChurchLimit();
    if (mounted) setState(() => _limitInfo = info);
  }

  Future<void> _create() async {
    // VALIDATION: form fields and confirmation checkbox
    if (!_formKey.currentState!.validate()) return;
    if (!_confirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please confirm you are an authorized representative'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Church creation limit still applies (1 free / 3 Pro) — this
    // is unrelated to privacy, which is now mandatory for everyone.
    if (_limitInfo != null && _limitInfo!['allowed'] == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'You\'ve reached the limit of ${_limitInfo!['limit']} churches.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      // API CALL: ChurchService.createChurch → Supabase DB
      // Churches are always private — no toggle, no public
      // discovery. Joining only happens via in-person QR scan.
      await _churchService.createChurch(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        website: _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Church profile created! Find your QR code in church settings to invite members in person.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final isLimitError = e.toString().contains('church_limit_reached');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isLimitError
                ? 'You\'ve reached your church creation limit.'
                : 'Failed to create church: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Create Church Profile',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── CHURCH LIMIT INDICATOR ─────────────────────
              if (_limitInfo != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _limitInfo!['allowed'] == false
                        ? Colors.red.withOpacity(0.1)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Icon(Icons.church_outlined, size: 16,
                        color: _limitInfo!['allowed'] == false ? Colors.red : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_limitInfo!['churches_created']}/${_limitInfo!['limit']} churches created',
                        style: TextStyle(
                          color: _limitInfo!['allowed'] == false ? Colors.red : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ]),
                ),
              ],

              // ── PRIVACY NOTICE ──────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_2, color: Colors.grey, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Churches join by QR code only',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w500)),
                          Text(
                            'Members must scan your church\'s QR code in person to join. There is no public discovery or invite link.',
                            style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── CHURCH NAME ───────────────────────────────
              _buildLabel('Church Name'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('e.g. First Baptist Church'),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Please enter a church name'
                    : null,
              ),

              const SizedBox(height: 20),

              // ── DESCRIPTION ───────────────────────────────
              _buildLabel('Description (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: _inputDecoration('Tell people about your church'),
              ),

              const SizedBox(height: 20),

              // ── LOCATION ──────────────────────────────────
              _buildLabel('Location (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _locationController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('e.g. Dallas, TX'),
              ),

              const SizedBox(height: 20),

              // ── WEBSITE ───────────────────────────────────
              _buildLabel('Website (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _websiteController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.url,
                decoration: _inputDecoration('e.g. https://mychurch.com'),
              ),

              const SizedBox(height: 28),

              // ── CONFIRMATION ──────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _confirmed
                        ? Colors.white.withOpacity(0.3)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _confirmed,
                      onChanged: (val) =>
                          setState(() => _confirmed = val ?? false),
                      activeColor: Colors.white,
                      checkColor: Colors.black,
                      side: const BorderSide(color: Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'I confirm that I am an authorized representative of this church and have permission to create this profile.',
                        style: TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // ── CREATE BUTTON ─────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _create,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2))
                      : const Text('Create Church Profile',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500));
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white, width: 1),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}