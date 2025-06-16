import 'dart:typed_data';

import '../config/app_config.dart';
import '../models/election.dart';
import '../models/voter.dart';
import 'blind_signature_service.dart';
import 'nostr_key_manager.dart';
import 'nostr_service.dart';

class TokenRequestService {
  final NostrService _nostrService = NostrService();

  Future<void> requestBlindSignature(Election election) async {
    await _nostrService.connect(AppConfig.relayUrl);

    final voter = Voter.generate();
    final rsaKey = BlindSignatureService.publicKeyFromPem(election.rsaPubKey);
    final result = BlindSignatureService.blindMessage(
      voter.hashedNonce,
      rsaKey,
    );

    final keys = await NostrKeyManager.getDerivedKeys();
    final privHex = _bytesToHex(keys['privateKey']);
    final pubHex = _bytesToHex(keys['publicKey']);

    await _nostrService.sendBlindSignatureRequest(
      ecPubKey: AppConfig.ecPublicKey,
      electionId: election.id,
      blindedNonce: result.blindedMessage,
      voterPrivKeyHex: privHex,
      voterPubKeyHex: pubHex,
    );
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
