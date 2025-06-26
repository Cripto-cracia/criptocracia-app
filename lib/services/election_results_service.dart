import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for storing election results locally keyed by election id.
class ElectionResultsService {
  static String _key(String electionId) => 'election_results_$electionId';

  /// Save results for an election as a map of candidateId to vote count.
  static Future<void> saveResults(String electionId, Map<int, int> results) async {
    final prefs = await SharedPreferences.getInstance();
    final map = results.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString(_key(electionId), jsonEncode(map));
  }

  /// Retrieve stored results for an election if available.
  static Future<Map<int, int>?> getResults(String electionId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key(electionId));
    if (jsonStr == null) return null;
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      return data.map((k, v) => MapEntry(int.parse(k), v as int));
    } catch (_) {
      return null;
    }
  }

  /// Clear stored results for an election.
  static Future<void> clearResults(String electionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(electionId));
  }
}
