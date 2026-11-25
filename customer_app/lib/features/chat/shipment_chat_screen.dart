import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/services/socket_service.dart';
import '../../core/theme/app_theme.dart';

class ShipmentChatScreen extends ConsumerStatefulWidget {
  final String shipmentId;
  const ShipmentChatScreen({super.key, required this.shipmentId});

  @override
  ConsumerState<ShipmentChatScreen> createState() => _ShipmentChatScreenState();
}

class _ShipmentChatScreenState extends ConsumerState<ShipmentChatScreen> {
  final _msgCtrl = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final res = await ref.read(dioProvider).get('/chat/${widget.shipmentId}/messages');
    if (mounted) setState(() => _messages.addAll(List<Map<String, dynamic>>.from(res.data['messages'] ?? [])));

    final socketSvc = ref.read(socketServiceProvider);
    await socketSvc.connect();
    socketSvc.joinShipmentRoom(widget.shipmentId);
    socketSvc.socket?.on('chat:new_message', (msg) {
      if (mounted) setState(() => _messages.add(Map<String, dynamic>.from(msg)));
    });
  }

  void _send() {
    if (_msgCtrl.text.trim().isEmpty) return;
    ref.read(socketServiceProvider).sendChatMessage(shipmentId: widget.shipmentId, text: _msgCtrl.text.trim());
    _msgCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Courier Chat'), backgroundColor: AppColors.white, elevation: 0),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                final isCustomer = m['senderRole'] == 'customer';
                return Align(
                  alignment: isCustomer ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: isCustomer ? AppColors.primaryOrange : AppColors.white, borderRadius: BorderRadius.circular(18)),
                    child: Text(m['text'] ?? '', style: TextStyle(color: isCustomer ? AppColors.white : AppColors.primaryText)),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _msgCtrl, decoration: const InputDecoration(hintText: 'Type message...'))),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _send,
                  child: const CircleAvatar(radius: 26, backgroundColor: AppColors.primaryOrange, child: Icon(Icons.send_rounded, color: AppColors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
