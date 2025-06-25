import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:blind_rsa_signatures/blind_rsa_signatures.dart';
import 'voter_session_service.dart';
import 'nostr_service.dart';
import 'nostr_key_manager.dart';
import '../models/message.dart';
import '../config/app_config.dart';

/// Service for creating and sending votes according to step 3 of the cryptographic protocol
/// Implements the vote packaging and sending logic from the Rust voter app
class VoteService {
  static const VoteService _instance = VoteService._internal();
  static VoteService get instance => _instance;

  const VoteService._internal();

  factory VoteService() => _instance;

  /// Send a vote for the specified candidate in the election
  /// This implements step 3 part 2 of the cryptographic protocol:
  /// Package (h_n, token, blinding_factor, candidate_id) and send via Gift Wrap
  Future<void> sendVote({
    required String electionId,
    required int candidateId,
  }) async {
    try {
      debugPrint('🗳️ Starting vote creation and sending process...');
      debugPrint('   Election ID: $electionId');
      debugPrint('   Candidate ID: $candidateId');

      // 1) Retrieve session data with all required components
      debugPrint('📦 Retrieving session data...');
      final session = await VoterSessionService.getCompleteSession();

      if (session == null) {
        throw Exception(
          'No voting session found. Please request a vote token first.',
        );
      }

      if (session['electionId'] != electionId) {
        throw Exception(
          'Session election mismatch. Expected: $electionId, Found: ${session['electionId']}',
        );
      }

      // Extract required components (matching Rust app variables)
      final nonce = session['nonce'] as Uint8List?;
      final hashBytes = session['hashBytes'] as Uint8List?; // h_n_bytes
      final voteToken =
          session['unblindedSignature']
              as Uint8List?; // Already unblinded by BlindSignatureProcessor

      final rsaPubKey = session['rsaPubKey'] as String?;
      // CRITICAL: Get the original randomizer used during blinding
      // This must be retrieved from storage, not from session data
      debugPrint('🔍 DIAGNOSTIC: Checking randomizer storage...');
      final messageRandomizer =
          await VoterSessionService.getMessageRandomizer(); // r

      // Also check if it's in the BlindingResult
      final blindingResult = session['blindingResult'] as BlindingResult?;
      debugPrint(
        '🔍 BlindingResult messageRandomizer: ${blindingResult?.messageRandomizer?.length ?? 'NULL'}',
      );

      if (nonce == null ||
          hashBytes == null ||
          voteToken == null ||
          rsaPubKey == null) {
        throw Exception(
          'Incomplete session data. Missing required voting components.',
        );
      }

      if (messageRandomizer == null) {
        debugPrint('🚨 DIAGNOSTIC: Randomizer missing from storage');
        debugPrint(
          '🚨 This suggests BlindingResult.messageRandomizer was null during saveSession()',
        );
        debugPrint('🚨 The blind_rsa_signatures library may have a bug');
        throw Exception(
          'Missing original blinding randomizer - this is required for vote verification',
        );
      }

      debugPrint('✅ Session data retrieved successfully');
      debugPrint('   Nonce: ${nonce.length} bytes');
      debugPrint('   Hash bytes (h_n): ${hashBytes.length} bytes');
      debugPrint(
        '   Vote token (already unblinded): ${voteToken.length} bytes',
      );
      debugPrint(
        '   Original randomizer (r): ${messageRandomizer.length} bytes',
      );

      // ✅ NOTE: Signature is already unblinded by BlindSignatureProcessor
      debugPrint(
        '✅ Using pre-unblinded vote token from BlindSignatureProcessor',
      );

      // Verify the vote token locally before sending (optional validation)
      final ecPublicKey = PublicKey.fromDer(base64.decode(rsaPubKey));
      final signature = Signature(voteToken);
      final isValidToken = signature.verify(
        ecPublicKey,
        messageRandomizer,
        hashBytes,
        Options.defaultOptions,
      );

      if (!isValidToken) {
        throw Exception(
          'Vote token verification failed - signature is invalid',
        );
      }

      debugPrint('✅ Vote token verified locally - ready to send');

      // 2) Create vote payload in colon-delimited format
      debugPrint('🔄 Creating vote payload...');

      // Base64 encode the cryptographic components (h_n:token:r:candidate_id)
      final hNBase64 = base64.encode(hashBytes);
      final tokenBase64 = base64.encode(
        voteToken,
      ); // Use UNBLINDED signature, not raw blind signature
      final rBase64 = base64.encode(
        messageRandomizer,
      ); // We already validated it's not null

      // Create colon-delimited payload as per Rust implementation
      final votePayload = '$hNBase64:$tokenBase64:$rBase64:$candidateId';

      debugPrint('✅ Vote payload created');
      debugPrint('   h_n (Base64): ${hNBase64.substring(0, 20)}...');
      debugPrint('   token (Base64): ${tokenBase64.substring(0, 20)}...');
      debugPrint('   r (Base64): ${rBase64.substring(0, 20)}...');
      debugPrint('   candidate_id: $candidateId');
      debugPrint('   Payload length: ${votePayload.length} chars');
      debugPrint('🔍 CRITICAL: Using UNBLINDED signature as vote token');
      debugPrint(
        '🔍 CRITICAL: Using original blinding randomizer in vote payload',
      );

      // 3) Create Message with election_id, kind=2, and vote payload
      debugPrint('📨 Creating vote message...');
      final message = Message(
        id: electionId,
        kind: 2, // Vote message type
        payload: votePayload,
      );

      final messageJson = message.toJson();
      debugPrint('✅ Vote message created: $messageJson');

      // 4) Generate random Nostr keys for voter anonymity
      debugPrint('🔐 Generating random keys for anonymity...');
      final randomKeys = await NostrKeyManager.generateRandomKeyPair();
      final randomPrivKeyHex = randomKeys['privateKeyHex'] as String;
      final randomPubKeyHex = randomKeys['publicKeyHex'] as String;

      debugPrint('✅ Random keys generated');
      debugPrint('   Random pubkey: ${randomPubKeyHex.substring(0, 16)}...');

      // 5) Send vote via Gift Wrap with anonymous keys
      debugPrint('🎁 Creating and sending Gift Wrap...');
      final nostrService = NostrService.instance;

      // Ensure connection to relay
      if (!nostrService.isConnected) {
        debugPrint('🔌 Connecting to relay first...');
        await nostrService.connect(AppConfig.relayUrl);
      }

      // Send the vote message via Gift Wrap to EC's public key
      await nostrService.sendVoteMessage(
        messageJson: messageJson,
        ecPubKey: AppConfig.ecPublicKey,
        randomPrivKeyHex: randomPrivKeyHex,
        randomPubKeyHex: randomPubKeyHex,
      );

      debugPrint('🎉 Vote sent successfully!');
      debugPrint('   Used anonymous keys for voter privacy');
      debugPrint('   Vote cannot be traced back to voter identity');
    } catch (e) {
      debugPrint('❌ Error sending vote: $e');
      rethrow;
    }
  }
}
