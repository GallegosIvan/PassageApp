import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../services/ai_service.dart';
import '../../services/bible_service.dart';
import '../../services/app_cache.dart';
import '../../widgets/upgrade_sheet.dart';
import '../bible/bible_reader_screen.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _aiService = AiService();
  final _bibleService = BibleService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  // ── SPEECH TO TEXT ─────────────────────────────────────────
  // Uses the device's built-in speech recognition (iOS Speech
  // framework / Android SpeechRecognizer) — free, no cloud API,
  // no per-use cost. Tapping the mic starts listening; live
  // partial results are written straight into the message field
  // so the user can see what's being transcribed and edit it
  // before sending, same as if they'd typed it.
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  List<Map<String, dynamic>> _conversations = [];
  String? _currentConversationId;
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic> _tokenUsage = {};
  bool _isLoading = true;
  bool _isTyping = false;
  bool _isStreaming = false;
  String _streamingContent = '';
  bool _showConversations = false;
  String _userTranslationId = 'BSB';

  static const Map<String, String> _bookNameToId = {
    'genesis': 'GEN', 'exodus': 'EXO', 'leviticus': 'LEV',
    'numbers': 'NUM', 'deuteronomy': 'DEU', 'joshua': 'JOS',
    'judges': 'JDG', 'ruth': 'RUT', '1 samuel': '1SA',
    '2 samuel': '2SA', '1 kings': '1KI', '2 kings': '2KI',
    '1 chronicles': '1CH', '2 chronicles': '2CH', 'ezra': 'EZR',
    'nehemiah': 'NEH', 'esther': 'EST', 'job': 'JOB',
    'psalms': 'PSA', 'psalm': 'PSA', 'proverbs': 'PRO',
    'ecclesiastes': 'ECC', 'song of solomon': 'SNG',
    'song of songs': 'SNG', 'isaiah': 'ISA', 'jeremiah': 'JER',
    'lamentations': 'LAM', 'ezekiel': 'EZK', 'daniel': 'DAN',
    'hosea': 'HOS', 'joel': 'JOL', 'amos': 'AMO',
    'obadiah': 'OBA', 'jonah': 'JON', 'micah': 'MIC',
    'nahum': 'NAH', 'habakkuk': 'HAB', 'zephaniah': 'ZEP',
    'haggai': 'HAG', 'zechariah': 'ZEC', 'malachi': 'MAL',
    'matthew': 'MAT', 'mark': 'MRK', 'luke': 'LUK',
    'john': 'JHN', 'acts': 'ACT', 'romans': 'ROM',
    '1 corinthians': '1CO', '2 corinthians': '2CO',
    'galatians': 'GAL', 'ephesians': 'EPH', 'philippians': 'PHP',
    'colossians': 'COL', '1 thessalonians': '1TH',
    '2 thessalonians': '2TH', '1 timothy': '1TI',
    '2 timothy': '2TI', 'titus': 'TIT', 'philemon': 'PHM',
    'hebrews': 'HEB', 'james': 'JAS', '1 peter': '1PE',
    '2 peter': '2PE', '1 john': '1JN', '2 john': '2JN',
    '3 john': '3JN', 'jude': 'JUD', 'revelation': 'REV',
  };

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _initSpeech();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  // ── INIT SPEECH RECOGNITION ────────────────────────────────
  // Checks availability up front so the mic button can be hidden
  // (rather than shown-but-broken) on devices/simulators where
  // speech recognition isn't supported or permission is denied.
  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition isn\'t available on this device'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        // Guard against a late result landing after the user has already
        // hit send — _isListening is set false synchronously in
        // _sendMessage before clearing the field, so this check prevents
        // a stray transcription from repopulating it afterward.
        if (!_isListening) return;
        setState(() {
          _messageController.text = result.recognizedWords;
          _messageController.selection = TextSelection.fromPosition(
            TextPosition(offset: _messageController.text.length),
          );
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> _loadInitialData() async {
    // Show cached conversations instantly if available
    final cachedConvos = AppCache.instance.aiConversations;
    if (cachedConvos != null) {
      setState(() {
        _conversations = cachedConvos;
        _isLoading = false;
      });
      if (cachedConvos.isNotEmpty) {
        _loadConversation(cachedConvos.first['id'] as String);
      }
    } else {
      setState(() => _isLoading = true);
    }

    // Always fetch token usage fresh (rate limits)
    final results = await Future.wait([
      _aiService.getTokenUsage(),
      _bibleService.getUserTranslationId(),
    ]);

    final tokenUsage = results[0] as Map<String, dynamic>;
    final translationId = results[1] as String;
    final isPaid = tokenUsage['paid'] as bool? ?? false;

    final conversations = await _aiService.getConversations(isPaid: isPaid);
    AppCache.instance.setAiConversations(conversations);

    if (mounted) {
      setState(() {
        _conversations = conversations;
        _tokenUsage = tokenUsage;
        _userTranslationId = translationId;
        _isLoading = false;
      });

      if (cachedConvos == null) {
        if (conversations.isNotEmpty) {
          _loadConversation(conversations.first['id'] as String);
        } else {
          _startNewConversation();
        }
      }
    }
  }

  Future<void> _startNewConversation() async {
    final isPaid = _tokenUsage['paid'] as bool? ?? false;

    if (!isPaid && _conversations.length >= 5) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Conversation limit reached',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'Free accounts can save up to 5 conversations. Upgrade to Pro for unlimited conversation history.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final upgraded = await UpgradeSheet.show(context);
                if (upgraded == true && mounted) _loadInitialData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              child: const Text('Upgrade to Pro'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final id = await _aiService.startConversation('New conversation');
      final conversations = await _aiService.getConversations(isPaid: isPaid);
      if (mounted) {
        setState(() {
          _currentConversationId = id;
          _conversations = conversations;
          _messages = [
            {
              'role': 'assistant',
              'content': 'Hi! I\'m your Passage Bible assistant. Ask me anything about the Bible, faith, prayer, or a passage you\'re reading.',
              'created_at': DateTime.now().toIso8601String(),
            }
          ];
          _showConversations = false;
        });
      }
    } catch (e) {
      print('startNewConversation error: $e');
    }
  }

  Future<void> _loadConversation(String conversationId) async {
    setState(() {
      _currentConversationId = conversationId;
      _showConversations = false;
      _isLoading = true;
    });

    final dbMessages = await _aiService.getMessages(conversationId);
    final messages = <Map<String, dynamic>>[];

    if (dbMessages.isEmpty) {
      messages.add({
        'role': 'assistant',
        'content': 'Hi! I\'m your Passage Bible assistant. Ask me anything about the Bible, faith, prayer, or a passage you\'re reading.',
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      messages.addAll(dbMessages.map((m) => {
        'role': m['role'] as String,
        'content': m['content'] as String,
        'created_at': m['created_at'] as String?,
      }));
    }

    if (mounted) {
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isTyping || _isStreaming) return;

    // Stop listening and wait for it to fully stop BEFORE clearing the
    // field. If a late speech result lands after .clear() runs, it would
    // repopulate the field with stale transcribed text — stopping first
    // and awaiting it prevents that race.
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    }

    if (_currentConversationId == null) {
      await _startNewConversation();
    }

    final userMessage = {
      'role': 'user',
      'content': text,
      'created_at': DateTime.now().toIso8601String(),
    };

    setState(() {
      _messages.add(userMessage);
      _isTyping = true;
      _streamingContent = '';
    });
    _messageController.clear();
    _scrollToBottom();

    try {
      final messagesToSend = _messages
          .where((m) => !(m['role'] == 'assistant' &&
              (m['content'] as String).startsWith('Hi! I\'m your Passage')))
          .map((m) => {'role': m['role'] as String, 'content': m['content'] as String})
          .toList();

      final response = await _aiService.sendMessage(
        messages: messagesToSend,
        conversationId: _currentConversationId!,
        translationId: _userTranslationId,
      );

      final assistantMessage = response['message'] as String;
      final tokensRemaining = response['tokens_remaining'] as int?;
      final createdAt = response['created_at'] as String? ?? DateTime.now().toIso8601String();

      if (mounted) {
        setState(() {
          _isTyping = false;
          _isStreaming = true;
          _streamingContent = '';
        });

        await _animateText(assistantMessage);

        if (mounted) {
          setState(() {
            _isStreaming = false;
            _streamingContent = '';
            _messages.add({
              'role': 'assistant',
              'content': assistantMessage,
              'created_at': createdAt,
            });
            if (tokensRemaining != null) {
              _tokenUsage['tokens_remaining'] = tokensRemaining;
            }
          });
          _scrollToBottom();
          if (messagesToSend.length == 1) {
            // Update conversation title to first user message
            final title = text.length > 40 ? '${text.substring(0, 40)}...' : text;
            await _aiService.updateConversationTitle(_currentConversationId!, title);
            _refreshConversations();
          }
        }
      }
    } on AiLimitException catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeLast();
          _isTyping = false;
          _isStreaming = false;
          _streamingContent = '';
        });
        _showLimitDialog(e);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeLast();
          _isTyping = false;
          _isStreaming = false;
          _streamingContent = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _animateText(String fullText) async {
    const targetDuration = 2000;
    const minDelay = 4;
    const maxDelay = 20;
    const chunkSize = 3;

    final totalChunks = (fullText.length / chunkSize).ceil();
    final delayPerChunk = (targetDuration / totalChunks)
        .clamp(minDelay.toDouble(), maxDelay.toDouble())
        .toInt();

    for (int i = 0; i < fullText.length; i += chunkSize) {
      if (!mounted || !_isStreaming) break;
      setState(() {
        _streamingContent = fullText.substring(
          0,
          (i + chunkSize) > fullText.length ? fullText.length : i + chunkSize,
        );
      });
      _scrollToBottom();
      await Future.delayed(Duration(milliseconds: delayPerChunk));
    }

    if (mounted) setState(() => _streamingContent = fullText);
  }

  Future<void> _refreshConversations() async {
    final isPaid = _tokenUsage['paid'] as bool? ?? false;
    final conversations = await _aiService.getConversations(isPaid: isPaid);
    if (mounted) setState(() => _conversations = conversations);
  }

  void _showLimitDialog(AiLimitException e) {
    if (e.isPaid) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Daily limit reached',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'You\'ve used all 50,000 tokens for today. Your limit resets at midnight — come back tomorrow to continue studying.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      UpgradeSheet.show(context).then((upgraded) {
        if (upgraded == true && mounted) _loadInitialData();
      });
    }
  }

  Future<void> _deleteConversation(String conversationId) async {
    try {
      await _aiService.deleteConversation(conversationId);
      final isPaid = _tokenUsage['paid'] as bool? ?? false;
      final conversations = await _aiService.getConversations(isPaid: isPaid);
      if (mounted) {
        setState(() => _conversations = conversations);
        if (_currentConversationId == conversationId) {
          if (conversations.isNotEmpty) {
            _loadConversation(conversations.first['id'] as String);
          } else {
            _startNewConversation();
          }
        }
      }
    } catch (e) {
      print('deleteConversation error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTimestamp(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.parse(dateStr).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $period';
    if (diff.inDays == 0) return timeStr;
    if (diff.inDays == 1) return 'Yesterday $timeStr';
    return '${date.month}/${date.day} $timeStr';
  }

  String _formatConversationTime(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.parse(dateStr);
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _navigateToBibleReference(String reference) async {
    try {
      final translationId = await _bibleService.getUserTranslationId();
      final regex = RegExp(
        r'^((?:\d\s)?[A-Za-z]+(?:\s[A-Za-z]+)*)\s(\d+)(?::(\d+))?',
        caseSensitive: false,
      );
      final match = regex.firstMatch(reference.trim());
      if (match == null) { _showReferenceError(reference); return; }

      final bookName = match.group(1)!.trim().toLowerCase();
      final chapter = int.tryParse(match.group(2) ?? '1') ?? 1;
      final bookId = _bookNameToId[bookName];
      if (bookId == null) { _showReferenceError(reference); return; }

      final books = await _bibleService.getBooks(translationId);
      final book = books.firstWhere(
        (b) => (b['id'] as String).toUpperCase() == bookId,
        orElse: () => <String, dynamic>{},
      );
      if (book.isEmpty) { _showReferenceError(reference); return; }
      if (!mounted) return;

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BibleReaderScreen(
          translationId: translationId,
          bookId: book['id'] as String,
          bookName: book['name'] as String,
          chapterNumber: chapter,
          totalChapters: book['numberOfChapters'] as int,
        ),
      ));
    } catch (e) {
      _showReferenceError(reference);
    }
  }

  void _showReferenceError(String reference) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Could not find "$reference" in the Bible reader'),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  MarkdownStyleSheet get _markdownStyle => MarkdownStyleSheet(
    p: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
    h2: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, height: 1.8),
    strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    listBullet: const TextStyle(color: Colors.white, fontSize: 14),
    blockquote: const TextStyle(color: Colors.white70, fontSize: 14, fontStyle: FontStyle.italic),
  );

  @override
  Widget build(BuildContext context) {
    final isPaid = _tokenUsage['paid'] as bool? ?? false;
    final dailyLimit = isPaid ? 50000 : (_tokenUsage['daily_limit'] as int? ?? 2000);
    final tokensRemaining = (_tokenUsage['tokens_remaining'] as int? ?? dailyLimit).clamp(0, dailyLimit);
    final tokensUsed = (dailyLimit - tokensRemaining).clamp(0, dailyLimit);
    final usagePercent = (tokensUsed / dailyLimit).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Bible AI',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            onPressed: () => setState(() => _showConversations = !_showConversations),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _startNewConversation,
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(children: [
              // ── TOKEN USAGE BAR ───────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF111111),
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                   Flexible(
                    child: Text(
                     '$tokensRemaining / ${isPaid ? '50,000' : '2,000'} tokens remaining today',
                     style: const TextStyle(color: Colors.grey, fontSize: 12),
                     overflow: TextOverflow.ellipsis,
                    ),
                   ),
                   if (!isPaid)
                    GestureDetector(
                        onTap: () async {
                          final upgraded = await UpgradeSheet.show(context);
                          if (upgraded == true && mounted) await _loadInitialData();
                        },
                        child: const Text('Upgrade for more tokens',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (1.0 - usagePercent).clamp(0.0, 1.0),
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isPaid
                            ? (tokensRemaining < 10000 ? Colors.red : Colors.white)
                            : (usagePercent > 0.8 ? Colors.red : Colors.white),
                      ),
                      minHeight: 4,
                    ),
                  ),
                ]),
              ),

              // ── CONVERSATION HISTORY PANEL ────────────
              if (_showConversations)
                Container(
                  height: 200,
                  color: const Color(0xFF111111),
                  child: Column(children: [
                    // Counter row for free users
                    if (!isPaid)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Row(children: [
                          Text('${_conversations.length}/5 conversations',
                              style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () async {
                              final upgraded = await UpgradeSheet.show(context);
                              if (upgraded == true && mounted) _loadInitialData();
                            },
                            child: const Text('Unlimited with Pro',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    Expanded(
                      child: _conversations.isEmpty
                          ? const Center(
                              child: Text('No conversations yet',
                                  style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: _conversations.length,
                              itemBuilder: (context, index) {
                                final conv = _conversations[index];
                                final isSelected = conv['id'] == _currentConversationId;
                                return ListTile(
                                  dense: true,
                                  selected: isSelected,
                                  selectedTileColor: Colors.white.withOpacity(0.05),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  title: Text(
                                    conv['title'] as String? ?? 'Conversation',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.grey,
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    _formatConversationTime(conv['created_at'] as String?),
                                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 16),
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        backgroundColor: const Color(0xFF1A1A1A),
                                        title: const Text('Delete conversation?',
                                            style: TextStyle(color: Colors.white)),
                                        content: const Text('This cannot be undone.',
                                            style: TextStyle(color: Colors.grey)),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _deleteConversation(conv['id'] as String);
                                            },
                                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  onTap: () => _loadConversation(conv['id'] as String),
                                );
                              },
                            ),
                    ),
                  ]),
                ),

              // ── MESSAGES ──────────────────────────────
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _messages.length + (_isTyping ? 1 : 0) + (_isStreaming ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isTyping && index == _messages.length) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            _TypingDot(delay: 0),
                            SizedBox(width: 4),
                            _TypingDot(delay: 200),
                            SizedBox(width: 4),
                            _TypingDot(delay: 400),
                          ]),
                        ),
                      );
                    }

                    if (_isStreaming && index == _messages.length) {
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(18),
                                topRight: Radius.circular(18),
                                bottomLeft: Radius.circular(4),
                                bottomRight: Radius.circular(18),
                              ),
                            ),
                            child: MarkdownBody(data: _streamingContent, styleSheet: _markdownStyle),
                          ),
                        ),
                      ]);
                    }

                    final message = _messages[index];
                    final isUser = message['role'] == 'user';
                    final timestamp = _formatTimestamp(message['created_at'] as String?);

                    return Column(
                      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                            decoration: BoxDecoration(
                              color: isUser ? Colors.white : const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(isUser ? 18 : 4),
                                bottomRight: Radius.circular(isUser ? 4 : 18),
                              ),
                            ),
                            child: isUser
                                ? Text(message['content'] as String? ?? '',
                                    style: const TextStyle(color: Colors.black, fontSize: 14, height: 1.5))
                                : MarkdownBody(
                                    data: message['content'] as String? ?? '',
                                    styleSheet: _markdownStyle,
                                    onTapLink: (text, href, title) {
                                      if (href != null && href.startsWith('bible://')) {
                                        final reference = Uri.decodeComponent(
                                            href.replaceFirst('bible://', ''));
                                        _navigateToBibleReference(reference);
                                      }
                                    },
                                  ),
                          ),
                        ),
                        if (timestamp.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
                            child: Text(timestamp,
                                style: const TextStyle(color: Colors.white30, fontSize: 10)),
                          ),
                      ],
                    );
                  },
                ),
              ),

              // ── LISTENING INDICATOR ───────────────────
              if (_isListening)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: const Color(0xFF1A1A1A),
                  child: Row(children: [
                    const Icon(Icons.mic, color: Colors.redAccent, size: 14),
                    const SizedBox(width: 8),
                    const Text('Listening...',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),

              // ── INPUT BAR ─────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: _isListening ? 'Listening...' : 'Ask about a verse or topic...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Mic button — only shown if speech recognition is
                  // available on this device. Tapping toggles listening;
                  // partial results stream live into the text field above.
                  if (_speechAvailable)
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: _isListening ? Colors.redAccent : Colors.white12,
                      child: IconButton(
                        icon: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          size: 18,
                          color: _isListening ? Colors.white : Colors.white70,
                        ),
                        onPressed: _toggleListening,
                      ),
                    ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _messageController.text.trim().isEmpty
                        ? Colors.white12
                        : Colors.white,
                    child: IconButton(
                      icon: Icon(Icons.send_rounded, size: 18,
                          color: _messageController.text.trim().isEmpty ? Colors.white38 : Colors.black),
                      onPressed: _messageController.text.trim().isEmpty ? null : _sendMessage,
                    ),
                  ),
                ]),
              ),
            ]),
    );
  }
}

// ── TYPING INDICATOR DOT ──────────────────────────────────────
class _TypingDot extends StatefulWidget {
  final int delay;
  const _TypingDot({required this.delay});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _animation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 6, height: 6,
        decoration: const BoxDecoration(color: Colors.white54, shape: BoxShape.circle),
      ),
    );
  }
}