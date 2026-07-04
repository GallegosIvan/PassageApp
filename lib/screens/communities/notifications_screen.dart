import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final result = await _client
          .from('notifications')
          .select()
          .eq('user_id', _client.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) setState(() {
        _notifications = List<Map<String, dynamic>>.from(result);
        _isLoading = false;
      });
      // Mark all as read
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', _client.auth.currentUser!.id)
          .eq('is_read', false);
    } catch (e) {
      print('loadNotifications error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearAll() async {
    try {
      await _client
          .from('notifications')
          .delete()
          .eq('user_id', _client.auth.currentUser!.id);
      if (mounted) setState(() => _notifications = []);
    } catch (e) {
      print('clearNotifications error: $e');
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'reply': return Icons.reply_outlined;
      case 'announcement': return Icons.campaign_outlined;
      case 'church_message': return Icons.chat_bubble_outline;
      case 'streak_reminder': return Icons.local_fire_department_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  String _timeAgo(String createdAt) {
    final date = DateTime.parse(createdAt).toLocal();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text('Notifications',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text('Clear all',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _notifications.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none, color: Colors.grey, size: 48),
                      SizedBox(height: 16),
                      Text('No notifications yet',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Replies, announcements, and reminders\nwill appear here',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                          textAlign: TextAlign.center),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  color: Colors.white,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notif = _notifications[index];
                      final isUnread = notif['is_read'] == false;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: isUnread
                              ? const Color(0xFF1A1A2E)
                              : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: isUnread
                              ? Border.all(color: Colors.white24)
                              : null,
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              _iconForType(notif['type'] as String? ?? ''),
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            notif['title'] as String? ?? '',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(
                                notif['body'] as String? ?? '',
                                style: const TextStyle(color: Colors.grey, fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _timeAgo(notif['created_at'] as String),
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
