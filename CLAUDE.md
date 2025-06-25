# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Criptocracia is an experimental, trustless open-source electronic voting system. The project description mentions it's built in Rust with blind RSA signatures and uses the Nostr protocol, but the current codebase is a Flutter application that appears to be in early development stages (currently shows a basic counter app).

## Development Commands

### Basic Flutter Commands
- `flutter run` - Run the app in development mode with hot reload
- `flutter build apk` - Build Android APK
- `flutter build ios` - Build iOS app
- `flutter build web` - Build web version

### Testing and Code Quality
- `flutter test` - Run all tests
- `flutter test --dart-define=CI=true` - Run tests with performance tests skipped (for CI)
- `flutter test --dart-define=SLOW_DEVICE=true` - Run tests with performance tests skipped (for slow devices)
- `flutter test --dart-define=SKIP_TIMING=true` - Run tests without timing assertions (for emulators)
- `flutter analyze` - Run static analysis (uses flutter_lints rules)
- `flutter pub get` - Install dependencies
- `flutter pub upgrade` - Update dependencies

### Platform-Specific Development
- `flutter run -d chrome` - Run on web browser
- `flutter run -d android` - Run on Android device/emulator
- `flutter run -d ios` - Run on iOS device/simulator

## Project Structure

This is a standard Flutter project with multi-platform support:
- `lib/main.dart` - Main application entry point
- `test/` - Widget and unit tests
- `android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/` - Platform-specific code
- `pubspec.yaml` - Dependencies and project configuration
- `analysis_options.yaml` - Code analysis rules using flutter_lints

## Current State

The Criptocracia Flutter voter app implements all core features from the voter TUI client:

### Implemented Features
- ✅ Voter nonce generation and hashing (lib/models/voter.dart)
- ✅ CLI argument handling (lib/config/app_config.dart)
- ✅ Elections listing UI (lib/screens/elections_screen.dart)
- ✅ Election and candidate selection (lib/screens/election_detail_screen.dart)
- ✅ Vote casting workflow (lib/screens/voting_screen.dart)
- ✅ Real-time results display (lib/screens/results_screen.dart)
- ✅ Nostr communication service (lib/services/nostr_service.dart - MVP implementation)

### Architecture
- Provider pattern for state management
- Modular service layer for crypto and Nostr operations
- Material Design 3 UI with responsive design
- CLI configuration support

### Configuration
The app is preconfigured for mobile use with:
- **Relay URL**: `wss://relay.mostro.network`
- **EC Public Key**: `0000001ace57d0da17fc18562f4658ac6d093b2cc8bb7bd44853d0c196e24a9c`

### Running the App
```bash
flutter run                    # Standard run
flutter run -- --debug         # With debug mode enabled
flutter run -- --help          # Show available options
```

### Recent Updates

#### Blind Signature Protocol Implementation
- ✅ Fixed blind signature randomizer generation (changed third parameter to `true` in `blind()` function)
- ✅ Complete cryptographic protocol implementation matching Rust EC specification
- ✅ End-to-end voting flow with proper blind signature verification
- ✅ Comprehensive integration tests for pure library API usage
- ✅ Debug utilities for Rust EC verification troubleshooting

#### Testing Framework
- ✅ Pure library API tests using only `blind_rsa_signatures` library
- ✅ Complete voting protocol verification without external dependencies
- ✅ Rust EC compatibility debugging tests
- ✅ Security validation tests (invalid signatures, wrong messages)

### Current Protocol Implementation

The app now implements the complete blind signature voting protocol:

1. **Voter Side**: Generates nonce, blinds with randomizer enabled
2. **EC Side**: Signs blinded message using RSA private key  
3. **Voter Side**: Unblinds signature and verifies token
4. **Vote Creation**: Packages `h_n:token:r:candidate_id` format
5. **EC Verification**: Verifies signature using randomizer

### TODO for Production
- ✅ Implement full RSA blind signature cryptography
- ✅ Add comprehensive error handling and validation
- Replace mock NostrService with actual NDK integration
- Implement proper key management and storage
- Add settings screen for advanced configuration options
- Resolve Rust EC verification parameter compatibility
