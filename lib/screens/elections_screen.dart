import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/election.dart';
import '../providers/election_provider.dart';
import '../widgets/election_card.dart';
import 'election_detail_screen.dart';
import '../generated/app_localizations.dart';
import '../services/nostr_service.dart';
import '../services/nostr_key_manager.dart';
import '../services/crypto_service.dart';
import '../services/voter_session_service.dart';
import '../config/app_config.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:blind_rsa_signatures/blind_rsa_signatures.dart';

class ElectionsScreen extends StatefulWidget {
  const ElectionsScreen({super.key});

  @override
  State<ElectionsScreen> createState() => _ElectionsScreenState();
}

class _ElectionsScreenState extends State<ElectionsScreen> {
  @override
  void initState() {
    super.initState();
    // Elections are already loaded in MainScreenState, no need to load again
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<ElectionProvider>(
        builder: (context, provider, child) {
          return RefreshIndicator(
            onRefresh: () async {
              await provider.refreshElections();
            },
            child: _buildContent(context, provider),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, ElectionProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null) {
      return _buildScrollableErrorView(context, provider);
    }

    if (provider.elections.isEmpty) {
      return _buildScrollableEmptyView(context);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.elections.length,
      itemBuilder: (context, index) {
        final election = provider.elections[index];
        return ElectionCard(
          election: election,
          onTap: () async => await _navigateToElectionDetail(election),
        );
      },
    );
  }

  Widget _buildScrollableErrorView(
    BuildContext context,
    ElectionProvider provider,
  ) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height:
            MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            AppBar().preferredSize.height,
        child: Center(
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
                AppLocalizations.of(context).errorWithMessage(provider.error!),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => provider.loadElections(),
                child: Text(AppLocalizations.of(context).retry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableEmptyView(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height:
            MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            AppBar().preferredSize.height,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.how_to_vote_outlined,
                  size: 80,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context).noElectionsFound,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).noActiveElectionsFound,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Check if we already have a valid vote token for the given election
  /// This now includes proper validation of the token against the election
  Future<bool> _hasValidTokenForElection(String electionId) async {
    try {
      final session = await VoterSessionService.getCompleteSession();
      if (session == null) {
        debugPrint('🔍 No session data found');
        return false;
      }

      final sessionElectionId = session['electionId'] as String?;
      final unblindedSignature = session['unblindedSignature'] as Uint8List?;

      // Basic existence check
      final hasSessionData =
          sessionElectionId == electionId && unblindedSignature != null;

      debugPrint('🔍 Token check for election $electionId:');
      debugPrint('   Session election ID: $sessionElectionId');
      debugPrint('   Has unblinded signature: ${unblindedSignature != null}');
      debugPrint('   Session data exists: $hasSessionData');

      // If no session data, definitely no valid token
      if (!hasSessionData) {
        debugPrint(
          '🔄 No valid token found for election $electionId, requesting new token',
        );
        return false;
      }

      // ENHANCED VALIDATION: Check if the stored token is actually valid
      debugPrint('🔐 Validating stored token against election requirements...');

      // For now, we'll be conservative and treat any stored token as potentially invalid
      // until we can verify the voter is authorized for this specific election.

      // Check session age - if session is older than 24 hours, consider it stale
      final sessionTimestamp = session['timestamp'] as int?;
      if (sessionTimestamp != null) {
        final sessionAge =
            DateTime.now().millisecondsSinceEpoch - sessionTimestamp;
        final sessionAgeHours = sessionAge / (1000 * 60 * 60);

        debugPrint(
          '   Session age: ${sessionAgeHours.toStringAsFixed(1)} hours',
        );

        if (sessionAgeHours > 24) {
          debugPrint(
            '⚠️ Session is stale (>24h old), clearing and requesting new token',
          );
          await VoterSessionService.clearSession();
          return false;
        }
      }

      // If we get here, the token is valid and not stale
      debugPrint('✅ Valid token found and trusted for election $electionId');

      return true;
    } catch (e) {
      debugPrint('❌ Error checking token availability: $e');
      return false;
    }
  }

  Future<void> _navigateToElectionDetail(Election election) async {
    if (election.status.toLowerCase() == 'open') {
      // Check if we already have a valid token for this election
      final hasToken = await _hasValidTokenForElection(election.id);

      if (hasToken) {
        debugPrint(
          '✅ Valid token already exists for election ${election.id}, skipping request',
        );
      } else {
        debugPrint(
          '🔄 No valid token found for election ${election.id}, requesting new token',
        );
        await _requestBlindSignature(election);
      }
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElectionDetailScreen(election: election),
      ),
    );
  }

  Future<void> _requestBlindSignature(Election election) async {
    try {
      final keys = await NostrKeyManager.getDerivedKeys();
      final privKey = keys['privateKey'] as Uint8List;
      final pubKey = keys['publicKey'] as Uint8List;

      String bytesToHex(Uint8List b) =>
          b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

      final voterPrivHex = bytesToHex(privKey);
      final voterPubHex = bytesToHex(pubKey);
      debugPrint('Voter private key (hex): $voterPrivHex');
      debugPrint('Voter public key (hex): $voterPubHex');

      final der = base64.decode(election.rsaPubKey);
      final ecPk = PublicKey.fromDer(der);

      final nonce = CryptoService.generateNonce();
      final hashed = CryptoService.hashNonce(nonce);
      final result = CryptoService.blindNonce(hashed, ecPk);

      // DEBUG: Check what's actually in the BlindingResult
      debugPrint('🔍 BLINDING RESULT DEBUG:');
      debugPrint('   blindMessage length: ${result.blindMessage.length}');
      debugPrint('   secret length: ${result.secret.length}');
      debugPrint(
        '   messageRandomizer: ${result.messageRandomizer?.length ?? 'NULL'}',
      );
      if (result.messageRandomizer != null) {
        debugPrint(
          '   messageRandomizer first 10 bytes: ${result.messageRandomizer!.take(10).toList()}',
        );
      }

      // Save complete session state including election ID and hash bytes (matching Rust app variable)
      await VoterSessionService.saveSession(
        nonce,
        result,
        hashed,
        election.id,
        election.rsaPubKey,
        voterPubHex,
      );

      // Use the shared NostrService instance to avoid concurrent connection issues
      final nostr = NostrService.instance;

      // Start listening for Gift Wrap responses before sending the request
      debugPrint('🎁 Starting Gift Wrap listener for voter responses...');
      await nostr.startGiftWrapListener(voterPubHex, voterPrivHex);

      // Send the blind signature request
      await nostr.sendBlindSignatureRequestSafe(
        ecPubKey: AppConfig.ecPublicKey,
        electionId: election.id,
        blindedNonce: result.blindMessage,
        voterPrivKeyHex: voterPrivHex,
        voterPubKeyHex: voterPubHex,
      );

      debugPrint('✅ Blind signature request sent, listening for response...');
    } catch (e) {
      debugPrint('❌ Error requesting blind signature: $e');
    }
  }
}
