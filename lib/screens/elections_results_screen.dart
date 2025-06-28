import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../models/election_result.dart';
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
    _initializeElectionMetadataAsync();
    _startListening();
  }

  /// Initialize election metadata from ElectionProvider
  /// Ensures elections are loaded before showing results
  Future<void> _initializeElectionMetadataAsync() async {
    final electionProvider = context.read<ElectionProvider>();
    debugPrint('🔄 Initializing election metadata from ElectionProvider...');
    debugPrint('   Available elections: ${electionProvider.elections.length}');
    
    // If no elections loaded yet, trigger loading
    if (electionProvider.elections.isEmpty && !electionProvider.isLoading) {
      debugPrint('📥 No elections loaded, triggering election loading...');
      await electionProvider.loadElections();
    }
    
    // Wait a bit for elections to load if still loading
    if (electionProvider.isLoading) {
      debugPrint('⏳ Waiting for elections to finish loading...');
      int attempts = 0;
      while (electionProvider.isLoading && attempts < 50) { // Max 5 seconds
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
    }
    
    // Store metadata for all loaded elections
    for (final election in electionProvider.elections) {
      debugPrint('   Processing election: ${election.id} -> ${election.name}');
      ElectionResultsService.instance.storeElectionMetadata(election);
    }
    debugPrint('✅ Initialized ${electionProvider.elections.length} election metadata entries');
    
    // Now load results
    _loadResults();
  }

  @override
  void dispose() {
    _resultsSubscription?.cancel();
    super.dispose();
  }

  void _loadResults() {
    if (mounted) {
      setState(() {
        _electionResults = ElectionResultsService.instance.getAllElectionResults();
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
    // Refresh election metadata first, then results
    await _initializeElectionMetadataAsync();
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
              Text(
                'Election ID: ${result.electionId}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              // TODO placeholder
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.construction,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'TODO',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Detailed results view\ncoming soon',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[500],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      // Show basic stats for now
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                'Current Stats',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatItem('Total Votes', result.totalVotes.toString()),
                                  _buildStatItem('Candidates', result.candidateVotes.length.toString()),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Close button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
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
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).navResults),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
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
              'No Election Results Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Results will appear here when the Election Coordinator publishes vote counts for elections.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
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
    final winningCandidate = result.getWinningCandidate();
    
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
                    child: Text(
                      result.electionName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
                  if (winningCandidate != null) ...[
                    const SizedBox(width: 24),
                    _buildQuickStat(
                      Icons.emoji_events,
                      'Leading',
                      'ID $winningCandidate',
                    ),
                  ],
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
}