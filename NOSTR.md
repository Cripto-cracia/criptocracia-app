# Nostr Protocol Implementation in Criptocracia

This document provides a comprehensive overview of how the Criptocracia voting system uses the Nostr protocol for decentralized communication, including detailed specifications of custom event types, NIP-59 Gift Wrap messaging, and the complete voting protocol flow.

## Table of Contents

1. [Overview](#overview)
2. [Nostr Event Types](#nostr-event-types)
3. [NIP-59 Gift Wrap Messaging](#nip-59-gift-wrap-messaging)
4. [Communication Flow](#communication-flow)
5. [Security Model](#security-model)
6. [Technical Implementation](#technical-implementation)
7. [References](#references)

## Overview

Criptocracia implements a trustless electronic voting system using the Nostr protocol for decentralized communication. The system combines blind RSA signatures for voter privacy with Nostr's censorship-resistant messaging infrastructure to create a secure, transparent, and anonymous voting platform.

### Key Nostr Features Utilized

- **Decentralized Communication**: No central authority controls message routing
- **Event-Based Architecture**: Standardized event types for elections and results
- **NIP-59 Gift Wrap**: End-to-end encrypted messaging between voters and election coordinators
- **Real-time Updates**: Live subscription to election events and results
- **Parameterized Replaceable Events**: Efficient updates to election data

## Nostr Event Types

### Kind 35000 - Election Events

Election events are **parameterized replaceable events** (as defined in NIP-01) that broadcast election information from the Election Coordinator (EC) to all participants.

#### Event Structure

```json
{
  "id": "event_id",
  "pubkey": "ec_public_key",
  "kind": 35000,
  "created_at": 1234567890,
  "content": "{\"id\":\"election_id\",\"name\":\"Election Name\",\"start_time\":1234567890,\"end_time\":1234567890,\"candidates\":[{\"id\":1,\"name\":\"Candidate 1\",\"votes\":0},{\"id\":2,\"name\":\"Candidate 2\",\"votes\":0}],\"status\":\"open\",\"rsa_pub_key\":\"base64_encoded_rsa_public_key\"}",
  "tags": [
    ["d", "election_id"]
  ],
  "sig": "signature"
}
```

#### Content Fields

- **id**: Unique election identifier
- **name**: Human-readable election name
- **start_time**: Unix timestamp when voting begins
- **end_time**: Unix timestamp when voting ends
- **candidates**: Array of candidate objects with id, name, and current vote count
- **status**: Current election state (`open`, `in-progress`, `finished`, `canceled`)
- **rsa_pub_key**: Base64-encoded RSA public key for blind signature verification

#### Event Properties

- **Addressable**: Yes, using the `d` tag with election ID
- **Replaceable**: Yes, newer events replace older ones with the same `d` tag
- **Creator**: Election Coordinator (EC) - the entity managing the election
- **Updates**: Event is updated when election status changes or results are updated

#### When Events Are Created/Updated

1. **Creation**: When an election is first announced by the EC
2. **Status Updates**: When election status changes (open → in-progress → finished)
3. **Result Updates**: When vote tallies are updated (real-time or periodic)
4. **Cancellation**: When an election is canceled by the EC

### Kind 35001 - Election Results Events

Results events provide real-time vote tallies and are also **parameterized replaceable events** linked to specific elections.

#### Event Structure

```json
{
  "id": "event_id",
  "pubkey": "ec_public_key",
  "kind": 35001,
  "created_at": 1234567890,
  "content": "[[4,21],[3,35],[1,12]]",
  "tags": [
    ["d", "election_id"]
  ],
  "sig": "signature"
}
```

#### Content Format

The content is a JSON array of arrays, where each inner array contains:
- `[candidate_id, vote_count]`

Example: `[[4,21],[3,35],[1,12]]` means:
- Candidate 4 has 21 votes
- Candidate 3 has 35 votes  
- Candidate 1 has 12 votes

#### When Results Events Are Sent

1. **Initial Creation**: When the first vote is cast in an election
2. **Real-time Updates**: After each vote is processed and validated
3. **Periodic Updates**: Batch updates at regular intervals (implementation-dependent)
4. **Final Results**: When the election is concluded

#### Event Properties

- **Addressable**: Yes, using the `d` tag with election ID
- **Replaceable**: Yes, newer results replace older ones
- **Creator**: Election Coordinator (EC) - the entity tallying votes
- **Linked Election**: Referenced by the `d` tag matching the election ID from kind 35000 events

## NIP-59 Gift Wrap Messaging

The voting protocol uses NIP-59 Gift Wrap events (kind 1059) for secure, encrypted communication between voters and the Election Coordinator.

### Gift Wrap Event Structure

```json
{
  "id": "event_id",
  "pubkey": "random_public_key",
  "kind": 1059,
  "created_at": 1234567890,
  "content": "encrypted_rumor_content",
  "tags": [
    ["p", "recipient_public_key"]
  ],
  "sig": "signature"
}
```

### Message Protocol

Inside each Gift Wrap event, the encrypted rumor contains a `Message` object:

```json
{
  "id": "message_id",
  "election_id": "election_id",
  "kind": 1,
  "payload": "base64_encoded_data"
}
```

#### Message Types (kind field)

1. **Kind 1 - Token Messages**
   - **Purpose**: Blind signature token exchange
   - **Direction**: Bidirectional (voter ↔ EC)
   - **Payload**: Base64-encoded cryptographic data

2. **Kind 2 - Vote Messages**
   - **Purpose**: Cast votes anonymously
   - **Direction**: Voter → EC (via anonymous keys)
   - **Payload Format**: `h_n:token:r:candidate_id`
   - **Components**:
     - `h_n`: Base64-encoded hash of voter nonce
     - `token`: Base64-encoded unblinded signature
     - `r`: Base64-encoded randomizer
     - `candidate_id`: Integer candidate identifier

3. **Kind 3 - Error Messages**
   - **Purpose**: Error notifications
   - **Direction**: EC → Voter
   - **Payload**: Error description (plain text or Base64)

### Security Properties

- **Perfect Forward Secrecy**: Each message uses unique ephemeral keys
- **Metadata Protection**: Sender/recipient hidden from relay operators
- **Timestamp Obfuscation**: Created_at values are intentionally randomized
- **Content Encryption**: Message content encrypted with recipient's public key

## Communication Flow

### Phase 1: Election Discovery

1. **Voter**: Subscribes to kind 35000 events to discover available elections
2. **EC**: Publishes election event with candidate list and RSA public key
3. **Voter**: Selects election and prepares to participate

### Phase 2: Token Request (Blind Signature)

1. **Voter Actions**:
   - Generates 128-bit random nonce
   - Computes SHA-256 hash of nonce: `h_n = SHA256(nonce)`
   - Blinds the hash using EC's RSA public key: `blinded_h_n = blind(h_n, r, rsa_pub_key)`
   - Creates Message: `{"id": "blind_signature_request", "election_id": "election_id", "kind": 1, "payload": base64(blinded_h_n)}`
   - Wraps in NIP-59 Gift Wrap and sends to EC

2. **EC Actions**:
   - Receives and decrypts Gift Wrap event
   - Validates election ID and voter eligibility
   - Signs blinded hash with RSA private key: `blind_signature = sign(blinded_h_n, rsa_private_key)`
   - Creates response Message: `{"id": "blind_signature_response", "election_id": "election_id", "kind": 1, "payload": base64(blind_signature)}`
   - Wraps in NIP-59 Gift Wrap and sends to voter

### Phase 3: Token Processing

1. **Voter Actions**:
   - Receives and decrypts Gift Wrap response
   - Unblinds signature: `token = unblind(blind_signature, r, rsa_pub_key)`
   - Verifies token authenticity: `verify(token, h_n, rsa_pub_key)`
   - Stores token for voting

### Phase 4: Vote Casting

1. **Voter Actions**:
   - Selects candidate: `candidate_id`
   - Constructs vote payload: `vote_payload = h_n:token:r:candidate_id`
   - Generates anonymous Nostr key pair for this vote
   - Creates Message: `{"id": "vote_message", "election_id": "election_id", "kind": 2, "payload": base64(vote_payload)}`
   - Wraps in NIP-59 Gift Wrap using anonymous keys and sends to EC

2. **EC Actions**:
   - Receives anonymous vote message
   - Verifies RSA signature: `verify(token, h_n, rsa_pub_key)`
   - Validates randomizer consistency
   - Ensures h_n hasn't been used before (prevents double-voting)
   - Increments candidate vote count
   - Updates kind 35001 results event

### Phase 5: Results Monitoring

1. **All Participants**: Subscribe to kind 35001 events for real-time results
2. **EC**: Publishes updated results after each validated vote
3. **Voters**: Receive live vote tallies throughout the election

## Security Model

### Cryptographic Guarantees

- **Vote Secrecy**: Blind signatures ensure EC cannot link votes to voters
- **Voter Privacy**: NIP-59 encryption hides voter-EC communication from relays
- **Vote Integrity**: RSA signatures prevent vote forgery
- **Double-Vote Prevention**: Nonce tracking prevents multiple votes per token
- **Anonymity**: Anonymous keys for vote casting prevent identity correlation

### Attack Resistance

- **Relay Censorship**: Multiple relays and decentralized architecture
- **Traffic Analysis**: Gift Wrap encryption hides communication patterns
- **Vote Buying**: Blind signatures prevent proof of specific votes
- **Coercion**: Voters cannot prove how they voted
- **Replay Attacks**: Nonce uniqueness prevents vote reuse

### Privacy Protections

- **Unlinkable Votes**: Each vote uses fresh anonymous keys
- **Metadata Protection**: NIP-59 hides timing and correlation data
- **Forward Secrecy**: Compromised keys don't reveal past votes
- **Recipient Anonymity**: EC identity protected during vote casting

## Technical Implementation

### Core Components

#### NostrService (`lib/services/nostr_service.dart`)

```dart
class NostrService {
  // Connects to Nostr relays
  // Handles NIP-59 Gift Wrap encryption/decryption
  // Manages event subscriptions and publishing
  // Processes incoming messages
}
```

#### Message Model (`lib/models/message.dart`)

```dart
class Message {
  final String id;          // Message ID
  final String electionId;  // Election ID
  final int kind;           // Message type (1=Token, 2=Vote, 3=Error)
  final String payload;     // Base64 encoded data
}
```

#### Subscription Management (`lib/services/subscription_manager.dart`)

```dart
class SubscriptionManager {
  // Manages Nostr subscriptions
  // Handles connection pooling
  // Routes events to appropriate handlers
}
```

### Event Processing

1. **Election Events**: Filtered by kind 35000, processed for election discovery
2. **Results Events**: Filtered by kind 35001 and election ID (`d` tag)
3. **Gift Wrap Events**: Filtered by kind 1059 and recipient public key (`p` tag)

### Error Handling

- **Network Errors**: Connection timeouts, relay failures
- **Decryption Errors**: Invalid Gift Wrap events, malformed messages
- **Validation Errors**: Invalid signatures, expired elections
- **Protocol Errors**: Malformed message structure, missing fields

## References

### Nostr Improvement Proposals (NIPs)

- **[NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md)**: Basic Protocol Flow, Event Structure, Parameterized Replaceable Events
- **[NIP-59](https://github.com/nostr-protocol/nips/blob/master/59.md)**: Gift Wrap (Encrypted Direct Messages)

### Cryptographic Standards

- **RSA Blind Signatures**: [Chaum's Blind Signature Scheme](https://en.wikipedia.org/wiki/Blind_signature)
- **SHA-256**: [FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf)
- **NIP-06**: [Nostr Key Derivation](https://github.com/nostr-protocol/nips/blob/master/06.md)

### Implementation References

- **dart_nostr**: Dart implementation of Nostr protocol
- **nip59**: NIP-59 Gift Wrap encryption library
- **blind_rsa_signatures**: RSA blind signature implementation

---

**Note**: This document describes the current implementation of the Criptocracia Nostr protocol. As an experimental system, specifications may evolve based on security reviews and practical experience.