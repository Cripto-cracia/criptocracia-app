class ElectionResult {
  final String electionId;
  final String electionName;
  final Map<int, int> candidateVotes; // candidateId -> voteCount
  final DateTime lastUpdate;
  final int totalVotes;

  ElectionResult({
    required this.electionId,
    required this.electionName,
    required this.candidateVotes,
    required this.lastUpdate,
  }) : totalVotes = candidateVotes.values.fold(0, (sum, votes) => sum + votes);

  /// Get vote count for a specific candidate
  int getVotesForCandidate(int candidateId) {
    return candidateVotes[candidateId] ?? 0;
  }

  /// Get list of candidate IDs sorted by vote count (descending)
  List<int> getCandidatesByVotes() {
    final candidates = candidateVotes.keys.toList();
    candidates.sort((a, b) => candidateVotes[b]!.compareTo(candidateVotes[a]!));
    return candidates;
  }

  /// Get the winning candidate ID (most votes)
  int? getWinningCandidate() {
    if (candidateVotes.isEmpty) return null;
    final sorted = getCandidatesByVotes();
    return sorted.first;
  }

  /// Check if this election has any votes
  bool get hasVotes => totalVotes > 0;

  @override
  String toString() {
    return 'ElectionResult(id: $electionId, name: $electionName, totalVotes: $totalVotes, lastUpdate: $lastUpdate)';
  }
}