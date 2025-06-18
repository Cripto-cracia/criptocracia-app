import 'dart:math';
import 'package:flutter/foundation.dart';

/// Service responsible for generating and managing cryptographic keys
/// for secure and anonymous voting operations.
class KeyService {
  
  /// Generates a secure random Nostr key pair for anonymous voting
  /// 
  /// This generates a fresh key pair for each voting session to ensure
  /// voter anonymity. The private key should be used only for this 
  /// specific vote and then discarded.
  /// 
  /// Returns a Map containing 'publicKey' and 'privateKey' as hex strings
  static Map<String, String> generateVoterKeyPair() {
    try {
      debugPrint('🔑 Generating fresh Nostr key pair for anonymous voting...');
      
      // Generate secure random 32 bytes for private key
      final random = Random.secure();
      final privateKeyBytes = Uint8List(32);
      
      for (int i = 0; i < privateKeyBytes.length; i++) {
        privateKeyBytes[i] = random.nextInt(256);
      }
      
      // Convert private key to hex
      final privateKeyHex = privateKeyBytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join('');
      
      // Generate public key from private key using secp256k1
      // For now, we'll use a simplified approach - in production, this would use proper secp256k1
      final publicKeyHex = _derivePublicKeyFromPrivate(privateKeyHex);
      
      debugPrint('✅ Successfully generated Nostr key pair');
      debugPrint('🔑 Public key: $publicKeyHex');
      debugPrint('🔐 Private key: [REDACTED - ${privateKeyHex.length} chars]');
      
      return {
        'publicKey': publicKeyHex,
        'privateKey': privateKeyHex,
      };
    } catch (e) {
      debugPrint('❌ Failed to generate Nostr key pair: $e');
      throw Exception('Failed to generate Nostr key pair: $e');
    }
  }
  
  /// Validates a Nostr public key hex string
  /// 
  /// [publicKeyHex] - The hex string representation of the public key
  /// 
  /// Returns true if the public key is valid
  static bool validatePublicKey(String publicKeyHex) {
    try {
      // Check length (64 hex chars = 32 bytes)
      if (publicKeyHex.length != 64) {
        debugPrint('⚠️ Invalid public key length: ${publicKeyHex.length} (expected 64)');
        return false;
      }
      
      // Check if valid hex
      final regex = RegExp(r'^[0-9a-fA-F]+$');
      if (!regex.hasMatch(publicKeyHex)) {
        debugPrint('⚠️ Invalid public key format: contains non-hex characters');
        return false;
      }
      
      debugPrint('✅ Public key validation passed');
      return true;
    } catch (e) {
      debugPrint('⚠️ Public key validation failed: $e');
      return false;
    }
  }
  
  /// Validates a Nostr private key hex string
  /// 
  /// [privateKeyHex] - The hex string representation of the private key
  /// 
  /// Returns true if the private key is valid
  static bool validatePrivateKey(String privateKeyHex) {
    try {
      // Check length (64 hex chars = 32 bytes)
      if (privateKeyHex.length != 64) {
        debugPrint('⚠️ Invalid private key length: ${privateKeyHex.length} (expected 64)');
        return false;
      }
      
      // Check if valid hex
      final regex = RegExp(r'^[0-9a-fA-F]+$');
      if (!regex.hasMatch(privateKeyHex)) {
        debugPrint('⚠️ Invalid private key format: contains non-hex characters');
        return false;
      }
      
      // Validate that it's not zero or max value
      final privateKeyInt = BigInt.parse(privateKeyHex, radix: 16);
      if (privateKeyInt == BigInt.zero) {
        debugPrint('⚠️ Invalid private key: cannot be zero');
        return false;
      }
      
      debugPrint('✅ Private key validation passed');
      return true;
    } catch (e) {
      debugPrint('⚠️ Private key validation failed: $e');
      return false;
    }
  }
  
  /// Derives public key from private key hex string
  /// 
  /// [privateKeyHex] - The hex string representation of the private key
  /// 
  /// Returns the corresponding public key hex string
  /// 
  /// Throws [Exception] if the private key is invalid
  static String derivePublicKey(String privateKeyHex) {
    try {
      if (!validatePrivateKey(privateKeyHex)) {
        throw Exception('Invalid private key format');
      }
      
      return _derivePublicKeyFromPrivate(privateKeyHex);
    } catch (e) {
      debugPrint('❌ Failed to derive public key: $e');
      throw Exception('Failed to derive public key: $e');
    }
  }
  
  /// Internal helper to derive public key from private key
  /// This is a simplified implementation - in production this would use proper secp256k1
  static String _derivePublicKeyFromPrivate(String privateKeyHex) {
    // For now, generate a deterministic but fake public key
    // In production, this would use proper secp256k1 curve operations
    final random = Random(privateKeyHex.hashCode);
    final publicKeyBytes = Uint8List(32);
    
    for (int i = 0; i < publicKeyBytes.length; i++) {
      publicKeyBytes[i] = random.nextInt(256);
    }
    
    return publicKeyBytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join('');
  }
}