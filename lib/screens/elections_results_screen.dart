import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../models/election_result.dart';
import '../models/election.dart';
import '../services/election_results_service.dart';
import '../providers/election_provider.dart';
import '../generated/app_localizations.dart';

class ElectionsResultsScreen extends StatefulWidget {
  const ElectionsResultsScreen({super.key});

  @override
  State<ElectionsResultsScreen> createState() => _ElectionsResultsScreenState();
}

class _ElectionsResultsScreenState extends State<ElectionsResultsScreen> {
  List<ElectionResult> _electionResults = [];
  StreamSubscription? _resultsSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeElectionMetadata();
    _loadResults();
    _startListening();
  }

  /// Initialize election metadata and listen for changes
  void _initializeElectionMetadata() {
    final electionProvider = context.read<ElectionProvider>();
    _syncElectionMetadata(electionProvider.elections);
    
    // Listen for new elections
    electionProvider.addListener(_onElectionsChanged);
  }

  void _onElectionsChanged() {
    final electionProvider = context.read<ElectionProvider>();
    _syncElectionMetadata(electionProvider.elections);
    _loadResults(); // Reload to pick up new metadata
  }

  /// Sync election metadata with ElectionResultsService
  void _syncElectionMetadata(List<Election> elections) {
    // Store metadata for all elections
    for (final election in elections) {
      ElectionResultsService.instance.storeElectionMetadata(election);
    }
  }

  @override
  void dispose() {
    _resultsSubscription?.cancel();
    final electionProvider = context.read<ElectionProvider>();
    electionProvider.removeListener(_onElectionsChanged);
    super.dispose();
  }

  void _loadResults() {
    if (mounted) {
      setState(() {
        // Get all results from global service
        final allResults = ElectionResultsService.instance.getAllElectionResults();
        
        // Filter to only show results for elections that have metadata (are currently visible)
        final electionProvider = context.read<ElectionProvider>();
        final visibleElectionIds = electionProvider.elections.map((e) => e.id).toSet();
        
        _electionResults = allResults.where((result) {
          final hasMetadata = visibleElectionIds.contains(result.electionId);
          if (!hasMetadata) {
            debugPrint('🔍 Filtering out results for non-visible election: ${result.electionId}');
          }
          return hasMetadata;
        }).toList();
        
        debugPrint('📊 Loaded ${_electionResults.length} results for visible elections (${allResults.length} total)');
        _isLoading = false;
      });
    }
  }

  void _startListening() {
    _resultsSubscription = ElectionResultsService.instance.resultsUpdateStream.listen(
      (electionId) {
        debugPrint('📊 Results updated for election: $electionId');
        _loadResults();
      },
    );
  }

  Future<void> _onRefresh() async {
    // Trigger election provider refresh which will update metadata via Consumer
    final electionProvider = context.read<ElectionProvider>();
    await electionProvider.refreshElections();
  }

  void _showElectionDetailModal(ElectionResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Text(
                result.electionName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(result.electionStatus),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _getStatusDisplayText(result.electionStatus),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Election ID: ${result.electionId}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              // Election Results
              Expanded(
                child: Column(
                  children: [
                    // Show basic stats
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              AppLocalizations.of(context).electionResults,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatItem(AppLocalizations.of(context).totalVotesLabel, result.totalVotes.toString()),
                                _buildStatItem(AppLocalizations.of(context).candidatesLabel, result.candidateVotes.length.toString()),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Candidate results list
                    Expanded(
                      child: _buildCandidateResultsList(result, scrollController),
                    ),
                  ],
                ),
              ),
              // Close button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppLocalizations.of(context).close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _electionResults.isEmpty
                ? _buildEmptyState()
                : _buildResultsList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.poll_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).noElectionResultsYet,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).resultsWillAppearHere,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _onRefresh,
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context).refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _electionResults.length,
      itemBuilder: (context, index) {
        final result = _electionResults[index];
        return _buildElectionResultCard(result);
      },
    );
  }

  Widget _buildElectionResultCard(ElectionResult result) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showElectionDetailModal(result),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.electionName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(result.electionStatus),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getStatusDisplayText(result.electionStatus),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey[400],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'ID: ${result.electionId}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 12),
              // Stats row
              Row(
                children: [
                  _buildQuickStat(
                    Icons.how_to_vote,
                    'Total Votes',
                    result.totalVotes.toString(),
                  ),
                  const SizedBox(width: 24),
                  _buildQuickStat(
                    Icons.people,
                    'Candidates',
                    result.candidateVotes.length.toString(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Last update
              Text(
                'Last updated: ${_formatUpdateTime(result.lastUpdate)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStat(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCandidateResultsList(ElectionResult result, ScrollController scrollController) {
    if (result.candidateVotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).noVotesRecordedYet,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    final sortedCandidates = result.getCandidatesByVotes();

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemCount: sortedCandidates.length,
      itemBuilder: (context, index) {
        final candidateId = sortedCandidates[index];
        final votes = result.getVotesForCandidate(candidateId);
        final percentage = result.totalVotes > 0 
            ? (votes / result.totalVotes * 100).toStringAsFixed(1)
            : '0.0';
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Ranking
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: index == 0 
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: index == 0 
                            ? Theme.of(context).colorScheme.onPrimary
                            : Colors.grey[600],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Candidate info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.getCandidateDisplayName(candidateId),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context).voteDisplayFormat(votes, percentage),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Vote count badge
                if (index == 0 && votes > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.emoji_events,
                          size: 16,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          result.isFinished ? AppLocalizations.of(context).winner : AppLocalizations.of(context).leading,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatUpdateTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${time.day}/${time.month} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'in-progress':
        return Colors.green;
      case 'finished':
        return Colors.blue;
      case 'canceled':
        return Colors.red;
      case 'open':
      default:
        return Colors.orange;
    }
  }

  String _getStatusDisplayText(String status) {
    switch (status.toLowerCase()) {
      case 'in-progress':
        return AppLocalizations.of(context).statusInProgress;
      case 'finished':
        return AppLocalizations.of(context).statusFinished;
      case 'canceled':
        return AppLocalizations.of(context).statusCanceled;
      case 'open':
      default:
        return AppLocalizations.of(context).statusOpen;
    }
  }
}