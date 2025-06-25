import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:blind_rsa_signatures/blind_rsa_signatures.dart';
import '../models/message.dart';
import 'voter_session_service.dart';
import 'crypto_service.dart';

/// Service for processing blind signature responses from the Election Coordinator
/// Handles the unblinding and verification of vote tokens
class BlindSignatureProcessor {
  static const BlindSignatureProcessor _instance =
      BlindSignatureProcessor._internal();
  static BlindSignatureProcessor get instance => _instance;

  const BlindSignatureProcessor._internal();

  /// Process a blind signature response message (kind=1)
  /// This implements step 3 of the cryptographic protocol
  Future<bool> processBlindSignatureResponse(Message message) async {
    if (!message.isTokenMessage) {
      debugPrint('❌ Message is not a token message, kind: ${message.kind}');
      return false;
    }

    try {
      debugPrint('🔓 Processing blind signature response...');
      debugPrint('   Election ID: ${message.id}');
      debugPrint('   Payload length: ${message.payload.length} chars');

      // 1) Decode Base64 blind signature payload
      debugPrint('📤 Decoding base64 blind signature...');
      final blindSigBytes = base64.decode(message.payload);
      debugPrint('✅ Decoded ${blindSigBytes.length} bytes');

      // 2) Retrieve session data for this election
      debugPrint('🔑 Retrieving session data for election: ${message.id}');
      final sessionData = await VoterSessionService.getCompleteSession();

      if (sessionData == null) {
        debugPrint('❌ No session data found');
        return false;
      }

      final storedElectionId = sessionData['electionId'] as String?;
      if (storedElectionId != message.id) {
        debugPrint(
          '❌ Election ID mismatch: stored=$storedElectionId, received=${message.id}',
        );
        return false;
      }

      // Extract required session components
      final nonce = sessionData['nonce'] as Uint8List?;
      final hashBytes = sessionData['hashBytes'] as Uint8List?;
      final secret = sessionData['secret'] as Uint8List?;
      final blindingResult = sessionData['blindingResult'] as BlindingResult?;

      if (nonce == null ||
          hashBytes == null ||
          secret == null ||
          blindingResult == null) {
        debugPrint('❌ Missing required session components');
        debugPrint('   nonce: ${nonce != null}');
        debugPrint('   hashBytes: ${hashBytes != null}');
        debugPrint('   secret: ${secret != null}');
        debugPrint('   blindingResult: ${blindingResult != null}');
        return false;
      }

      debugPrint('✅ Session data retrieved successfully');
      debugPrint('   Nonce: ${nonce.length} bytes');
      debugPrint('   Hash bytes: ${hashBytes.length} bytes');
      debugPrint('   Secret: ${secret.length} bytes');

      // 3) Get EC public key from election data
      final ecPublicKey = await _getElectionCoordinatorPublicKey(message.id);
      if (ecPublicKey == null) {
        debugPrint(
          '❌ Could not retrieve EC public key for election: ${message.id}',
        );
        return false;
      }

      // 4) Reconstruct BlindSignature from bytes
      debugPrint(
        '🔐 Reconstructing BlindSignature from ${blindSigBytes.length} bytes...',
      );
      // Note: This assumes the blind_rsa_signatures library has a way to reconstruct from bytes
      // The exact method may vary depending on the library implementation

      // 5) Get message randomizer from same source as VoteService (CRITICAL for consistency)
      final messageRandomizer =
          await VoterSessionService.getMessageRandomizer();

      // CRITICAL: Require randomizer to exist (matching Rust behavior)
      if (messageRandomizer == null) {
        debugPrint('❌ Missing message randomizer for token finalization');
        debugPrint('❌ This matches Rust behavior - randomizer is required');
        return false;
      }

      debugPrint('🔓 Unblinding signature with stored parameters...');
      debugPrint('   Using secret: ${secret.length} bytes');
      debugPrint(
        '   Using message randomizer: ${messageRandomizer.length} bytes (from VoterSessionService)',
      );
      debugPrint('   Using original hash: ${hashBytes.length} bytes');

      // 6) Unblind the signature using CryptoService
      final unblindedSignature = CryptoService.unblindSignature(
        blindSigBytes,
        secret,
        messageRandomizer, // Pass actual randomizer (never null due to check above)
        hashBytes,
        ecPublicKey,
      );

      debugPrint('✅ Signature unblinded successfully');

      // 7) Verify the vote token
      debugPrint('🔍 Verifying vote token against EC public key...');
      final isValid = CryptoService.verifyVoteToken(
        unblindedSignature,
        messageRandomizer, // Using same randomizer (guaranteed non-null)
        nonce,
        ecPublicKey,
      );

      if (!isValid) {
        debugPrint('❌ Vote token verification failed');
        return false;
      }

      debugPrint('✅ Vote token verified and valid');

      // 8) Store the vote token in session
      debugPrint('💾 Storing vote token in session...');
      debugPrint(
        '🔍 CRITICAL: Storing UNBLINDED signature (ready for VoteService)',
      );
      debugPrint('🔍 CRITICAL: Using SAME randomizer source as VoteService');
      await VoterSessionService.saveUnblindedSignature(
        _signatureToBytes(unblindedSignature),
        messageRandomizer, // Same randomizer that was used for unblinding
      );

      debugPrint('✅ Vote token stored successfully');
      debugPrint('🎫 Ready to cast vote for election: ${message.id}');

      return true;
    } catch (e) {
      debugPrint('❌ Error processing blind signature response: $e');
      return false;
    }
  }

