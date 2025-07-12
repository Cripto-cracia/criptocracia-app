import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../generated/app_localizations.dart';
import '../providers/settings_provider.dart';
import '../models/relay_status.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _ecKeyController = TextEditingController();
  final TextEditingController _relayController = TextEditingController();
  bool _isRefreshing = false;
  SettingsProvider? _settingsProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settingsProvider == null) {
      _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      _settingsProvider!.addListener(_onSettingsChanged);
      _updateEcKeyController(_settingsProvider!);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_settingsProvider != null) {
        _settingsProvider!.initializeStatusMonitoring();
      }
    });
  }

  void _onSettingsChanged() {
    if (mounted && _settingsProvider != null) {
      _updateEcKeyController(_settingsProvider!);
    }
  }

  void _updateEcKeyController(SettingsProvider settingsProvider) {
    if (mounted && _ecKeyController.text != settingsProvider.ecPublicKey) {
      debugPrint('🔄 Updating EC key controller from ${_ecKeyController.text} to ${settingsProvider.ecPublicKey}');
      _ecKeyController.text = settingsProvider.ecPublicKey;
    }
  }

  @override
  void dispose() {
    _settingsProvider?.removeListener(_onSettingsChanged);
    _ecKeyController.dispose();
    _relayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).settings),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshRelayStatuses,
            tooltip: AppLocalizations.of(context).refreshRelayStatuses,
          ),
        ],
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRelaySection(context, settingsProvider),
                const SizedBox(height: 32),
                _buildEcKeySection(context, settingsProvider),
                const SizedBox(height: 32),
                _buildLanguageSection(context, settingsProvider),
                const SizedBox(height: 32),
                _buildConnectionStatsSection(context, settingsProvider),
                const SizedBox(height: 32),
                _buildVersionInfo(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRelaySection(BuildContext context, SettingsProvider settingsProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).relayManagement,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).relayManagementDescription,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ...settingsProvider.relayUrls.map((url) => _buildRelayItem(context, settingsProvider, url)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAddRelayDialog(context, settingsProvider),
                icon: const Icon(Icons.add),
                label: Text(AppLocalizations.of(context).addRelay),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelayItem(BuildContext context, SettingsProvider settingsProvider, String url) {
    final status = settingsProvider.relayStatuses[url];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildStatusIndicator(status),
        title: Text(
          url,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        subtitle: _buildStatusSubtitle(context, status),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditRelayDialog(context, settingsProvider, url),
              tooltip: AppLocalizations.of(context).editRelay,
            ),
            if (settingsProvider.relayUrls.length > 1)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => _showDeleteRelayDialog(context, settingsProvider, url),
                tooltip: AppLocalizations.of(context).deleteRelay,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(RelayStatus? status) {
    if (status == null) {
      return const CircleAvatar(
        radius: 8,
        backgroundColor: Colors.grey,
        child: Icon(Icons.help_outline, size: 12, color: Colors.white),
      );
    }

    Color color;
    IconData icon;
    
    if (status.isConnected) {
      color = Colors.green;
      icon = Icons.check;
    } else {
      color = Colors.red;
      icon = Icons.error;
    }

    return CircleAvatar(
      radius: 8,
      backgroundColor: color,
      child: Icon(icon, size: 12, color: Colors.white),
    );
  }

  Widget _buildStatusSubtitle(BuildContext context, RelayStatus? status) {
    if (status == null) {
      return Text(AppLocalizations.of(context).statusUnknown);
    }

    final List<String> parts = [];
    
    if (status.isConnected) {
      parts.add(AppLocalizations.of(context).statusConnected);
    } else {
      parts.add(AppLocalizations.of(context).statusDisconnected);
    }

    if (status.latencyMs != null) {
      parts.add('${status.latencyMs}ms');
    }

    if (status.lastSeen != null) {
      final diff = DateTime.now().difference(status.lastSeen!);
      if (diff.inMinutes < 1) {
        parts.add(AppLocalizations.of(context).lastSeenJustNow);
      } else if (diff.inHours < 1) {
        parts.add(AppLocalizations.of(context).lastSeenMinutesAgo(diff.inMinutes));
      } else {
        parts.add(AppLocalizations.of(context).lastSeenHoursAgo(diff.inHours));
      }
    }

    if (status.error != null) {
      parts.add(AppLocalizations.of(context).errorPrefix(status.error!));
    }

    return Text(
      parts.join(' • '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildEcKeySection(BuildContext context, SettingsProvider settingsProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).ecPublicKeyTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).ecPublicKeyDescription,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ecKeyController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).ecPublicKeyLabel,
                hintText: AppLocalizations.of(context).ecPublicKeyHint,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () => _saveEcKey(context, settingsProvider),
                  tooltip: AppLocalizations.of(context).saveEcKey,
                ),
              ),
              maxLength: 64,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSection(BuildContext context, SettingsProvider settingsProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).languageSelection,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).languageSelectionDescription,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _buildLanguageOption(
              context,
              settingsProvider,
              null, // System default
              AppLocalizations.of(context).systemDefault,
            ),
            _buildLanguageOption(
              context,
              settingsProvider,
              const Locale('en'),
              AppLocalizations.of(context).english,
            ),
            _buildLanguageOption(
              context,
              settingsProvider,
              const Locale('es'),
              AppLocalizations.of(context).spanish,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(
    BuildContext context,
    SettingsProvider settingsProvider,
    Locale? locale,
    String title,
  ) {
    return ListTile(
      title: Text(title),
      leading: Radio<String>(
        value: locale?.languageCode ?? 'system',
        groupValue: settingsProvider.selectedLocale?.languageCode ?? 'system',
        onChanged: (value) => _changeLanguage(context, settingsProvider, locale),
      ),
      onTap: () => _changeLanguage(context, settingsProvider, locale),
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _changeLanguage(
    BuildContext context,
    SettingsProvider settingsProvider,
    Locale? locale,
  ) async {
    final success = await settingsProvider.updateLocale(locale);
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).languageChanged),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildConnectionStatsSection(BuildContext context, SettingsProvider settingsProvider) {
    final stats = settingsProvider.getConnectionStats();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).connectionStats,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  context,
                  AppLocalizations.of(context).totalRelays,
                  stats['total']!,
                  Colors.blue,
                ),
                _buildStatItem(
                  context,
                  AppLocalizations.of(context).connectedRelays,
                  stats['connected']!,
                  Colors.green,
                ),
                _buildStatItem(
                  context,
                  AppLocalizations.of(context).disconnectedRelays,
                  stats['disconnected']!,
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, int value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value.toString(),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildVersionInfo(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).versionInfo,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final packageInfo = snapshot.data!;
                  return Column(
                    children: [
                      _buildInfoRow(
                        context,
                        AppLocalizations.of(context).appVersion,
                        packageInfo.version,
                      ),
                      if (packageInfo.buildNumber.isNotEmpty)
                        _buildInfoRow(
                          context,
                          AppLocalizations.of(context).buildNumber,
                          packageInfo.buildNumber,
                        ),
                      _buildInfoRow(
                        context,
                        AppLocalizations.of(context).gitCommit,
                        () {
                          const fullCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: 'unknown');
                          return fullCommit == 'unknown' ? fullCommit : fullCommit.substring(0, 7);
                        }(),
                        monospace: true,
                      ),
                    ],
                  );
                } else {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, {bool monospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: monospace ? 'monospace' : null,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshRelayStatuses() async {
    setState(() => _isRefreshing = true);
    
    try {
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      await settingsProvider.refreshRelayStatuses();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).relayStatusesRefreshed),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).errorRefreshingStatuses),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _saveEcKey(BuildContext context, SettingsProvider settingsProvider) {
    final newKey = _ecKeyController.text.trim();
    
    if (settingsProvider.updateEcPublicKey(newKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).ecKeyUpdatedSuccessfully),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).invalidEcKeyFormat),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAddRelayDialog(BuildContext context, SettingsProvider settingsProvider) {
    _relayController.clear();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).addRelay),
        content: TextField(
          controller: _relayController,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).relayUrl,
            hintText: AppLocalizations.of(context).relayUrlPlaceholder,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () async {
              final url = _relayController.text.trim();
              if (url.isNotEmpty) {
                final success = await settingsProvider.addRelay(url);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? AppLocalizations.of(context).relayAdded
                          : AppLocalizations.of(context).failedToAddRelay),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text(AppLocalizations.of(context).add),
          ),
        ],
      ),
    );
  }

  void _showEditRelayDialog(BuildContext context, SettingsProvider settingsProvider, String url) {
    _relayController.text = url;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).editRelay),
        content: TextField(
          controller: _relayController,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).relayUrl,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () async {
              final newUrl = _relayController.text.trim();
              if (newUrl.isNotEmpty) {
                final success = await settingsProvider.updateRelay(url, newUrl);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? AppLocalizations.of(context).relayUpdated
                          : AppLocalizations.of(context).failedToUpdateRelay),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text(AppLocalizations.of(context).update),
          ),
        ],
      ),
    );
  }

  void _showDeleteRelayDialog(BuildContext context, SettingsProvider settingsProvider, String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).confirmDeleteRelay),
        content: Text(AppLocalizations.of(context).deleteRelayConfirmation(url)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () async {
              final success = await settingsProvider.removeRelay(url);
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? AppLocalizations.of(context).relayDeleted
                        : AppLocalizations.of(context).failedToDeleteRelay),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );
  }
}