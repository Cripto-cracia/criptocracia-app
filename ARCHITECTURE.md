# Criptocracia App Architecture

## Project Overview

Criptocracia is an experimental, trustless open-source electronic voting system built as a Flutter mobile application. The system implements blind RSA signatures for voter privacy and uses the Nostr protocol for decentralized communication.

## Core Technologies

- **Frontend**: Flutter (cross-platform mobile app)
- **Protocol**: Nostr (decentralized social network protocol)
- **Cryptography**: Blind RSA signatures, secp256k1 elliptic curve
- **Key Management**: BIP32/BIP44 hierarchical deterministic wallets
- **Storage**: Hive (encrypted local database) with hardware-backed security

## Architecture Components

### 1. Key Management (`lib/services/nostr_key_manager.dart`)

**Purpose**: Manages cryptographic keys following NIP-06 specification

**Key Features**:
- BIP39 mnemonic generation and validation
- BIP32/BIP44 hierarchical deterministic key derivation
- NIP-06 compliant derivation path: `m/44'/1237'/1989'/0/0`
- NIP-19 bech32 encoding for npub addresses
- Secure key storage integration
- Mnemonic persistence across app reinstalls

**Recent Improvements**:
- ✅ Replaced insecure XOR-based key derivation with proper BIP32/BIP44 implementation
- ✅ Added `blockchain_utils` library for cryptographically secure key derivation
- ✅ Implemented proper NIP-19 bech32 encoding instead of hex concatenation
- ✅ Fixed mnemonic persistence using secure storage instead of SharedPreferences
- ✅ Added session validation and key recovery mechanisms

### 2. Secure Storage (`lib/services/secure_storage_service.dart`)

**Purpose**: Hardware-backed encrypted storage for sensitive data

**Key Features**:
- Device fingerprinting for hardware-backed security
- PBKDF2 key derivation (100,000 iterations)
- AES encryption with Hive database
- Platform-specific device identification
- Runtime key derivation (no hardcoded secrets)
- Bootstrap key management for circular dependency resolution

**Security Improvements**:
- ✅ Replaced `flutter_secure_storage` with custom Hive-based solution
- ✅ Removed hardcoded secrets and implemented device-specific key derivation
- ✅ Added hardware-backed security with device fingerprinting
- ✅ Enhanced encryption with platform-specific entropy sources
- ✅ Implemented secure master key storage with validation

### 3. Voting Session Management (`lib/services/voter_session_service.dart`)

**Purpose**: Comprehensive voting session state management matching Rust client functionality

**Key Features**:
- Complete session state tracking (nonce, election ID, hash bytes, blinding secrets)
- Initial vs complete session management
- Blind signature response handling
- Session validation and integrity checking
- Secure parameter storage and retrieval
- Session cleanup and recovery capabilities

**Architecture**:
- **Initial Session**: Created when user selects election (nonce, blindingResult, hashBytes, electionId)
- **Complete Session**: After receiving blind signature response (adds blindSignature, messageRandomizer)
- **Session Validation**: Cryptographic integrity verification of stored data
- **Recovery Methods**: Clear sessions and handle corrupted data

### 4. Cryptographic Operations (`lib/services/crypto_service.dart`)

**Purpose**: Complete RSA blind signature cryptographic operations

**Key Features**:
- **Nonce Generation**: Cryptographically secure random nonce generation
- **Hash Operations**: SHA-256 hashing for blind signature operations
- **Blind Signature Operations**: Complete blinding/unblinding workflow
- **Signature Verification**: RSA signature verification against messages
- **Vote Token Processing**: End-to-end blind signature response handling

**Implementation**:
- `generateNonce()`: Secure 128-bit random nonce generation
- `hashNonce()`: SHA-256 hashing of nonces
- `blindNonce()`: RSA blinding using EC public key
- `unblindSignature()`: RSA signature unblinding with blinding factors
- `verifySignature()`: RSA signature verification
- `processBlindSignatureResponse()`: Complete workflow for EC response

### 5. Nostr Communication (`lib/services/nostr_service.dart`)

