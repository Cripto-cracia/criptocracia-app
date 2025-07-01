import 'package:flutter/material.dart';
import 'dart:async';
import '../models/election.dart';
import '../services/nostr_service.dart';
import '../services/election_results_service.dart';
import '../config/app_config.dart';

class ResultsProvider with ChangeNotifier {
  final NostrService _nostrService = NostrService();
  final ElectionResultsService _resultsService = ElectionResultsService.instance;
  
  Map<int, int> _results = {}; // candidate_id -> vote_count
  bool _isLoading = false;
  bool _isListening = false;
  String? _error;
  DateTime? _lastUpdate;
  StreamSubscription? _resultsSubscription;
  StreamSubscription? _resultsUpdateSubscription;
  Timer? _initialLoadTimer;
  
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
    notifyListeners();
    
    try {
      // Load existing results from global service first
      _loadExistingResults(electionId);
      
      // Connect to relay
      await _nostrService.connect(AppConfig.relayUrls);
      
      // Start listening to real-time results events for this specific election
      final resultsStream = _nostrService.subscribeToElectionResults(
        AppConfig.ecPublicKey, 
        electionId,
      );
      _resultsSubscription = resultsStream.listen(
        (event) => _handleRealResultEvent(event, electionId),
        onError: (error) {
          _error = 'Error listening to results: $error';
          _isListening = false;
          _isLoading = false;
          notifyListeners();
        },
      );
      
      // Also listen to global results service updates
      _resultsUpdateSubscription = _resultsService.resultsUpdateStream.listen(
        (updatedElectionId) {
          if (updatedElectionId == electionId) {
            _loadExistingResults(electionId);
          }
        },
      );
      
      _isListening = true;
      _isLoading = false;
      notifyListeners();
      
      // Start periodic check for initial results loading
      _startInitialLoadTimer(electionId);
      
      // Force emit current state from global service in case we missed initial updates
      _resultsService.emitCurrentState();
      
      // Add a small delay and force refresh to catch any racing conditions
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_isListening) {
          debugPrint('🔄 Forced refresh after connection delay');
          _loadExistingResults(electionId);
        }
      });
      
    } catch (e) {
      _error = 'Failed to start listening to results: $e';
      _isLoading = false;
      _isListening = false;
      notifyListeners();
    }
  }
  
  void _loadExistingResults(String electionId) {
    final existingResults = _resultsService.getElectionResults(electionId);
    
    // Always update results and notify listeners, even if empty
    _results = existingResults != null ? Map<int, int>.from(existingResults) : <int, int>{};
    _lastUpdate = DateTime.now();
    
    if (existingResults?.isNotEmpty ?? false) {
      debugPrint('📊 Loaded existing results for $electionId: $_results');
    } else {
      debugPrint('📊 No existing results found for $electionId, initializing empty');
    }
    
    // Always notify to ensure UI updates
    notifyListeners();
  }
  
  void _handleRealResultEvent(event, String electionId) {
    try {
      debugPrint('🎯 Processing real election results event for $electionId');
      debugPrint('   Event content: ${event.content}');
      
      // The content should be in format: "[[candidateId, votes], [candidateId, votes]]"
      // This is already parsed and stored by the NostrService in ElectionResultsService
      // So we just need to reload from the service
      _loadExistingResults(electionId);
      
    } catch (e) {
      debugPrint('❌ Error processing real result event: $e');
    }
  }
  
  void _startInitialLoadTimer(String electionId) {
    // Cancel any existing timer
    _initialLoadTimer?.cancel();
    
    // Set up periodic check for the first 5 seconds to catch late-arriving results
    int checkCount = 0;
    const maxChecks = 5; // Check every second for 5 seconds
    
    _initialLoadTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      checkCount++;
      
      // Check if we now have results
      final currentResults = _resultsService.getElectionResults(electionId);
      final hasNewResults = currentResults?.isNotEmpty ?? false;
      
      if (hasNewResults) {
        debugPrint('🎉 Found results on periodic check #$checkCount for $electionId: $currentResults');
        _loadExistingResults(electionId);
        timer.cancel();
        _initialLoadTimer = null;
        debugPrint('✅ Stopped periodic check early - results found');
        return;
      }
      
      debugPrint('🔄 Periodic check #$checkCount for election $electionId - no results yet');
      
      // Stop after max checks
      if (checkCount >= maxChecks) {
        timer.cancel();
        _initialLoadTimer = null;
        debugPrint('✅ Stopped periodic check after $checkCount attempts - no results found');
      }
    });
  }

  void stopListening() {
    _resultsSubscription?.cancel();
    _resultsSubscription = null;
    _resultsUpdateSubscription?.cancel();
    _resultsUpdateSubscription = null;
    _initialLoadTimer?.cancel();
    _initialLoadTimer = null;
    _isListening = false;
    notifyListeners();
  }
  
  Future<void> refreshResults(String electionId) async {
    if (_isListening) {
      // Just reload from service and trigger a new subscription
      _loadExistingResults(electionId);
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
    _initialLoadTimer?.cancel();
    _nostrService.disconnect();
    super.dispose();
  }
}