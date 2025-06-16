# RSA Blind Signature

A Dart library implementing David Chaum's RSA blind signature scheme. It can be used by clients and servers to issue and verify unlinkable tokens.

## Protocol Overview

A client asks a server to sign a message. The server receives the message and returns a signature. Using that `(message, signature)` pair, the client can locally compute a second valid `(message', signature')` pair. Anyone can verify that `(message', signature')` is valid for the server's public key, even though the server never saw that pair. However, no one besides the client can link `(message', signature')` to `(message, signature)`.

With this scheme a server can issue a token and later verify it without being able to link both actions to the same client.

1. The client creates a random message and blinds it with a secret factor.
2. The server signs the blind message and returns the blind signature.
3. The client unblinds the signature, obtaining a `(message, signature)` pair that anyone can verify.
4. Anyone, including the server, can later check that `(message, signature)` is valid without knowing when step 2 occurred.

Originally designed by David Chaum, this technique was used for anonymising DigiCash transactions.

## Usage

```dart
import 'dart:typed_data';
import 'package:rsa_blind_signature/rsa_blind_signature.dart';
import 'package:pointycastle/export.dart';

Future<void> main() async {
  // [SERVER]: Generate an RSA-2048 key pair
  final keyPair = await BlindSignature.generateKeyPair();
  final publicKey = keyPair.publicKey;
  final privateKey = keyPair.privateKey;

  // [CLIENT]: create a message and blind it
  final msg = Uint8List.fromList('test'.codeUnits);
  final blinding = BlindSignature.blindMessage(msg, publicKey);

  // [SERVER]: sign the blinded message
  final blindSig = BlindSignature.signBlindedMessage(blinding.blindedMessage, privateKey);

  // [CLIENT]: unblind and verify locally
  final sig = BlindSignature.unblindSignature(blindSig, blinding.blindingFactor, publicKey);
  final valid = BlindSignature.verifySignature(msg, sig, publicKey);
  print('Signature valid: \$valid');
}
```
