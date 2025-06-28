import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/election_result.dart';
import '../models/election.dart';

/// Service for managing election results globally across the app
/// Stores results as Map with electionId as key and Map with candidateId and voteCount as value
class ElectionResultsService {
  static ElectionResultsService? _instance;
  static ElectionResultsService get instance {
    _instance ??= ElectionResultsService._internal();
    return _instance!;
  }

  // Global storage: electionId -> (candidateId -> voteCount)
  final Map<String, Map<int, int>> _electionResults = {};
  
  // Election metadata storage: electionId -> Election
  final Map<String, Election> _electionMetadata = {};
  
  // Last update times: electionId -> DateTime
  final Map<String, DateTime> _lastUpdateTimes = {};
  
  // Stream controller to notify listeners of results changes
  final StreamController<String> _resultsUpdateController = 
      StreamController<String>.broadcast();

  ElectionResultsService._internal();

  /// Stream of election IDs that have been updated
  Stream<String> get resultsUpdateStream => _resultsUpdateController.stream;

  // … other methods …

  /// Parse JSON content – extracted for easier testing/mocking
  dynamic _parseJson(String content) {
    return jsonDecode(content);
  }

  /// Safe JSON parsing with error handling
  dynamic _parseJsonSafely(String content) {
    try {
      // Remove any whitespace and validate basic format
      final trimmed = content.trim();
      if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
        throw FormatException('Content is not a JSON array');
      }
      
      // Parse using dart:convert's jsonDecode
      return _parseJson(trimmed);
    } catch (e) {
      debugPrint('❌ JSON parse error: $e');
      rethrow;
    }
  }

  /// Get current results for a specific election
  Map<int, int>? getElectionResults(String electionId) {
    return _electionResults[electionId];
  }

  /// Store election metadata for results display
  void storeElectionMetadata(Election election) {
    _electionMetadata[election.id] = election;
  }

  /// Get all elections that have results
  List<ElectionResult> getAllElectionResults() {
    final results = <ElectionResult>[];
    
    for (final entry in _electionResults.entries) {
      final electionId = entry.key;
      final candidateVotes = entry.value;
      final metadata = _electionMetadata[electionId];
      
      final electionName = metadata?.name ?? 'Unknown Election ($electionId)';
      
      results.add(ElectionResult(
        electionId: electionId,
        electionName: electionName,
        candidateVotes: Map.from(candidateVotes),
        lastUpdate: _lastUpdateTimes[electionId] ?? DateTime.now(),
      ));
    }
    
    // Sort by last update (most recent first)
    results.sort((a, b) => b.lastUpdate.compareTo(a.lastUpdate));
    return results;
  }

  /// Check if election has results
  bool hasResultsForElection(String electionId) {
    return _electionResults.containsKey(electionId);
  }

  /// Emit current state for all elections
  void emitCurrentState() {
    for (final electionId in _electionResults.keys) {
      _resultsUpdateController.add(electionId);
    }
  }

  /// Update election results from Nostr event content
  /// Handles format: [[4,21],[3,35]] where each array is [candidate_id, vote_count]
  void updateResultsFromEventContent(String electionId, String content) {
    try {
      debugPrint('📊 Updating results for election: $electionId');
      debugPrint('   Content: $content');
      
      final results = _parseJsonSafely(content);
      if (results is List) {
        final Map<int, int> candidateVotes = {};
        
        for (final result in results) {
          if (result is List && result.length >= 2) {
            // New format: [candidate_id, vote_count]
            final candidateId = result[0] as int;
            final voteCount = result[1] as int;
            candidateVotes[candidateId] = voteCount;
            debugPrint('   Candidate $candidateId: $voteCount votes');
          } else if (result is Map && result.containsKey('candidate_id') && result.containsKey('vote_count')) {
            // Legacy format: {"candidate_id": X, "vote_count": Y}
            candidateVotes[result['candidate_id']] = result['vote_count'];
          }
        }
        
        _electionResults[electionId] = candidateVotes;
        _lastUpdateTimes[electionId] = DateTime.now(); // Store actual update time
        debugPrint('✅ Results updated for election $electionId: $candidateVotes');
        _resultsUpdateController.add(electionId);
      }
    } catch (e) {
      debugPrint('❌ Error updating results from event content: $e');
    }
  }

  void dispose() {
    _resultsUpdateController.close();
  }
}