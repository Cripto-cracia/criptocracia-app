import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:blind_rsa_signatures/blind_rsa_signatures.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: avoid_relative_lib_imports
import '../lib/services/crypto_service.dart';

/// Test to validate the vote service unblinding fix
/// This simulates the exact scenario where EC sends blind signature
/// and voter needs to unblind it before creating vote payload
void main() {
  group('Vote Service Unblinding Fix', () {
    test('Raw blind signature should be unblinded before sending to EC', () async {
      print('🧪 Testing Vote Service Unblinding Fix\n');
      
      // 1) Setup: Generate EC key pair and voter data
      print('📋 STEP 1: Setup cryptographic components');
      final keyPair = await KeyPair.generate(null, 2048);
      final ecPublicKey = keyPair.pk;
      final ecSecretKey = keyPair.sk;
      
      // Generate voter nonce and hash it
      final random = math.Random.secure();
      final nonce = Uint8List(16);
      for (int i = 0; i < nonce.length; i++) {
        nonce[i] = random.nextInt(256);
      }
      final hashBytes = Uint8List.fromList(sha256.convert(nonce).bytes);
      
      print('   ✅ EC key pair generated');
      print('   ✅ Voter nonce: ${nonce.length} bytes');
      print('   ✅ Hash bytes: ${hashBytes.length} bytes');
      
      // 2) Voter blinds the hash (what happens during token request)
      print('\n📋 STEP 2: Voter blinds hash and sends to EC');
      final blindingResult = ecPublicKey.blind(null, hashBytes, true, Options.defaultOptions);
      final blindedMessage = blindingResult.blindMessage;
      final secret = blindingResult.secret;
      final messageRandomizer = blindingResult.messageRandomizer!;
      
      print('   ✅ Hash blinded successfully');
      print('   ✅ Blinded message: ${blindedMessage.length} bytes');
      print('   ✅ Secret: ${secret.length} bytes');
      print('   ✅ Randomizer: ${messageRandomizer.length} bytes');
      
      // 3) EC signs the blinded message (what EC does)
      print('\n📋 STEP 3: EC signs blinded message');
      final rawBlindSignature = ecSecretKey.blindSign(null, blindedMessage, Options.defaultOptions);
      
      print('   ✅ Raw blind signature: ${rawBlindSignature.length} bytes');
      print('   🔍 This is what gets stored in VoterSessionService');
      
      // 4) Simulate the OLD broken approach (what was happening before)
      print('\n❌ STEP 4: OLD BROKEN APPROACH - Using raw blind signature directly');
      bool brokenVerification = false;
      try {
        final brokenSignature = Signature(rawBlindSignature);
        brokenVerification = brokenSignature.verify(
          ecPublicKey,
          messageRandomizer,
          hashBytes,
          Options.defaultOptions,
        );
        print('   Raw blind signature verification: $brokenVerification');
      } catch (e) {
        print('   ❌ Raw blind signature verification failed: $e');
      }
      
      // 5) Simulate the NEW fixed approach (what should happen now)
      print('\n✅ STEP 5: NEW FIXED APPROACH - Unblind signature first');
      
      // Use CryptoService.unblindSignature (what VoteService now does)
      final unblindedSignature = CryptoService.unblindSignature(
        rawBlindSignature,
        secret,
        messageRandomizer,
        hashBytes,
        ecPublicKey,
      );
      
      final voteToken = unblindedSignature.bytes;
      print('   ✅ Signature unblinded successfully');
      print('   ✅ Vote token: ${voteToken.length} bytes');
      
      // Verify the unblinded signature
      final tokenVerification = CryptoService.verifySignature(
        unblindedSignature,
        messageRandomizer,
        hashBytes,
        ecPublicKey,
      );
      
      print('   ✅ Vote token verification: $tokenVerification');
      
      // 6) Create vote payload as VoteService does
      print('\n📋 STEP 6: Create vote payload with unblinded signature');
      
      final hNBase64 = base64.encode(hashBytes);
      final tokenBase64 = base64.encode(voteToken); // Using UNBLINDED signature
      final rBase64 = base64.encode(messageRandomizer);
      final candidateId = 42;
      
      final votePayload = '$hNBase64:$tokenBase64:$rBase64:$candidateId';
      
      print('   ✅ Vote payload created');
      print('   ✅ h_n (Base64): ${hNBase64.substring(0, 20)}...');
      print('   ✅ token (Base64): ${tokenBase64.substring(0, 20)}...');
      print('   ✅ r (Base64): ${rBase64.substring(0, 20)}...');
      print('   ✅ candidate_id: $candidateId');
      print('   ✅ Payload length: ${votePayload.length} chars');
      
      // 7) Simulate EC verification (what Rust EC does)
      print('\n📋 STEP 7: Simulate Rust EC verification');
      
      // Parse the vote payload
      final parts = votePayload.split(':');
      final receivedHN = base64.decode(parts[0]);
      final receivedToken = base64.decode(parts[1]);
      final receivedR = base64.decode(parts[2]);
      final receivedCandidate = int.parse(parts[3]);
      
      print('   ✅ Parsed vote payload:');
      print('      h_n: ${receivedHN.length} bytes');
      print('      token: ${receivedToken.length} bytes');
      print('      r: ${receivedR.length} bytes');
      print('      candidate: $receivedCandidate');
      
      // Verify as Rust EC would
      final ecReceivedSignature = Signature(receivedToken);
      final ecVerification = ecReceivedSignature.verify(
        ecPublicKey,
        receivedR,
        receivedHN,
        Options.defaultOptions,
      );
      
      print('   🎯 EC verification result: $ecVerification');
      
      // 8) Assertions
      print('\n🎉 ASSERTIONS:');
      expect(brokenVerification, false, reason: 'Raw blind signature should fail verification');
      expect(tokenVerification, true, reason: 'Unblinded signature should pass verification');
      expect(ecVerification, true, reason: 'EC should be able to verify the vote');
      
      print('   ❌ Raw blind signature verification: $brokenVerification (expected)');
      print('   ✅ Unblinded signature verification: $tokenVerification');
      print('   ✅ EC verification of vote: $ecVerification');
      
      if (ecVerification) {
        print('\n🎯 SUCCESS! The fix works correctly.');
        print('   Dart voter can now send votes that Rust EC will accept.');
      } else {
        print('\n❌ FAILURE! Something is still wrong.');
      }
    });
  });
}