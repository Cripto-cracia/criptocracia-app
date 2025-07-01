# Changelog

All notable changes to the Criptocracia Flutter voter app are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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