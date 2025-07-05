import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'providers/election_provider.dart';
import 'providers/results_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/elections_screen.dart';
import 'screens/elections_results_screen.dart';
import 'screens/account_screen.dart';
import 'screens/settings_screen.dart';
import 'services/nostr_key_manager.dart';
import 'services/secure_storage_service.dart';
import 'services/nostr_service.dart';
import 'generated/app_localizations.dart';

void main(List<String> args) async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Parse command line arguments
  AppConfig.parseArguments(args);
  
  try {
    // Initialize secure storage
    await SecureStorageService.init();
    
    // Initialize Nostr keys if needed
    await NostrKeyManager.initializeKeysIfNeeded();
    
  } catch (e) {

    debugPrint('❌ Critical initialization error: $e');
    // Show a simple error app
    runApp(MaterialApp(
      title: 'Criptocracia - Error',
      home: Scaffold(
        appBar: AppBar(title: const Text('Initialization Error')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Critical initialization error:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                e.toString(),
                style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ),
    ));
    return;
  }
  
  runApp(const CriptocraciaApp());
}

class CriptocraciaApp extends StatelessWidget {
  const CriptocraciaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ElectionProvider()),
        ChangeNotifierProvider(create: (_) => ResultsProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider.instance),
      ],
      child: MaterialApp(
        title: 'Criptocracia',
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('es'),
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF03FFFE)),
          useMaterial3: true,
        ),
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  StreamSubscription? _electionResultsSubscription;

  @override
  void initState() {
    super.initState();
    // Initialize Nostr keys on first launch
    _initializeKeys();
    // Start global election results subscription
    _startGlobalElectionResultsSubscription();
    // Load elections immediately to have metadata available
    _loadElectionsOnStartup();
  }

  @override
  void dispose() {
    debugPrint('🧹 MainScreenState: Disposing resources...');
    
    // Cancel specific subscription
    _electionResultsSubscription?.cancel();
    
    // Dispose NostrService and all managed subscriptions
    NostrService.instance.dispose();
    
    super.dispose();
    debugPrint('✅ MainScreenState: Disposal completed');
  }

  Future<void> _initializeKeys() async {
    try {
      await NostrKeyManager.initializeKeysIfNeeded();
    } catch (e) {
      debugPrint('Error initializing Nostr keys: $e');
    }
  }

  /// Load elections on app startup to ensure metadata is available for results
  void _loadElectionsOnStartup() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ElectionProvider>().loadElections();
      }
    });
  }

  Future<void> _startGlobalElectionResultsSubscription() async {
    try {
      debugPrint('🚀 Starting global election results subscription...');
      
      final nostrService = NostrService.instance;
      
      // Connect to the relay
      await nostrService.connect(AppConfig.relayUrls);
      
      // Subscribe to ALL election results events from EC
      final electionResultsStream = nostrService.subscribeToAllElectionResults(AppConfig.ecPublicKey);
      
      // Listen to the stream to store all election results globally
      _electionResultsSubscription = electionResultsStream.listen(
        (event) {
          debugPrint('🎯 GLOBAL: Election results received in MainScreen: ${event.id}');
          
          // Extract election ID from d tag
          final dTag = event.tags.firstWhere(
            (tag) => tag.length >= 2 && tag[0] == 'd',
            orElse: () => ['d', 'unknown'],
          );
          final electionId = dTag.length >= 2 ? dTag[1] : 'unknown';
          
          debugPrint('   Election ID: $electionId');
          debugPrint('   Kind: ${event.kind}');
          debugPrint('   Content: ${event.content}');
          debugPrint('   Results automatically stored in global service');
        },
        onError: (error) {
          debugPrint('❌ GLOBAL: Error in election results stream: $error');
        },
        onDone: () {
          debugPrint('🔚 GLOBAL: Election results stream closed');
        },
      );
      
      debugPrint('✅ Global election results subscription started successfully');
      debugPrint('   Listening for ALL kind 35001 events from: ${AppConfig.ecPublicKey}');
      debugPrint('   Results will be stored globally for all elections');
      
    } catch (e) {
      debugPrint('❌ Failed to start global election results subscription: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const ElectionsScreen(),
      const ElectionsResultsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(AppLocalizations.of(context).appTitle),
        centerTitle: true,
        actions: [
          if (AppConfig.debugMode)
            IconButton(
              icon: const Icon(Icons.bug_report),
              onPressed: () => _showDebugInfo(),
              tooltip: AppLocalizations.of(context).debugInfo,
            ),
        ],
      ),
      drawer: _buildDrawer(),
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.how_to_vote),
            label: AppLocalizations.of(context).navElections,
          ),
          BottomNavigationBarItem(icon: const Icon(Icons.poll), label: AppLocalizations.of(context).navResults),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Image.asset(
                  'assets/images/app_logo.png',
                  height: 32,
                  width: 32,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).appTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  AppLocalizations.of(context).appSubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.how_to_vote),
            title: Text(AppLocalizations.of(context).navElections),
            onTap: () {
              Navigator.pop(context);
              setState(() => _currentIndex = 0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.poll),
            title: Text(AppLocalizations.of(context).navResults),
            onTap: () {
              Navigator.pop(context);
              setState(() => _currentIndex = 1);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(AppLocalizations.of(context).navAccount),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AccountScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(AppLocalizations.of(context).settings),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          if (AppConfig.debugMode) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.bug_report),
              title: Text(AppLocalizations.of(context).debugInfo),
              onTap: () {
                Navigator.pop(context);
                _showDebugInfo();
              },
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(AppLocalizations.of(context).navAbout),
            onTap: () {
              Navigator.pop(context);
              _showAppInfo();
            },
          ),
        ],
      ),
    );
  }

  void _showDebugInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).debugInformation),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context).relayUrlDebug(AppConfig.relayUrls.join(', '))),
            Text(AppLocalizations.of(context).ecPublicKey(AppConfig.ecPublicKey)),
            Text(AppLocalizations.of(context).debugMode(AppConfig.debugMode.toString())),
            Text(AppLocalizations.of(context).configured(AppConfig.isConfigured.toString())),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).close),
          ),
        ],
      ),
    );
  }

  void _showAppInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).appTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).aboutDescription,
            ),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context).features),
            Text(AppLocalizations.of(context).featureAnonymous),
            Text(AppLocalizations.of(context).featureRealtime),
            Text(AppLocalizations.of(context).featureDecentralized),
            Text(AppLocalizations.of(context).featureTamperEvident),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).close),
          ),
        ],
      ),
    );
  }
}
