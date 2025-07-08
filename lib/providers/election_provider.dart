import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/election.dart';
import '../services/nostr_service.dart';
import '../services/selected_election_service.dart';
import '../services/election_results_service.dart';
import '../config/app_config.dart';
import 'dart:convert';
import 'dart:async';

class ElectionProvider with ChangeNotifier {
  final NostrService _nostrService = NostrService.instance;
  StreamSubscription? _eventsSubscription;
  Timer? _periodicRefreshTimer;

  List<Election> _elections = [];
  bool _isLoading = false;
  String? _error;

  List<Election> get elections => _elections;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadElections() async {
    debugPrint('🚀 Starting election loading process...');

    if (!AppConfig.isConfigured) {
      _error =
          'App not configured. Please provide relay URL and EC public key.';
      debugPrint('❌ App not configured');
      notifyListeners();
      return;
    }

    debugPrint(
      '⚙️ App configured with relays: ${AppConfig.relayUrls.join(', ')}',
    );

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('🔌 Connecting to Nostr service...');
      await _nostrService.connect(AppConfig.relayUrls);

      // Listen for election events
      debugPrint('👂 Starting to listen for election events...');
      final electionsStream = _nostrService.subscribeToElections(
        AppConfig.ecPublicKey,
      );

      // Give a brief moment for the subscription to establish, then stop loading if no events
      Timer(const Duration(seconds: 1), () {
        if (_isLoading && _elections.isEmpty) {
          debugPrint(
            '📭 No events received after subscription - showing no elections message',
          );
          _isLoading = false;
          notifyListeners();
        }
      });

      // Listen to real-time events
      debugPrint('🔄 Listening for real-time election events...');

      // Set up stream subscription instead of await for to handle completion
      _eventsSubscription?.cancel(); // Cancel any existing subscription
      _eventsSubscription = electionsStream.listen(
        (event) {
          debugPrint(
            '📨 Received event in provider: kind=${event.kind}, id=${event.id}',
          );

          try {
            if (event.kind == 35000) {
              debugPrint('🗳️ Found kind 35000 event, parsing content...');
              final content = jsonDecode(event.content);
              debugPrint('📋 Parsed content: $content');

              final election = Election.fromJson(content);
              debugPrint(
                '✅ Created election: ${election.name} (${election.id})',
              );

              // Apply client-side filtering: only show elections where end_time is within last 12 hours
              final now = DateTime.now();
              final cutoffTime = now.subtract(const Duration(hours: 12));
              
              if (election.endTime.isBefore(cutoffTime)) {
                debugPrint(
                  '⏭️ Skipping old election: ${election.name} (ended: ${election.endTime})',
                );
                return; // Skip this old election
              }
              
              debugPrint(
                '📅 Election within 12h end window: ${election.name} (ends: ${election.endTime})',
              );

              // Store election metadata for results service
              ElectionResultsService.instance.storeElectionMetadata(election);

              // Update existing election or add new one
              final existingIndex = _elections.indexWhere(
                (e) => e.id == election.id,
              );
              if (existingIndex != -1) {
                // Check for status changes before updating
                final oldElection = _elections[existingIndex];
                final statusChanged = oldElection.status != election.status;

                // Update existing election (status change, candidate updates, etc.)
                _elections = [..._elections];
                _elections[existingIndex] = election;
                debugPrint(
                  '🔄 Updated existing election: ${election.name} - Status: ${election.status}',
                );

                if (statusChanged) {
                  debugPrint('🚨 ELECTION STATUS CHANGED: ${election.id}');
                  debugPrint('   From: ${oldElection.status}');
                  debugPrint('   To: ${election.status}');
                }

                // Update selected election if this election is currently selected
                _updateSelectedElectionIfMatches(election);
              } else {
                // Add new election to the list
                _elections = [..._elections, election];
                debugPrint(
                  '📝 Added new election to list: ${election.name} - Status: ${election.status}',
                );
              }

              // Sort elections to show most recent first
              _sortElections();

              // Stop loading if this is the first election or if we have elections
              if (_isLoading && _elections.isNotEmpty) {
                _isLoading = false;
              }

              notifyListeners();
              debugPrint('📊 Total elections: ${_elections.length}');
            } else {
              debugPrint('➡️ Skipping non-election event: kind=${event.kind}');
            }
          } catch (e) {
            debugPrint('❌ Error parsing election event: $e');
            debugPrint('📄 Event content was: ${event.content}');
          }
        },
        onError: (error) {
          debugPrint('🚨 Stream error in provider: $error');
          if (_isLoading) {
            _isLoading = false;
            notifyListeners();
          }
        },
        onDone: () {
          debugPrint('📡 Nostr stream completed');
          if (_isLoading) {
            _isLoading = false;
            notifyListeners();
          }
        },
      );

      // Keep the subscription alive - don't await for it to complete

      // Start periodic refresh as backup for missed real-time events
      _startPeriodicRefresh();
    } catch (e) {
      _error = 'Failed to load elections: $e';
      _isLoading = false;
      debugPrint('💥 Error loading elections: $e');
      notifyListeners();

      // Try to disconnect on error
      try {
        await _nostrService.disconnect();
      } catch (_) {}
    }
  }

  Future<void> refreshElections() async {
    // Cancel existing subscription and clear data
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _stopPeriodicRefresh();
    _elections = [];
    _error = null;
    await loadElections();
  }

  /// Sort elections to show most recent first (by start time)
  void _sortElections() {
    _elections.sort((a, b) {
      // Sort by start time, most recent first
      return b.startTime.compareTo(a.startTime);
    });
    debugPrint('📊 Elections sorted by start time (most recent first)');
  }

  /// Start periodic refresh to catch missed real-time events
  void _startPeriodicRefresh() {
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) {
      debugPrint(
        '🔄 Periodic refresh: checking for missed election updates...',
      );
      _performSilentRefresh();
    });
    debugPrint('⏰ Started periodic refresh every 30 seconds');
  }

  /// Perform a silent refresh without changing loading state
  Future<void> _performSilentRefresh() async {
    if (!_nostrService.isConnected) {
      debugPrint('⚠️ Skipping refresh: not connected to relay');
      return;
    }

    try {
      // Create a temporary subscription to get latest events
      final electionsStream = _nostrService.subscribeToElections(
        AppConfig.ecPublicKey,
      );

      // Listen for a short period to catch any missed events
      final subscription = electionsStream.listen(
        (event) {
          if (event.kind == 35000) {
            try {
              final content = jsonDecode(event.content);
              final election = Election.fromJson(content);

              // Apply client-side filtering: only show elections where end_time is within last 12 hours
              final now = DateTime.now();
              final cutoffTime = now.subtract(const Duration(hours: 12));
              
              if (election.endTime.isBefore(cutoffTime)) {
                debugPrint(
                  '⏭️ Skipping old election during refresh: ${election.name} (ended: ${election.endTime})',
                );
                return; // Skip this old election
              }

              // Store election metadata for results service
              ElectionResultsService.instance.storeElectionMetadata(election);

              // Check if this is a new election or an update to existing one
              final existingIndex = _elections.indexWhere(
                (e) => e.id == election.id,
              );
              if (existingIndex == -1) {
                debugPrint(
                  '🆕 Found new election during refresh: ${election.name}',
                );
                _elections = [..._elections, election];
                _sortElections();
                notifyListeners();
              } else {
                // Check if existing election has been updated
                final oldElection = _elections[existingIndex];
                if (oldElection.status != election.status) {
                  debugPrint(
                    '🔄 Found election status update during refresh: ${election.name}',
                  );
                  debugPrint(
                    '   Status changed from ${oldElection.status} to ${election.status}',
                  );
                  _elections = [..._elections];
                  _elections[existingIndex] = election;
                  _updateSelectedElectionIfMatches(election);
                  notifyListeners();
                }
              }
            } catch (e) {
              debugPrint('❌ Error parsing election during refresh: $e');
            }
          }
        },
        onError: (error) {
          debugPrint('⚠️ Error during periodic refresh: $error');
        },
      );

      // Close the temporary subscription after 2 seconds
      Timer(const Duration(seconds: 2), () {
        subscription.cancel();
      });
    } catch (e) {
      debugPrint('❌ Error during periodic refresh: $e');
    }
  }

  /// Stop periodic refresh
  void _stopPeriodicRefresh() {
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = null;
    debugPrint('⏹️ Stopped periodic refresh');
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    _stopPeriodicRefresh();
    _nostrService.disconnect();
    super.dispose();
  }

  Election? getElectionById(String id) {
    try {
      return _elections.firstWhere((election) => election.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Update the selected election if the updated election matches the currently selected one
  Future<void> _updateSelectedElectionIfMatches(
    Election updatedElection,
  ) async {
    try {
      final isSelected = await SelectedElectionService.isElectionSelected(
        updatedElection.id,
      );
      if (isSelected) {
        await SelectedElectionService.setSelectedElection(updatedElection);
        debugPrint(
          '🔄 Updated selected election storage: ${updatedElection.name} - Status: ${updatedElection.status}',
        );
      }
    } catch (e) {
      debugPrint('❌ Error updating selected election: $e');
    }
  }

  /// Get the currently selected election from storage
  Future<Election?> getSelectedElection() async {
    return await SelectedElectionService.getSelectedElection();
  }

  /// Check if there is a selected election
  Future<bool> hasSelectedElection() async {
    return await SelectedElectionService.hasSelectedElection();
  }

  /// Clear the selected election
  Future<void> clearSelectedElection() async {
    await SelectedElectionService.clearSelectedElection();
    debugPrint('🗑️ Cleared selected election from storage');
  }
}
