# Criptocracia - Flutter Voter App

Criptocracia is an experimental, trustless open-source electronic voting system. This Flutter application serves as the voter client, implementing blind RSA signatures to ensure vote secrecy and voter anonymity, while using the Nostr protocol for decentralized, encrypted message transport.

## 🗳️ Project Overview

This Flutter app is the mobile voter client for the Criptocracia voting system. It provides a secure, privacy-preserving interface for voters to participate in elections using cryptographic techniques that ensure both vote secrecy and system integrity.

### Key Features

- **🔐 Blind RSA Signatures**: Privacy-preserving vote tokens that ensure vote secrecy
- **🌐 Nostr Protocol**: Decentralized communication using NIP-59 Gift Wrap encryption
- **🔑 Hierarchical Deterministic Keys**: BIP32/BIP44 key derivation following NIP-06 specification
- **🏛️ Hardware-Backed Security**: Device-specific encryption for sensitive data storage
- **📱 Cross-Platform**: Native support for Android, iOS, Web, Windows, macOS, and Linux
- **🌍 Multi-Language**: English and Spanish localization support
- **🔒 Secure Persistence**: Mnemonic phrases survive app reinstalls with enhanced security

## 🏗️ Architecture

### Core Components

- **NostrKeyManager**: BIP39 mnemonic generation and NIP-06 key derivation
- **SecureStorageService**: Hardware-backed encrypted storage with device fingerprinting
- **VoterSessionService**: Comprehensive voting session state management
- **CryptoService**: Complete RSA blind signature operations
- **NostrService**: NIP-59 encrypted communication with Nostr relays

### Security Model

```
Hardware Security → Device Fingerprint → PBKDF2 → AES Encryption → Secure Storage
                                      ↓
BIP39 Mnemonic → BIP32/44 Keys → Nostr Identity → Encrypted Communication
                                      ↓
Voting Session → Blind Signatures → Vote Tokens → Anonymous Voting
```

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK**: Version 3.8.1 or higher
- **Dart SDK**: Included with Flutter
- **Platform Tools**: 
  - Android Studio (for Android development)
  - Xcode (for iOS development on macOS)
  - Visual Studio (for Windows development)

### Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd criptocracia_app
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Verify setup**:
   ```bash
   flutter doctor
   ```

4. **Run the app**:
   ```bash
   flutter run
   ```

### Platform-Specific Setup

#### Android
```bash
flutter run -d android
```

#### iOS (macOS only)
```bash
flutter run -d ios
```

#### Web
```bash
flutter run -d chrome
```

#### Desktop
```bash
flutter run -d windows  # Windows
flutter run -d macos    # macOS
flutter run -d linux    # Linux
```

## 🧪 Testing

### Run All Tests
```bash
flutter test
```

### Test Configurations
```bash
flutter test --dart-define=CI=true              # CI environment
flutter test --dart-define=SLOW_DEVICE=true     # Slow devices
flutter test --dart-define=SKIP_TIMING=true     # Skip timing tests
```

### Coverage Report
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

## 🔧 Development

### Build Configurations

#### Development
```bash
flutter run --dart-define=debug=true
```

#### Production Builds
```bash
flutter build apk --release      # Android APK
flutter build appbundle          # Android App Bundle  
flutter build ios --release      # iOS
flutter build web --release      # Web
flutter build windows --release  # Windows
flutter build macos --release    # macOS
flutter build linux --release    # Linux
```

### Code Quality

#### Static Analysis
```bash
flutter analyze
```

#### Linting
The project uses `flutter_lints` for code quality enforcement. Configuration is in `analysis_options.yaml`.

### Debugging

#### Enable Debug Logging
```bash
flutter run --dart-define=debug=true
```

#### Common Debug Commands
```bash
flutter logs                    # View device logs
flutter pub deps               # Dependency tree
flutter pub outdated          # Check for updates
flutter clean                 # Clean build cache
```

## 🛡️ Security Features

### Cryptographic Standards
- **BIP39**: Mnemonic phrase generation and validation
- **BIP32/BIP44**: Hierarchical deterministic key derivation
- **NIP-06**: Nostr key derivation specification
- **NIP-19**: Bech32 encoding for Nostr addresses
- **NIP-59**: Gift Wrap encryption for private messaging
- **RSA Blind Signatures**: Privacy-preserving vote tokens
- **SHA-256**: Cryptographic hashing for integrity verification

### Storage Security
- **Device Fingerprinting**: Hardware-specific encryption keys
- **PBKDF2**: 100,000 iterations for key derivation
- **AES Encryption**: Hive database with encrypted storage
- **Secure Boot Chain**: Bootstrap → Master → Application keys
- **Mnemonic Persistence**: Survives app reinstalls and updates

