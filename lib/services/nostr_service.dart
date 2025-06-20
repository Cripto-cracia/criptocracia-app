import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dart_nostr/dart_nostr.dart';
import 'package:nip59/nip59.dart';

class NostrService {
  static NostrService? _instance;
  static NostrService get instance {
    _instance ??= NostrService._internal();
    return _instance!;
  }

  bool _connected = false;
  bool _connecting = false;
  StreamSubscription? _eventSubscription;
  late Nostr _nostr;
  NostrKeyPairs? _currentKeyPair;

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

      // Initialize dart_nostr with the relay
      _nostr = Nostr.instance;
      await _nostr.services.relays.init(
        relaysUrl: [relayUrl],
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

      // Close all relay connections - dart_nostr handles this automatically

      _connected = false;
      _connecting = false;
      _currentKeyPair = null;
      debugPrint('Disconnected from Nostr relays');
    } catch (e) {
      debugPrint('Error disconnecting from Nostr relays: $e');
      // Force disconnection even if there was an error
      _connected = false;
      _connecting = false;
      _currentKeyPair = null;
    }
  }

  bool get isConnected => _connected;

  void loginPrivateKey({
    required String pubKeyHex,
    required String privKeyHex,
  }) {
    try {
      debugPrint('🔐 Attempting to login with:');
      debugPrint('   Public key: $pubKeyHex (${pubKeyHex.length} chars)');
      debugPrint('   Private key: $privKeyHex (${privKeyHex.length} chars)');

      // Generate key pair from private key using dart_nostr
      _currentKeyPair = _nostr.services.keys.generateKeyPairFromExistingPrivateKey(privKeyHex);
      
      // Validate that the generated public key matches the expected one
      if (_currentKeyPair!.public != pubKeyHex) {
        throw Exception('Generated public key does not match expected key');
      }
      
      debugPrint('✅ Login successful');
    } catch (e) {
      debugPrint('❌ Login failed: $e');
      _currentKeyPair = null;
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

      if (_currentKeyPair == null) {
        throw Exception('No current key pair available');
      }

      final payload = jsonEncode({
        'id': electionId,
        'kind': 1,
        'payload': base64.encode(blindedNonce),
      });

      debugPrint('📦 Creating NIP-59 gift wrap...');
      
      // Create NIP-59 gift wrap using the nip59 library
      final giftWrapEvent = await Nip59.createNIP59Event(
        payload,
        ecPubKey,
        voterPrivKeyHex,
        generateKeyPairFromPrivateKey: _nostr.services.keys.generateKeyPairFromExistingPrivateKey,
        generateKeyPair: _nostr.services.keys.generateKeyPair,
        isValidPrivateKey: _nostr.services.keys.isValidPrivateKey,
      );

      debugPrint('📡 Broadcasting event...');
      debugPrint('🔍 Gift wrap event details:');
      debugPrint('   ID: ${giftWrapEvent.id}');
      debugPrint('   Kind: ${giftWrapEvent.kind}');
      debugPrint('   PubKey: ${giftWrapEvent.pubkey}');
      debugPrint('   Created: ${giftWrapEvent.createdAt}');
      final signature = giftWrapEvent.sig;
      debugPrint('   Signature: $signature');
      if (signature != null) {
        debugPrint('   Signature length: ${signature.length}');
        
        // Validate signature format before broadcasting
        if (signature.length != 128) {
          throw Exception(
            'Invalid signature length: ${signature.length}, expected 128',
          );
        }
      } else {
        throw Exception('Event signature is null');
      }

      // Broadcast using dart_nostr
      _nostr.services.relays.sendEventToRelays(giftWrapEvent);

      // Add a small delay to allow the broadcast to complete
      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint('✅ Sent wrapped event: ${giftWrapEvent.id}');
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
    final filter = NostrFilter(
      kinds: [35000],
      since: since,
    );

    debugPrint('📡 Starting subscription for kind 35000 events...');

    // Create request using dart_nostr
    final request = NostrRequest(
      filters: [filter],
    );

    // Start subscription using dart_nostr
    final nostrStream = _nostr.services.relays.startEventsSubscription(
      request: request,
    );

    debugPrint('🎯 Subscription started, waiting for events...');

    // Convert dart_nostr events to our NostrEvent format
    return nostrStream.stream
        .map((dartNostrEvent) {
          debugPrint(
            '📥 Received event: kind=${dartNostrEvent.kind}, id=${dartNostrEvent.id}',
          );
          return dartNostrEvent;
        })
        .where((dartNostrEvent) {
          final hasContent = dartNostrEvent.content?.isNotEmpty ?? false;
          debugPrint(
            '🔍 Filtering event: kind=${dartNostrEvent.kind}, hasContent=$hasContent',
          );
          return (dartNostrEvent.id?.isNotEmpty ?? false) &&
              (dartNostrEvent.content?.isNotEmpty ?? false) &&
              (dartNostrEvent.tags?.isNotEmpty ?? false);
        })
        .map((dartNostrEvent) {
          debugPrint('✅ Processing valid event: ${dartNostrEvent.id}');
          return NostrEvent(
            id: dartNostrEvent.id ?? '',
            pubkey: dartNostrEvent.pubkey ?? '',
            createdAt: (dartNostrEvent.createdAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch) ~/ 1000,
            kind: dartNostrEvent.kind ?? 0,
            tags: dartNostrEvent.tags?.map((tag) => tag.map((e) => e.toString()).toList()).toList() ?? [],
            content: dartNostrEvent.content ?? '',
            sig: dartNostrEvent.sig ?? '',
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
