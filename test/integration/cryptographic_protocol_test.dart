import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:blind_rsa_signatures/blind_rsa_signatures.dart';
import 'package:crypto/crypto.dart';

/// Direct cryptographic protocol test using blind_rsa_signatures library only
/// This test simulates the complete voting flow as described in the protocol:
/// 1. Voter generates nonce and blinds it
/// 2. EC signs the blinded message
/// 3. Voter unblinds and verifies the signature
/// 4. Vote is created and validated by EC
void main() {
  group('Cryptographic Protocol (Direct Library)', () {
    late PublicKey ecPublicKey;
    late SecretKey ecSecretKey;
    const int candidateId = 42;

    setUpAll(() async {
      // Generate EC's RSA key pair for testing
      final keyPair = await KeyPair.generate(null, 2048);
      ecPublicKey = keyPair.pk;
      ecSecretKey = keyPair.sk;

      print('🔐 Generated EC RSA key pair for testing');
      print('   Key pair generated successfully');
    });

    test('Complete cryptographic voting protocol', () async {
      print('\n🗳️ === COMPLETE CRYPTOGRAPHIC PROTOCOL TEST ===');

      // ========================================
      // STEP 1: Voter Side - Blind Signature Request
      // ========================================
      print(
        '\n📋 STEP 1: Voter generates nonce and creates blind signature request',
      );

      // 1.1) Voter generates a random nonce (128-bit BigUint)
      final random = Random.secure();
      final nonce = Uint8List(16); // 128-bit nonce
      for (int i = 0; i < nonce.length; i++) {
        nonce[i] = random.nextInt(256);
      }
      print('✅ Generated nonce: ${nonce.length} bytes');
      expect(
        nonce.length,
        equals(16),
        reason: 'Nonce should be 128 bits (16 bytes)',
      );

      // 1.2) Voter computes h_n = SHA256(nonce)
      final hashedNonce = Uint8List.fromList(sha256.convert(nonce).bytes);
      print('✅ Computed h_n = SHA256(nonce): ${hashedNonce.length} bytes');
      expect(
        hashedNonce.length,
        equals(32),
        reason: 'SHA256 hash should be 32 bytes',
      );

      // 1.3) Voter blinds h_n using EC's RSA public key
      final blindingResult = ecPublicKey.blind(
        null,
        hashedNonce,
        true, // IMPORTANT: true enables randomizer generation
        Options.defaultOptions,
      );
      print('✅ Blinded h_n successfully');
      print('   Blinded message: ${blindingResult.blindMessage.length} bytes');
      print(
        '   Secret (blinding factor): ${blindingResult.secret.length} bytes',
      );
      print(
        '   Message randomizer: ${blindingResult.messageRandomizer?.length ?? 'NULL'}',
      );

      // Verify blinding result structure
      expect(blindingResult.blindMessage.length, greaterThan(0));
      expect(blindingResult.secret.length, greaterThan(0));

      // ========================================
      // STEP 2: EC Side - Blind Signature Issuance
      // ========================================
      print('\n🏛️ STEP 2: Election Coordinator signs blinded message');

      // 2.1) EC receives blinded_h_n (simulating message from voter)
      final receivedBlindedMessage = blindingResult.blindMessage;
      print(
        '✅ EC received blinded message: ${receivedBlindedMessage.length} bytes',
      );

      // 2.2) EC signs the blinded message using its RSA secret key
      // This simulates the Rust EC code: election.issue_token(req, sk.clone())
      final blindSignature = ecSecretKey.blindSign(
        null,
        receivedBlindedMessage,
        Options.defaultOptions,
      );
      print('✅ EC issued blind signature: ${blindSignature.length} bytes');
      expect(
        blindSignature.length,
        greaterThan(0),
        reason: 'Blind signature should not be empty',
      );

      // ========================================
      // STEP 3: Voter Side - Unblinding and Verification
      // ========================================
      print('\n🔓 STEP 3: Voter unblinds signature and verifies token');

      // 3.1) Voter unblinds the blind signature using stored blinding factor
      final unblindedSignature = ecPublicKey.finalize(
        blindSignature,
        blindingResult.secret,
        blindingResult.messageRandomizer,
        hashedNonce,
        Options.defaultOptions,
      );
      print('✅ Signature unblinded successfully');

      // 3.2) Voter verifies the token against EC's public RSA key
      final isTokenValid = unblindedSignature.verify(
        ecPublicKey,
        blindingResult.messageRandomizer,
        hashedNonce,
        Options.defaultOptions,
      );

      expect(isTokenValid, isTrue, reason: 'Vote token should be valid');
      print('✅ Vote token verified successfully');

      // ========================================
      // STEP 4: Vote Creation and Packaging
      // ========================================
      print('\n🗳️ STEP 4: Voter creates vote payload');

      // 4.1) Package vote in colon-delimited format: h_n:token:r:candidate_id
      final tokenBytes = unblindedSignature.bytes;
      final randomizerBytes = blindingResult.messageRandomizer ?? Uint8List(0);

      final hNBase64 = base64.encode(hashedNonce);
      final tokenBase64 = base64.encode(tokenBytes);
      final rBase64 = randomizerBytes.isNotEmpty
          ? base64.encode(randomizerBytes)
          : '';
      final votePayload = '$hNBase64:$tokenBase64:$rBase64:$candidateId';

      print('✅ Created vote payload');
      print('   h_n (Base64): ${hNBase64.substring(0, 20)}...');
      print('   token (Base64): ${tokenBase64.substring(0, 20)}...');
      print(
        '   r (Base64): ${rBase64.length > 0 ? rBase64.substring(0, 20) : 'EMPTY'}...',
      );
      print('   candidate_id: $candidateId');
      print('   Total payload length: ${votePayload.length} chars');

      // ========================================
      // STEP 5: EC Side - Vote Verification
      // ========================================
      print('\n🔍 STEP 5: Election Coordinator verifies vote');

      // 5.1) EC parses vote payload
      final payloadParts = votePayload.split(':');
      expect(
        payloadParts.length,
        equals(4),
        reason: 'Vote payload should have 4 parts',
      );

      final receivedHN = base64.decode(payloadParts[0]);
      final receivedToken = base64.decode(payloadParts[1]);
      final receivedR = payloadParts[2].isNotEmpty
          ? base64.decode(payloadParts[2])
          : Uint8List(0);
      final receivedCandidateId = int.parse(payloadParts[3]);

      print('✅ Parsed vote payload');
      print('   Received h_n: ${receivedHN.length} bytes');
      print('   Received token: ${receivedToken.length} bytes');
      print('   Received r: ${receivedR.length} bytes');
      print('   Received candidate ID: $receivedCandidateId');

      // 5.2) EC verifies the signature using signature.verify() as described in protocol
      final receivedSignature = Signature(receivedToken);
      final isVoteValid = receivedSignature.verify(
        ecPublicKey,
        receivedR,
        receivedHN,
        Options.defaultOptions,
      );

      expect(isVoteValid, isTrue, reason: 'Vote signature should be valid');
      print('✅ Vote signature verified by EC');

      // 5.3) Additional validation checks
      expect(
        receivedCandidateId,
        equals(candidateId),
        reason: 'Candidate ID should match',
      );
      expect(
        receivedHN,
        equals(hashedNonce),
        reason: 'Hash should match original h_n',
      );
      expect(
        receivedToken,
        equals(tokenBytes),
        reason: 'Token should match unblinded signature',
      );

      print('✅ All validation checks passed');

      // ========================================
      // PROTOCOL VERIFICATION SUMMARY
      // ========================================
      print('\n🎉 === PROTOCOL VERIFICATION COMPLETE ===');

      print('✅ Step 1 - Nonce generation and blinding: PASSED');
      print('✅ Step 2 - EC blind signature issuance: PASSED');
      print('✅ Step 3 - Signature unblinding and verification: PASSED');
      print('✅ Step 4 - Vote payload creation: PASSED');
      print('✅ Step 5 - EC vote verification: PASSED');

      print('\n🎯 CRYPTOGRAPHIC PROTOCOL: COMPLETE SUCCESS');
      print(
        '   All steps of the blind signature voting protocol executed correctly',
      );
      print('   Vote is cryptographically valid and can be counted by EC');
    });

    test('Invalid signature is rejected by EC', () async {
      print('\n🚫 === INVALID SIGNATURE REJECTION TEST ===');

      // Create a valid nonce and hash
      final random = Random.secure();
      final nonce = Uint8List(16);
      for (int i = 0; i < nonce.length; i++) {
        nonce[i] = random.nextInt(256);
      }
      final hashedNonce = Uint8List.fromList(sha256.convert(nonce).bytes);

      // Create INVALID vote payload with corrupted signature
      final invalidTokenBytes = Uint8List.fromList(
        List.generate(256, (i) => i % 256),
      );
      final hNBase64 = base64.encode(hashedNonce);
      final invalidTokenBase64 = base64.encode(invalidTokenBytes);
      final invalidVotePayload = '$hNBase64:$invalidTokenBase64::$candidateId';

      // EC tries to verify invalid vote
      final payloadParts = invalidVotePayload.split(':');
      final receivedHN = base64.decode(payloadParts[0]);
      final receivedToken = base64.decode(payloadParts[1]);
      final receivedR = Uint8List(0); // Empty randomizer

      final invalidSignature = Signature(receivedToken);
      final isVoteValid = invalidSignature.verify(
        ecPublicKey,
        receivedR,
        receivedHN,
        Options.defaultOptions,
      );

      expect(
        isVoteValid,
        isFalse,
        reason: 'Invalid signature should be rejected',
      );
      print('✅ Invalid signature correctly rejected by EC');
    });

    test('Signature verification fails with wrong message', () async {
      print('\n🚫 === WRONG MESSAGE REJECTION TEST ===');

      // Create valid blind signature for one message
      final random = Random.secure();
      final nonce1 = Uint8List(16);
      for (int i = 0; i < nonce1.length; i++) {
        nonce1[i] = random.nextInt(256);
      }
      final hashedNonce1 = Uint8List.fromList(sha256.convert(nonce1).bytes);
      final blindingResult1 = ecPublicKey.blind(
        null,
        hashedNonce1,
        true,
        Options.defaultOptions,
      );

      final blindSignature1 = ecSecretKey.blindSign(
        null,
        blindingResult1.blindMessage,
        Options.defaultOptions,
      );

      final unblindedSignature1 = ecPublicKey.finalize(
        blindSignature1,
        blindingResult1.secret,
        blindingResult1.messageRandomizer,
        hashedNonce1,
        Options.defaultOptions,
      );

      // Try to verify against DIFFERENT message
      final nonce2 = Uint8List(16);
      for (int i = 0; i < nonce2.length; i++) {
        nonce2[i] = random.nextInt(256);
      }
      final hashedNonce2 = Uint8List.fromList(sha256.convert(nonce2).bytes);

      final isValid = unblindedSignature1.verify(
        ecPublicKey,
        blindingResult1.messageRandomizer ?? Uint8List(0),
        hashedNonce2, // Wrong message!
        Options.defaultOptions,
      );

      expect(
        isValid,
        isFalse,
        reason: 'Signature should not verify against wrong message',
      );
      print('✅ Signature correctly rejected for wrong message');
    });

    test('Message randomizer consistency check', () async {
      print('\n🔍 === RANDOMIZER CONSISTENCY TEST ===');

      final random = Random.secure();
      final nonce = Uint8List(16);
      for (int i = 0; i < nonce.length; i++) {
        nonce[i] = random.nextInt(256);
      }
      final hashedNonce = Uint8List.fromList(sha256.convert(nonce).bytes);
      final blindingResult = ecPublicKey.blind(
        null,
        hashedNonce,
        true,
        Options.defaultOptions,
      );

      print(
        '🔍 Blinding result randomizer: ${blindingResult.messageRandomizer?.length ?? 'NULL'}',
      );

      // This test documents the current behavior with the blind_rsa_signatures library
      if (blindingResult.messageRandomizer != null) {
        print(
          '✅ Message randomizer is available: ${blindingResult.messageRandomizer!.length} bytes',
        );

        // Complete the protocol with randomizer
        final blindSignature = ecSecretKey.blindSign(
          null,
          blindingResult.blindMessage,
          Options.defaultOptions,
        );

        final unblindedSignature = ecPublicKey.finalize(
          blindSignature,
          blindingResult.secret,
          blindingResult.messageRandomizer!,
          hashedNonce,
          Options.defaultOptions,
        );

        final isValid = unblindedSignature.verify(
          ecPublicKey,
          blindingResult.messageRandomizer!,
          hashedNonce,
          Options.defaultOptions,
        );

        expect(
          isValid,
          isTrue,
          reason: 'Signature should verify with proper randomizer',
        );
        print('✅ Protocol works correctly with randomizer');
      } else {
        print('⚠️ Message randomizer is NULL - library limitation detected');
        print('⚠️ This may cause issues in production voting verification');

        // Test fallback behavior
        final blindSignature = ecSecretKey.blindSign(
          null,
          blindingResult.blindMessage,
          Options.defaultOptions,
        );

        try {
          final unblindedSignature = ecPublicKey.finalize(
            blindSignature,
            blindingResult.secret,
            Uint8List(0), // Empty randomizer
            hashedNonce,
            Options.defaultOptions,
          );

          // This documents current behavior - may pass or fail depending on library
          print(
            '📋 Testing fallback behavior with empty randomizer: ${unblindedSignature.bytes.length} bytes',
          );
        } catch (e) {
          print('📋 Fallback behavior failed as expected: $e');
        }
      }
    });

    test('Complete end-to-end protocol without any helper functions', () async {
      print('\n🔬 === PURE LIBRARY API TEST ===');
      print('This test uses ONLY the blind_rsa_signatures library API');

      // Step 1: Generate voter nonce and hash it
      final random = Random.secure();
      final voterNonce = Uint8List(16);
      for (int i = 0; i < voterNonce.length; i++) {
        voterNonce[i] = random.nextInt(256);
      }
      final voterHashedNonce = Uint8List.fromList(
        sha256.convert(voterNonce).bytes,
      );
      print('✅ Voter generated nonce and computed hash');

      // Step 2: Voter creates blind signature request
      final voterBlindingResult = ecPublicKey.blind(
        null,
        voterHashedNonce,
        true,
        Options.defaultOptions,
      );
      print('✅ Voter created blind signature request');
      print(
        '   Blinded message: ${voterBlindingResult.blindMessage.length} bytes',
      );
      print('   Secret: ${voterBlindingResult.secret.length} bytes');
      print(
        '   Randomizer: ${voterBlindingResult.messageRandomizer?.length ?? 'NULL'}',
      );

      // Step 3: EC signs the blinded message
      final ecBlindSignature = ecSecretKey.blindSign(
        null,
        voterBlindingResult.blindMessage,
        Options.defaultOptions,
      );
      print('✅ EC signed blinded message');
      print('   Blind signature: ${ecBlindSignature.length} bytes');

      // Step 4: Voter unblinds the signature
      final voterFinalSignature = ecPublicKey.finalize(
        ecBlindSignature,
        voterBlindingResult.secret,
        voterBlindingResult.messageRandomizer,
        voterHashedNonce,
        Options.defaultOptions,
      );
      print('✅ Voter unblinded signature');

      // Step 5: Voter verifies their token
      final voterTokenValid = voterFinalSignature.verify(
        ecPublicKey,
        voterBlindingResult.messageRandomizer,
        voterHashedNonce,
        Options.defaultOptions,
      );
      expect(voterTokenValid, isTrue, reason: 'Voter token should be valid');
      print('✅ Voter verified their token');

      // Step 6: Create vote payload (h_n:token:r:candidate_id)
      final voteHN = base64.encode(voterHashedNonce);
      final voteToken = base64.encode(voterFinalSignature.bytes);
      final voteR = voterBlindingResult.messageRandomizer != null
          ? base64.encode(voterBlindingResult.messageRandomizer!)
          : '';
      final voteCandidate = '123';
      final fullVotePayload = '$voteHN:$voteToken:$voteR:$voteCandidate';
      print('✅ Created vote payload: ${fullVotePayload.length} chars');

      // Step 7: EC verifies the vote
      final voteComponents = fullVotePayload.split(':');
      final ecReceivedHN = base64.decode(voteComponents[0]);
      final ecReceivedToken = base64.decode(voteComponents[1]);
      final ecReceivedR = voteComponents[2].isNotEmpty
          ? base64.decode(voteComponents[2])
          : Uint8List(0);
      final ecReceivedCandidate = voteComponents[3];

      final ecVoteSignature = Signature(ecReceivedToken);
      final ecVoteValid = ecVoteSignature.verify(
        ecPublicKey,
        ecReceivedR,
        ecReceivedHN,
        Options.defaultOptions,
      );

      expect(ecVoteValid, isTrue, reason: 'EC should accept valid vote');
      expect(
        ecReceivedCandidate,
        equals('123'),
        reason: 'Candidate should match',
      );
      print('✅ EC verified and accepted vote');

      print('\n🎯 PURE LIBRARY API TEST: SUCCESS');
      print(
        '   Complete protocol executed using only blind_rsa_signatures library',
      );
      print('   No helper functions or external dependencies used');
    });

    test('Debug Rust EC verification issue', () async {
      print('\n🐛 === RUST EC VERIFICATION DEBUG TEST ===');
      print('This test replicates the exact scenario from mobile app logs');

      // Replicate exact scenario from mobile logs
      final random = Random.secure();
      final voterNonce = Uint8List(16);
      for (int i = 0; i < voterNonce.length; i++) {
        voterNonce[i] = random.nextInt(256);
      }
      
      final voterHashedNonce = Uint8List.fromList(sha256.convert(voterNonce).bytes);
      print('🔍 Generated voter nonce and hash');
      print('   Nonce: ${voterNonce.length} bytes');
      print('   Hash: ${voterHashedNonce.length} bytes');

      // Blind with randomizer enabled (as fixed in CryptoService)
      final blindingResult = ecPublicKey.blind(
        null,
        voterHashedNonce,
        true, // This is the fix that enables randomizer
        Options.defaultOptions,
      );
      
      print('🔍 Blinding result:');
      print('   Blinded message: ${blindingResult.blindMessage.length} bytes');
      print('   Secret: ${blindingResult.secret.length} bytes');
      print('   Randomizer: ${blindingResult.messageRandomizer?.length ?? 'NULL'} bytes');
      
      expect(blindingResult.messageRandomizer, isNotNull, 
        reason: 'Randomizer should be generated with third parameter = true');
      expect(blindingResult.messageRandomizer!.length, equals(32),
        reason: 'Randomizer should be 32 bytes');

      // EC signs the blinded message
      final blindSignature = ecSecretKey.blindSign(
        null,
        blindingResult.blindMessage,
        Options.defaultOptions,
      );
      print('🔍 EC blind signature: ${blindSignature.length} bytes');

      // Voter unblinds the signature
      final unblindedSignature = ecPublicKey.finalize(
        blindSignature,
        blindingResult.secret,
        blindingResult.messageRandomizer!,
        voterHashedNonce,
        Options.defaultOptions,
      );
      print('🔍 Unblinded signature: ${unblindedSignature.bytes.length} bytes');

      // Test different verification approaches to match Rust EC
      print('\n🧪 Testing different signature verification approaches:');

      // Approach 1: Standard verification (what mobile app does)
      final verifyResult1 = unblindedSignature.verify(
        ecPublicKey,
        blindingResult.messageRandomizer!,
        voterHashedNonce,
        Options.defaultOptions,
      );
      print('   Approach 1 (standard): $verifyResult1');

      // Approach 2: Try with empty randomizer (Rust might expect this)
      final verifyResult2 = unblindedSignature.verify(
        ecPublicKey,
        Uint8List(0), // Empty randomizer
        voterHashedNonce,
        Options.defaultOptions,
      );
      print('   Approach 2 (empty randomizer): $verifyResult2');

      // Approach 3: Try with original nonce instead of hash
      final verifyResult3 = unblindedSignature.verify(
        ecPublicKey,
        blindingResult.messageRandomizer!,
        voterNonce, // Original nonce, not hash
        Options.defaultOptions,
      );
      print('   Approach 3 (original nonce): $verifyResult3');

      // Create vote payload as mobile app does
      final voteHN = base64.encode(voterHashedNonce);
      final voteToken = base64.encode(unblindedSignature.bytes);
      final voteR = base64.encode(blindingResult.messageRandomizer!);
      const candidateId = 2; // Same as mobile logs
      final votePayload = '$voteHN:$voteToken:$voteR:$candidateId';
      
      print('\n🔍 Vote payload components:');
      print('   h_n (Base64): ${voteHN.substring(0, 20)}...');
      print('   token (Base64): ${voteToken.substring(0, 20)}...');
      print('   r (Base64): ${voteR.substring(0, 20)}...');
      print('   candidate_id: $candidateId');
      print('   Full payload length: ${votePayload.length} chars');

      // Parse payload as Rust EC would
      final payloadParts = votePayload.split(':');
      final ecReceivedHN = base64.decode(payloadParts[0]);
      final ecReceivedToken = base64.decode(payloadParts[1]);
      final ecReceivedR = base64.decode(payloadParts[2]);
      final ecReceivedCandidate = int.parse(payloadParts[3]);

      print('\n🔍 EC parsed components:');
      print('   Received h_n: ${ecReceivedHN.length} bytes');
      print('   Received token: ${ecReceivedToken.length} bytes');
      print('   Received r: ${ecReceivedR.length} bytes');
      print('   Received candidate: $ecReceivedCandidate');

      // Test EC verification (different approaches)
      final ecSignature = Signature(ecReceivedToken);
      
      print('\n🔍 EC verification tests:');
      
      // Test 1: With randomizer
      final ecVerify1 = ecSignature.verify(
        ecPublicKey,
        ecReceivedR,
        ecReceivedHN,
        Options.defaultOptions,
      );
      print('   EC Test 1 (with randomizer): $ecVerify1');

      // Test 2: Without randomizer
      final ecVerify2 = ecSignature.verify(
        ecPublicKey,
        Uint8List(0), // Empty randomizer
        ecReceivedHN,
        Options.defaultOptions,
      );
      print('   EC Test 2 (no randomizer): $ecVerify2');

      print('\n🔍 ANALYSIS:');
      if (verifyResult1 && ecVerify1) {
        print('✅ Both client and EC verification work with randomizer');
      } else if (verifyResult1 && !ecVerify1) {
        print('❌ Client verification works but EC fails - parameter mismatch');
        print('   This suggests Rust EC expects different verification parameters');
      } else {
        print('❌ Verification issue detected');
      }

      // The key insight: This test should reveal what the Rust EC expects
      print('\n💡 RECOMMENDATION:');
      print('   Check if Rust EC is using the randomizer correctly in verify()');
      print('   Dart: signature.verify(publicKey, randomizer, message, options)');
      print('   Rust: signature.verify() should use same parameter order');
    });
  });
}
