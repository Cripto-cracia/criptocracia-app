import 'dart:convert';
import 'dart:async';
import 'package:blind_rsa_signatures/blind_rsa_signatures.dart';
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';
import 'package:crypto/crypto.dart';

/// Comprehensive voting session management matching Rust client app state
class VoterSessionService {
  static const _nonceKey = 'voter_nonce';
  static const _blindingResultKey = 'voter_blinding_result';
  static const _hashBytesKey = 'voter_hash_bytes';
  static const _electionIdKey = 'voter_election_id';
  static const _blindingSecretKey = 'voter_blinding_secret';
  static const _msgRandomizerKey = 'voter_msg_randomizer';
  static const _rsaPubKeyKey = 'voter_rsa_pub_key';

  // Using SecureStorageService for all storage operations

  // Stream controller for vote token availability notifications
  static final StreamController<VoteTokenEvent> _voteTokenController = 
      StreamController<VoteTokenEvent>.broadcast();

  /// Stream that emits when vote tokens become available for elections
  static Stream<VoteTokenEvent> get voteTokenStream => _voteTokenController.stream;

  /// Save initial voting session state when user selects election
  static Future<void> saveSession(
    Uint8List nonce,
    BlindingResult result,
    Uint8List hashBytes,
    String electionId,
    String rsaPubKey,
  ) async {
    debugPrint('💾 Saving initial voting session for election: $electionId');
    
    await SecureStorageService.write(key: _nonceKey, value: base64.encode(nonce));
    await SecureStorageService.write(
      key: _blindingResultKey,
      value: jsonEncode(result.toJson()),
    );
    await SecureStorageService.write(key: _hashBytesKey, value: base64.encode(hashBytes));
    await SecureStorageService.write(key: _electionIdKey, value: electionId);
    await SecureStorageService.write(key: _rsaPubKeyKey, value: rsaPubKey);
    
    // Store blinding secret (needed for later unblinding)
    await SecureStorageService.write(key: _blindingSecretKey, value: base64.encode(result.secret));
    
    // CRITICAL: Store the original randomizer used during blinding (this is the 'r' from Rust)
    // This must be the same randomizer that was used to create the blinded message
    if (result.messageRandomizer != null) {
      await SecureStorageService.write(key: _msgRandomizerKey, value: base64.encode(result.messageRandomizer!));
      debugPrint('🔐 Stored original blinding randomizer: ${result.messageRandomizer!.length} bytes');
    } else {
      debugPrint('⚠️ WARNING: No messageRandomizer in BlindingResult - this may cause vote verification issues');
    }
    
    debugPrint('✅ Initial session data saved successfully');
  }

  /// Save additional session data after receiving blind signature response
  static Future<void> saveBlindSignatureResponse(
    Uint8List blindSignature,
    Uint8List? messageRandomizer,
  ) async {
    debugPrint('💾 Saving blind signature response data');
    
    // Store the blind signature received from Election Coordinator
    await SecureStorageService.write(key: 'blind_signature', value: base64.encode(blindSignature));
    
    // NOTE: We do NOT overwrite the original randomizer here
    // The randomizer used in voting must be the same one used during blinding
    // which is already stored during saveSession()
    if (messageRandomizer != null) {
      debugPrint('🔍 EC provided messageRandomizer: ${messageRandomizer.length} bytes (not overwriting original)');
    }
    
    debugPrint('✅ Blind signature response saved successfully');
    
    // Emit vote token availability event
    final electionId = await getElectionId();
    if (electionId != null) {
      final event = VoteTokenEvent(
        electionId: electionId,
        isAvailable: true,
        timestamp: DateTime.now(),
      );
      _voteTokenController.add(event);
      debugPrint('📡 Emitted vote token available event for election: $electionId');
    }
  }

  static Future<Uint8List?> getNonce() async {
    final data = await SecureStorageService.read(key: _nonceKey);
    if (data == null) return null;
    return base64.decode(data);
  }

  static Future<BlindingResult?> getBlindingResult() async {
    final data = await SecureStorageService.read(key: _blindingResultKey);
    if (data == null) return null;
    return BlindingResult.fromJson(jsonDecode(data));
  }

  /// Get hash bytes (h_n_bytes equivalent from Rust)
  static Future<Uint8List?> getHashBytes() async {
    final data = await SecureStorageService.read(key: _hashBytesKey);
    if (data == null) return null;
    return base64.decode(data);
  }

