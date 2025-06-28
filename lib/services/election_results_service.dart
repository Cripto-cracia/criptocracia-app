import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';

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

  /// Emit current state for all elections
  void emitCurrentState() {
    for (final electionId in _electionResults.keys) {
      _resultsUpdateController.add(electionId);
    }
  }

  /// Update election results from Nostr event content
  void updateResultsFromEventContent(String electionId, String content) {
    try {
      final results = _parseJsonSafely(content);
      if (results is List) {
        final Map<int, int> candidateVotes = {};
        for (final result in results) {
          if (result is Map && result.containsKey('candidate_id') && result.containsKey('vote_count')) {
            candidateVotes[result['candidate_id']] = result['vote_count'];
          }
        }
        _electionResults[electionId] = candidateVotes;
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