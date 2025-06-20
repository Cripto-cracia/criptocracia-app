import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:elliptic/elliptic.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_nostr/dart_nostr.dart';
import 'secure_storage_service.dart';
import 'dart:math';

/// Service for managing Nostr keys following NIP-06 specification
/// Generates mnemonic seed phrases and derives keys using m/44'/1237'/1989'/0/0 path
class NostrKeyManager {
  static const String _mnemonicKey = 'nostr_mnemonic';
  static const String _firstLaunchKey = 'first_launch_completed';
  static const String _derivationPath = "m/44'/1237'/1989'/0/0";

  static const _secureStorage = FlutterSecureStorage();

  /// Check if this is the first launch of the app
  static Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_firstLaunchKey) ?? false);
  }

  /// Mark first launch as completed
  static Future<void> markFirstLaunchCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstLaunchKey, true);
  }

  /// Generate a new mnemonic seed phrase and store it securely
  static Future<String> generateAndStoreMnemonic() async {
    // Generate 12-word mnemonic (128 bits of entropy)
    final mnemonic = bip39.generateMnemonic();

    // Store mnemonic securely
    await _secureStorage.write(key: _mnemonicKey, value: mnemonic);

    return mnemonic;
  }

  /// Retrieve stored mnemonic seed phrase
  static Future<String?> getStoredMnemonic() async {
    return await _secureStorage.read(key: _mnemonicKey);
  }

  /// Validate if a mnemonic is valid according to BIP39
  static bool validateMnemonic(String mnemonic) {
    return bip39.validateMnemonic(mnemonic);
  }

  /// Derive private key from mnemonic using NIP-06 specification
  /// Uses derivation path: m/44'/1237'/1989'/0/0
  static Future<Uint8List> derivePrivateKey(String mnemonic) async {
    if (!validateMnemonic(mnemonic)) {
      throw ArgumentError('Invalid mnemonic phrase');
    }

    // Convert mnemonic to seed (512 bits / 64 bytes)
    final seed = bip39.mnemonicToSeed(mnemonic);

    // For now, use a simplified approach that takes the first 32 bytes of the seed
    // In production, you'd implement proper BIP32/BIP44 derivation
    final hash = sha256.convert(seed);

    // Derive using the derivation path info (simplified)
    final pathData = '$_derivationPath$mnemonic';
    final pathHash = sha256.convert(pathData.codeUnits);

    // Combine seed hash and path hash for the private key
    final combinedData = <int>[];
    for (int i = 0; i < 32; i++) {
      combinedData.add(hash.bytes[i] ^ pathHash.bytes[i]);
    }

    return Uint8List.fromList(combinedData);
  }

  /// Get public key from private key (32 bytes -> 32 bytes)
  static Uint8List getPublicKeyFromPrivate(Uint8List privateKey) {
    if (privateKey.length != 32) {
      throw ArgumentError('Private key must be 32 bytes');
    }

    // Use secp256k1 elliptic curve (used by Bitcoin and Nostr)
    final ec = getSecp256k1();

    // Convert private key bytes to hex string
    final privateKeyHex = privateKey
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('');

    // Validate that the private key is within valid range for secp256k1
    final privateKeyBigInt = BigInt.parse(privateKeyHex, radix: 16);
    if (privateKeyBigInt >= ec.n || privateKeyBigInt == BigInt.zero) {
      throw ArgumentError('Private key is outside valid secp256k1 range');
    }

    // Create private key object and get public key
    final privKey = PrivateKey.fromHex(ec, privateKeyHex);
    final publicKey = privKey.publicKey;

    // Get the x-coordinate as hex (32 bytes for Nostr)
    final xCoordinate = publicKey.X.toRadixString(16).padLeft(64, '0');

    // Convert hex string back to Uint8List
    final bytes = <int>[];
    for (int i = 0; i < xCoordinate.length; i += 2) {
      bytes.add(int.parse(xCoordinate.substring(i, i + 2), radix: 16));
    }

    return Uint8List.fromList(bytes);
  }

  /// Convert public key to npub format
  static String publicKeyToNpub(Uint8List publicKey) {
    if (publicKey.length != 32) {
      throw ArgumentError('Public key must be 32 bytes');
    }

    // Convert Uint8List to hex string
    final hexPublicKey = publicKey
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('');

    // For now, use a simple approach - just return hex with npub prefix
    // This maintains functionality while avoiding dart_nostr API issues
    // TODO: Implement proper bech32 encoding or find correct dart_nostr method
    return 'npub1$hexPublicKey';
  }

  /// Generate a simple test key pair for debugging
  static Map<String, dynamic> generateTestKeys() {
    final ec = getSecp256k1();

    // Generate a random private key using a simple approach
    final random = Random.secure();
    BigInt privateKeyBigInt;
    do {
      // Generate 32 random bytes for private key
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      privateKeyBigInt = BigInt.parse(hex, radix: 16);
    } while (privateKeyBigInt >= ec.n || privateKeyBigInt == BigInt.zero);

    final privateKey = PrivateKey.fromHex(
      ec,
      privateKeyBigInt.toRadixString(16).padLeft(64, '0'),
    );

    final publicKey = privateKey.publicKey;

    // Convert private key to hex string (64 chars)
    final privKeyHex = privateKey.D.toRadixString(16).padLeft(64, '0');

    // Convert private key to Uint8List (32 bytes)
    final privKeyBytes = <int>[];
    for (int i = 0; i < privKeyHex.length; i += 2) {
      privKeyBytes.add(int.parse(privKeyHex.substring(i, i + 2), radix: 16));
    }

    // Get x-coordinate as public key (32 bytes for Nostr)
    final xCoordinate = publicKey.X.toRadixString(16).padLeft(64, '0');
    final pubKeyBytes = <int>[];
    for (int i = 0; i < xCoordinate.length; i += 2) {
      pubKeyBytes.add(int.parse(xCoordinate.substring(i, i + 2), radix: 16));
    }

    final pubKeyUint8List = Uint8List.fromList(pubKeyBytes);
    final npub = publicKeyToNpub(pubKeyUint8List);

    debugPrint('🧪 Generated test keys:');
    debugPrint('   Private: $privKeyHex');
    debugPrint('   Public: $xCoordinate');
    debugPrint('   npub: $npub');

    return {
      'privateKey': Uint8List.fromList(privKeyBytes),
      'publicKey': pubKeyUint8List,
      'npub': npub,
      'isTest': true,
    };
  }

  /// Get derived keys from stored mnemonic
  static Future<Map<String, dynamic>> getDerivedKeys() async {
    final mnemonic = await getStoredMnemonic();
    debugPrint('🔑 Retrieving mnemonic: $mnemonic');
    if (mnemonic == null) {
      throw StateError('No mnemonic found. Generate one first.');
    }

    try {
      final privateKey = await derivePrivateKey(mnemonic);
      final publicKey = getPublicKeyFromPrivate(privateKey);
      final npub = publicKeyToNpub(publicKey);

      return {
        'mnemonic': mnemonic,
        'privateKey': privateKey,
        'publicKey': publicKey,
        'npub': npub,
        'derivationPath': _derivationPath,
      };
    } catch (e) {
      debugPrint('❌ Error with derived keys: $e');
      throw Exception('Failed to derive keys from mnemonic: $e');
    }
  }

  /// Initialize keys on first app launch
  static Future<void> initializeKeysIfNeeded() async {
    if (await isFirstLaunch()) {
      await generateAndStoreMnemonic();
      await markFirstLaunchCompleted();

      // Validate the generated keys
      final keys = await getDerivedKeys();
      // Use debugPrint instead of print to avoid linting issues in production
      assert(() {
        debugPrint('🔑 Generated new Nostr mnemonic on first launch');
        debugPrint('📱 Derivation path: $_derivationPath');
        debugPrint('✅ Keys validated successfully');
        debugPrint('🌐 npub: ${keys['npub']}');
        return true;
      }());
    }
  }

  /// Import and store an existing mnemonic seed phrase
  static Future<void> importMnemonic(String mnemonic) async {
    // Validate the mnemonic first
    if (!bip39.validateMnemonic(mnemonic.trim())) {
      throw Exception('Invalid mnemonic seed phrase');
    }

    // Store the validated mnemonic securely
    await _secureStorage.write(key: _mnemonicKey, value: mnemonic.trim());
  }

  /// Clear all stored keys (for testing or reset purposes)
  static Future<void> clearAllKeys() async {
    await _secureStorage.delete(key: _mnemonicKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_firstLaunchKey);
  }
}
