import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// APPEAL SCREEN (user-facing)
// Restricted users can submit one appeal explaining why they
// should be unrestricted. Shows the current status (pending,
// approved, denied) and the admin's response once resolved.
// ============================================================

class AppealScreen extends StatefulWidget {
  const AppealScreen({super.key});

  @override
  State<AppealScreen> createState() => _AppealScreenState();
}

class _AppealScreenState extends State<AppealScreen> {
  final _client = Supabase.instance.client;
  final _textController = TextEditingController();
  Map<String, dynamic>? _existingAppeal;
  bool _hasUsedApproval = false;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadAppealStatus();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadAppealStatus() async {
    setState(() => _isLoading = true);
    try {
      final result = await _client.rpc('get_my_appeal_status');
      final userRow = await _client
          .from('users')
          .select('has_used_appeal_approval')
          .eq('id', _client.auth.currentUser!.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _existingAppeal = result != null ? Map<String, dynamic>.from(result) : null;
          _hasUsedApproval = userRow?['has_used_appeal_approval'] == true;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('loadAppealStatus error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitAppeal() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await _client.rpc('submit_restriction_appeal', params: {'p_appeal_text': text});
      _textController.clear();
      await _loadAppealStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appeal submitted'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      final message = e.toString();
      String displayMessage;
      if (message.contains('appeal_already_pending')) {
        displayMessage = 'You already have a pending appeal';
      } else if (message.contains('appeal_already_used')) {
        displayMessage = 'You\'ve already submitted your one appeal for this account.';
      } else if (message.contains('not_restricted')) {
        displayMessage = 'Your account is not currently restricted';
      } else {
        displayMessage = 'Failed to submit appeal';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayMessage), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Appeal Restriction',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _existingAppeal != null
                  ? _buildExistingAppeal(_existingAppeal!)
                  : _hasUsedApproval
                      ? _buildAppealAlreadyUsed()
                      : _buildNewAppealForm(),
            ),
    );
  }

  Widget _buildAppealAlreadyUsed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.gavel_outlined, color: Colors.red, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You\'ve already used your one appeal on this account. Further restrictions cannot be appealed.',
                  style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNewAppealForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your account is permanently restricted from posting, replying, and chatting due to repeated reported violations.',
          style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 8),
        const Text(
          'If you believe this was a mistake, you can explain why below. An admin will review your appeal and respond.',
          style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _textController,
          maxLines: 8,
          maxLength: 1000,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Explain why you believe your restriction should be lifted...',
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: const Color(0xFF1A1A1A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isSubmitting || _textController.text.trim().isEmpty ? null : _submitAppeal,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                : const Text('Submit Appeal', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildExistingAppeal(Map<String, dynamic> appeal) {
    final status = appeal['status'] as String;
    final response = appeal['admin_response'] as String?;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusLabel = 'Approved — restriction lifted';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'denied':
        statusColor = Colors.red;
        statusLabel = 'Denied';
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = Colors.orange;
        statusLabel = 'Pending review';
        statusIcon = Icons.hourglass_empty;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('YOUR APPEAL', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10)),
          child: Text(appeal['appeal_text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
        ),
        if (response != null) ...[
          const SizedBox(height: 20),
          const Text('ADMIN RESPONSE', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10)),
            child: Text(response, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
          ),
        ],
        if (status == 'denied') ...[
          const SizedBox(height: 16),
          const Text(
            'This decision is final. No further appeals are available on this account.',
            style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }
}