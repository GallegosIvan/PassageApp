import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/church_chat_service.dart';
import '../../services/community_service.dart';
import '../../widgets/restricted_dialog.dart';
import '../../widgets/report_sheet.dart';
import 'community_settings_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ============================================================
// CHURCH CHAT SCREEN
// Linear group-chat UI for general church communities (youth
// group, parents, serving teams) — distinct from the threaded
// Bible-study community model. Open to all members, with a
// lightweight reply-to-message affordance instead of separate
// thread screens.
// ============================================================

class ChurchChatScreen extends StatefulWidget {
  final Map<String, dynamic> community;

  const ChurchChatScreen({super.key, required this.community});

  @override
  State<ChurchChatScreen> createState() => _ChurchChatScreenState();
}

class _ChurchChatScreenState extends State<ChurchChatScreen> {
  final _chatService = ChurchChatService();
  final _communityService = CommunityService();
  final _client = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _replyingTo;
  bool _isLoading = true;
  bool _isSending = false;
  String? _currentUserId;
  bool _isAdmin = false;
  RealtimeChannel? _channel;

  // Draft photo attachment — picked but not yet sent. User can
  // still add a caption and must explicitly tap Send.
  Uint8List? _draftImageBytes;
  String? _draftImageExtension;

  @override
  void initState() {
    super.initState();
    _currentUserId = _client.auth.currentUser?.id;
    _loadMessages();
    _checkIfAdmin();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _checkIfAdmin() async {
    final isAdmin = await _chatService.isCommunityAdmin(widget.community['id']);
    if (mounted) setState(() => _isAdmin = isAdmin);
  }

  Future<void> _showQrSheet() async {
    final token = await _communityService.getSubGroupQrToken(widget.community['id']);
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load QR code'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Join QR code',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Anyone who already follows your church can scan this to join this group.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(
                data: token,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final messages = await _chatService.getMessages(widget.community['id']);
    if (mounted) {
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _subscribeToRealtime() {
    _channel = _client
        .channel('church_chat_${widget.community['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'church_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'community_id',
            value: widget.community['id'],
          ),
          callback: (payload) => _loadMessages(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'church_messages',
          callback: (payload) => _loadMessages(),
        )
        .subscribe();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final hasImage = _draftImageBytes != null;
    if (text.isEmpty && !hasImage) return;

    setState(() => _isSending = true);
    try {
      String? imageUrl;
      if (hasImage) {
        imageUrl = await _chatService.uploadChatImageBytes(
          communityId: widget.community['id'],
          bytes: _draftImageBytes!,
          fileExtension: _draftImageExtension ?? 'jpg',
        );
      }

      await _chatService.sendMessage(
        communityId: widget.community['id'],
        content: text,
        replyToId: _replyingTo?['id'],
        imageUrl: imageUrl,
      );

      _messageController.clear();
      setState(() {
        _replyingTo = null;
        _draftImageBytes = null;
        _draftImageExtension = null;
      });
    } catch (e) {
      print('sendMessage error: $e');
      if (mounted) {
        final isRestricted = e.toString().contains('user_restricted');
        if (isRestricted) {
          await RestrictedDialog.show(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send message'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      setState(() {
        _draftImageBytes = bytes;
        _draftImageExtension = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      });
    } catch (e) {
      print('pickPhoto error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load photo'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _removeDraftImage() {
    setState(() {
      _draftImageBytes = null;
      _draftImageExtension = null;
    });
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await _chatService.deleteMessage(messageId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete message'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showMessageOptions(Map<String, dynamic> message) {
    final messageUserId = message['user_id'] as String?;
    final isOwner = messageUserId == _currentUserId;
    final canDelete = isOwner || _isAdmin;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: const Icon(Icons.reply_outlined, color: Colors.white),
              title: const Text('Reply', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyingTo = message);
              },
            ),
            if (!isOwner)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.white),
                title: const Text('Report message', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  ReportSheet.show(context,
                    type: ReportType.churchMessage,
                    targetId: message['id'],
                    targetUserId: messageUserId,
                  );
                },
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete message', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(message['id']);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(String messageId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete message?', style: TextStyle(color: Colors.white)),
        content: const Text('This cannot be undone.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () { Navigator.pop(context); _deleteMessage(messageId); },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _replyPreviewText(Map<String, dynamic> message) {
    final content = message['content'] as String? ?? '';
    if (content.isNotEmpty) {
      return content.length > 60 ? '${content.substring(0, 60)}...' : content;
    }
    if (message['image_url'] != null) return 'Photo';
    return '';
  }

  String _timeAgo(String dateStr) {
    final date = DateTime.parse(dateStr);
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.community['name'] ?? '',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isAdmin && widget.community['is_private'] == true)
            IconButton(
              icon: const Icon(Icons.qr_code, color: Colors.white),
              tooltip: 'Show join QR code',
              onPressed: _showQrSheet,
            ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () async {
                final updated = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => CommunitySettingsScreen(
                      community: widget.community,
                      isCreator: widget.community['created_by'] == _currentUserId,
                    ),
                  ),
                );
                if (updated == true && mounted) Navigator.of(context).pop(true);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 48),
                            SizedBox(height: 16),
                            Text('No messages yet', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text('Say something to get the conversation started', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final messageUserId = message['user_id'] as String?;
                          final isOwner = messageUserId == _currentUserId;
                          final user = message['users'];
                          final displayName = user?['display_name'] ?? user?['username'] ?? 'Unknown';
                          final replyTo = message['reply_to'];

                          return GestureDetector(
                            onLongPress: () => _showMessageOptions(message),
                            child: Column(
                              crossAxisAlignment: isOwner ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                // Name sits above the bubble, not inside it —
                                // the bubble itself stays focused purely on
                                // content (image/text), sender identity is a
                                // separate visual layer above it.
                                if (!isOwner)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                                    child: Text(displayName,
                                        style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: isOwner ? MainAxisAlignment.end : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Flexible(
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 4),
                                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isOwner
                                              ? Colors.white.withOpacity(0.12)
                                              : const Color(0xFF1A1A1A),
                                          borderRadius: BorderRadius.circular(14),
                                          border: isOwner
                                              ? Border.all(color: Colors.white.withOpacity(0.15), width: 1)
                                              : null,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (replyTo != null)
                                              Container(
                                                margin: const EdgeInsets.only(bottom: 6),
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: const Border(left: BorderSide(color: Colors.white24, width: 2)),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    if (replyTo['image_url'] != null) ...[
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: Image.network(
                                                          replyTo['image_url'],
                                                          width: 28,
                                                          height: 28,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) => Container(
                                                            width: 28, height: 28,
                                                            color: Colors.white10,
                                                            child: const Icon(Icons.image_outlined, color: Colors.grey, size: 14),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                    ],
                                                    Flexible(
                                                      child: Text(
                                                        _replyPreviewText(replyTo),
                                                        style: const TextStyle(
                                                          color: Colors.grey,
                                                          fontSize: 11,
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (message['image_url'] != null) ...[
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(10),
                                                child: Image.network(
                                                  message['image_url'],
                                                  fit: BoxFit.cover,
                                                  loadingBuilder: (context, child, progress) {
                                                    if (progress == null) return child;
                                                    return Container(
                                                      height: 160,
                                                      alignment: Alignment.center,
                                                      child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                                    );
                                                  },
                                                  errorBuilder: (context, error, stackTrace) => Container(
                                                    height: 100,
                                                    alignment: Alignment.center,
                                                    child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                            ],
                                            if ((message['content'] as String? ?? '').isNotEmpty)
                                              Text(message['content'],
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    height: 1.4,
                                                  )),
                                            const SizedBox(height: 4),
                                            Text(_timeAgo(message['created_at']),
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 10,
                                                )),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Options button sits OUTSIDE the bubble
                                    // entirely — a clean trailing icon rather
                                    // than crammed inline with the message
                                    // text. Long-press still works as an
                                    // alternative entry point on touch devices.
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                                      child: GestureDetector(
                                        onTap: () => _showMessageOptions(message),
                                        child: const Icon(Icons.more_horiz, color: Colors.white38, size: 18),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          if (_draftImageBytes != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              color: const Color(0xFF1A1A1A),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _draftImageBytes!,
                      height: 100,
                      width: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: _removeDraftImage,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1A1A1A),
              child: Row(
                children: [
                  Container(width: 3, height: 32, color: Colors.white24,
                      margin: const EdgeInsets.only(right: 10)),
                  if (_replyingTo!['image_url'] != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        _replyingTo!['image_url'],
                        width: 32, height: 32, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 32, height: 32, color: Colors.white10,
                          child: const Icon(Icons.image_outlined, color: Colors.grey, size: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Replying to',
                            style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                        Text(
                          _replyPreviewText(_replyingTo!),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _replyingTo = null),
                    child: const Icon(Icons.close, color: Colors.grey, size: 18),
                  ),
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.only(
              left: 16, right: 16, top: 10,
              bottom: 10,
            ),
            color: const Color(0xFF1A1A1A),
            child: Row(
              children: [
                if (_isAdmin) ...[
                  GestureDetector(
                    onTap: _isSending ? null : _pickPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.image_outlined, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.black,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _isSending ? null : _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: _isSending
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Icon(Icons.send, color: Colors.black, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}