**Purpose**: Handles Nostr protocol communication for voting operations

**Key Features**:
- dart_nostr library integration (migrated from NDK)
- NIP-59 Gift Wrap encryption for voter privacy
- Blind signature request handling
- Real-time event subscriptions
- Secure message encryption/decryption
- Connection management and error handling

**Migration History**:
- ✅ Migrated from NDK to dart_nostr library
- ✅ Integrated NIP-59 library for Gift Wrap functionality
- ✅ Maintained API compatibility during migration
- ✅ Added secure key pair management for message encryption

### 6. Application State (`lib/models/` and `lib/providers/`)

**Purpose**: Application-wide state management using Provider pattern

**Key Components**:
- **Voter Model**: Session state with nonce and blind signature data
- **Election Models**: Election and candidate data structures  
- **Provider Classes**: ElectionProvider, ResultsProvider, VotingProvider
- **State Persistence**: Integration with secure storage services

## Data Flow Architecture

### 1. App Initialization Flow
```
App Start → SecureStorageService.init() → NostrKeyManager.initializeKeysIfNeeded()
├── First Launch: Generate Mnemonic → Store Securely
└── Existing User: Validate Existing Mnemonic → Continue
```

### 2. Election Selection Flow
```
User Taps Election → Generate Nonce → Hash Nonce → Blind Hash
├── Store Session: (nonce, blindingResult, hashBytes, electionId)
├── Send Blind Signature Request via NIP-59 Gift Wrap
└── Navigate to Election Detail Screen
```

### 3. Voting Process Flow
```
Blind Signature Request → Election Coordinator → Blind Signature Response
├── Store Response: (blindSignature, messageRandomizer)
├── Unblind Signature → Verify Vote Token
├── Cast Vote with Verified Token
└── Display Results
```

## Cryptographic Flow

### 1. Key Generation (First Launch)
```
Mnemonic (BIP39) → Seed → BIP32 Master Key → NIP-06 Derivation Path → Nostr Keys
                                         (m/44'/1237'/1989'/0/0)
```

### 2. Secure Storage Flow
```
Device Fingerprint → PBKDF2 → Encryption Key → AES Encrypted Hive Storage
├── Bootstrap Key: Device-specific key for master key storage
├── Master Key: Randomly generated, securely stored
└── Derived Keys: Application-specific encryption keys
```

### 3. Blind Signature Flow
```
1. Voter: Generate Nonce (128-bit random)
2. Voter: Hash Nonce (SHA-256)
3. Voter: Blind Hash (RSA with EC public key)
4. Voter: Send Blinded Hash to EC via NIP-59
5. EC: Sign Blinded Hash → Return Blind Signature
6. Voter: Unblind Signature → Verify → Vote Token
```

### 4. Nostr Communication Flow
```
Private Key → Public Key → npub (NIP-19) → Nostr Identity
├── Message Creation: EventBuilder with vote data
├── Gift Wrap: NIP-59 encryption for privacy
└── Relay Communication: Send/receive encrypted events
```

## Security Architecture

### 1. Hardware-Backed Security
- **Device Fingerprinting**: Platform-specific hardware identifiers
- **PBKDF2 Key Derivation**: 100,000 iterations with device-specific salt
- **Runtime Key Generation**: No hardcoded secrets or encryption keys
- **Secure Boot Chain**: Bootstrap → Master → Application keys

### 2. Cryptographic Standards
- **BIP32/BIP44**: Industry-standard hierarchical deterministic wallets
- **NIP-06**: Nostr key derivation specification
- **NIP-19**: Nostr address encoding (bech32)
- **NIP-59**: Gift Wrap encryption for private messaging
- **secp256k1**: Bitcoin/Nostr standard elliptic curve
- **RSA Blind Signatures**: Privacy-preserving voting tokens
- **SHA-256**: Cryptographic hashing for integrity

### 3. Key Management Security
- **Mnemonic Persistence**: Hardware-encrypted storage across reinstalls
- **Private Key Derivation**: On-demand generation (never stored directly)
- **Session Isolation**: Each voting session cryptographically isolated
- **Forward Secrecy**: Session data clearable without affecting identity