  /// Get election ID for current session
  static Future<String?> getElectionId() async {
    return await SecureStorageService.read(key: _electionIdKey);
  }

  /// Get blinding secret for signature unblinding
  static Future<Uint8List?> getBlindingSecret() async {
    final data = await SecureStorageService.read(key: _blindingSecretKey);
    if (data == null) return null;
    return base64.decode(data);
  }

  /// Get message randomizer (r equivalent from Rust)
  static Future<Uint8List?> getMessageRandomizer() async {
    final data = await SecureStorageService.read(key: _msgRandomizerKey);
    if (data == null) return null;
    final decoded = base64.decode(data);
    // Return null if we stored empty bytes (indicating messageRandomizer was null)
    return decoded.isEmpty ? null : decoded;
  }

  /// Get RSA public key for current election
  static Future<String?> getRsaPubKey() async {
    return await SecureStorageService.read(key: _rsaPubKeyKey);
  }


  /// Clear all session data
  static Future<void> clearSession() async {
    debugPrint('🗑️ Clearing all voting session data');
    
    await SecureStorageService.delete(key: _nonceKey);
    await SecureStorageService.delete(key: _blindingResultKey);
    await SecureStorageService.delete(key: _hashBytesKey);
    await SecureStorageService.delete(key: _electionIdKey);
    await SecureStorageService.delete(key: _blindingSecretKey);
    await SecureStorageService.delete(key: _msgRandomizerKey);
    await SecureStorageService.delete(key: _rsaPubKeyKey);
    await SecureStorageService.delete(key: 'blind_signature');
    
    debugPrint('✅ Session data cleared successfully');
  }

  /// Check if initial session data exists (after election selection)
  static Future<bool> hasInitialSession() async {
    final nonce = await getNonce();
    final result = await getBlindingResult();
    final hashBytes = await getHashBytes();
    final electionId = await getElectionId();
    
    return nonce != null && result != null && hashBytes != null && electionId != null;
  }

  /// Check if complete session exists (after receiving blind signature response)
  static Future<bool> hasCompleteSession() async {
    final hasInitial = await hasInitialSession();
    final blindSig = await getBlindSignature();
    
    return hasInitial && blindSig != null;
  }

  /// Get stored blind signature from Election Coordinator
  static Future<Uint8List?> getBlindSignature() async {
    final data = await SecureStorageService.read(key: 'blind_signature');
    if (data == null) return null;
    return base64.decode(data);
  }

  /// Get complete session state (equivalent to Rust app variable)
  static Future<Map<String, dynamic>?> getCompleteSession() async {
    if (!(await hasInitialSession())) return null;
    
    return {
      'nonce': await getNonce(),
      'blindingResult': await getBlindingResult(),
      'hashBytes': await getHashBytes(),
      'electionId': await getElectionId(),
      'secret': await getBlindingSecret(),
      'messageRandomizer': await getMessageRandomizer(),
      'blindSignature': await getBlindSignature(),
      'rsaPubKey': await getRsaPubKey(),
    };
  }

  /// Validate session integrity
  static Future<bool> validateSession() async {
    try {
      final session = await getCompleteSession();
      if (session == null) return false;
      
      // Verify all required components exist
      final nonce = session['nonce'] as Uint8List?;
      final hashBytes = session['hashBytes'] as Uint8List?;
      final electionId = session['electionId'] as String?;
      final blindingResult = session['blindingResult'] as BlindingResult?;
      
      if (nonce == null || hashBytes == null || electionId == null || blindingResult == null) {
        return false;
      }
      
      // Verify hash bytes match hashed nonce
      final expectedHash = Uint8List.fromList(
        sha256.convert(nonce).bytes
      );
      
      if (hashBytes.length != expectedHash.length) return false;
      for (int i = 0; i < hashBytes.length; i++) {
        if (hashBytes[i] != expectedHash[i]) return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Dispose of the stream controller (call when app is closing)
  static void dispose() {
    _voteTokenController.close();
  }
}

/// Event class for vote token availability notifications
class VoteTokenEvent {
  final String electionId;
  final bool isAvailable;
  final DateTime timestamp;

  VoteTokenEvent({
    required this.electionId,
    required this.isAvailable,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'VoteTokenEvent(electionId: $electionId, isAvailable: $isAvailable, timestamp: $timestamp)';
  }
}
