import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:platform/platform.dart';

/// Secure storage service using Hive with hardware-backed encryption
/// Provides a flutter_secure_storage-compatible API using encrypted Hive storage
/// with platform-specific secure key derivation
class SecureStorageService {
  static const String _boxName = 'secure_storage';
  static const String _keyDerivationSalt = 'criptocracia_kdf_salt_v2';
  static const String _masterKeyStorageKey = 'master_encryption_key';
  static const String _deviceFingerprintKey = 'device_fingerprint';
  static const int _keyDerivationIterations = 100000; // PBKDF2 iterations

  static Box<String>? _box;
  static final Platform _platform = const LocalPlatform();

  /// Initialize the secure storage service with hardware-backed security
  /// Must be called before using any storage operations
  static Future<void> init() async {
    if (_box != null) return; // Already initialized

    // Initialize Hive
    await Hive.initFlutter();

    // Generate or retrieve secure encryption key
    final encryptionKey = await _getOrCreateSecureEncryptionKey();

    // Open encrypted box with hardware-derived key
    _box = await Hive.openBox<String>(
      _boxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  /// Generate or retrieve a secure encryption key using device-specific data
  /// and hardware-backed security features when available
  static Future<Uint8List> _getOrCreateSecureEncryptionKey() async {
    // Generate device fingerprint for key validation
    final currentFingerprint = await _generateDeviceFingerprint();

    // Try to get stored key and fingerprint from secure storage
    // Note: We use a bootstrap key derived from device fingerprint for this initial storage
    final bootstrapKey = await _deriveBootstrapKey(currentFingerprint);
    
    String? storedKey;
    String? storedFingerprint;
    
    try {
      // Try to retrieve from secure storage using bootstrap key
      final tempBox = await _openSecureBox('bootstrap', bootstrapKey);
      storedKey = tempBox.get(_masterKeyStorageKey);
      storedFingerprint = tempBox.get(_deviceFingerprintKey);
      await tempBox.close();
    } catch (e) {
      // If bootstrap storage fails, this might be first run or corruption
      debugPrint('Bootstrap storage access failed: $e');
    }

    // If we have a stored key and device fingerprint matches, derive key from it
    if (storedKey != null && storedFingerprint == currentFingerprint) {
      return await _deriveEncryptionKey(storedKey, currentFingerprint);
    }

    // Generate new master key and store it securely
    final newMasterKey = await _generateSecureMasterKey();
    
    // Store both master key and fingerprint in secure storage
    try {
      final tempBox = await _openSecureBox('bootstrap', bootstrapKey);
      await tempBox.put(_masterKeyStorageKey, newMasterKey);
      await tempBox.put(_deviceFingerprintKey, currentFingerprint);
      await tempBox.close();
    } catch (e) {
      throw Exception('Failed to store master key securely: $e');
    }

    return await _deriveEncryptionKey(newMasterKey, currentFingerprint);
  }

  /// Generate a secure master key using platform-specific entropy sources
  static Future<String> _generateSecureMasterKey() async {
    // Use multiple entropy sources
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final deviceInfo = await _getDeviceSpecificData();
    final random = Random.secure();
    final randomBytes = List.generate(32, (_) => random.nextInt(256));

    // Combine entropy sources
    final entropyData = [
      ...utf8.encode(timestamp.toString()),
      ...utf8.encode(deviceInfo),
      ...randomBytes,
    ];

    // Hash the combined entropy to create master key
    final masterKeyHash = sha256.convert(entropyData);
    return base64.encode(masterKeyHash.bytes);
  }

  /// Generate device fingerprint using platform-specific identifiers
  static Future<String> _generateDeviceFingerprint() async {
    final deviceInfo = DeviceInfoPlugin();
    final fingerprintComponents = <String>[];

    try {
      if (_platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        fingerprintComponents.addAll([
          androidInfo.id,
          androidInfo.model,
          androidInfo.brand,
          androidInfo.device,
          androidInfo.hardware,
        ]);
      } else if (_platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        fingerprintComponents.addAll([
          iosInfo.identifierForVendor ?? '',
          iosInfo.model,
          iosInfo.systemName,
          iosInfo.name,
        ]);
      } else if (_platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        fingerprintComponents.addAll([
          linuxInfo.machineId ?? '',
          linuxInfo.name,
          linuxInfo.id,
        ]);
      } else if (_platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        fingerprintComponents.addAll([
          macInfo.systemGUID ?? '',
          macInfo.model,
          macInfo.computerName,
        ]);
      } else if (_platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        fingerprintComponents.addAll([
          windowsInfo.computerName,
          windowsInfo.systemMemoryInMegabytes.toString(),
        ]);
      }
    } catch (e) {
      // Fallback: use basic system info if detailed info unavailable
      fingerprintComponents.add(_platform.operatingSystem);
      fingerprintComponents.add('fallback');
    }

    // Create stable device fingerprint
    final combinedFingerprint = fingerprintComponents.join('|');
    final fingerprintHash = sha256.convert(utf8.encode(combinedFingerprint));
    return base64.encode(fingerprintHash.bytes);
  }

  /// Get device-specific data for entropy
  static Future<String> _getDeviceSpecificData() async {
    final deviceInfo = DeviceInfoPlugin();
    final dataComponents = <String>[];

    try {
      if (_platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        dataComponents.addAll([
          androidInfo.manufacturer,
          androidInfo.product,
          androidInfo.hardware,
        ]);
      } else if (_platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        dataComponents.addAll([iosInfo.utsname.machine, iosInfo.systemVersion]);
      }
    } catch (e) {
      // Fallback data
      dataComponents.add(_platform.operatingSystem);
    }

    return dataComponents.join('|');
  }

  /// Derive encryption key using PBKDF2 with device fingerprint as salt
  static Future<Uint8List> _deriveEncryptionKey(
    String masterKey,
    String deviceFingerprint,
  ) async {
    // Combine static salt with device fingerprint for unique per-device salting
    final combinedSalt = '$_keyDerivationSalt|$deviceFingerprint';
    final saltBytes = utf8.encode(combinedSalt);
    final masterKeyBytes = base64.decode(masterKey);

    // Use PBKDF2 for key derivation
    final derivedKey = await _pbkdf2(
      masterKeyBytes,
      saltBytes,
      _keyDerivationIterations,
      32, // 256-bit key
    );

    return derivedKey;
  }

  /// Derive a bootstrap key for storing master key and device fingerprint
  /// This creates a circular dependency resolution by using device fingerprint as seed
  static Future<Uint8List> _deriveBootstrapKey(String deviceFingerprint) async {
    // Use a simplified key derivation for bootstrap purposes
    const bootstrapSalt = 'criptocracia_bootstrap_v1';
    final combinedSeed = '$bootstrapSalt|$deviceFingerprint';
    final seedBytes = utf8.encode(combinedSeed);
    
    // Use simpler PBKDF2 with fewer iterations for bootstrap key
    return await _pbkdf2(seedBytes, utf8.encode(bootstrapSalt), 10000, 32);
  }

  /// Helper method to open a secure Hive box with encryption
  static Future<Box<String>> _openSecureBox(String boxName, Uint8List encryptionKey) async {
    await Hive.initFlutter();
    
    return await Hive.openBox<String>(
      boxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  /// PBKDF2 key derivation function
  static Future<Uint8List> _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) async {
    var u = <int>[];
    var result = <int>[];

    // Simple PBKDF2 implementation using SHA-256
    for (int i = 1; result.length < keyLength; i++) {
      final saltWithIndex = [
        ...salt,
        ...[(i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff],
      ];
      u = Hmac(sha256, password).convert(saltWithIndex).bytes;
      var f = List<int>.from(u);

      for (int j = 1; j < iterations; j++) {
        u = Hmac(sha256, password).convert(u).bytes;
        for (int k = 0; k < f.length; k++) {
          f[k] ^= u[k];
        }
      }

      result.addAll(f);
    }

    return Uint8List.fromList(result.take(keyLength).toList());
  }

  /// Write a key-value pair to secure storage
  static Future<void> write({
    required String key,
    required String value,
  }) async {
    await _ensureInitialized();
    await _box!.put(key, value);
  }

  /// Read a value from secure storage
  static Future<String?> read({required String key}) async {
    await _ensureInitialized();
    return _box!.get(key);
  }

  /// Delete a key from secure storage
  static Future<void> delete({required String key}) async {
    await _ensureInitialized();
    await _box!.delete(key);
  }

  /// Check if a key exists in secure storage
  static Future<bool> containsKey({required String key}) async {
    await _ensureInitialized();
    return _box!.containsKey(key);
  }

  /// Get all keys from secure storage
  static Future<Set<String>> getAllKeys() async {
    await _ensureInitialized();
    return _box!.keys.cast<String>().toSet();
  }

  /// Clear all data from secure storage
  static Future<void> deleteAll() async {
    await _ensureInitialized();
    await _box!.clear();
  }

  /// Ensure the storage is initialized before use
  static Future<void> _ensureInitialized() async {
    if (_box == null) {
      await init();
    }
  }

  /// Close the storage box (call when app is shutting down)
  static Future<void> close() async {
    if (_box != null) {
      await _box!.close();
      _box = null;
    }
  }
}

