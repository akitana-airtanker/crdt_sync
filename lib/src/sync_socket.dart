import 'dart:async';
import 'dart:convert';

import 'package:crdt/crdt.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef Handshake = ({
  String nodeId,
  Hlc lastModified,
  Map<String, dynamic>? data,
});

class SyncSocket {
  final IO.Socket socket;
  final void Function(int? code, String? reason) onDisconnect;
  final void Function(CrdtChangeset changeset) onChangeset;
  final bool verbose;

  late final StreamSubscription _subscription;

  final _handshakeCompleter = Completer<Handshake>();

  /// Begin managing the socket:
  /// 1. Perform handshake.
  /// 2. Monitor for incoming changesets.
  /// 3. Send local changesets on demand.
  /// 4. Disconnect when done.
  SyncSocket(
    this.socket,
    String localNodeId, {
    required this.onDisconnect,
    required this.onChangeset,
    required this.verbose,
  }) {
    socket.on('message', (data) async {
      final message = jsonDecode(data);
      _log('⬇️ $message');
      if (!_handshakeCompleter.isCompleted) {
        // The first message is a handshake
        final lastModified = message['last_modified'];
        if (lastModified == null) {
          _log('Invalid argument(s): last_modified is null');
          return;
        }
        _handshakeCompleter.complete((
          nodeId: message['node_id'] as String,
          // Modified timestamps always use the local node id
          lastModified: Hlc.parse(lastModified as String)
              .apply(nodeId: localNodeId),
          data: message['data'] as Map<String, dynamic>?
        ));
      } else if (message.containsKey('chat')) {
        // Handle chat message
        final changeset = parseCrdtChangeset(message);
        _log('Processing chat message: $changeset'); // 受信したチャットメッセージのログを追加
        onChangeset(changeset);
      } else {
        _log('Unknown message format: $message');
      }
    });

    // Manually create a StreamSubscription to handle socket disconnection
    _subscription = Stream.periodic(Duration(seconds: 1)).listen((_) {
      if (socket.disconnected) {
        close();
      }
    });
  }

  void _send(Map<String, Object?> data) {
    if (data.isEmpty) return;
    _log('⬆️ $data');
    try {
      socket.emit('message', jsonEncode(data));
    } catch (e, st) {
      _log('$e\n$st');
      close(4000, '$e');
    }
  }

  /// Monitor handshake completion. Useful for establishing connections.
  Future<Handshake> receiveHandshake() => _handshakeCompleter.future;

  /// Send local handshake
  void sendHandshake(String nodeId, Hlc lastModified, Object? data) => _send({
        'node_id': nodeId,
        'last_modified': lastModified,
        'data': data,
      });

  /// Send local changeset
  void sendChangeset(CrdtChangeset changeset) =>
      _send(changeset..removeWhere((key, value) => value.isEmpty));

  /// Close this connection
  Future<void> close([int? code, String? reason]) async {
    await Future.wait<void>([
      _subscription.cancel(),
      Future(() => socket.close()), // 非同期操作に置き換え
    ]);

    onDisconnect(code, reason); // codeを使用
  }

  void _log(String msg) {
    if (verbose) print(msg);
  }
}