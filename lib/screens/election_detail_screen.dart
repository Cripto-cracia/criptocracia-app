import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:blind_rsa_signatures/blind_rsa_signatures.dart';
import '../models/election.dart';
import '../models/message.dart';
import '../widgets/vote_confirmation_dialog.dart';
import '../generated/app_localizations.dart';
import '../services/selected_election_service.dart';
import '../services/vote_service.dart';
import '../services/voter_session_service.dart';
import '../services/nostr_service.dart';
import '../services/nostr_key_manager.dart';
import '../services/crypto_service.dart';
import '../services/blind_signature_processor.dart';
import '../config/app_config.dart';
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
  StreamSubscription? _messageSubscription;
  StreamSubscription? _errorSubscription;
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
    _setupMessageListeners();
    // Start automatic token request if needed
    _triggerAutomaticTokenRequestIfNeeded();
  }

  @override
  void dispose() {
    _voteTokenSubscription?.cancel();
    _messageSubscription?.cancel();
    _errorSubscription?.cancel();
    _tokenRequestTimeout?.cancel();
    super.dispose();
  }

  /// Setup listeners for incoming Gift Wrap messages
  void _setupMessageListeners() {
    final nostr = NostrService.instance;
    
    // Listen for incoming messages
    _messageSubscription = nostr.messageStream.listen((message) {
      debugPrint('📨 Received message in ElectionDetailScreen: $message');
      debugPrint('   For election: ${widget.election.id}');
      _handleIncomingMessage(message);
    });

    // Listen for errors
    _errorSubscription = nostr.errorStream.listen((error) {
      debugPrint('❌ NostrService error in ElectionDetailScreen: $error');
      // Could show user-friendly error message here
    });
    
    debugPrint('🎧 ElectionDetailScreen: Message listeners setup complete');
  }

  /// Handle incoming messages from Gift Wrap events
  Future<void> _handleIncomingMessage(Message message) async {
    try {
      debugPrint('🔄 ElectionDetailScreen: Processing message: $message');
      debugPrint('   Kind: ${message.kind}');
      debugPrint('   Election ID: ${message.electionId}');
      debugPrint('   isTokenMessage: ${message.isTokenMessage}');
      debugPrint('   isVoteMessage: ${message.isVoteMessage}');
      debugPrint('   isErrorMessage: ${message.isErrorMessage}');
      
      final processor = BlindSignatureProcessor.instance;
      final success = await processor.processMessage(message);
      
      debugPrint('🔄 ElectionDetailScreen: Message processing result: $success');
      
      if (success) {
        if (message.isTokenMessage) {
          debugPrint('✅ Blind signature processed successfully for election: ${message.electionId}');
        } else if (message.isErrorMessage) {
          debugPrint('❌ Error message processed for election: ${message.electionId}');
        }
      } else {
        debugPrint('❌ Failed to process message for election: ${message.electionId}');
      }
    } catch (e) {
      debugPrint('❌ Error handling incoming message: $e');
    }
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
    } catch (e) {
      debugPrint('❌ Error checking vote token: $e');
      setState(() {
        _hasVoteToken = false;
        _isRequestingToken = false;
      });
    }
  }

  /// Automatically trigger token request if user has no token and no active request
  Future<void> _triggerAutomaticTokenRequestIfNeeded() async {
    // Wait a bit for the initial state check to complete
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Re-check state after delay to ensure we have current values
    await _checkVoteTokenAvailability();
    
    // Only trigger automatic request if:
    // 1. User has no vote token
    // 2. No active token request
    // 3. Election allows candidate selection (open or in-progress)
    final allowCandidateSelection = 
        widget.election.status.toLowerCase() == 'open' ||
        widget.election.status.toLowerCase() == 'in-progress';
    
    if (!_hasVoteToken && !_isRequestingToken && allowCandidateSelection) {
      debugPrint('🤖 Auto-triggering token request for election: ${widget.election.id}');
      
      // Clear any stale session data first
      await VoterSessionService.clearSession();
      await _startTokenRequest();
    }
  }

  void _startTokenRequestTimeout() {
    // Cancel any existing timeout
    _tokenRequestTimeout?.cancel();
    
    // Start a 60-second timeout for token requests
    _tokenRequestTimeout = Timer(const Duration(seconds: 60), () {
      if (mounted && _isRequestingToken) {
        debugPrint('⏰ Token request timeout reached');
        
        // Clear session data on timeout to allow retry
        _clearFailedSession();
        
        setState(() {
          _isRequestingToken = false;
          _hasVoteToken = false;
        });
        
        // Show timeout message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).tokenRequestTimeout),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: AppLocalizations.of(context).retry,
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                _requestTokenManually();
              },
            ),
          ),
        );
      }
    });
    
    debugPrint('⏰ Started 60-second timeout for token request');
  }

  /// Start a token request for this election
  Future<void> _startTokenRequest() async {
    try {
      debugPrint('🎫 Starting token request for election: ${widget.election.id}');
      
      // Update UI state to show requesting status
      setState(() {
        _isRequestingToken = true;
        _hasVoteToken = false;
      });
      
      // Start timeout for this request
      _startTokenRequestTimeout();
      
      // Call the actual token request implementation
      await _requestBlindSignature();
      
      debugPrint('🎫 Token request initiated - waiting for response...');
      
    } catch (e) {
      debugPrint('❌ Error starting token request: $e');
      
      if (mounted) {
        setState(() {
          _isRequestingToken = false;
        });
      }
    }
  }

  /// Request blind signature for this election (copied from elections_screen.dart)
  Future<void> _requestBlindSignature() async {
    try {
      final election = widget.election;
      
      final keys = await NostrKeyManager.getDerivedKeys();
      final privKey = keys['privateKey'] as Uint8List;
      final pubKey = keys['publicKey'] as Uint8List;

      String bytesToHex(Uint8List b) =>
          b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

      final voterPrivHex = bytesToHex(privKey);
      final voterPubHex = bytesToHex(pubKey);

      final der = base64.decode(election.rsaPubKey);
      final ecPk = PublicKey.fromDer(der);

      final nonce = CryptoService.generateNonce();
      final hashed = CryptoService.hashNonce(nonce);
      final result = CryptoService.blindNonce(hashed, ecPk);


      // Save complete session state including election ID and hash bytes (matching Rust app variable)
      await VoterSessionService.saveSession(nonce, result, hashed, election.id, election.rsaPubKey);

      // Use the shared NostrService instance to avoid concurrent connection issues
      final nostr = NostrService.instance;
      
      // Start listening for Gift Wrap responses before sending the request
      await nostr.startGiftWrapListener(voterPubHex, voterPrivHex);
      
      // Send the blind signature request
      await nostr.sendBlindSignatureRequestSafe(
        ecPubKey: AppConfig.ecPublicKey,
        electionId: election.id,
        blindedNonce: result.blindMessage,
        voterPrivKeyHex: voterPrivHex,
        voterPubKeyHex: voterPubHex,
      );
      
      debugPrint('✅ Blind signature request sent successfully, listening for response...');
    } catch (e) {
      debugPrint('❌ Error requesting blind signature: $e');
      
      // Notify about the error through the token stream
      VoterSessionService.emitTokenError(widget.election.id, 'Request Error', e.toString());
      
      rethrow; // Re-throw so the calling method can handle it
    }
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

              // Show success feedback
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context).voteTokenReceived),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          } else if (event.isError) {
            // Handle error from EC
            debugPrint('🚨 Vote token error received: ${event.errorType}');
            debugPrint('   Error message: ${event.errorMessage}');

            // Clear session data for specific error types that indicate user needs to retry
            if (event.errorType == 'Unauthorized Voter' || 
                event.errorType == 'Token Already Issued' ||
                (event.errorMessage?.contains('unauthorized-voter') ?? false) ||
                (event.errorMessage?.contains('nonce-hash-already-issued') ?? false)) {
              
              debugPrint('🗑️ Clearing session data due to authorization error - allowing retry');
              _clearFailedSession();
            }

            if (mounted) {
              setState(() {
                _hasVoteToken = false;
                _isRequestingToken = false; // Stop showing "requesting" state
              });


              // Show error feedback with specific message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ ${event.errorType}: ${event.errorMessage}'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 8), // Longer duration for errors
                  action: SnackBarAction(
                    label: 'Retry',
                    textColor: Colors.white,
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      _requestTokenManually();
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


  /// Clear failed session data to allow retry
  Future<void> _clearFailedSession() async {
    try {
      debugPrint('🗑️ Clearing failed session data for election: ${widget.election.id}');
      
      // Clear all session data related to this election
      await VoterSessionService.clearSession();
      
      debugPrint('✅ Session data cleared - user can now retry token request');
    } catch (e) {
      debugPrint('❌ Error clearing failed session: $e');
    }
  }

  /// Manually request a token (retry mechanism)
  Future<void> _requestTokenManually() async {
    try {
      debugPrint('🔄 Manually requesting token for election: ${widget.election.id}');
      
      // First clear any existing session data
      await _clearFailedSession();
      
      // Start the token request directly
      await _startTokenRequest();
      
    } catch (e) {
      debugPrint('❌ Error in manual token request: $e');
      
      if (mounted) {
        setState(() {
          _isRequestingToken = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error requesting token: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

        final isActive = latestElection.status.toLowerCase() == 'in-progress';

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
                child: Column(
                  children: [
                    Row(
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
                                ? AppLocalizations.of(context).requestingVoteToken
                                : AppLocalizations.of(context).needVoteTokenInstruction,
                            style: TextStyle(
                              color: _isRequestingToken
                                  ? Colors.blue[800]
                                  : Colors.orange[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!_isRequestingToken) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _requestTokenManually,
                          icon: Icon(Icons.refresh),
                          label: Text(AppLocalizations.of(context).retry),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
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
                      label: Text(_isVoting ? AppLocalizations.of(context).sendingVote : AppLocalizations.of(context).vote),
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
                      label: Text(AppLocalizations.of(context).clearSelection),
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
            Text(AppLocalizations.of(context).voteTokenRequired),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).voteTokenInstructions,
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
            child: Text(AppLocalizations.of(context).ok),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to elections list
            },
            child: Text(AppLocalizations.of(context).goToElections),
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
            Text(AppLocalizations.of(context).electionNotStarted),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).votingPeriodNotStarted,
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
              AppLocalizations.of(context).canSelectCandidateNow,
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
            child: Text(AppLocalizations.of(context).ok),
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
