import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class PartnerChatScreen extends StatefulWidget {
  final Dio dio;
  final io.Socket? socket;
  final String shipmentId;
  final String trackingId;
  final String customerName;
  final String shipmentStatus;

  const PartnerChatScreen({
    super.key,
    required this.dio,
    required this.socket,
    required this.shipmentId,
    required this.trackingId,
    required this.customerName,
    required this.shipmentStatus,
  });

  @override
  State<PartnerChatScreen> createState() => _PartnerChatScreenState();
}

class _PartnerChatScreenState extends State<PartnerChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;

  static const List<String> _quickReplies = [
    "I'm on my way to pickup",
    'Reached pickup location',
    'Out for delivery, arriving soon',
    'At your doorstep — please share OTP',
  ];

  late final void Function(dynamic) _onNewMessage;
  late final void Function(dynamic) _onMessagesRead;

  @override
  void initState() {
    super.initState();
    _onNewMessage = (dynamic data) {
      if (!mounted || data is! Map) return;
      final msg = Map<String, dynamic>.from(data);
      if (msg['shipmentId']?.toString() != widget.shipmentId) return;

      final incomingId = msg['_id']?.toString();
      final exists = incomingId != null &&
          _messages.any((m) => m['_id']?.toString() == incomingId);
      if (!exists) {
        setState(() {
          _messages.add(msg);
        });
        _scrollToBottom();
      }

      if (msg['senderRole'] != 'agent') {
        widget.socket?.emit('chat:mark_read', {'shipmentId': widget.shipmentId});
      }
    };

    _onMessagesRead = (dynamic data) {
      if (!mounted || data is! Map) return;
      if (data['shipmentId']?.toString() != widget.shipmentId) return;
      if (data['readerRole'] == 'customer') {
        setState(() {
          for (final m in _messages) {
            if (m['senderRole'] == 'agent') {
              m['isRead'] = true;
            }
          }
        });
      }
    };

    _initChat();
  }

  Future<void> _initChat() async {
    try {
      final res = await widget.dio.get('/chat/${widget.shipmentId}/messages');
      final list = List<Map<String, dynamic>>.from(
        (res.data['messages'] ?? []).map((e) => Map<String, dynamic>.from(e)),
      );
      if (mounted) {
        setState(() {
          _messages
            ..clear()
            ..addAll(list);
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }

    final sock = widget.socket;
    if (sock != null) {
      sock.emit('shipment:join', {'shipmentId': widget.shipmentId});
      sock.emit('chat:mark_read', {'shipmentId': widget.shipmentId});
      sock.on('chat:new_message', _onNewMessage);
      sock.on('chat:messages_read', _onMessagesRead);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage([String? presetText]) {
    final text = (presetText ?? _msgCtrl.text).trim();
    if (text.isEmpty || _sending) return;

    final sock = widget.socket;
    if (sock == null || !sock.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Go ONLINE first to send live chat messages.'),
        ),
      );
      return;
    }

    if (presetText == null) {
      _msgCtrl.clear();
    }

    setState(() => _sending = true);
    sock.emitWithAck(
      'chat:send_message',
      {
        'shipmentId': widget.shipmentId,
        'text': text,
        'messageType': 'text',
      },
      ack: (dynamic ackData) {
        if (!mounted) return;
        setState(() => _sending = false);
        if (ackData is Map && ackData['ok'] == true && ackData['message'] is Map) {
          final saved = Map<String, dynamic>.from(ackData['message']);
          final savedId = saved['_id']?.toString();
          final exists = savedId != null &&
              _messages.any((m) => m['_id']?.toString() == savedId);
          if (!exists) {
            setState(() => _messages.add(saved));
            _scrollToBottom();
          }
        }
      },
    );

    // Fallback reset in case ack isn't returned promptly
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _sending) {
        setState(() => _sending = false);
      }
    });
  }

  String _formatTime(dynamic rawDate) {
    if (rawDate == null) return '';
    final dt = DateTime.tryParse(rawDate.toString())?.toLocal();
    if (dt == null) return '';
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$min $period';
  }

  @override
  void dispose() {
    widget.socket?.off('chat:new_message', _onNewMessage);
    widget.socket?.off('chat:messages_read', _onMessagesRead);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.socket?.connected == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: const Color(0xFFF9EDE8),
              child: Text(
                widget.customerName.isNotEmpty
                    ? widget.customerName[0].toUpperCase()
                    : 'C',
                style: const TextStyle(
                  color: Color(0xFFF99A4F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customerName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: connected
                              ? const Color(0xFF42B883)
                              : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${widget.trackingId} • ${widget.shipmentStatus}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!connected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              color: const Color(0xFFFFF4E8),
              child: const Text(
                'Live socket offline — toggle ONLINE on dashboard to send messages.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB86621),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 36,
                                  color: Color(0xFFF99A4F),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No messages yet',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Send a quick update or coordinate pickup/drop-off with the customer.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final m = _messages[index];
                          final isPartner = m['senderRole'] == 'agent';
                          final isRead = m['isRead'] == true;
                          return Align(
                            alignment: isPartner
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.76,
                              ),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: isPartner
                                    ? const Color(0xFFF99A4F)
                                    : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft:
                                      Radius.circular(isPartner ? 18 : 4),
                                  bottomRight:
                                      Radius.circular(isPartner ? 4 : 18),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: isPartner
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m['text']?.toString() ?? '',
                                    style: TextStyle(
                                      color: isPartner
                                          ? Colors.white
                                          : const Color(0xFF1A1D24),
                                      fontSize: 14,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatTime(m['createdAt']),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isPartner
                                              ? Colors.white70
                                              : Colors.grey,
                                        ),
                                      ),
                                      if (isPartner) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          isRead
                                              ? Icons.done_all_rounded
                                              : Icons.done_rounded,
                                          size: 13,
                                          color: isRead
                                              ? Colors.white
                                              : Colors.white70,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _quickReplies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final reply = _quickReplies[index];
                return ActionChip(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFE5E5E5)),
                  label: Text(
                    reply,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () => _sendMessage(reply),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Message customer...',
                        filled: true,
                        fillColor: const Color(0xFFF3F3F3),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _sending ? null : () => _sendMessage(),
                    child: const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFFF99A4F),
                      child: Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
