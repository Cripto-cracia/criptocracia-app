# Changelog

All notable changes to the Criptocracia Flutter voter app are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.7] - 2025-07-12

### Added
- **Language Selection Settings**: Added comprehensive language selection functionality in settings screen
- **Multi-language Support**: Users can now choose between System Default, English, and Spanish
- **Persistent Language Preference**: Language selection is saved and persists across app restarts
- **Real-time Language Switching**: Language changes apply immediately throughout the app
- **Localized Settings UI**: All language selection interface elements properly localized

### Enhanced
- **Settings Screen**: Added new Language Selection section with intuitive radio button interface
- **SettingsProvider**: Extended with locale management and persistent storage capabilities
- **Main App Architecture**: Updated MaterialApp to reactively respond to language preference changes
- **Internationalization**: Added 7 new localized strings for language selection functionality

### Improved
- **User Experience**: Clean, accessible language selection with clear descriptions and visual feedback
- **Code Quality**: All static analysis issues resolved, maintaining high code standards
- **Documentation**: Enhanced with comprehensive language selection implementation details

## [0.3.5] - 2025-07-11

### Improved
- Cleaned up verbose debug logging that cluttered output with repetitive election event information
- Removed noisy event reception, filtering, and processing logs while preserving essential debugging
- Improved log readability for better development experience

## [0.3.4] - 2025-07-11

### Fixed
- Fixed token validation contradiction where recently processed tokens were not recognized
- Fixed missing vote token success snackbar notification to users
- Fixed duplicate vote token success snackbar showing twice
- Improved modal drag area UX in elections results screen - entire modal surface now draggable
- Fixed Flutter analyze issues: deprecated withOpacity usage, unused methods, and string interpolation
- Enhanced token processing flow with better timing and user feedback

### Improved
- Better user experience with consistent success notifications for vote tokens
- Enhanced debugging and logging for token processing workflow
- Improved modal interaction in election results with full-surface drag support
- Cleaner codebase with resolved static analysis issues

## [0.3.3] - 2025-07-09

### Added
- Show real commit hash on production builds.
- Add `zapstore.yaml` config file.
- Add QR code functionality for npub sharing in account screen.
- Complete internationalization with English and Spanish support.
- Add support for multiple Nostr relays.
- Add localized status badges to election results list.
- Implement detailed election results view in modal.
- Implement Kind 3 error handling and enhance election services.
- Implement complete blind signature voting protocol with comprehensive testing.
- Implement NIP-59 compliant Gift Wrap processing with blind signature response handling.
- Add comprehensive project documentation.
- Implement complete voting session management and crypto operations.
- Secure voter session storage with flutter_secure_storage.
- Implement blind signature request.

### Improved
- Improve notification messages to users.
- Centralized message processing to prevent duplicate notifications.
- Add message listeners to `ElectionDetailScreen`.
- Improve drawer with branding and version display.
- Improve election card and results screen UI.
- Filter old elections by end_time within 12 hours.
- Add retry button for token requests and pull-to-refresh for elections.
- Implement settings persistence and updated Nostr protocol.
- Enhance device fingerprint security with encrypted storage.
- Implement secure BIP32/BIP44 hierarchical deterministic key derivation.
- Migrate from NDK to dart_nostr and replace flutter_secure_storage with Hive.

### Fixed
- Resolve duplicate token notifications.
- Fix the token response handling issue.
- Resolve election results filtering issue.
- Restrict voting to in-progress elections only.
- Add missing UI notification for successful token processing.
- Resolve Flutter analysis warnings and info messages.
- Add required permissions for GitHub Actions release creation.
- Add consistent AppBar background to settings screen.
- Remove build_runner step from GitHub workflow.
- Resolve NostrEvent type conflicts and dart_nostr import issues.
- Prevent duplicate vote token requests for same election.
- Dispose of election results stream subscription to prevent memory leak.
- Fix signature verification issues in voting protocol.
- Fix async consistency in blind signature request flow.
- Fix NostrService singleton pattern and improve public key generation.

## [0.3.2] - 2025-01-08

### Improved
- **Drawer Version Label**: Repositioned app version label to the bottom center of the navigation drawer for better visual balance and accessibility
- **UI Layout**: Enhanced drawer footer design with centered version display for improved user experience

## [0.3.1] - 2025-01-08

### Added
- **App Version Display**: Added version information to the bottom of the navigation drawer for easy access
- **Enhanced Branding**: Integrated official Criptocracia word logo in drawer header for improved brand consistency

