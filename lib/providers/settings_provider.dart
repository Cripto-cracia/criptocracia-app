import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/relay_status.dart';
import '../services/nostr_service.dart';

class SettingsProvider with ChangeNotifier {
  SettingsProvider() {
    // Initialize with default values
  }

  /// Load settings from persistent storage
  Future<void> loadSettings() async {
    await _loadSettings();
  }

  // Storage keys
  static const String _relayUrlsKey = 'settings_relay_urls';
  static const String _ecPublicKeyKey = 'settings_ec_public_key';
  static const String _selectedLocaleKey = 'settings_selected_locale';

  final List<String> _relayUrls = List.from(AppConfig.relayUrls);
  String _ecPublicKey = AppConfig.ecPublicKey;
  Locale? _selectedLocale; // null means system default
  final Map<String, RelayStatus> _relayStatuses = {};
  Timer? _statusCheckTimer;
  
  // Getters
  List<String> get relayUrls => List.unmodifiable(_relayUrls);
  String get ecPublicKey => _ecPublicKey;
  Locale? get selectedLocale => _selectedLocale;
  Map<String, RelayStatus> get relayStatuses => Map.unmodifiable(_relayStatuses);

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }

  /// Load settings from persistent storage
  Future<void> _loadSettings() async {
    try {
      debugPrint('📖 Loading settings from persistent storage...');
      final prefs = await SharedPreferences.getInstance();
      
      // Load EC public key
      final savedEcKey = prefs.getString(_ecPublicKeyKey);
      if (savedEcKey != null && savedEcKey.isNotEmpty) {
        // Validate the saved key
        if (savedEcKey.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(savedEcKey)) {
          _ecPublicKey = savedEcKey;
          AppConfig.ecPublicKey = savedEcKey;
          debugPrint('✅ Loaded EC public key from storage');
        } else {
          debugPrint('⚠️ Invalid saved EC key format, using default');
        }
      } else {
        debugPrint('ℹ️ No saved EC public key found, using default');
      }
      
      // Load relay URLs
      final savedRelayUrls = prefs.getStringList(_relayUrlsKey);
      if (savedRelayUrls != null && savedRelayUrls.isNotEmpty) {
        _relayUrls.clear();
        _relayUrls.addAll(savedRelayUrls);
        AppConfig.relayUrls = List.from(_relayUrls);
        debugPrint('✅ Loaded ${savedRelayUrls.length} relay URLs from storage');
      } else {
        debugPrint('ℹ️ No saved relay URLs found, using defaults');
      }

      // Load selected locale
      final savedLocaleCode = prefs.getString(_selectedLocaleKey);
      if (savedLocaleCode != null && savedLocaleCode.isNotEmpty) {
        if (savedLocaleCode == 'system') {
          _selectedLocale = null; // System default
        } else {
          _selectedLocale = Locale(savedLocaleCode);
        }
        debugPrint('✅ Loaded locale from storage: $savedLocaleCode');
      } else {
        debugPrint('ℹ️ No saved locale found, using system default');
      }
      
      debugPrint('✅ Settings loaded successfully');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading settings: $e');
      // Continue with default values if loading fails
    }
  }

  /// Save EC public key to persistent storage
  Future<void> _saveEcPublicKey() async {
    try {
      debugPrint('💾 Saving EC public key to storage...');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ecPublicKeyKey, _ecPublicKey);
      debugPrint('✅ EC public key saved successfully');
    } catch (e) {
      debugPrint('❌ Error saving EC public key: $e');
    }
  }

  /// Save relay URLs to persistent storage
  Future<void> _saveRelayUrls() async {
    try {
      debugPrint('💾 Saving relay URLs to storage...');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_relayUrlsKey, _relayUrls);
      debugPrint('✅ Relay URLs saved successfully');
    } catch (e) {
      debugPrint('❌ Error saving relay URLs: $e');
    }
  }

  /// Save selected locale to persistent storage
  Future<void> _saveSelectedLocale() async {
    try {
      debugPrint('💾 Saving selected locale to storage...');
      final prefs = await SharedPreferences.getInstance();
      final localeCode = _selectedLocale?.languageCode ?? 'system';
      await prefs.setString(_selectedLocaleKey, localeCode);
      debugPrint('✅ Selected locale saved successfully: $localeCode');
    } catch (e) {
      debugPrint('❌ Error saving selected locale: $e');
    }
  }

  /// Initialize relay status monitoring
  void initializeStatusMonitoring() {
    _updateRelayStatuses();
    _startStatusCheckTimer();
  }

  /// Start periodic status checking
  void _startStatusCheckTimer() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updateRelayStatuses();
    });
  }

  /// Update relay statuses for all configured relays
  void _updateRelayStatuses() {
    for (final url in _relayUrls) {
      _checkRelayStatus(url);
    }
  }

  /// Check status of a specific relay
  Future<void> _checkRelayStatus(String url) async {
    try {
      debugPrint('🔍 Checking status for relay: $url');
      
      // Create a temporary connection to test the relay
      final stopwatch = Stopwatch()..start();
      
      // For now, we'll use a simple connectivity check
      // In a real implementation, you might want to do a more sophisticated check
      final nostrService = NostrService.instance;
      final wasConnected = nostrService.isConnected;
      
      RelayStatus status;
      
      if (wasConnected) {
        // If already connected, assume this relay is working
        // (In a more sophisticated implementation, you'd check individual relay health)
        status = RelayStatus(
          url: url,
          isConnected: true,
          lastSeen: DateTime.now(),
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      } else {
        // Try to connect to test the relay
        try {
          await nostrService.connect([url]);
          status = RelayStatus(
            url: url,
            isConnected: true,
            lastSeen: DateTime.now(),
            latencyMs: stopwatch.elapsedMilliseconds,
          );
          
          // Disconnect after test if we weren't connected before
          if (!wasConnected) {
            await nostrService.disconnect();
          }
        } catch (e) {
          status = RelayStatus(
            url: url,
            isConnected: false,
            error: e.toString(),
            latencyMs: stopwatch.elapsedMilliseconds,
          );
        }
      }
      
      stopwatch.stop();
      
      _relayStatuses[url] = status;
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ Error checking relay status for $url: $e');
      _relayStatuses[url] = RelayStatus(
        url: url,
        isConnected: false,
        error: e.toString(),
      );
      notifyListeners();
    }
  }

  /// Add a new relay URL
  Future<bool> addRelay(String url) async {
    if (_relayUrls.contains(url)) {
      debugPrint('⚠️ Relay already exists: $url');
      return false;
    }

    try {
      // Validate URL format
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (!url.startsWith('ws://') && !url.startsWith('wss://'))) {
        throw Exception('Invalid WebSocket URL format');
      }

      _relayUrls.add(url);
      AppConfig.relayUrls = List.from(_relayUrls);
      
      // Save to persistent storage
      await _saveRelayUrls();
      
      // Test the new relay
      await _checkRelayStatus(url);
      
      notifyListeners();
      debugPrint('✅ Added relay: $url');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to add relay $url: $e');
      return false;
    }
  }

  /// Remove a relay URL
  Future<bool> removeRelay(String url) async {
    if (!_relayUrls.contains(url)) {
      return false;
    }

    if (_relayUrls.length <= 1) {
      debugPrint('⚠️ Cannot remove last relay');
      return false;
    }

    _relayUrls.remove(url);
    _relayStatuses.remove(url);
    AppConfig.relayUrls = List.from(_relayUrls);
    
    // Save to persistent storage
    _saveRelayUrls();
    
    notifyListeners();
    debugPrint('✅ Removed relay: $url');
    return true;
  }

  /// Update an existing relay URL
  Future<bool> updateRelay(String oldUrl, String newUrl) async {
    if (!_relayUrls.contains(oldUrl)) {
      return false;
    }

    if (oldUrl == newUrl) {
      return true;
    }

    if (_relayUrls.contains(newUrl)) {
      debugPrint('⚠️ New relay URL already exists: $newUrl');
      return false;
    }

    try {
      // Validate new URL format
      final uri = Uri.parse(newUrl);
      if (!uri.hasScheme || (!newUrl.startsWith('ws://') && !newUrl.startsWith('wss://'))) {
        throw Exception('Invalid WebSocket URL format');
      }

      final index = _relayUrls.indexOf(oldUrl);
      _relayUrls[index] = newUrl;
      _relayStatuses.remove(oldUrl);
      AppConfig.relayUrls = List.from(_relayUrls);
      
      // Save to persistent storage
      await _saveRelayUrls();
      
      // Test the updated relay
      await _checkRelayStatus(newUrl);
      
      notifyListeners();
      debugPrint('✅ Updated relay: $oldUrl -> $newUrl');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to update relay $oldUrl to $newUrl: $e');
      return false;
    }
  }

  /// Update EC public key
  bool updateEcPublicKey(String newKey) {
    try {
      // Validate key format (should be 64 character hex)
      if (newKey.length != 64) {
        throw Exception('EC public key must be exactly 64 characters');
      }
      
      // Check if it's valid hex by validating each character
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(newKey)) {
        throw Exception('EC public key must contain only hexadecimal characters (0-9, a-f, A-F)');
      }
      
      _ecPublicKey = newKey;
      AppConfig.ecPublicKey = newKey;
      
      // Save to persistent storage
      _saveEcPublicKey();
      
      notifyListeners();
      debugPrint('✅ Updated EC public key');
      return true;
    } catch (e) {
      debugPrint('❌ Invalid EC public key format: $e');
      return false;
    }
  }

  /// Manually refresh relay statuses
  Future<void> refreshRelayStatuses() async {
    debugPrint('🔄 Manually refreshing relay statuses...');
    _updateRelayStatuses();
  }

  /// Test connection to a specific relay
  Future<RelayStatus> testRelay(String url) async {
    debugPrint('🧪 Testing relay: $url');
    await _checkRelayStatus(url);
    return _relayStatuses[url] ?? RelayStatus(
      url: url,
      isConnected: false,
      error: 'Status not available',
    );
  }

  /// Update selected locale
  Future<bool> updateLocale(Locale? locale) async {
    try {
      _selectedLocale = locale;
      
      // Save to persistent storage
      await _saveSelectedLocale();
      
      notifyListeners();
      debugPrint('✅ Updated selected locale: ${locale?.languageCode ?? 'system default'}');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to update locale: $e');
      return false;
    }
  }

  /// Get connection statistics
  Map<String, int> getConnectionStats() {
    final connected = _relayStatuses.values.where((s) => s.isConnected).length;
    final disconnected = _relayStatuses.values.where((s) => !s.isConnected).length;
    final total = _relayUrls.length;
    
    return {
      'total': total,
      'connected': connected,
      'disconnected': disconnected,
    };
  }
}