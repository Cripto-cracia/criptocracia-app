import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/relay_status.dart';
import '../services/nostr_service.dart';

class SettingsProvider with ChangeNotifier {
  static SettingsProvider? _instance;
  static SettingsProvider get instance {
    _instance ??= SettingsProvider._internal();
    return _instance!;
  }

  SettingsProvider._internal();

  List<String> _relayUrls = List.from(AppConfig.relayUrls);
  String _ecPublicKey = AppConfig.ecPublicKey;
  Map<String, RelayStatus> _relayStatuses = {};
  Timer? _statusCheckTimer;
  
  // Getters
  List<String> get relayUrls => List.unmodifiable(_relayUrls);
  String get ecPublicKey => _ecPublicKey;
  Map<String, RelayStatus> get relayStatuses => Map.unmodifiable(_relayStatuses);

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
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
      
      // Check if it's valid hex
      int.parse(newKey, radix: 16);
      
      _ecPublicKey = newKey;
      AppConfig.ecPublicKey = newKey;
      
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