### Improved
- **Election Card Time Display**: Changed bottom time indicators to show precise start/end times (HH:MM format) instead of dates
- **Results Screen Layout**: Removed app bar title for cleaner, more focused results display with maximum content space
- **Drawer Design**: Replaced small logo + text with responsive word image (70% drawer width) for professional appearance
- **Results Filtering**: Fixed race condition in results filtering by moving filter logic to display layer instead of service layer

### Fixed
- **Election Results Display**: Resolved issue where results weren't showing due to premature filtering in global subscription
- **Real-time Results**: Ensured all election results are captured globally while maintaining proper filtering for UI display
- **Data Flow**: Improved results data flow to prevent loss of results due to timing issues between elections and results loading

## [0.3.0] - 2025-01-07

### Added
- **Token Request Retry Button**: Added retry functionality when vote token requests fail or time out
- **Automatic Token Requests**: Implemented automatic token request initiation when opening election detail screens
- **Pull-to-Refresh**: Added pull-down-to-refresh functionality to the elections list screen for manual updates
- **Session Management**: Enhanced session cleanup and state management for failed token requests
- **Timeout Handling**: Added 30-second timeout for token requests with proper error recovery

### Improved
- **Real-time Elections Display**: Enhanced client-side filtering to show elections from the last 48 hours
- **Error Handling**: Comprehensive error handling for authorization failures and network timeouts
- **User Experience**: Better visual feedback during token request states with loading indicators
- **Code Quality**: Cleaned up debug logging and removed temporary debugging UI elements

### Fixed
- **Token Request Flow**: Resolved issues where retry button wasn't appearing due to session state confusion
- **Session State**: Fixed token availability detection to properly show retry options when needed
- **UI Responsiveness**: Improved state transitions between requesting, success, and error states

## [0.2.4] - 2025-01-05

### Added
- **Enhanced ElectionCard UI**: Modern Material Design 3 styling with gradients and improved visual hierarchy
- **Time Remaining Indicators**: Smart countdown displays showing "Starts in X" or "Ends in X" for active elections
- **Linear Progress Bars**: Visual timeline showing election progress with color-coded status indicators
- **Interactive Animations**: Smooth scale animations on tap with custom splash and highlight colors
- **Action Hints**: Visual "Tap to view" indicators to improve user guidance and discoverability

### Fixed
- **Token Processing Notification**: Fixed critical issue where UI wasn't notified when vote tokens were successfully processed
- **Election Status Synchronization**: Resolved problem where "requesting token" state persisted even after token receipt
- **Vote Token Recognition**: Eliminated "need vote token" messages when tokens were already available in storage
- **UI State Management**: Ensured proper communication between token processing service and UI components

### Improved
- **Election Card Design**: Enhanced spacing, typography, and color contrast for better readability
- **Status Badge Styling**: Modern badges with transparency effects and better visual differentiation
- **Accessibility Support**: Added semantic labels and proper screen reader support for election cards
- **Touch Feedback**: Improved responsive design with proper touch targets for mobile interaction
- **Visual Consistency**: Replaced AppBar logo with text title for cleaner Material Design compliance

## [0.2.3] - 2025-01-02

### Added
- **Complete Internationalization**: Full English and Spanish localization support
- **Comprehensive ARB Files**: Added 30+ new localization keys covering all UI text
- **Multilingual Dialogs**: Vote confirmation, error messages, and status indicators
- **Localized Button Text**: All buttons and interactive elements properly translated
- **Dynamic Status Messages**: Election status, vote progress, and results in both languages

### Fixed
- **Missing Localization Import**: Added AppLocalizations import to vote confirmation dialog
- **Vote Display Format**: Corrected vote display to use proper localized function calls
- **Hardcoded Strings**: Replaced all remaining hardcoded UI text with localized versions
- **Static Analysis**: All Flutter analyze issues resolved with clean codebase

### Improved
- **User Experience**: Complete language support for Spanish-speaking users
- **Code Quality**: Eliminated all hardcoded user-facing strings
- **Maintainability**: Centralized all UI text in standard ARB localization files
- **Accessibility**: Proper localization foundation for future language additions

## [0.2.2] - 2025-01-01

### Fixed
- **Settings Screen AppBar**: Added consistent background color styling to match other screens
- **GitHub Actions Permissions**: Resolved release creation errors with proper workflow permissions
- **Visual Consistency**: Ensured uniform AppBar appearance across all application screens

