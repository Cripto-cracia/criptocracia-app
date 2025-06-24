# Integration Tests

This directory contains comprehensive integration tests for the Criptocracia voting system, specifically focusing on the blind signature cryptographic protocol.

## Test Files

### `cryptographic_protocol_test.dart`

Complete end-to-end testing of the blind signature voting protocol using only the `blind_rsa_signatures` library directly, without any helper services.

#### Test Coverage

1. **Complete Cryptographic Voting Protocol**
   - Voter nonce generation (128-bit)
   - SHA256 hash computation
   - Blind signature creation with randomizer
   - EC blind signature issuance
   - Signature unblinding and verification
   - Vote payload creation (`h_n:token:r:candidate_id`)
   - EC vote verification

2. **Security Validation**
   - Invalid signature rejection
   - Wrong message verification failure
   - Message randomizer consistency checks

3. **Pure Library API Test**
   - Uses only `blind_rsa_signatures` library APIs
   - No external dependencies or helper functions
   - Direct replication of protocol implementation

4. **Rust EC Compatibility Debug**
   - Tests different verification approaches
   - Identifies parameter order issues
   - Provides debugging output for EC verification problems

#### Key Features

- **Randomizer Support**: Tests with proper randomizer generation (`blind()` third parameter = `true`)
- **Protocol Compliance**: Matches exact Rust EC specification
- **Debugging Output**: Comprehensive logging for troubleshooting
- **Security Testing**: Validates cryptographic security properties

#### Running the Tests

```bash
# Run all integration tests
flutter test test/integration/

# Run specific test
flutter test test/integration/cryptographic_protocol_test.dart

# Run with verbose output
flutter test test/integration/cryptographic_protocol_test.dart --verbose

# Run specific test case
flutter test test/integration/cryptographic_protocol_test.dart --name "Complete cryptographic voting protocol"
```

#### Test Results

All tests validate the complete blind signature voting protocol:

```
🎉 === PROTOCOL VERIFICATION COMPLETE ===
✅ Step 1 - Nonce generation and blinding: PASSED
✅ Step 2 - EC blind signature issuance: PASSED  
✅ Step 3 - Signature unblinding and verification: PASSED
✅ Step 4 - Vote payload creation: PASSED
✅ Step 5 - EC vote verification: PASSED
```

## Protocol Implementation

The tests verify the exact protocol used by the Rust Election Coordinator:

1. **Voter generates nonce** (16 bytes, 128-bit)
2. **Computes hash** (`h_n = SHA256(nonce)`)
3. **Blinds hash** with EC's RSA public key and randomizer
4. **EC signs** blinded message using RSA private key
5. **Voter unblinds** signature and verifies token
6. **Creates vote** in format `h_n:token:r:candidate_id`
7. **EC verifies** vote using signature and randomizer

## Dependencies

- `blind_rsa_signatures`: RSA blind signature implementation
- `crypto`: SHA256 hashing
- `flutter_test`: Testing framework

## Notes

- These tests use pure library APIs without any service layer abstractions
- Randomizer generation is enabled for proper protocol compliance
- Tests identify and debug Rust EC verification parameter issues
- All cryptographic operations are validated for security properties