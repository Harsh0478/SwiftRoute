import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../constants/api_constants.dart';
import '../network/dio_client.dart';

final socketServiceProvider = Provider<SocketService>((ref) => SocketService(ref.watch(secureStorageProvider)));

class SocketService {
  final FlutterSecureStorage _storage;
  io.Socket? _socket;

  SocketService(this._storage);
  io.Socket? get socket => _socket;

  Future<void> connect() async {
    if (_socket != null && _socket!.connected) return;
    final token = await _storage.read(key: 'access_token');
    if (token == null) return;

    _socket = io.io(
      ApiConstants.socketUrl,
      io.OptionBuilder().setTransports(['websocket']).setAuth({'token': token}).enableReconnection().build(),
    )..connect();
  }

  void joinShipmentRoom(String shipmentId) => _socket?.emit('shipment:join', {'shipmentId': shipmentId});

  void sendChatMessage({required String shipmentId, required String text, String imageUrl = ''}) {
    _socket?.emit('chat:send_message', {
      'shipmentId': shipmentId,
      'text': text,
      'imageUrl': imageUrl,
      'messageType': imageUrl.isNotEmpty ? 'image' : 'text',
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}