### 4. Data Protection Layers
```
Application Data
    ↓
Secure Storage Service (Device-specific encryption)
    ↓
Hive Database (AES encrypted)
    ↓
Operating System Security
    ↓
Hardware Security Features
```

## Dependencies

### Core Dependencies
- `flutter`: Cross-platform UI framework
- `dart_nostr: ^9.1.1`: Nostr protocol implementation
- `nip59`: NIP-59 Gift Wrap encryption (git dependency)
- `blind_rsa_signatures`: Blind signature implementation (git dependency)

### Cryptography
- `blockchain_utils: ^3.0.0`: BIP32/BIP44 key derivation
- `bip39: ^1.0.6`: Mnemonic generation and validation
- `bech32: ^0.2.2`: NIP-19 address encoding
- `elliptic: ^0.3.11`: Elliptic curve cryptography
- `crypto: ^3.0.6`: General cryptographic functions

### Storage & Security
- `hive: ^2.2.3`: Local database
- `hive_flutter: ^1.1.0`: Flutter integration for Hive
- `device_info_plus: ^10.1.2`: Device fingerprinting
- `platform: ^3.1.5`: Cross-platform compatibility
- `shared_preferences: ^2.3.3`: Simple configuration storage

### State Management & UI
- `provider: ^6.1.2`: State management solution
- `flutter_localizations`: Internationalization support

## Development History

### Phase 1: Initial Implementation
- Basic Flutter app with counter functionality
- NDK integration for Nostr communication
- Initial blind signature implementation

### Phase 2: Security Hardening
- Migrated from NDK to dart_nostr
- Replaced flutter_secure_storage with Hive-based solution
- Implemented hardware-backed secure storage

### Phase 3: Cryptographic Compliance
- Fixed mnemonic generation workflow
- Implemented proper NIP-19 bech32 encoding
- Replaced insecure key derivation with BIP32/BIP44

### Phase 4: Complete Voting Implementation
- **Mnemonic Persistence Fix**: Resolved regeneration on app reinstall
- **Complete Crypto Operations**: Implemented RSA unblinding and verification
- **Session Management**: Comprehensive voting session state tracking
- **Voting Flow Integration**: End-to-end election selection and voting

### Current State
- ✅ Secure key management with industry standards
- ✅ NIP-06 compliant Nostr key derivation
- ✅ Hardware-backed encrypted storage with mnemonic persistence
- ✅ NIP-59 encrypted communication
- ✅ Complete blind signature voting workflow
- ✅ Comprehensive session state management
- ✅ RSA cryptographic operations implementation
- ✅ Election selection and voting flow

## Testing Strategy

### Unit Tests
- **Cryptographic Operations**: Key derivation, blind signatures, verification
- **Storage Security**: Encryption/decryption, device fingerprinting
- **Session Management**: State persistence, validation, recovery
- **Mnemonic Handling**: Generation, validation, persistence

### Integration Tests
- **Nostr Communication**: Message sending, gift wrap encryption/decryption
- **Voting Workflow**: Complete election selection to vote casting
- **Cross-platform**: Storage and crypto operations on all platforms

### Security Tests
- **Mnemonic Security**: Generation consistency, recovery validation
- **Key Derivation**: BIP32/BIP44 compliance, deterministic output
- **Storage Integrity**: Encryption strength, key derivation validation
- **Session Isolation**: Independent session state management

## Performance Considerations

### Cryptographic Operations
- **Background Processing**: Move heavy crypto operations off main thread
- **Key Caching**: Cache derived keys for session duration
- **Efficient Storage**: Optimized serialization for session data

### Storage Operations
- **Lazy Loading**: Load session data only when needed
- **Batch Operations**: Group storage writes for efficiency
- **Index Optimization**: Efficient key lookups in Hive database

## Error Handling Strategy

### Cryptographic Errors
- **Key Derivation Failures**: Graceful degradation with user notification
- **Signature Verification**: Clear error messages for invalid signatures
- **Mnemonic Corruption**: Recovery options and validation

