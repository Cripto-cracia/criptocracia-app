import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:blind_rsa_signatures/blind_rsa_signatures.dart';
import '../models/election.dart';
import '../widgets/vote_confirmation_dialog.dart';
import '../generated/app_localizations.dart';
import '../services/selected_election_service.dart';
import '../services/vote_service.dart';
import '../services/voter_session_service.dart';
import '../services/nostr_service.dart';
import '../services/nostr_key_manager.dart';
import '../services/crypto_service.dart';
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
  StreamSubscription<String>? _processingStatusSubscription;
  Election? _currentElection; // Track current election state
  Timer? _tokenRequestTimeout; // Timeout for token requests
  String? _processingStatus; // Current processing status for UI

  @override
  void initState() {
    super.initState();
    _currentElection = widget.election;
    // Save this election as the selected one when the user opens it
    _saveSelectedElection();
    _checkVoteTokenAvailability();
    _startVoteTokenListener();
    _startProcessingStatusListener();
    // Start automatic token request if needed
    _triggerAutomaticTokenRequestIfNeeded();
  }

  @override
  void dispose() {
    _voteTokenSubscription?.cancel();
    _processingStatusSubscription?.cancel();
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

  void _showUnauthorizedVoterDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.red),
            const SizedBox(width: 12),
            Text('Unauthorized Voter'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are not authorized to vote in this election.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why am I seeing this?',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• You were not added to the voter list for this election\n'
                    '• The election administrator controls who can vote\n'
                    '• This prevents false "token available" messages',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Contact the election administrator if you believe this is an error.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to elections list
            },
            child: Text('Go Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Understood'),
          ),
        ],
      ),
    );
  }

  void _showNip59InfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 12),
            Text('NIP-59 Security Protocol'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your token request is being processed securely using NIP-59 protocol.',
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
                    'What is NIP-59?',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Encrypts messages for privacy\n'
                    '• Randomizes timestamps to prevent tracking\n'
                    '• May require processing multiple events\n'
                    '• Ensures your vote remains anonymous',
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
            child: Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkVoteTokenAvailability() async {
    try {
      final session = await VoterSessionService.getCompleteSession();
      
      // Basic session check
      final hasSessionData =
          session != null &&
          session['unblindedSignature'] != null &&
          session['electionId'] == widget.election.id;

      debugPrint('🔍 Vote token check for election ${widget.election.id}:');
      debugPrint('   Session data exists: $hasSessionData');
      
      // Add detailed session debugging
      if (session != null) {
        final sessionElectionId = session['electionId'] as String?;
        final unblindedSig = session['unblindedSignature'] as Uint8List?;
        final timestamp = session['timestamp'] as int?;
        
        debugPrint('🔍 Session Details:');
        debugPrint('   Stored election ID: $sessionElectionId');
        debugPrint('   Current election ID: ${widget.election.id}');
        debugPrint('   Election ID match: ${sessionElectionId == widget.election.id}');
        debugPrint('   Has unblinded signature: ${unblindedSig != null}');
        debugPrint('   Session timestamp: ${timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp).toString() : 'null'}');
        
        if (timestamp != null) {
          final age = DateTime.now().millisecondsSinceEpoch - timestamp;
          final ageHours = age / (1000 * 60 * 60);
          debugPrint('   Session age: ${ageHours.toStringAsFixed(2)} hours');
        }
      }

      // ENHANCED VALIDATION: Smart validation that recognizes recent processing
      bool hasValidToken = false;
      
      if (hasSessionData) {
        debugPrint('🔐 Found session data, validating token...');
        
        // Check both session creation and processing timestamps
        final sessionTimestamp = session['timestamp'] as int?;
        final processingTimestamp = session['processingTimestamp'] as int?;
        
        if (sessionTimestamp != null) {
          final sessionAge = DateTime.now().millisecondsSinceEpoch - sessionTimestamp;
          final sessionAgeHours = sessionAge / (1000 * 60 * 60);
          
          debugPrint('   Session age: ${sessionAgeHours.toStringAsFixed(1)} hours');
          
          if (sessionAgeHours > 24) {
            debugPrint('⚠️ Session is stale (>24h old), clearing session');
            await VoterSessionService.clearSession();
            hasValidToken = false;
          } else {
            // Check if token was recently processed (within last hour)
            if (processingTimestamp != null) {
              final processingAge = DateTime.now().millisecondsSinceEpoch - processingTimestamp;
              final processingAgeMinutes = processingAge / (1000 * 60);
              
              debugPrint('   Token processing age: ${processingAgeMinutes.toStringAsFixed(1)} minutes');
              debugPrint('   Token processed at: ${DateTime.fromMillisecondsSinceEpoch(processingTimestamp)}');
              
              if (processingAgeMinutes <= 60) {
                // Token was recently processed and validated - trust it
                debugPrint('✅ Token recently processed and validated, trusting stored token');
                hasValidToken = true;
                
                // If token was processed very recently (< 5 minutes), show success snackbar
                // This handles cases where validation runs after VoteTokenEvent emission
                if (processingAgeMinutes <= 5 && mounted) {
                  debugPrint('🎉 Showing snackbar for very recently processed token (${processingAgeMinutes.toStringAsFixed(1)} min ago)');
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context).voteTokenReceived),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  });
                }
              } else {
                // Token is older, apply conservative validation
                debugPrint('🔄 Token is older than 1 hour, applying conservative validation');
                hasValidToken = false;
              }
            } else {
              // No processing timestamp - either old session or unauthorized
              debugPrint('⚠️ No processing timestamp found, applying conservative validation');
              hasValidToken = false;
            }
          }
        } else {
          debugPrint('⚠️ Session missing timestamp, treating as invalid');
          await VoterSessionService.clearSession();
          hasValidToken = false;
        }
      }

      // Check if we have an initial session (which means token request was started)
      final hasInitialSession = await VoterSessionService.hasInitialSession();
      final sessionElectionId = await VoterSessionService.getElectionId();
      final isRequestingForThisElection =
          hasInitialSession &&
          sessionElectionId == widget.election.id &&
          !hasValidToken;

      setState(() {
        _hasVoteToken = hasValidToken;
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
      debugPrint(
        '🤖 Auto-triggering token request for election: ${widget.election.id}',
      );

      // Clear any stale session data first
      await VoterSessionService.clearSession();
      await _startTokenRequest();
    }
  }

  void _startTokenRequestTimeout() {
    // Cancel any existing timeout
    _tokenRequestTimeout?.cancel();

    // Start a 90-second timeout for token requests (increased from 60s)
    _tokenRequestTimeout = Timer(const Duration(seconds: 90), () {
      if (mounted && _isRequestingToken) {
        debugPrint('⏰ Token request timeout reached after 90 seconds');
        debugPrint('🔍 Connection status: ${NostrService.instance.isConnected}');

        // Stop connection health monitoring
        NostrService.instance.stopConnectionHealthMonitoring();

        // Clear session data on timeout to allow retry
        _clearFailedSession();

        setState(() {
          _isRequestingToken = false;
          _hasVoteToken = false;
          _processingStatus = null; // Clear processing status
        });

        // Show timeout message with NIP-59 educational info
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context).tokenRequestTimeout),
                const SizedBox(height: 6),
                Text(
                  'Processing multiple events due to NIP-59 security',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
                Text(
                  'Connection: ${NostrService.instance.isConnected ? "Connected" : "Disconnected"}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 10),
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

    debugPrint('⏰ Started 90-second timeout for token request');
  }

  /// Start a token request for this election
  Future<void> _startTokenRequest() async {
    try {
      debugPrint(
        '🎫 Starting token request for election: ${widget.election.id}',
      );

      // Update UI state to show requesting status
      setState(() {
        _isRequestingToken = true;
        _hasVoteToken = false;
      });

      // Start timeout for this request
      _startTokenRequestTimeout();

      // Start connection health monitoring during token waiting
      NostrService.instance.startConnectionHealthMonitoring();

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
      await VoterSessionService.saveSession(
        nonce,
        result,
        hashed,
        election.id,
        election.rsaPubKey,
      );

      // Use the shared NostrService instance to avoid concurrent connection issues
      final nostr = NostrService.instance;

      // Start listening for Gift Wrap responses before sending the request
      // Pass the election ID for smart filtering and prioritization
      await nostr.startGiftWrapListener(
        voterPubHex, 
        voterPrivHex,
        expectedElectionId: election.id,
      );

      // Send the blind signature request
      await nostr.sendBlindSignatureRequestSafe(
        ecPubKey: AppConfig.ecPublicKey,
        electionId: election.id,
        blindedNonce: result.blindMessage,
        voterPrivKeyHex: voterPrivHex,
        voterPubKeyHex: voterPubHex,
      );

      debugPrint(
        '✅ Blind signature request sent successfully, listening for response...',
      );
    } catch (e) {
      debugPrint('❌ Error requesting blind signature: $e');

      // Notify about the error through the token stream
      VoterSessionService.emitTokenError(
        widget.election.id,
        'Request Error',
        e.toString(),
      );

      rethrow; // Re-throw so the calling method can handle it
    }
  }

  void _startProcessingStatusListener() {
    _processingStatusSubscription = NostrService.instance.processingStatusStream.listen(
      (status) {
        debugPrint('🔄 Processing status update: $status');
        if (mounted) {
          setState(() {
            _processingStatus = status;
          });
        }
      },
      onError: (error) {
        debugPrint('❌ Processing status stream error: $error');
      },
    );
    
    debugPrint('👂 Started listening for processing status updates');
  }

  void _startVoteTokenListener() {
    _voteTokenSubscription = VoterSessionService.voteTokenStream.listen(
      (event) {
        debugPrint('🔔 Received vote token event: $event');
        debugPrint('🔔 Event details:');
        debugPrint('   Election ID: ${event.electionId}');
        debugPrint('   Is Available: ${event.isAvailable}');
        debugPrint('   Is Success: ${event.isSuccess}');
        debugPrint('   Is Error: ${event.isError}');
        debugPrint('   Current _hasVoteToken: $_hasVoteToken');
        debugPrint('   Current _isRequestingToken: $_isRequestingToken');

        // Only process events for this election
        if (event.electionId == widget.election.id) {
          debugPrint('🎯 Processing event for current election: ${widget.election.id}');
          // Cancel timeout since we received a response
          _tokenRequestTimeout?.cancel();
          
          // Stop connection health monitoring
          NostrService.instance.stopConnectionHealthMonitoring();

          if (event.isSuccess) {
            // Handle successful token receipt
            debugPrint('✅ Vote token now available for this election!');
            debugPrint(
              '🔍 Before setState - _hasVoteToken: $_hasVoteToken, _isRequestingToken: $_isRequestingToken',
            );

            if (mounted) {
              // Check if this is a fresh token event (not already recognized)
              final wasTokenAlreadyAvailable = _hasVoteToken;
              
              setState(() {
                _hasVoteToken = true;
                _isRequestingToken = false;
                _processingStatus = null; // Clear processing status
              });

              debugPrint(
                '🔍 After setState - _hasVoteToken: $_hasVoteToken, _isRequestingToken: $_isRequestingToken',
              );
              debugPrint('🔍 Was token already available: $wasTokenAlreadyAvailable');

              // Always show success feedback for token events, regardless of previous state
              // This ensures users get confirmation even if validation logic already recognized the token
              debugPrint('🎉 Showing success snackbar for token receipt');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context).voteTokenReceived),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 5),
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
                (event.errorMessage?.contains('nonce-hash-already-issued') ??
                    false)) {
              debugPrint(
                '🗑️ Clearing session data due to authorization error - allowing retry',
              );
              _clearFailedSession();
              
              // Show specific unauthorized voter dialog for clarity
              if (event.errorType == 'Unauthorized Voter' || 
                  (event.errorMessage?.contains('unauthorized-voter') ?? false)) {
                _showUnauthorizedVoterDialog();
                return; // Don't show the generic error snackbar
              }
            }

            if (mounted) {
              setState(() {
                _hasVoteToken = false;
                _isRequestingToken = false; // Stop showing "requesting" state
                _processingStatus = null; // Clear processing status
              });

              // Show error feedback with specific message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ ${event.errorType}: ${event.errorMessage}'),
                  backgroundColor: Colors.red,
                  duration: const Duration(
                    seconds: 8,
                  ), // Longer duration for errors
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
      debugPrint(
        '🗑️ Clearing failed session data for election: ${widget.election.id}',
      );

      // Clear all session data related to this election
      await VoterSessionService.clearSession();

      debugPrint('✅ Session data cleared - user can now retry token request');
    } catch (e) {
      debugPrint('❌ Error clearing failed session: $e');
    }
  }

  /// Manual session validation for debugging
  Future<void> _debugValidateSession() async {
    try {
      debugPrint('🔧 DEBUG: Manual session validation triggered');
      
      final session = await VoterSessionService.getCompleteSession();
      if (session == null) {
        debugPrint('🔧 DEBUG: No session data found');
        return;
      }
      
      debugPrint('🔧 DEBUG: Full session contents:');
      session.forEach((key, value) {
        if (value is Uint8List) {
          debugPrint('   $key: ${value.length} bytes');
        } else {
          debugPrint('   $key: $value');
        }
      });
      
      final isValid = await VoterSessionService.validateSession();
      debugPrint('🔧 DEBUG: Session validation result: $isValid');
      
    } catch (e) {
      debugPrint('🔧 DEBUG: Session validation error: $e');
    }
  }

  /// Manual session clear for debugging
  Future<void> _debugClearSession() async {
    debugPrint('🔧 DEBUG: Manual session clear triggered');
    await VoterSessionService.clearSession();
    await _checkVoteTokenAvailability();
    debugPrint('🔧 DEBUG: Session cleared and token status refreshed');
  }

  /// Manually request a token (retry mechanism)
  Future<void> _requestTokenManually() async {
    try {
      debugPrint(
        '🔄 Manually requesting token for election: ${widget.election.id}',
      );

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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isRequestingToken
                                    ? AppLocalizations.of(
                                        context,
                                      ).requestingVoteToken
                                    : AppLocalizations.of(
                                        context,
                                      ).needVoteTokenInstruction,
                                style: TextStyle(
                                  color: _isRequestingToken
                                      ? Colors.blue[800]
                                      : Colors.orange[800],
                                ),
                              ),
                              if (_processingStatus != null && _isRequestingToken) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _processingStatus!,
                                        style: TextStyle(
                                          color: Colors.blue[600],
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                    if (_processingStatus!.contains('NIP-59') || 
                                        _processingStatus!.contains('historical'))
                                      IconButton(
                                        onPressed: _showNip59InfoDialog,
                                        icon: Icon(
                                          Icons.info_outline,
                                          size: 16,
                                          color: Colors.blue[600],
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: BoxConstraints(
                                          minWidth: 20,
                                          minHeight: 20,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
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
                      label: Text(
                        _isVoting
                            ? AppLocalizations.of(context).sendingVote
                            : AppLocalizations.of(context).vote,
                      ),
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
            content: Text(AppLocalizations.of(context).voteCastSuccess),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
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
