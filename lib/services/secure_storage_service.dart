import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Secure storage service using Hive with encryption
/// Provides a flutter_secure_storage-compatible API using encrypted Hive storage
class SecureStorageService {
  static const String _boxName = 'secure_storage';
  static const String _appSecret = 'criptocracia_secure_key_v1';
  static Box<String>? _box;

  /// Initialize the secure storage service
  /// Must be called before using any storage operations
  static Future<void> init() async {
    if (_box != null) return; // Already initialized

    // Initialize Hive
    await Hive.initFlutter();

    // Generate encryption key from app secret
    final encryptionKey = _generateEncryptionKey(_appSecret);

    // Open encrypted box
    _box = await Hive.openBox<String>(
      _boxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  /// Generate a 256-bit encryption key from app secret
  static Uint8List _generateEncryptionKey(String secret) {
    // Use PBKDF2 to derive a secure key from the app secret
    final salt = utf8.encode('criptocracia_salt_2024');
    final secretBytes = utf8.encode(secret);
    
    // Simple key derivation - in production you might want to use a proper PBKDF2
    final combined = [...secretBytes, ...salt];
    final digest = sha256.convert(combined);
    
    return Uint8List.fromList(digest.bytes);
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

/// Options classes for compatibility with flutter_secure_storage API
class AndroidOptions {
  final bool encryptedSharedPreferences;
  
  const AndroidOptions({this.encryptedSharedPreferences = false});
}

class IOSOptions {
  final String? groupId;
  
  const IOSOptions({this.groupId});
}

/// Flutter secure storage compatible wrapper
class FlutterSecureStorage {
  final AndroidOptions? aOptions;
  final IOSOptions? iOptions;

  const FlutterSecureStorage({
    this.aOptions,
    this.iOptions,
  });

  Future<void> write({required String key, required String value}) async {
    await SecureStorageService.write(key: key, value: value);
  }

  Future<String?> read({required String key}) async {
    return await SecureStorageService.read(key: key);
  }

  Future<void> delete({required String key}) async {
    await SecureStorageService.delete(key: key);
  }

  Future<bool> containsKey({required String key}) async {
    return await SecureStorageService.containsKey(key: key);
  }

  Future<Map<String, String>> readAll() async {
    final keys = await SecureStorageService.getAllKeys();
    final result = <String, String>{};
    
    for (final key in keys) {
      final value = await SecureStorageService.read(key: key);
      if (value != null) {
        result[key] = value;
      }
    }
    
    return result;
  }

  Future<void> deleteAll() async {
    await SecureStorageService.deleteAll();
  }
}