### Improved
- **Code Formatting**: Enhanced code readability with consistent formatting and line breaks
- **Election Subscription**: Improved event filtering with EC public key and time-based filtering
- **Stream Management**: Better error handling and debugging output for Nostr connections
- **Event Retrieval**: Added 12-hour lookback for more reliable election and results data

## [0.2.1] - 2025-01-01

### Fixed
- **GitHub Workflow**: Fixed automatic release workflow by removing unnecessary build_runner step
- **CI/CD Pipeline**: Resolved "Could not find package build_runner" error in GitHub Actions
- **Build Process**: Streamlined workflow to use Flutter's native localization system

## [0.2.0] - 2025-01-01

### Added
- **App Logo Integration**: Centered dark logo in main AppBar for improved branding
- **Drawer Visual Enhancement**: App logo in drawer header replacing generic voting icon
- **Comprehensive Settings Screen**: Full settings interface with organized sections
- **Multi-Relay Support**: Enhanced Nostr connectivity with multiple relay management
- **Real-time Relay Monitoring**: Live connection status indicators and statistics
- **EC Public Key Configuration**: Settings interface for Election Commission public key management
- **Version Information Display**: App version, build number, and git commit info in settings
- **Connection Statistics**: Total, connected, and disconnected relay counters
- **Relay Management Operations**: Add, edit, delete relay functionality with validation

### Changed
- **Visual Branding Consistency**: Unified logo usage throughout the application interface
- **Settings Organization**: Better structured settings with clear sections and descriptions
- **Relay Architecture**: Migrated from single relay to multi-relay support for reliability

### Fixed
- **Flutter Analysis Compliance**: Resolved all static analysis warnings and info messages
- **Code Quality Improvements**: Enhanced maintainability and type safety

## [Unreleased]

### Added
- **Comprehensive Real-time Election Updates**: Multi-layered approach with periodic refresh backup
- **Automatic Periodic Refresh**: Background timer checks for missed elections every 30 seconds
- **Enhanced Event Logging**: Detailed logging for election event reception and processing
- **Election List Sorting**: Elections now display with most recent first (sorted by start time)
- **NIP-59 Compliant Gift Wrap Filtering**: Fixed timestamp filtering to comply with NIP-59 specification
- **Rumor Timestamp Validation**: Added canonical timestamp validation after Gift Wrap decryption
- **Complete Voting Session Management**: Implemented comprehensive session state management matching Rust client functionality
- **RSA Blind Signature Operations**: Full implementation of blind signature crypto operations
- **Secure Mnemonic Storage**: Hardware-backed mnemonic persistence across app reinstalls
- **Enhanced Device Fingerprinting**: Improved secure storage with device-specific encryption
- **NIP-06 Key Derivation**: Proper Nostr key generation using BIP32/BIP44 hierarchical deterministic paths
- **Voting Flow Integration**: Complete election selection and blind signature request workflow
- **Session Validation**: Integrity checking for voting session data
- **Multi-language Support**: English and Spanish localization
- **Cross-platform Support**: Android, iOS, Web, Linux, macOS, and Windows compatibility

### Enhanced Services

#### VoterSessionService
- **Complete Session State Management**: Store and retrieve all voting session components
- **Initial vs Complete Session Tracking**: Separate handling for election selection vs signature response
- **Secure Parameter Storage**: Election ID, nonce, hash bytes, blinding secrets, and message randomizers
- **Session Validation**: Cryptographic integrity verification of stored session data
- **Recovery Methods**: Session cleanup and restoration capabilities

#### CryptoService
- **RSA Unblinding**: Complete implementation of signature unblinding using blinding factors
- **Signature Verification**: Full RSA signature verification against messages
- **Vote Token Processing**: End-to-end blind signature workflow processing
- **Nonce Generation**: Cryptographically secure random nonce generation
- **Hash Operations**: SHA-256 hashing for blind signature operations

#### NostrKeyManager
- **Mnemonic Persistence Fix**: Resolved mnemonic regeneration on app reinstall
- **Secure Storage Migration**: Moved from SharedPreferences to hardware-backed storage
- **Key Derivation Validation**: Proper NIP-06 implementation with m/44'/1237'/1989'/0/0 path
- **Session Initialization**: Automatic key generation and validation on first launch
- **Recovery Support**: Import existing mnemonics and clear keys for testing

#### SecureStorageService
- **Device Fingerprint Security**: Hardware-specific encryption key derivation
- **PBKDF2 Key Derivation**: 100,000 iteration password-based key derivation
- **Bootstrap Key Management**: Circular dependency resolution for master key storage
- **Platform-specific Entropy**: Device-specific data collection for security
- **Encrypted Hive Storage**: AES encryption with device-fingerprint-derived keys

