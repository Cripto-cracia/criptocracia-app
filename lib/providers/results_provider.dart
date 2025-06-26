import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../models/election.dart';
import '../services/nostr_service.dart';
import '../config/app_config.dart';
import '../services/election_results_service.dart';
import '../services/selected_election_service.dart';

class ResultsProvider with ChangeNotifier {
  final NostrService _nostrService = NostrService();
  
  Map<int, int> _results = {}; // candidate_id -> vote_count
  bool _isLoading = false;
  bool _isListening = false;
  String? _error;
  DateTime? _lastUpdate;
  StreamSubscription? _resultsSubscription;
  String? _currentElectionId;
  
  Map<int, int> get results => _results;
  bool get isLoading => _isLoading;
  bool get isListening => _isListening;
  String? get error => _error;
  DateTime? get lastUpdate => _lastUpdate;
  
  Future<void> startListening(String electionId) async {
    if (!AppConfig.isConfigured) {
      _error = 'App not configured. Please provide relay URL and EC public key.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    _currentElectionId = electionId;
    notifyListeners();

    try {
      await _nostrService.connect(AppConfig.relayUrl);

      // Load any stored results for this election
      final stored = await ElectionResultsService.getResults(electionId);
      if (stored != null) {
        _results = stored;
        _lastUpdate = DateTime.now();
      }

      // Start listening to results
      final resultsStream = _nostrService.subscribeToResults(electionId);
      _resultsSubscription = resultsStream.listen(
        _handleResultEvent,
        onError: (error) {
          _error = 'Error listening to results: $error';
          _isListening = false;
          _isLoading = false;
          notifyListeners();
        },
      );
      
      _isListening = true;
      _isLoading = false;
      notifyListeners();

    } catch (e) {
      _error = 'Failed to start listening to results: $e';
      _isLoading = false;
      _isListening = false;
      notifyListeners();
    }
  }
  
  void _handleResultEvent(event) async {
    try {
      final decoded = jsonDecode(event.content);

      if (decoded is List) {
        final Map<int, int> parsed = {};
        for (final item in decoded) {
          if (item is List && item.length >= 2) {
            final id = int.tryParse(item[0].toString()) ?? 0;
            final votes = int.tryParse(item[1].toString()) ?? 0;
            parsed[id] = votes;
          }
        }
        if (parsed.isNotEmpty) {
          _results = parsed;
          _lastUpdate = DateTime.now();
          notifyListeners();

          if (_currentElectionId != null &&
              await SelectedElectionService.isElectionSelected(
                _currentElectionId!,
              )) {
            await ElectionResultsService.saveResults(
              _currentElectionId!,
              _results,
            );
          }
        }
      }
    } catch (e) {
      // Skip invalid result events
    }
  }
  
  void stopListening() {
    _resultsSubscription?.cancel();
    _resultsSubscription = null;
    _isListening = false;
    _currentElectionId = null;
    notifyListeners();
  }
  
  Future<void> refreshResults(String electionId) async {
    if (_isListening) {
      // Just trigger a reload by stopping and starting
      stopListening();
      await Future.delayed(const Duration(milliseconds: 100));
      await startListening(electionId);
    } else {
      await startListening(electionId);
    }
  }
  
  List<Candidate> getCandidatesWithVotes(Election election) {
    final candidatesWithVotes = election.candidates.map((candidate) {
      final votes = _results[candidate.id] ?? 0;
      return Candidate(
        id: candidate.id,
        name: candidate.name,
        votes: votes,
      );
    }).toList();
    
    // Sort by vote count (descending)
    candidatesWithVotes.sort((a, b) => b.votes.compareTo(a.votes));
    
    return candidatesWithVotes;
  }
  
  int getTotalVotes() {
    return _results.values.fold(0, (sum, votes) => sum + votes);
  }
  
  int getVotesForCandidate(int candidateId) {
    return _results[candidateId] ?? 0;
  }
  
  double getPercentageForCandidate(int candidateId) {
    final totalVotes = getTotalVotes();
    if (totalVotes == 0) return 0.0;
    
    final candidateVotes = getVotesForCandidate(candidateId);
    return (candidateVotes / totalVotes) * 100;
  }
  
  @override
  void dispose() {
    stopListening();
    _currentElectionId = null;
    _nostrService.disconnect();
    super.dispose();
  }
}
