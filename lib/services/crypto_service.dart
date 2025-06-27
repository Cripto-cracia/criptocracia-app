import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:blind_rsa_signatures/blind_rsa_signatures.dart';
import 'package:flutter/foundation.dart';

class CryptoService {
  static Uint8List generateNonce() {
    // Simplified nonce generation for MVP
    final random = Random.secure();
    final nonce = Uint8List(16); // 128-bit nonce

    for (int i = 0; i < nonce.length; i++) {
      nonce[i] = random.nextInt(256);
    }

    return nonce;
  }

  static Uint8List hashNonce(Uint8List nonce) {
    return Uint8List.fromList(sha256.convert(nonce).bytes);
  }

  static BlindingResult blindNonce(
    Uint8List hashedNonce,
    PublicKey ecPublicKey,
  ) {
    try {
      debugPrint('🔒 Blinding nonce with EC public key');
      debugPrint('   Hashed nonce length: ${hashedNonce.length} bytes');
      debugPrint('   Hashed nonce (hex): ${hashedNonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');

      const options = Options.defaultOptions;
      debugPrint('🔧 Calling ecPublicKey.blind() with parameters:');
      debugPrint('   salt: null');
      debugPrint('   message: ${hashedNonce.length} bytes');
      debugPrint('   generateMessageRandomizer: true');
      debugPrint('   options: $options');

      final result = ecPublicKey.blind(null, hashedNonce, true, options);

      debugPrint('✅ Nonce blinded successfully');
      debugPrint('📊 DETAILED BlindingResult Analysis:');
      debugPrint('   Blinded message length: ${result.blindMessage.length} bytes');
      debugPrint('   Blinded message (first 32 bytes hex): ${result.blindMessage.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      debugPrint('   Secret length: ${result.secret.length} bytes');
      debugPrint('   Secret (first 16 bytes hex): ${result.secret.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      
      if (result.messageRandomizer != null) {
        debugPrint('   ✅ MessageRandomizer: ${result.messageRandomizer!.length} bytes');
        debugPrint('   MessageRandomizer (first 16 bytes hex): ${result.messageRandomizer!.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
        debugPrint('   MessageRandomizer (last 16 bytes hex): ${result.messageRandomizer!.skip(result.messageRandomizer!.length - 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      } else {
        debugPrint('   ❌ MessageRandomizer: NULL - This will cause vote verification to fail!');
        debugPrint('   🚨 CRITICAL: blind_rsa_signatures library did not generate messageRandomizer');
        debugPrint('   🚨 This is likely a version difference between local and git dependencies');
      }

      // Additional validation
      if (result.blindMessage.isEmpty) {
        debugPrint('❌ WARNING: blindMessage is empty');
      }
      if (result.secret.isEmpty) {
        debugPrint('❌ WARNING: secret is empty');
      }

      debugPrint('🔍 BlindingResult object type: ${result.runtimeType}');
      debugPrint('🔍 BlindingResult toString(): $result');

      return result;
    } catch (e) {
      debugPrint('❌ Failed to blind nonce: $e');
      debugPrint('   Exception type: ${e.runtimeType}');
      debugPrint('   Exception details: $e');
      rethrow;
    }
  }

  /// Unblind a signature using the blinding result components
  static Signature unblindSignature(
    Uint8List blindSignature,
    Uint8List secret,
    Uint8List messageRandomizer,
    Uint8List originalHashedMessage,
    PublicKey ecPublicKey,
  ) {
    try {
      debugPrint('🔓 Unblinding signature');

      // Use the blind_rsa_signatures library to finalize the signature
      final signature = ecPublicKey.finalize(
        blindSignature,
        secret,
        messageRandomizer,
        originalHashedMessage,
        Options.defaultOptions,
      );

      debugPrint('✅ Signature unblinded successfully');
      return signature;
    } catch (e) {
      debugPrint('❌ Failed to unblind signature: $e');
      rethrow;
    }
  }

  /// Verify an RSA signature against a message
  static bool verifySignature(
    Signature signature,
    Uint8List messageRandomizer,
    Uint8List message,
    PublicKey ecPublicKey,
  ) {
    try {
      debugPrint('🔍 Verifying signature against message');
      debugPrint('   Message length: ${message.length} bytes');

      // Use the blind_rsa_signatures library to verify
      final isValid = signature.verify(
        ecPublicKey,
        messageRandomizer,
        message,
        Options.defaultOptions,
      );

      debugPrint(
        isValid
            ? '✅ Signature verification successful'
            : '❌ Signature verification failed',
      );
      return isValid;
    } catch (e) {
      debugPrint('❌ Signature verification error: $e');
      return false;
    }
  }

  /// Verify a vote token (unblinded signature) against the original nonce
  static bool verifyVoteToken(
    Signature unblindedSignature,
    Uint8List messageRandomizer,
    Uint8List originalNonce,
    PublicKey ecPublicKey,
  ) {
    // Hash the original nonce (as done during blinding)
    final hashedNonce = hashNonce(originalNonce);

    // Verify the unblinded signature against the hashed nonce
    return verifySignature(
      unblindedSignature,
      messageRandomizer,
      hashedNonce,
      ecPublicKey,
    );
  }

  /// Generate a secure vote token by processing the complete blind signature flow
  static Map<String, dynamic> processBlindSignatureResponse(
    Uint8List blindSignatureFromEC,
    Uint8List originalNonce,
    Uint8List secret,
    Uint8List messageRandomizer,
    PublicKey ecPublicKey,
  ) {
    try {
      // Hash the original nonce (as done during blinding)
      final hashedNonce = hashNonce(originalNonce);

      // Unblind the signature received from the Election Coordinator
      final unblindedSignature = unblindSignature(
        blindSignatureFromEC,
        secret,
        messageRandomizer,
        hashedNonce,
        ecPublicKey,
      );

      // Verify the unblinded signature is valid
      final isValid = verifyVoteToken(
        unblindedSignature,
        messageRandomizer,
        originalNonce,
        ecPublicKey,
      );

      if (!isValid) {
        throw Exception(
          'Vote token verification failed - signature is invalid',
        );
      }

      debugPrint('🎫 Vote token generated and verified successfully');

      return {
        'voteToken': unblindedSignature,
        'originalNonce': originalNonce,
        'verified': isValid,
      };
    } catch (e) {
      debugPrint('❌ Failed to process blind signature response: $e');
      rethrow;
    }
  }
}