### Fixed
- **Real-time Election Updates**: Comprehensive solution with unlimited filtering and periodic backup refresh
- **Election Subscription Reliability**: Removed all filtering limits to maximize event reception
- **Missing Election Events**: Added periodic refresh mechanism to catch any missed real-time events
- **Gift Wrap Signature Validation**: Fixed NoSuchMethodError by removing invalid isSignatureValid() call
- **NIP-59 Gift Wrap Filtering**: Removed time-based filtering that was incompatible with timestamp randomization
- **Gift Wrap Timestamp Handling**: Now uses canonical rumor timestamps instead of randomized wrapper timestamps
- **Election Selection Crash**: Resolved null pointer exception when tapping elections
- **Mnemonic Persistence**: Fixed mnemonic regeneration bug on app reinstall/rebuild
- **Voting Flow Logic**: Corrected session data handling during blind signature process
- **Storage Inconsistency**: Unified secure storage approach across all sensitive data
- **Crypto Implementation**: Fixed incomplete RSA operations causing UnimplementedError

### Technical Improvements
- **Error Handling**: Enhanced exception handling throughout crypto operations
- **Debug Logging**: Comprehensive logging for voting process troubleshooting
- **Type Safety**: Improved null safety and type checking
- **Performance**: Reduced main thread blocking during crypto operations
- **Testing**: Added comprehensive unit tests for crypto operations
- **Code Quality**: Static analysis improvements and lint compliance

### Security Enhancements
- **Hardware-backed Security**: Leverages device-specific hardware identifiers
- **Encrypted Storage**: All sensitive data encrypted with device-derived keys
- **Key Isolation**: Separate encryption contexts for different data types
- **Integrity Validation**: Cryptographic verification of stored session data
- **Secure Defaults**: Conservative security settings and proper entropy sources

### Architecture Updates
- **Modular Service Design**: Clear separation of concerns across services
- **Provider Pattern**: Consistent state management using Flutter Provider
- **Secure by Default**: Security-first approach to all data handling
- **Cross-platform Compatibility**: Unified codebase for all supported platforms
- **Rust Client Parity**: Feature and behavior matching with reference implementation

## [Previous Versions]

### Initial Implementation
- Basic Flutter app structure with counter example
- Multi-platform project setup (Android, iOS, Web, Desktop)
- Internationalization framework
- Material Design 3 theming
- Provider-based state management foundation

---

## Migration Notes

### Breaking Changes
- **VoterSessionService API**: `saveSession()` now requires additional parameters (hashBytes, electionId)
- **CryptoService Methods**: `unblindSignature()` and `verifySignature()` have updated signatures
- **Storage Keys**: New secure storage keys added for comprehensive session management

### Upgrade Path
1. Existing installations will automatically migrate to new secure storage
2. Old session data will be cleared for security (users need to restart voting process)
3. Mnemonics are preserved across updates with enhanced security

### Dependencies Added
- `bip39`: BIP39 mnemonic generation and validation
- `blockchain_utils`: BIP32/BIP44 hierarchical deterministic key derivation
- `bech32`: NIP-19 bech32 encoding for Nostr public keys
- `device_info_plus`: Device fingerprinting for secure storage
- `hive_flutter`: Encrypted local storage
- `platform`: Cross-platform compatibility utilities

## Security Considerations

### Data Protection
- **Mnemonic Security**: 12-word BIP39 mnemonics stored with hardware-backed encryption
- **Session Isolation**: Each voting session cryptographically isolated
- **Device Binding**: Storage keys derived from device-specific hardware identifiers
- **Forward Secrecy**: Session data can be cleared without affecting identity keys

### Cryptographic Standards
- **RSA Blind Signatures**: Industry-standard blind signature implementation
- **PBKDF2**: 100,000 iterations for key derivation
- **SHA-256**: Cryptographic hashing for integrity verification
- **AES Encryption**: Hive storage encrypted with AES cipher
- **secp256k1**: Elliptic curve cryptography for Nostr keys

### Threat Model
- **Device Loss**: Data remains encrypted and inaccessible without device
- **App Reinstall**: Mnemonics persist while temporary session data is cleared
- **Storage Tampering**: Integrity validation detects data corruption
- **Network Interception**: All sensitive operations performed locally

---

*For detailed technical implementation, see ARCHITECTURE.md*
*For deployment and usage instructions, see README.md*