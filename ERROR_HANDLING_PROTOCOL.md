# Criptocracia Error Handling Protocol - Kind 3 Messages

## Overview

This document describes the implementation of Kind 3 (Error) messages in the Criptocracia voting system. Kind 3 messages allow the Election Coordinator (EC) to communicate specific error conditions back to voters, providing better user experience than silent failures or timeouts.

## Message Types

The Criptocracia protocol supports three message kinds:

- **Kind 1**: Token Request/Response (blind signature operations)
- **Kind 2**: Vote submission
- **Kind 3**: Error messages (NEW)

## Error Message Structure

### JSON Format

Error messages follow the same basic structure as other Criptocracia messages:

```json
{
  "id": "election_id",
  "kind": 3,
  "payload": "error_message_content"
}
```

### Payload Format

Unlike Kind 1 and Kind 2 messages, Kind 3 message payloads can be:

1. **Plain text**: Direct error message

## Error Types and Messages

### 1. Unauthorized Voter

**EC Log Message**: `Unauthorized voter`

**Recommended Kind 3 Payload**:
```
unauthorized-voter
```

**Flutter Display**: 
> ❌ Unauthorized Voter: You are not authorized to vote in this election. Please contact the election administrator.

### 2. Token Already Issued

**EC Log Message**: `nonce hash already issued`

**Recommended Kind 3 Payload**:
```
nonce-hash-already-issued
```

**Flutter Display**:
> ❌ Token Already Issued: A vote token has already been issued for this election. You cannot request another token.

### 3. Election Not Found

**Recommended Kind 3 Payload**:
```
election-not-found
```

**Flutter Display**:
> ❌ Election Not Found: The requested election was not found.

### 4. Election Closed

**Recommended Kind 3 Payload**:
```
election-closed
```

**Flutter Display**:
> ❌ Election Closed: This election is no longer accepting votes.

### 5. Generic Errors

For any other error conditions, the EC can send the raw error message and it will be displayed to the user as-is.


## Message Flow

### Successful Token Request (Kind 1)
```
Voter → [Kind 1 Request] → EC
Voter ← [Kind 1 Response with token] ← EC
```

### Failed Token Request (Kind 3)
```
Voter → [Kind 1 Request] → EC
Voter ← [Kind 3 Error message] ← EC
```

## Error Message Delivery

Error messages are sent using the same NIP-59 Gift Wrap protocol as other messages:

1. **EC creates Kind 3 message** with error details
2. **EC encrypts message** using NIP-59 Gift Wrap to voter's pubkey
3. **EC publishes** encrypted message to Nostr relay
4. **Flutter client receives** and decrypts the message
5. **Flutter client processes** error and shows user-friendly message
6. **Flutter client stops** "requesting token" state and shows error

## Timeout Handling

In addition to Kind 3 error messages, the Flutter client includes a 30-second timeout for token requests:

- If no response (success or error) is received within 30 seconds
- Client shows timeout message: "Token request timeout. The Election Coordinator may be unavailable."
- User can retry by navigating back to elections list

## Testing Error Conditions

### Test Case 1: Unauthorized Voter

1. Generate new voter keypair (not registered with EC)
2. Request vote token for an election
3. Expected: Kind 3 message with "unauthorized-voter" payload
4. Expected UI: Clear error message, no infinite loading

### Test Case 2: Double Token Request

1. Use registered voter to request token (should succeed)
2. Request token again for same election
3. Expected: Kind 3 message with "nonce-hash-already-issued" payload
4. Expected UI: Clear error about duplicate request

### Test Case 3: Timeout

1. Disconnect EC or block network
2. Request vote token
3. Expected: 30-second timeout with retry option
4. No infinite loading state

## Backward Compatibility

- Kind 3 messages are **additive** - existing Kind 1 and Kind 2 flows unchanged
- EC can choose to implement Kind 3 gradually
- Flutter client gracefully handles missing error messages (falls back to timeout)
- No breaking changes to existing voting protocol

## Security Considerations

- Error messages are encrypted using NIP-59 Gift Wrap (same as other messages)
- Error details are only sent to the requesting voter
- No sensitive information exposed in error messages
- Rate limiting should still apply to prevent error message spam

This implementation provides a robust error handling foundation for the Criptocracia voting system while maintaining full backward compatibility.