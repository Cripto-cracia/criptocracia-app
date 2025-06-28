import 'election.dart';

class ElectionResult {
  final String electionId;
  final String electionName;
  final Map<int, int> candidateVotes; // candidateId -> voteCount
  final DateTime lastUpdate;
  final int totalVotes;
  final String electionStatus;
  final List<Candidate>? candidates;

  ElectionResult({
    required this.electionId,
    required this.electionName,
    required this.candidateVotes,
    required this.lastUpdate,
    required this.electionStatus,
    this.candidates,
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

  /// Get candidate name by ID, with fallback to "Unknown Candidate"
  String getCandidateName(int candidateId) {
    if (candidates == null) return 'Unknown Candidate';
    try {
      final candidate = candidates!.firstWhere((c) => c.id == candidateId);
      return candidate.name;
    } catch (e) {
      return 'Unknown Candidate';
    }
  }

  /// Get formatted candidate display (Name + ID)
  String getCandidateDisplayName(int candidateId) {
    final name = getCandidateName(candidateId);
    return '$name (ID: $candidateId)';
  }

  /// Check if election is finished
  bool get isFinished => electionStatus.toLowerCase() == 'finished';

  @override
  String toString() {
    return 'ElectionResult(id: $electionId, name: $electionName, totalVotes: $totalVotes, status: $electionStatus, lastUpdate: $lastUpdate)';
  }
}