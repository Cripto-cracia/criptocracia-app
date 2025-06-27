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

  // … rest of class …
}
}