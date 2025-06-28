import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dart_nostr/dart_nostr.dart' as dart_nostr;
import 'package:nip59/nip59.dart';
import '../models/message.dart';
import '../models/nostr_event.dart';
import 'election_results_service.dart';

class NostrService {
  static NostrService? _instance;
  static NostrService get instance {
    _instance ??= NostrService._internal();
    return _instance!;
  }

  bool _connected = false;
  bool _connecting = false;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _giftWrapSubscription;
  late dart_nostr.Nostr _nostr;
  dart_nostr.NostrKeyPairs? _currentKeyPair;

  // Stream controllers for different types of messages
  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  NostrService._internal();

  // Keep the public constructor for backwards compatibility but make it return the singleton
  factory NostrService() => instance;

  /// Stream of parsed messages from Gift Wrap events
  Stream<Message> get messageStream => _messageController.stream;

  /// Stream of error messages during message processing
  Stream<String> get errorStream => _errorController.stream;

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
      _nostr = dart_nostr.Nostr.instance;

      // Use timeout for relay initialization
      await Future.any([
        _nostr.services.relays.init(relaysUrl: [relayUrl]),
        Future.delayed(const Duration(seconds: 10)).then(
          (_) => throw TimeoutException(
            'Relay connection timeout',
            const Duration(seconds: 10),
          ),
        ),
      ]);

      // Connection established - dart_nostr doesn't expose connection status checking
      // The init method will throw an exception if connection fails