### Privacy Protection
- **Blind Signatures**: Vote content hidden from election coordinators
- **Gift Wrap Encryption**: Message content hidden from relays
- **Session Isolation**: Independent encryption for each voting session
- **Forward Secrecy**: Session data clearable without affecting identity

## 📱 User Interface

### Screens
- **Elections Screen**: Browse and select available elections
- **Election Detail**: View candidates and election information
- **Voting Screen**: Cast votes with blind signature tokens
- **Results Screen**: Real-time election results display
- **Account Screen**: View voter identity and session information

### Navigation
- **Bottom Navigation**: Switch between Elections and Results
- **Drawer Menu**: Access account settings and app information
- **Material Design 3**: Modern UI with adaptive theming

### Internationalization
- **Languages**: English (en) and Spanish (es)
- **Localization**: ARB format in `lib/l10n/`
- **Runtime**: Automatic language detection with manual override

## 🌐 Network Configuration

### Default Configuration
- **Relay URL**: `wss://relay.mostro.network`
- **Election Coordinator**: `0000001ace57d0da17fc18562f4658ac6d093b2cc8bb7bd44853d0c196e24a9c`

### Custom Configuration
Configuration can be customized via command line arguments:
```bash
flutter run -- --relay=wss://custom.relay.url --ec-pubkey=<coordinator-key>
```

## 🔗 Dependencies

### Core Dependencies
- `flutter`: Cross-platform UI framework
- `dart_nostr: ^9.1.1`: Nostr protocol implementation
- `provider: ^6.1.2`: State management

### Cryptography
- `blind_rsa_signatures`: RSA blind signature operations (git)
- `nip59`: NIP-59 Gift Wrap encryption (git)
- `blockchain_utils: ^3.0.0`: BIP32/BIP44 key derivation
- `bip39: ^1.0.6`: Mnemonic generation and validation
- `bech32: ^0.2.2`: NIP-19 address encoding
- `elliptic: ^0.3.11`: Elliptic curve cryptography
- `crypto: ^3.0.6`: General cryptographic functions

### Storage & Security
- `hive: ^2.2.3`: Local encrypted database
- `hive_flutter: ^1.1.0`: Flutter integration for Hive
- `device_info_plus: ^10.1.2`: Device fingerprinting
- `shared_preferences: ^2.3.3`: Simple configuration storage

## 📚 Documentation

- **[CHANGELOG.md](CHANGELOG.md)**: Detailed change history and new features
- **[ARCHITECTURE.md](ARCHITECTURE.md)**: Technical architecture and implementation details
- **[REPLACE_APP_ICON.md](REPLACE_APP_ICON.md)**: Instructions for customizing app icons

## 🤝 Contributing

### Development Workflow
1. Create feature branch from `main`
2. Implement changes with tests
3. Run quality checks: `flutter analyze && flutter test`
4. Submit pull request with description

### Code Standards
- Follow Dart/Flutter style guidelines
- Write tests for new functionality
- Document public APIs
- Use meaningful commit messages

### Security Considerations
- Never commit secrets or private keys
- Follow secure coding practices
- Test cryptographic operations thoroughly
- Review security implications of changes

## 🐛 Troubleshooting

### Common Issues

#### Build Failures
- Ensure Flutter SDK is up to date: `flutter upgrade`
- Clean build cache: `flutter clean && flutter pub get`
- Check platform-specific tools: `flutter doctor`

#### Cryptographic Errors
- Verify mnemonic validation in NostrKeyManager
- Check device fingerprinting in SecureStorageService
- Validate RSA key formats in CryptoService

#### Storage Issues
- Ensure app has storage permissions
- Check device fingerprint consistency
- Validate encryption key derivation

#### Network Connectivity
- Verify relay URL accessibility
- Check Nostr event formatting
- Validate NIP-59 encryption/decryption

### Debug Information
```bash
# Check session state
flutter run --dart-define=debug=true

# Analyze dependencies
flutter pub deps

# Verify environment
flutter doctor -v
```

## 📄 License

This project is part of the Criptocracia open-source electronic voting system. Please refer to the main project repository for license information.

## 🔗 Related Projects

- **Criptocracia Core**: Rust-based election coordinator and backend services
- **Criptocracia CLI**: Command-line voter client (reference implementation)

## 📞 Support

For technical issues, feature requests, or security concerns:
- Open an issue in the project repository
- Review existing documentation in ARCHITECTURE.md
- Check troubleshooting section above

---

**⚠️ Experimental Software**: This is experimental voting software. Thoroughly review security considerations and test in non-production environments before any real-world usage.

**🔒 Security Notice**: Always verify the integrity of election coordinator public keys and relay URLs before participating in elections.