### Storage Errors
- **Device Changes**: Handle device fingerprint changes
- **Corruption Detection**: Validate integrity and offer recovery
- **Migration Support**: Smooth transitions between storage versions

### Network Errors
- **Relay Connectivity**: Retry logic and fallback relays
- **Message Delivery**: Confirmation and retry mechanisms
- **Timeout Handling**: Appropriate timeouts for crypto operations

## Configuration Management

### Development Environment
```bash
flutter run --dart-define=debug=true
```

### Testing Configuration
```bash
flutter test --dart-define=CI=true
flutter test --dart-define=SLOW_DEVICE=true
flutter test --dart-define=SKIP_TIMING=true
```

### Production Build
```bash
flutter build apk --release
flutter build ios --release
flutter build web --release
```

### Platform-Specific Builds
```bash
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

## Future Improvements

### Short Term
- **Enhanced Error Handling**: User-friendly error messages and recovery
- **Performance Optimization**: Background crypto operations
- **UI/UX Polish**: Improved voting flow user experience
- **Testing Coverage**: Comprehensive test suite completion

### Medium Term
- **Multi-Election Support**: Concurrent election participation
- **Advanced Voting Schemes**: Ranked choice, approval voting
- **Audit Trail**: Cryptographic verification of vote integrity
- **Offline Capabilities**: Local vote storage and delayed submission

### Long Term
- **Hardware Security Modules**: Enhanced key protection
- **Zero-Knowledge Proofs**: Advanced privacy features
- **Decentralized Identity**: DID integration for voter verification
- **Scalability**: Large-scale election support

## Troubleshooting

### Common Issues

#### Build Failures
- **Dependency conflicts**: Check Flutter and dependency versions
- **Platform-specific issues**: Verify platform SDKs and tools
- **Git dependencies**: Ensure network access for git packages

#### Cryptographic Issues
- **Key derivation errors**: Verify mnemonic validation and BIP32 implementation
- **Signature failures**: Check RSA key formats and parameters
- **Hash mismatches**: Validate nonce generation and hashing

#### Storage Issues
- **Permissions**: Ensure app has storage permissions
- **Encryption failures**: Check device fingerprinting and key derivation
- **Data corruption**: Validate integrity and offer session reset

#### Nostr Connectivity
- **Relay issues**: Check relay URL and network connectivity
- **Message encryption**: Verify NIP-59 implementation and key pairs
- **Event formatting**: Validate Nostr event structure

### Debug Commands
```bash
flutter analyze                    # Static analysis
flutter test                      # Run all tests
flutter test --coverage           # Generate coverage report
flutter pub deps                  # Dependency tree
flutter doctor                    # Environment check
flutter pub get                   # Refresh dependencies
```

### Debug Information
- **Session State**: Use VoterSessionService.validateSession()
- **Key Validation**: Use NostrKeyManager.getDerivedKeys()
- **Storage Health**: Check SecureStorageService operations
- **Crypto Operations**: Enable debug logging in CryptoService

## Notes for Future Development

1. **Key Management**: The current implementation follows NIP-06 and BIP standards. Any changes should maintain compatibility and migration paths.

2. **Storage Security**: The secure storage service uses device-specific encryption. Changing the implementation requires careful migration strategies.

3. **Nostr Integration**: The app uses dart_nostr with NIP-59 for encryption. Ensure compatibility when updating dependencies.

4. **Blind Signatures**: The voting workflow depends on proper blind signature implementation. Test thoroughly when making changes.

5. **Cross-Platform**: The app targets all major platforms. Consider platform-specific security features when expanding functionality.

6. **Session Management**: The voting session state is critical for security. Ensure session isolation and proper cleanup.

7. **Performance**: Cryptographic operations can be expensive. Consider background processing and caching strategies.

8. **Error Recovery**: Provide clear recovery paths for all error conditions, especially cryptographic and storage failures.

## Contact and Documentation

- **Technical Documentation**: See CHANGELOG.md for recent changes
- **Setup Instructions**: See README.md for development setup
- **Security Considerations**: Review security sections in this document
- **Testing**: Follow testing strategy outlined above