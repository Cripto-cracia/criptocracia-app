import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/election.dart';
import '../providers/results_provider.dart';
import '../widgets/result_card.dart';
import '../generated/app_localizations.dart';

class ResultsScreen extends StatefulWidget {
  final Election election;

  const ResultsScreen({super.key, required this.election});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final ResultsProvider _resultsProvider;

  @override
  void initState() {
    super.initState();
    _resultsProvider = context.read<ResultsProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resultsProvider.startListening(widget.election.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(
            context,
          ).electionResultsTitle(widget.election.name),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Consumer<ResultsProvider>(
            builder: (context, provider, child) {
              return IconButton(
                icon: Icon(
                  provider.isListening ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () {
                  if (provider.isListening) {
                    provider.stopListening();
                  } else {
                    provider.startListening(widget.election.id);
                  }
                },
                tooltip: provider.isListening
                    ? AppLocalizations.of(context).pauseUpdatesTooltip
                    : AppLocalizations.of(context).resumeUpdatesTooltip,
              );
            },
          ),
        ],
      ),
      body: Consumer<ResultsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.results.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(
                      context,
                    ).errorWithMessage(provider.error!),
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        provider.startListening(widget.election.id),
                    child: Text(AppLocalizations.of(context).retry),
                  ),
                ],
              ),
            );
          }

          final candidates = provider.getCandidatesWithVotes(widget.election);
          final totalVotes = provider.getTotalVotes();

          return RefreshIndicator(
            onRefresh: () => provider.refreshResults(widget.election.id),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.poll,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppLocalizations.of(
                                  context,
                                ).electionSummarySection,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildSummaryItem(
                                context,
                                AppLocalizations.of(context).totalVotesLabel,
                                totalVotes.toString(),
                                Icons.how_to_vote,
                              ),
                              _buildSummaryItem(
                                context,
                                AppLocalizations.of(context).candidatesLabel,
                                candidates.length.toString(),
                                Icons.people,
                              ),
                              _buildSummaryItem(
                                context,
                                AppLocalizations.of(context).statusLabel,
                                provider.isListening
                                    ? AppLocalizations.of(context).liveStatus
                                    : AppLocalizations.of(context).pausedStatus,
                                provider.isListening
                                    ? Icons.radio_button_checked
                                    : Icons.pause,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Results Header
                  Row(
                    children: [
                      Text(
                        AppLocalizations.of(context).resultsSection,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (provider.isListening)
                        Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.green,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context).liveStatus,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  if (candidates.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.poll_outlined,
                              size: 48,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context).noVotesRecordedYet,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...candidates.map((candidate) {
                      final percentage = totalVotes > 0
                          ? (candidate.votes / totalVotes * 100)
                          : 0.0;
                      final rank = candidates.indexOf(candidate) + 1;

                      return ResultCard(
                        candidate: candidate,
                        totalVotes: totalVotes,
                        percentage: percentage,
                        rank: rank,
                        isWinner: rank == 1 && totalVotes > 0,
                      );
                    }),

                  const SizedBox(height: 16),

                  // Last Update Info
                  if (provider.lastUpdate != null)
                    Center(
                      child: Text(
                        AppLocalizations.of(context).lastUpdatedLabel(
                          _formatLastUpdate(provider.lastUpdate!),
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Raw Event Log
                  _buildExplorerLog(context, provider.explorerLog),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildExplorerLog(BuildContext context, List<String> logs) {
    if (logs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nostr Event Explorer',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 150,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              Color color = Colors.black;
              if (log.startsWith('[SUCCESS]')) {
                color = Colors.green;
              } else if (log.startsWith('[ERROR]') || log.startsWith('[FATAL]')) {
                color = Colors.red;
              } else if (log.startsWith('[INFO]')) {
                color = Colors.blue;
              }
              return Text(
                log,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: color,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