  /// Get the Election Coordinator's RSA public key for the given election
  /// This retrieves the election data and extracts the RSA public key
  Future<PublicKey?> _getElectionCoordinatorPublicKey(String electionId) async {
    try {
      debugPrint('🔑 Retrieving EC RSA public key for election: $electionId');

      // Get the session data which includes the election information
      final sessionData = await VoterSessionService.getCompleteSession();
      if (sessionData == null) {
        debugPrint('❌ No session data available');
        return null;
      }

      // For now, we'll use the RSA public key that was used during the initial blinding
      // This key should be the same one used by the Election Coordinator for signing
      final rsaPubKeyBase64 = sessionData['rsaPubKey'] as String?;
      if (rsaPubKeyBase64 == null) {
        debugPrint('❌ No RSA public key found in session data');
        return null;
      }

      debugPrint('🔓 Converting Base64 RSA public key to PublicKey object');
      final der = base64.decode(
        rsaPubKeyBase64,
      ); // rsaPubKeyBase64 is Base64-encoded DER from Nostr event
      final publicKey = PublicKey.fromDer(der);

      debugPrint('✅ EC RSA public key retrieved successfully');
      return publicKey;
    } catch (e) {
      debugPrint('❌ Error retrieving EC RSA public key: $e');
      return null;
    }
  }

  /// Convert Signature to bytes for storage
  /// This serializes the signature for secure storage
  Uint8List _signatureToBytes(Signature signature) {
    try {
      debugPrint('🔄 Converting signature to bytes for storage');

      // The blind_rsa_signatures library should provide a way to serialize signatures
      // For now, we'll use the signature bytes directly if available
      // This may need adjustment based on the actual library implementation
      final signatureBytes = signature.bytes;

      debugPrint('✅ Signature converted to ${signatureBytes.length} bytes');
      return signatureBytes;
    } catch (e) {
      debugPrint('❌ Error converting signature to bytes: $e');
      // Return empty bytes if conversion fails
      return Uint8List(0);
    }
  }

  /// Process vote response message (kind=2)
  Future<void> processVoteResponse(Message message) async {
    if (!message.isVoteMessage) {
      debugPrint('❌ Message is not a vote message, kind: ${message.kind}');
      return;
    }

    try {
      debugPrint('🗳️ Processing vote response...');
      debugPrint('   Election ID: ${message.id}');
      debugPrint('   Response: ${message.payload}');

      // For now, just log the response
      // In a full implementation, this could:
      // 1. Parse the response payload
      // 2. Update voting status
      // 3. Notify the UI of successful vote casting

      debugPrint('✅ Vote response processed');
    } catch (e) {
      debugPrint('❌ Error processing vote response: $e');
    }
  }

  /// Process any message based on its kind
  Future<bool> processMessage(Message message) async {
    debugPrint('📨 Processing message: $message');

    switch (message.kind) {
      case 1:
        return await processBlindSignatureResponse(message);
      case 2:
        await processVoteResponse(message);
        return true;
      default:
        debugPrint('❌ Unknown message kind: ${message.kind}');
        return false;
    }
  }
}
