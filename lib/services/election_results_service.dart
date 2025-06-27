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

  /// Get results for a specific election
  Map<int, int> getElectionResults(String electionId) {
    return Map<int, int>.from(_electionResults[electionId] ?? {});
  }

  /// Update results for a specific election
  void updateElectionResults(String electionId, Map<int, int> results) {
    debugPrint('📊 Updating results for election $electionId: $results');
    _electionResults[electionId] = Map<int, int>.from(results);
    
    // Always emit update, even if results are the same
    _resultsUpdateController.add(electionId);
  }

  /// Force emit current state for an election (useful for late subscribers)
  void emitCurrentState(String electionId) {
    if (_electionResults.containsKey(electionId)) {
      debugPrint('🔄 Force emitting current state for election $electionId');
      _resultsUpdateController.add(electionId);
    }
  }

  /// Parse and update results from Nostr event content
  /// Content format: "[[candidateId, votes], [candidateId, votes]]"
  /// Example: "[[4,21],[3,35]]"
  void updateResultsFromEventContent(String electionId, String content) {
    try {
      debugPrint('📡 Parsing results for election $electionId: $content');
      
      // Parse the JSON array format
      final dynamic parsedContent = _parseJsonSafely(content);
      
      if (parsedContent is List) {
        final Map<int, int> results = {};
        
        for (final item in parsedContent) {
          if (item is List && item.length >= 2) {
            final candidateId = _parseIntSafely(item[0]);
            final voteCount = _parseIntSafely(item[1]);
            
            if (candidateId != null && voteCount != null) {
              results[candidateId] = voteCount;
            }
          }
        }
        
        if (results.isNotEmpty) {
          updateElectionResults(electionId, results);
          debugPrint('✅ Successfully updated $electionId with ${results.length} candidates');
        } else {
          debugPrint('⚠️ No valid results found in content: $content');
        }
      } else {
        debugPrint('❌ Invalid content format for election $electionId: $content');
      }
    } catch (e) {
      debugPrint('❌ Error parsing results for election $electionId: $e');
      debugPrint('   Content: $content');
    }
  }

  /// Get vote count for a specific candidate in an election
  int getVotesForCandidate(String electionId, int candidateId) {
    return _electionResults[electionId]?[candidateId] ?? 0;
  }

  /// Get total votes for an election
  int getTotalVotes(String electionId) {
    final results = _electionResults[electionId];
    if (results == null) return 0;
    
    return results.values.fold(0, (sum, votes) => sum + votes);
  }

  /// Check if we have results for an election
  bool hasResultsForElection(String electionId) {
    return _electionResults.containsKey(electionId) && 
           _electionResults[electionId]!.isNotEmpty;
  }

  /// Get all elections that have results
  List<String> getElectionsWithResults() {
    return _electionResults.keys.where((electionId) => 
        _electionResults[electionId]!.isNotEmpty).toList();
  }

  /// Clear results for a specific election
  void clearElectionResults(String electionId) {
    debugPrint('🗑️ Clearing results for election: $electionId');
    _electionResults.remove(electionId);
    _resultsUpdateController.add(electionId);
  }

  /// Clear all results
  void clearAllResults() {
    debugPrint('🗑️ Clearing all election results');
    final electionIds = List<String>.from(_electionResults.keys);
    _electionResults.clear();
    
    // Notify all elections were cleared
    for (final electionId in electionIds) {
      _resultsUpdateController.add(electionId);
    }
  }

  /// Get debug information about stored results
  Map<String, dynamic> getDebugInfo() {
    return {
      'total_elections': _electionResults.length,
      'elections_with_results': getElectionsWithResults().length,
      'results_summary': _electionResults.map((electionId, results) => 
          MapEntry(electionId, {
            'candidates': results.length,
            'total_votes': results.values.fold(0, (sum, votes) => sum + votes),
          })),
    };
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

  /// Parse JSON content - extracted for easier testing/mocking
  dynamic _parseJson(String content) {
    // Import dart:convert at the top of file for jsonDecode
    final regex = RegExp(r'\[\s*\[\s*(\d+)\s*,\s*(\d+)\s*\]\s*(?:,\s*\[\s*(\d+)\s*,\s*(\d+)\s*\]\s*)*\]');
    
    if (!regex.hasMatch(content)) {
      throw FormatException('Content does not match expected format: [[id,votes],[id,votes]]');
    }

    // Simple regex-based parsing for the specific format [[id,votes],[id,votes]]
    final itemRegex = RegExp(r'\[\s*(\d+)\s*,\s*(\d+)\s*\]');
    final matches = itemRegex.allMatches(content);
    
    final List<List<int>> result = [];
    for (final match in matches) {
      final candidateId = int.parse(match.group(1)!);
      final votes = int.parse(match.group(2)!);
      result.add([candidateId, votes]);
    }
    
    return result;
  }

  /// Safe integer parsing
  int? _parseIntSafely(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is double) return value.round();
    return null;
  }

  /// Dispose resources
  void dispose() {
    _resultsUpdateController.close();
  }
}