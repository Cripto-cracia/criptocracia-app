import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/election.dart';
import '../widgets/vote_confirmation_dialog.dart';
import '../generated/app_localizations.dart';
import '../services/selected_election_service.dart';
import '../services/vote_service.dart';
import '../services/voter_session_service.dart';
import '../providers/election_provider.dart';

class ElectionDetailScreen extends StatefulWidget {
  final Election election;

  const ElectionDetailScreen({super.key, required this.election});

  @override
  State<ElectionDetailScreen> createState() => _ElectionDetailScreenState();
}

class _ElectionDetailScreenState extends State<ElectionDetailScreen> {
  int? _selectedCandidateId;
  bool _isVoting = false;
  bool _hasVoteToken = false;
  bool _isRequestingToken = false;
  StreamSubscription<VoteTokenEvent>? _voteTokenSubscription;
  Election? _currentElection; // Track current election state
  Timer? _tokenRequestTimeout; // Timeout for token requests

  @override
  void initState() {
    super.initState();
    _currentElection = widget.election;
    // Save this election as the selected one when the user opens it
    _saveSelectedElection();
    _checkVoteTokenAvailability();
    _startVoteTokenListener();
  }

  @override
  void dispose() {
    _voteTokenSubscription?.cancel();
    _tokenRequestTimeout?.cancel();
    super.dispose();
  }

  Future<void> _saveSelectedElection() async {
    try {
      await SelectedElectionService.setSelectedElection(widget.election);
      debugPrint(
        '💾 Saved selected election: ${widget.election.name} (${widget.election.id})',
      );
    } catch (e) {
      debugPrint('❌ Error saving selected election: $e');
    }
  }

  Future<void> _checkVoteTokenAvailability() async {
    try {
      final session = await VoterSessionService.getCompleteSession();
      final hasToken =
          session != null &&
          session['unblindedSignature'] != null &&
          session['electionId'] == widget.election.id;

      // Check if we have an initial session (which means token request was started)
      final hasInitialSession = await VoterSessionService.hasInitialSession();
      final sessionElectionId = await VoterSessionService.getElectionId();
      final isRequestingForThisElection =
          hasInitialSession &&
          sessionElectionId == widget.election.id &&
          !hasToken;

      setState(() {
        _hasVoteToken = hasToken;
        _isRequestingToken = isRequestingForThisElection;
      });

      // Start timeout if we're requesting a token
      if (_isRequestingToken) {
        _startTokenRequestTimeout();
      }

      debugPrint('🎫 Vote token available: $_hasVoteToken');
      debugPrint('🔄 Requesting token: $_isRequestingToken');
      _debugCurrentState();
    } catch (e) {
      debugPrint('❌ Error checking vote token: $e');
      setState(() {
        _hasVoteToken = false;
        _isRequestingToken = false;
      });
    }
  }

