import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/church_service.dart';
import '../../services/community_service.dart';
import 'church_detail_screen.dart';
import 'church_chat_screen.dart';
import 'community_detail_screen.dart';

// ============================================================
// QR SCAN SCREEN
// Resolves a scanned code against TWO possible targets:
// 1. A church (the only way to join a church at all)
// 2. A private church sub-group (an opt-in restriction within
//    a church someone already follows — e.g. a parents-only chat)
//
// Tries church lookup first, then falls back to community
// lookup. Each shows its own confirmation screen before joining
// — scanning alone never joins anything automatically.
// ============================================================

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _churchService = ChurchService();
  final _communityService = CommunityService();
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    final token = barcode?.rawValue;
    if (token == null || token.isEmpty) return;

    setState(() => _isProcessing = true);
    await _controller.stop();

    // Try church token first — this is the more common case
    final church = await _churchService.getChurchByQrToken(token);
    if (!mounted) return;

    if (church != null) {
      _showChurchJoinConfirmation(church, token);
      return;
    }

    // Not a church token — try resolving as a private sub-group
    // join. We don't have a "lookup without joining" RPC for
    // sub-groups (the join RPC itself validates and returns info),
    // so we attempt the join directly and handle errors gracefully.
    await _attemptSubGroupJoin(token);
  }

  void _showInvalidCodeDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Invalid QR code', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This QR code is not recognized. It may have been regenerated or no longer exists.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isProcessing = false);
              _controller.start();
            },
            child: const Text('Try again', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showNotChurchMemberDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Join the church first', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This group belongs to a church you haven\'t joined yet. Scan that church\'s QR code first, then try this group again.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isProcessing = false);
              _controller.start();
            },
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── CHURCH JOIN FLOW ───────────────────────────────────────
  void _showChurchJoinConfirmation(Map<String, dynamic> church, String token) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.church_outlined, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                church['name'] ?? 'Church',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (church['location'] != null) ...[
              Row(children: [
                const Icon(Icons.location_on_outlined, color: Colors.grey, size: 14),
                const SizedBox(width: 4),
                Text(church['location'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ]),
              const SizedBox(height: 8),
            ],
            if (church['description'] != null) ...[
              Text(church['description'], style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
            ],
            const Text(
              'Do you want to join this church?',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isProcessing = false);
              _controller.start();
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => _confirmChurchJoin(church),
            child: const Text('Join', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmChurchJoin(Map<String, dynamic> church) async {
    Navigator.pop(context); // close confirmation dialog

    try {
      await _churchService.followChurch(church['id']);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ChurchDetailScreen(church: church)),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Joined ${church['name']}!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to join. You may already be a member.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  // ── PRIVATE SUB-GROUP JOIN FLOW ────────────────────────────
  // Unlike the church flow, the join RPC itself validates the
  // token AND checks church membership in one call — there's no
  // separate "preview" step, since sub-group info isn't public
  // until you're already inside the church.
  Future<void> _attemptSubGroupJoin(String token) async {
    try {
      final community = await _communityService.joinCommunityByQrToken(token);
      if (!mounted) return;
      _showSubGroupJoinedDialog(community);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString();
      if (message.contains('invalid_token')) {
        _showInvalidCodeDialog();
      } else if (message.contains('not_church_member')) {
        _showNotChurchMemberDialog();
      } else {
        _showInvalidCodeDialog();
      }
    }
  }

  void _showSubGroupJoinedDialog(Map<String, dynamic> community) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check, color: Colors.green, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Joined ${community['name'] ?? 'group'}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'You can find this group in your Communities tab.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Scan QR code',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Scan a church QR code to join, or a group QR code to join a specific group within a church you already follow.',
                style: TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}