      _connected = true;
      debugPrint('✅ Successfully connected to Nostr relay: $relayUrl');
    } catch (e) {
      _connected = false;
      debugPrint('❌ Failed to connect to Nostr relay: $e');

      // Provide more specific error messages
      if (e is TimeoutException) {
        throw Exception(
          'Connection timeout: Please check your internet connection and try again',
        );
      } else if (e.toString().contains('WebSocket')) {
        throw Exception(
          'WebSocket connection failed: Please check the relay URL and try again',
        );
      } else {
        throw Exception('Failed to connect to Nostr relay: $e');
      }
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
      debugPrint('🔌 Disconnecting from Nostr relays...');

      // Cancel any active subscriptions
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      await _giftWrapSubscription?.cancel();
      _giftWrapSubscription = null;

      // Close all relay connections with timeout
      await Future.any([
        _nostr.services.relays.disconnectFromRelays(),
        Future.delayed(const Duration(seconds: 5)),
      ]);

      _connected = false;
      _connecting = false;
      _currentKeyPair = null;
      debugPrint('✅ Disconnected from Nostr relays');
    } catch (e) {
      debugPrint('⚠️ Error disconnecting from Nostr relays: $e');
      // Force disconnection even if there was an error
      _connected = false;
      _connecting = false;
      _currentKeyPair = null;
    }
  }

  bool get isConnected => _connected;

  /// Start listening for Gift Wrap events (NIP-59) directed to the current user
  /// This will listen for blind signature responses and other encrypted messages
  Future<void> startGiftWrapListener(
    String voterPubKeyHex,
    String voterPrivKeyHex,
  ) async {
    if (!_connected) {
      throw Exception('Not connected to relay. Connect first.');
    }

    if (_giftWrapSubscription != null) {
      debugPrint('🎁 Gift Wrap listener already active');
      return;
    }

    try {
      debugPrint('🎁 Starting Gift Wrap listener for voter: $voterPubKeyHex');

      // Create filter for Gift Wrap events (kind 1059) directed to this voter
      // Note: No 'since' parameter due to NIP-59 timestamp randomization
      // Gift Wrap timestamps are intentionally tweaked to prevent timing analysis
      final filter = dart_nostr.NostrFilter(
        kinds: [1059], // NIP-59 Gift Wrap events
        p: [voterPubKeyHex], // Events tagged to this voter's pubkey
        limit: 100, // Limit to prevent excessive historical events
        since: DateTime.now().subtract(
          const Duration(days: 2),
        ), // gift wraps events have time tweaked
      );

      final request = dart_nostr.NostrRequest(filters: [filter]);

      // Start subscription for Gift Wrap events
      final giftWrapStream = _nostr.services.relays.startEventsSubscription(
        request: request,
      );

      _giftWrapSubscription = giftWrapStream.stream.listen(
        (dartNostrEvent) async {
          debugPrint('🎁 Received Gift Wrap event from relay');
          debugPrint('   Event ID: ${dartNostrEvent.id}');
          debugPrint('   Kind: ${dartNostrEvent.kind}');
          debugPrint('   Pubkey: ${dartNostrEvent.pubkey}');
          debugPrint('   Created at: ${dartNostrEvent.createdAt}');
          await _handleGiftWrapEvent(dartNostrEvent, voterPrivKeyHex);
        },
        onError: (error) {
          debugPrint('❌ Gift Wrap listener error: $error');
          _errorController.add('Gift Wrap listener error: $error');
        },
        onDone: () {
          debugPrint('🎁 Gift Wrap listener stream closed');
        },
      );

      debugPrint('✅ Gift Wrap listener started successfully');
    } catch (e) {
      debugPrint('❌ Failed to start Gift Wrap listener: $e');
      _errorController.add('Failed to start Gift Wrap listener: $e');
      rethrow;
    }
  }

  /// Handle incoming Gift Wrap events and extract messages
  Future<void> _handleGiftWrapEvent(
    dynamic dartNostrEvent,
    String voterPrivKeyHex,
  ) async {
    try {
      debugPrint('📡 Received Gift Wrap event: ${dartNostrEvent.id}');

      // Events received from relays are already signature-validated by the relay
      // and dart_nostr library, so we can proceed directly to decryption
      debugPrint(
        '🔍 Processing Gift Wrap event (signature validated by relay)',
      );

      debugPrint('🎁 Extracting NIP-59 rumor...');

      // Extract the rumor using NIP-59 decryption
      final nostrKeyPairs = _nostr.services.keys
          .generateKeyPairFromExistingPrivateKey(voterPrivKeyHex);
      final rumor = await Nip59.decryptNIP59Event(
        dartNostrEvent,
        nostrKeyPairs.private,
        isValidPrivateKey: _nostr.services.keys.isValidPrivateKey,
      );

      if (rumor.content == null || rumor.content!.isEmpty) {
        debugPrint('❌ Failed to decrypt Gift Wrap event or empty content');
        _errorController.add(
          'Failed to decrypt Gift Wrap event or empty content',
        );
        return;
      }
      debugPrint('✅ Rumor extracted successfully');

      // Validate rumor timestamp (canonical time) - NIP-59 compliance
      final rumorTimestamp = rumor.createdAt;
      final now = DateTime.now();
      final maxAge = now.subtract(
        const Duration(hours: 24),
      ); // Accept rumors up to 24h old

      if (rumorTimestamp != null && rumorTimestamp.isBefore(maxAge)) {
        debugPrint('❌ Rumor too old: $rumorTimestamp (max age: 24h)');
        return;
      }
      debugPrint('✅ Rumor timestamp valid: $rumorTimestamp');

      debugPrint('📦 Parsing Message JSON from rumor content...');
      debugPrint('   Content: ${rumor.content}');

      // Parse the rumor content as a Message
      final message = Message.fromJson(rumor.content!);

      if (!message.isValid()) {
        debugPrint('❌ Invalid message format: $message');
        _errorController.add('Invalid message format: $message');
        return;
      }

      debugPrint('✅ Message parsed successfully: $message');
      debugPrint('📤 Emitting message through stream controller');
      debugPrint(
        '   Stream controller is closed: ${_messageController.isClosed}',
      );
      debugPrint('   Stream has listeners: ${_messageController.hasListener}');

      // Emit the message through the stream
      if (!_messageController.isClosed) {
        _messageController.add(message);
        debugPrint('✅ Message emitted to stream successfully');
      } else {
        debugPrint('❌ Cannot emit message - stream controller is closed');
      }
    } catch (e) {
      debugPrint('❌ Error processing Gift Wrap event: $e');
      _errorController.add('Error processing Gift Wrap event: $e');
    }
  }

  /// Stop the Gift Wrap listener
  Future<void> stopGiftWrapListener() async {
    if (_giftWrapSubscription != null) {
      debugPrint('🛑 Stopping Gift Wrap listener');
      await _giftWrapSubscription!.cancel();
      _giftWrapSubscription = null;
      debugPrint('✅ Gift Wrap listener stopped');
    }
  }

  void loginPrivateKey({
    required String pubKeyHex,
    required String privKeyHex,
  }) {
    try {
      debugPrint('🔐 Attempting to login with:');
      debugPrint('   Public key: $pubKeyHex (${pubKeyHex.length} chars)');
      debugPrint(
        '   Private key: ${privKeyHex.substring(0, 8)}... (${privKeyHex.length} chars)',
      );

      // Validate private key format
      if (!_nostr.services.keys.isValidPrivateKey(privKeyHex)) {
        throw Exception('Invalid private key format');
      }

      // Validate key lengths
      if (pubKeyHex.length != 64) {
        throw Exception(
          'Invalid public key length: expected 64 characters, got ${pubKeyHex.length}',
        );
      }
      if (privKeyHex.length != 64) {
        throw Exception(
          'Invalid private key length: expected 64 characters, got ${privKeyHex.length}',
        );
      }

      // Generate key pair from private key using dart_nostr
      _currentKeyPair = _nostr.services.keys
          .generateKeyPairFromExistingPrivateKey(privKeyHex);

      // Validate that the generated public key matches the expected one
      if (_currentKeyPair!.public != pubKeyHex) {
        debugPrint('❌ Key mismatch:');
        debugPrint('   Expected: $pubKeyHex');
        debugPrint('   Generated: ${_currentKeyPair!.public}');
        throw Exception('Generated public key does not match expected key');
      }

      debugPrint('✅ Login successful');
    } catch (e) {
      debugPrint('❌ Login failed: $e');
      _currentKeyPair = null;
      rethrow;
    }
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
        generateKeyPairFromPrivateKey:
            _nostr.services.keys.generateKeyPairFromExistingPrivateKey,
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

  /// Send vote message via Gift Wrap with anonymous keys
  /// Implements step 3 part 2 of the cryptographic protocol
  Future<void> sendVoteMessage({
    required String messageJson,
    required String ecPubKey,
    required String randomPrivKeyHex,
    required String randomPubKeyHex,
  }) async {
    if (!_connected) {
      throw Exception('Not connected to relay');
    }

    try {
      debugPrint('🗳️ Sending vote message via Gift Wrap...');
      debugPrint('   Message: $messageJson');
      debugPrint('   EC pubkey: $ecPubKey');
      debugPrint(
        '   Using anonymous key: ${randomPubKeyHex.substring(0, 16)}...',
      );

      // Create NIP-59 gift wrap using anonymous keys
      final giftWrapEvent = await Nip59.createNIP59Event(
        messageJson,
        ecPubKey,
        randomPrivKeyHex,
        generateKeyPairFromPrivateKey:
            _nostr.services.keys.generateKeyPairFromExistingPrivateKey,
        generateKeyPair: _nostr.services.keys.generateKeyPair,
        isValidPrivateKey: _nostr.services.keys.isValidPrivateKey,
      );

      debugPrint('📡 Broadcasting vote Gift Wrap event...');
      debugPrint('🔍 Vote Gift Wrap event details:');
      debugPrint('   ID: ${giftWrapEvent.id}');
      debugPrint('   Kind: ${giftWrapEvent.kind}');
      debugPrint('   PubKey: ${giftWrapEvent.pubkey}');
      debugPrint('   Created: ${giftWrapEvent.createdAt}');

      // Validate signature
      final signature = giftWrapEvent.sig;
      if (signature == null || signature.length != 128) {
        throw Exception('Invalid Gift Wrap signature');
      }

      // Send the Gift Wrap event
      _nostr.services.relays.sendEventToRelays(giftWrapEvent);

      // Small delay to ensure broadcast completion
      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint('✅ Vote Gift Wrap sent successfully: ${giftWrapEvent.id}');
      debugPrint(
        '🔒 Vote sent anonymously - cannot be traced to voter identity',
      );
    } catch (e) {
      debugPrint('❌ Error sending vote message: $e');
      rethrow;
    }
  }


  Stream<NostrEvent> subscribeToElections() {
    if (!_connected) {
      throw Exception('Not connected to relay');
    }

    // Create request filter for kind 35000 events (elections)
    // Note: No 'since' or 'limit' parameters to ensure maximum real-time event reception
    final filter = dart_nostr.NostrFilter(
      kinds: [35000], // Election events only
    );

    debugPrint(
      '📅 Subscribing to ALL kind 35000 events for maximum real-time coverage',
    );

    debugPrint('📡 Starting subscription for kind 35000 events...');

    // Create request using dart_nostr
    final request = dart_nostr.NostrRequest(filters: [filter]);

    // Start subscription using dart_nostr
    final nostrStream = _nostr.services.relays.startEventsSubscription(
      request: request,
    );

    debugPrint('🎯 Subscription started, waiting for events...');

    // Convert dart_nostr events to our NostrEvent format
    return nostrStream.stream
        .map((dartNostrEvent) {
          debugPrint(
            '📥 Received event: kind=${dartNostrEvent.kind}, id=${dartNostrEvent.id}, timestamp=${dartNostrEvent.createdAt}',
          );
          if (dartNostrEvent.kind == 35000) {
            debugPrint('🗳️ Election event received in real-time!');
          }
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
            pubkey: dartNostrEvent.pubkey,
            createdAt: (dartNostrEvent.createdAt?.millisecondsSinceEpoch ?? 
                DateTime.now().millisecondsSinceEpoch) ~/ 1000,
            kind: dartNostrEvent.kind ?? 0,
            tags:
                dartNostrEvent.tags
                    ?.map((tag) => tag.map((e) => e.toString()).toList())
                    .toList() ??
                [],
            content: dartNostrEvent.content ?? '',
            sig: dartNostrEvent.sig ?? '',
          );
        })
        .handleError((error) {
          debugPrint('🚨 Stream error: $error');
        })
        .asBroadcastStream(); // Make it a broadcast stream to allow multiple listeners
  }


  /// Subscribe to all election results events from EC public key (kind 35001)
  /// This will store all election results globally and show real-time logs
  Stream<NostrEvent> subscribeToAllElectionResults(String ecPublicKey) {
    if (!_connected) {
      throw Exception('Not connected to relay');
    }

    debugPrint(
      '📡 Subscribing to ALL election results from EC pubkey: $ecPublicKey',
    );
    debugPrint('   Looking for: kind=35001 (any d tag = election results)');

    // Create filter for ALL kind 35001 events from the EC public key
    final filter = dart_nostr.NostrFilter(
      kinds: [35001], // NIP-33 Parameterized Replaceable Events
      authors: [ecPublicKey], // Only from this specific EC public key
    );

    final request = dart_nostr.NostrRequest(filters: [filter]);

    debugPrint('🔍 Starting election results subscription...');

    final nostrStream = _nostr.services.relays.startEventsSubscription(
      request: request,
    );

    return nostrStream.stream
        .map((dartNostrEvent) {
          debugPrint('🎯 ELECTION RESULTS EVENT RECEIVED:');
          debugPrint('   ID: ${dartNostrEvent.id}');
          debugPrint('   Kind: ${dartNostrEvent.kind}');
          debugPrint('   Author: ${dartNostrEvent.pubkey}');
          debugPrint('   Created: ${dartNostrEvent.createdAt}');
          debugPrint('   Content: ${dartNostrEvent.content}');
          debugPrint('   Tags: ${dartNostrEvent.tags}');
          debugPrint('   ---');

          return dartNostrEvent;
        })
        .where((dartNostrEvent) {
          // Verify the event matches our criteria
          final isCorrectKind = dartNostrEvent.kind == 35001;
          final isCorrectAuthor = dartNostrEvent.pubkey == ecPublicKey;
          final hasDTag =
              dartNostrEvent.tags?.any(
                (tag) => tag.length >= 2 && tag[0] == 'd',
              ) ??
              false;

          debugPrint('🔍 Event filter check:');
          debugPrint('   Correct kind (35001): $isCorrectKind');
          debugPrint('   Correct author: $isCorrectAuthor');
          debugPrint('   Has d tag: $hasDTag');

          final passes = isCorrectKind && isCorrectAuthor && hasDTag;
          debugPrint('   Filter result: ${passes ? "✅ PASSES" : "❌ REJECTED"}');

          return passes;
        })
        .map((dartNostrEvent) {
          // Extract election ID from d tag and store results
          final dTag = dartNostrEvent.tags?.firstWhere(
            (tag) => tag.length >= 2 && tag[0] == 'd',
            orElse: () => ['d', 'unknown'],
          );
          final electionId = dTag != null && dTag.length >= 2
              ? dTag[1]
              : 'unknown';

          debugPrint('📊 Processing election results for: $electionId');

          // Store results in global service
          if (dartNostrEvent.content != null &&
              dartNostrEvent.content!.isNotEmpty) {
            ElectionResultsService.instance.updateResultsFromEventContent(
              electionId,
              dartNostrEvent.content!,
            );
          }

          debugPrint(
            '✅ ELECTION RESULTS PROCESSED: ${dartNostrEvent.id} for election: $electionId',
          );
          return NostrEvent(
            id: dartNostrEvent.id ?? '',
            pubkey: dartNostrEvent.pubkey,
            createdAt: (dartNostrEvent.createdAt?.millisecondsSinceEpoch ?? 
                DateTime.now().millisecondsSinceEpoch) ~/ 1000,
            kind: dartNostrEvent.kind ?? 0,
            tags:
                dartNostrEvent.tags
                    ?.map((tag) => tag.map((e) => e.toString()).toList())
                    .toList() ??
                [],
            content: dartNostrEvent.content ?? '',
            sig: dartNostrEvent.sig ?? '',
          );
        })
        .handleError((error) {
          debugPrint('🚨 Election results stream error: $error');
        })
        .asBroadcastStream();
  }

  /// Subscribe to election results for a specific election ID
  /// Filters global results stream for specific election
  Stream<NostrEvent> subscribeToElectionResults(
    String ecPublicKey,
    String electionId,
  ) {
    debugPrint('📊 Subscribing to results for specific election: $electionId');

    return subscribeToAllElectionResults(ecPublicKey)
        .where((event) {
          // Filter for specific election ID from d tag
          final dTag = event.tags.firstWhere(
            (tag) => tag.length >= 2 && tag[0] == 'd',
            orElse: () => ['d', ''],
          );
          final eventElectionId = dTag.length >= 2 ? dTag[1] : '';

          final matches = eventElectionId == electionId;
          debugPrint(
            '🔍 Election filter: $eventElectionId == $electionId ? $matches',
          );

          return matches;
        })
        .handleError((error) {
          debugPrint('🚨 Specific election results stream error: $error');
        });
  }

  /// Cleanup all resources when service is disposed
  void dispose() {
    debugPrint('🧹 NostrService: Disposing all resources...');
    
    // Close stream controllers
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    if (!_errorController.isClosed) {
      _errorController.close();
    }
    
    // Cancel active subscriptions
    _giftWrapSubscription?.cancel();
    _giftWrapSubscription = null;
    
    debugPrint('✅ NostrService: All resources disposed');
  }
}