  void _startTokenRequestTimeout() {
    // Cancel any existing timeout
    _tokenRequestTimeout?.cancel();
    
    // Start a 30-second timeout for token requests
    _tokenRequestTimeout = Timer(const Duration(seconds: 30), () {
      if (mounted && _isRequestingToken) {
        debugPrint('⏰ Token request timeout reached');
        
        setState(() {
          _isRequestingToken = false;
          _hasVoteToken = false;
        });
        
        // Show timeout message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏰ Token request timeout. The Election Coordinator may be unavailable.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                // Navigate back to elections screen to retry
                Navigator.of(context).pop();
              },
            ),
          ),
        );
      }
    });
    
    debugPrint('⏰ Started 30-second timeout for token request');
  }

  void _startVoteTokenListener() {
    _voteTokenSubscription = VoterSessionService.voteTokenStream.listen(
      (event) {
        debugPrint('🔔 Received vote token event: $event');

        // Only process events for this election
        if (event.electionId == widget.election.id) {
          // Cancel timeout since we received a response
          _tokenRequestTimeout?.cancel();
          
          if (event.isSuccess) {
            // Handle successful token receipt
            debugPrint('✅ Vote token now available for this election!');
            debugPrint(
              '🔍 Before setState - _hasVoteToken: $_hasVoteToken, _isRequestingToken: $_isRequestingToken',
            );

            if (mounted) {
              setState(() {
                _hasVoteToken = true;
                _isRequestingToken = false;
              });

              debugPrint(
                '🔍 After setState - _hasVoteToken: $_hasVoteToken, _isRequestingToken: $_isRequestingToken',
              );
              _debugCurrentState();

              // Show success feedback
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Vote token received! You can now vote.'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          } else if (event.isError) {
            // Handle error from EC
            debugPrint('🚨 Vote token error received: ${event.errorType}');
            debugPrint('   Error message: ${event.errorMessage}');

            if (mounted) {
              setState(() {
                _hasVoteToken = false;
                _isRequestingToken = false; // Stop showing "requesting" state
              });

              _debugCurrentState();

              // Show error feedback with specific message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ ${event.errorType}: ${event.errorMessage}'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 8), // Longer duration for errors
                  action: SnackBarAction(
                    label: 'Dismiss',
                    textColor: Colors.white,
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    },
                  ),
                ),
              );
            }
          }
        }
      },
      onError: (error) {
        debugPrint('❌ Vote token stream error: $error');
      },
    );

    debugPrint(
      '🎧 Started listening for vote token events for election: ${widget.election.id}',
    );
  }

  void _debugCurrentState() {
    final now = DateTime.now();
    final election = _currentElection ?? widget.election;
    final isActive =
        election.status.toLowerCase() == 'in-progress' ||
        (election.status.toLowerCase() == 'open' &&
            now.isAfter(election.startTime) &&
            now.isBefore(election.endTime));

    debugPrint('🔍 === CURRENT STATE DEBUG ===');
    debugPrint('   Election ID: ${election.id}');
    debugPrint('   Election Status: ${election.status}');
    debugPrint('   Start Time: ${election.startTime}');
    debugPrint('   End Time: ${election.endTime}');
    debugPrint('   Current Time: $now');
    debugPrint('   Is Active: $isActive');
    debugPrint('   Has Vote Token: $_hasVoteToken');
    debugPrint('   Is Requesting Token: $_isRequestingToken');
    debugPrint('   Is Voting: $_isVoting');
    debugPrint('   Selected Candidate: $_selectedCandidateId');
    debugPrint('   Candidates Count: ${election.candidates.length}');
    debugPrint(
      '   Allow Selection: ${election.status.toLowerCase() == 'open' || election.status.toLowerCase() == 'in-progress'}',
    );
    debugPrint('   Allow Voting: $isActive');
    debugPrint('=============================');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ElectionProvider>(
      builder: (context, provider, child) {
        // Get the most up-to-date election from provider
        final latestElection = provider.elections.firstWhere(
          (e) => e.id == widget.election.id,
          orElse: () => widget.election, // Fallback to original if not found
        );

        // Update our current election reference if it changed
        if (_currentElection?.status != latestElection.status) {
          debugPrint(
            '🔄 Election status updated in UI: ${_currentElection?.status} -> ${latestElection.status}',
          );
          _currentElection = latestElection;
        }

        final now = DateTime.now();
        final isActive =
            latestElection.status.toLowerCase() == 'in-progress' ||
            (latestElection.status.toLowerCase() == 'open' &&
                now.isAfter(latestElection.startTime) &&
                now.isBefore(latestElection.endTime));

        // Allow candidate selection if election is open or in-progress
        final allowCandidateSelection =
            latestElection.status.toLowerCase() == 'open' ||
            latestElection.status.toLowerCase() == 'in-progress';
        final allowVoting = isActive;

        return _buildElectionDetail(
          context,
          latestElection,
          isActive,
          allowCandidateSelection,
          allowVoting,
        );
      },
    );
  }

  Widget _buildElectionDetail(
    BuildContext context,
    Election election,
    bool isActive,
    bool allowCandidateSelection,
    bool allowVoting,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(election.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Election Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            election.name,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        _buildStatusChip(context, election),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context).electionStartLabel(
                                  _formatDateTime(election.startTime),
                                ),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                AppLocalizations.of(context).electionEndLabel(
                                  _formatDateTime(election.endTime),
                                ),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Election ID
                    Row(
                      children: [
                        Icon(
                          Icons.fingerprint,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Election ID: ${election.id}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontFamily: 'monospace',
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Candidates Section
            Text(
              AppLocalizations.of(
                context,
              ).candidatesCount(election.candidates.length),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            if (election.candidates.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    AppLocalizations.of(context).noCandidatesForElection,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              )
            else
              // Candidate selection with radio buttons
              ...election.candidates.map(
                (candidate) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: RadioListTile<int>(
                    title: Text(
                      candidate.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text('Candidate ID: ${candidate.id}'),
                    value: candidate.id,
                    groupValue: _selectedCandidateId,
                    onChanged: allowCandidateSelection
                        ? (value) {
                            setState(() {
                              _selectedCandidateId = value;
                            });
                            debugPrint(
                              '🗳️ Selected candidate: ${candidate.name} (ID: ${candidate.id})',
                            );
                          }
                        : null,
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Debug information
            if (kDebugMode) // Show only in debug builds
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Debug Info:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text('Active: $isActive', style: TextStyle(fontSize: 11)),
                    Text(
                      'Allow Selection: $allowCandidateSelection',
                      style: TextStyle(fontSize: 11),
                    ),
                    Text(
                      'Allow Voting: $allowVoting',
                      style: TextStyle(fontSize: 11),
                    ),
                    Text(
                      'Has Token: $_hasVoteToken',
                      style: TextStyle(fontSize: 11),
                    ),
                    Text(
                      'Requesting: $_isRequestingToken',
                      style: TextStyle(fontSize: 11),
                    ),
                    Text(
                      'Status: ${election.status}',
                      style: TextStyle(fontSize: 11),
                    ),
                    Text(
                      'Candidates: ${election.candidates.length}',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),

            // Vote token status
            if (!_hasVoteToken && allowCandidateSelection)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _isRequestingToken
                      ? Colors.blue.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  border: Border.all(
                    color: _isRequestingToken ? Colors.blue : Colors.orange,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (_isRequestingToken)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue,
                          ),
                        ),
                      )
                    else
                      Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isRequestingToken
                            ? 'Requesting vote token... Please wait.'
                            : 'You need to request a vote token first by selecting this election from the elections list.',
                        style: TextStyle(
                          color: _isRequestingToken
                              ? Colors.blue[800]
                              : Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Action buttons
            if (allowCandidateSelection && election.candidates.isNotEmpty)
              Column(
                children: [
                  // Vote button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _selectedCandidateId != null && !_isVoting
                          ? (_hasVoteToken
                                ? (allowVoting
                                      ? _showVoteConfirmation
                                      : _showElectionNotStarted)
                                : _showNoTokenDialog)
                          : null,
                      icon: _isVoting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.how_to_vote),
                      label: Text(_isVoting ? 'Sending Vote...' : 'Vote'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Clear selection button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _selectedCandidateId != null && !_isVoting
                          ? _clearSelection
                          : null,
                      icon: Icon(Icons.clear),
                      label: Text('Clear Selection'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, Election election) {
    Color chipColor;
    String label;
    IconData icon;

    switch (election.status.toLowerCase()) {
      case 'open':
        chipColor = Colors.orange;
        label = AppLocalizations.of(context).statusOpen;
        icon = Icons.schedule;
        break;
      case 'in-progress':
        chipColor = Colors.green;
        label = AppLocalizations.of(context).statusInProgress;
        icon = Icons.radio_button_checked;
        break;
      case 'finished':
        chipColor = Colors.blue;
        label = AppLocalizations.of(context).statusFinished;
        icon = Icons.check_circle_outline;
        break;
      case 'canceled':
        chipColor = Colors.red;
        label = AppLocalizations.of(context).statusCanceled;
        icon = Icons.cancel_outlined;
        break;
      default:
        chipColor = Colors.grey;
        label = election.status;
        icon = Icons.info_outline;
    }

    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: chipColor,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _clearSelection() {
    setState(() {
      _selectedCandidateId = null;
    });
    debugPrint('🗑️ Cleared candidate selection');
  }

  void _showVoteConfirmation() {
    if (_selectedCandidateId == null) return;

    final election = _currentElection ?? widget.election;
    final selectedCandidate = election.candidates.firstWhere(
      (c) => c.id == _selectedCandidateId,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => VoteConfirmationDialog(
        candidate: selectedCandidate,
        election: election,
        onConfirm: _sendVote,
      ),
    );
  }

  void _showNoTokenDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 12),
            Text('Vote Token Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You need a vote token to cast your vote.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To get a vote token:',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Go back to the elections list\n'
                    '2. Tap on this election again\n'
                    '3. The app will request a vote token automatically',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to elections list
            },
            child: Text('Go to Elections'),
          ),
        ],
      ),
    );
  }

  void _showElectionNotStarted() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.schedule, color: Colors.blue),
            const SizedBox(width: 12),
            Text('Election Not Started'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The voting period for this election has not started yet.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Election Times:',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Starts: ${_formatDateTime((_currentElection ?? widget.election).startTime)}\n'
                    'Ends: ${_formatDateTime((_currentElection ?? widget.election).endTime)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You can select your candidate now and vote when the election starts.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendVote() async {
    if (_selectedCandidateId == null) return;

    setState(() {
      _isVoting = true;
    });

    try {
      debugPrint(
        '🗳️ Sending vote for candidate $_selectedCandidateId in election ${widget.election.id}',
      );

      final voteService = VoteService();
      await voteService.sendVote(
        electionId: (_currentElection ?? widget.election).id,
        candidateId: _selectedCandidateId!,
      );

      debugPrint('✅ Vote sent successfully!');

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Vote sent successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // Navigate back to elections list
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Error sending vote: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error sending vote: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVoting = false;
        });
      }
    }
  }
}
