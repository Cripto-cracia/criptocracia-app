import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ndk/ndk.dart';

class NostrService {
  static NostrService? _instance;
  static NostrService get instance {
    _instance ??= NostrService._internal();
    return _instance!;
  }

  bool _connected = false;
  bool _connecting = false;
  StreamSubscription? _eventSubscription;
  late Ndk _ndk;

  NostrService._internal();

  // Keep the public constructor for backwards compatibility but make it return the singleton
  factory NostrService() => instance;

  Future<void> connect(String relayUrl) async {
    if (_connected) {
      debugPrint('🔗 Already connected to relay');
      return;
    }

    if (_connecting) {
      debugPrint('🔗 Connection already in progress, waiting...');
      // Wait for connection to complete
      int attempts = 0;
      while (_connecting && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      return;
    }

    try {
      _connecting = true;
      debugPrint('🔗 Attempting to connect to Nostr relay: $relayUrl');

      // Initialize NDK with the relay
      _ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: [relayUrl],
        ),
      );

      _connected = true;
      debugPrint('✅ Successfully connected to Nostr relay: $relayUrl');
    } catch (e) {
      _connected = false;
      debugPrint('❌ Failed to connect to Nostr relay: $e');
      throw Exception('Failed to connect to Nostr relay: $e');
    } finally {
      _connecting = false;
    }
  }

  Future<void> disconnect() async {
    if (!_connected) {
      debugPrint('🔗 Already disconnected from relays');
      return;
    }

    try {
      // Cancel any active subscription
      await _eventSubscription?.cancel();
      _eventSubscription = null;

      // Close all relay connections
      if (_connected) {
        await _ndk.destroy();
      }

      _connected = false;
      _connecting = false;
      debugPrint('Disconnected from Nostr relays');
    } catch (e) {
      debugPrint('Error disconnecting from Nostr relays: $e');
      // Force disconnection even if there was an error
      _connected = false;
      _connecting = false;
    }
  }

  String get publicKey => 'mock_public_key'; // TODO: Generate actual key pair

  bool get isConnected => _connected;

  void loginPrivateKey({
    required String pubKeyHex,
    required String privKeyHex,
  }) {
    try {
      debugPrint('🔐 Attempting to login with:');
      debugPrint('   Public key: $pubKeyHex (${pubKeyHex.length} chars)');
      debugPrint('   Private key: $privKeyHex (${privKeyHex.length} chars)');
      
      if (_ndk.accounts.hasAccount(pubKeyHex)) {
        debugPrint('🔄 Switching to existing account');
        _ndk.accounts.switchAccount(pubkey: pubKeyHex);
      } else {
        debugPrint('🆕 Creating new account');
        _ndk.accounts.loginPrivateKey(pubkey: pubKeyHex, privkey: privKeyHex);
      }
      debugPrint('✅ Login successful');
    } catch (e) {
      debugPrint('❌ Login failed: $e');
      rethrow;
    }
  }

  Future<void> sendBlindedNonce(
    String ecPublicKey,
    Uint8List blindedNonce,
  ) async {
    if (!_connected) throw Exception('Not connected to relay');
    debugPrint('Sending blinded nonce to EC: ${base64.encode(blindedNonce)}');
  }

  Future<void> sendBlindSignatureRequest({
    required String ecPubKey,
    required String electionId,
    required Uint8List blindedNonce,
    required String voterPrivKeyHex,
    required String voterPubKeyHex,
  }) async {
    // Ensure we're connected, but don't create a new connection if already connected
    if (!_connected) {
      debugPrint('🔗 Not connected, will connect first...');
      throw Exception('Not connected to relay. Please connect first.');
    }

    try {
      debugPrint('🔐 Logging in with voter keys...');
      loginPrivateKey(pubKeyHex: voterPubKeyHex, privKeyHex: voterPrivKeyHex);

      final payload = jsonEncode({
        'id': electionId,
        'kind': 1,
        'payload': base64.encode(blindedNonce),
      });

      debugPrint('📦 Creating rumor with payload...');
      final rumor = await _ndk.giftWrap.createRumor(
        content: payload,
        kind: 1,
        tags: [],
      );

      debugPrint('🎁 Creating gift wrap...');
      final giftWrap = await _ndk.giftWrap.toGiftWrap(
        rumor: rumor,
        recipientPubkey: ecPubKey,
      );

      debugPrint('📡 Broadcasting event...');
      debugPrint('🔍 Gift wrap event details:');
      debugPrint('   ID: ${giftWrap.id}');
      debugPrint('   Kind: ${giftWrap.kind}');
      debugPrint('   PubKey: ${giftWrap.pubKey}');
      debugPrint('   Created: ${giftWrap.createdAt}');
      debugPrint('   Signature: ${giftWrap.sig}');
      debugPrint('   Signature length: ${giftWrap.sig.length}');
      
      // Validate signature format before broadcasting
      if (giftWrap.sig.length != 128) {
        debugPrint('⚠️ Warning: Signature length is ${giftWrap.sig.length}, expected 128');
      }
      
      _ndk.broadcast.broadcast(nostrEvent: giftWrap);

      // Add a small delay to allow the broadcast to complete
      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint('✅ Sent wrapped event: ${giftWrap.id}');
    } catch (e) {
      debugPrint('❌ Error sending blind signature request: $e');
      rethrow;
    }
  }

  /// Send blind signature request using the existing connection from the provider
  Future<void> sendBlindSignatureRequestSafe({
    required String ecPubKey,
    required String electionId,
    required Uint8List blindedNonce,
    required String voterPrivKeyHex,
    required String voterPubKeyHex,
  }) async {
    try {
      await sendBlindSignatureRequest(
        ecPubKey: ecPubKey,
        electionId: electionId,
        blindedNonce: blindedNonce,
        voterPrivKeyHex: voterPrivKeyHex,
        voterPubKeyHex: voterPubKeyHex,
      );
    } catch (e) {
      debugPrint('❌ Blind signature request failed: $e');
      // Don't rethrow to prevent UI crashes
    }
  }

  Future<void> castVote(
    String electionId,
    int candidateId,
    Uint8List signature,
  ) async {
    if (!_connected) throw Exception('Not connected to relay');
    debugPrint(
      'Casting vote for candidate $candidateId in election $electionId',
    );
  }

  Stream<NostrEvent> subscribeToElections() {
    if (!_connected) {
      throw Exception('Not connected to relay');
    }

    // Calculate DateTime for 24 hours ago
    final since = DateTime.now().subtract(const Duration(hours: 24));
    debugPrint('📅 Looking for kind 35000 events since: $since');

    // Create request filter for kind 35000 events from last 24 hours
    final filter = Filter(
      kinds: const [35000],
      since: since.millisecondsSinceEpoch ~/ 1000,
    );

    debugPrint('📡 Starting subscription for kind 35000 events...');

    // Start subscription using NDK
    final response = _ndk.requests.subscription(filters: [filter]);

    debugPrint('🎯 Subscription started, waiting for events...');

    // Convert NDK events to our NostrEvent format
    return response.stream
        .map((ndkEvent) {
          debugPrint(
            '📥 Received event: kind=${ndkEvent.kind}, id=${ndkEvent.id}',
          );
          return ndkEvent;
        })
        .where((ndkEvent) {
          debugPrint(
            '🔍 Filtering event: kind=${ndkEvent.kind}, hasContent=${ndkEvent.content.isNotEmpty}',
          );
          return ndkEvent.id.isNotEmpty &&
              ndkEvent.content.isNotEmpty &&
              ndkEvent.tags.isNotEmpty;
        })
        .map((ndkEvent) {
          debugPrint('✅ Processing valid event: ${ndkEvent.id}');
          return NostrEvent(
            id: ndkEvent.id,
            pubkey: ndkEvent.pubKey,
            createdAt: ndkEvent.createdAt,
            kind: ndkEvent.kind,
            tags: ndkEvent.tags,
            content: ndkEvent.content,
            sig: ndkEvent.sig,
          );
        })
        .handleError((error) {
          debugPrint('🚨 Stream error: $error');
        })
        .asBroadcastStream(); // Make it a broadcast stream to allow multiple listeners
  }

  Stream<NostrEvent> subscribeToResults(String electionId) {
    // TODO: Implement actual Nostr results subscription
    return Stream.periodic(const Duration(seconds: 5), (count) {
      return NostrEvent(
        id: "mock_result_$count",
        pubkey: "mock_pubkey",
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 1,
        tags: [],
        content: jsonEncode({
          'type': 'election_results',
          'election_id': electionId,
          'results': {'1': 10 + count * 2, '2': 8 + count * 3},
        }),
        sig: "mock_signature",
      );
    });
  }

  Stream<NostrEvent> subscribeToBlindSignatures() {
    return Stream.fromIterable([]);
  }

  Future<Uint8List?> waitForBlindSignature() async {
    await Future.delayed(const Duration(seconds: 2));
    return Uint8List.fromList([1, 2, 3, 4]); // Mock signature
  }
}

// Nostr event class (keeping our own for consistency)
class NostrEvent {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });
}
