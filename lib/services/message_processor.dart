import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import 'blind_signature_processor.dart';

/// Centralized message processor to handle all Gift Wrap messages
/// This prevents duplicate processing when multiple screens are active
class MessageProcessor {
  static MessageProcessor? _instance;
  static MessageProcessor get instance {
    _instance ??= MessageProcessor._internal();
    return _instance!;
  }

  MessageProcessor._internal();

  // Keep track of processed message IDs to prevent duplicates
  final Set<String> _processedMessageIds = <String>{};
  StreamSubscription? _messageSubscription;
  bool _isInitialized = false;

  /// Initialize the message processor with NostrService
  void initialize() {
    if (_isInitialized) {
      debugPrint('🔄 MessageProcessor already initialized');
      return;
    }

    debugPrint('🚀 Initializing centralized MessageProcessor');
    _isInitialized = true;
    
    // This will be set up when NostrService connects
    debugPrint('✅ MessageProcessor initialized successfully');
  }

  /// Set up message subscription from NostrService
  void setupMessageSubscription(Stream<Message> messageStream) {
    if (_messageSubscription != null) {
      debugPrint('🔄 MessageProcessor: Message subscription already active');
      return;
    }

    debugPrint('🎧 MessageProcessor: Setting up message subscription');
    
    _messageSubscription = messageStream.listen(
      (message) {
        _handleMessage(message);
      },
      onError: (error) {
        debugPrint('❌ MessageProcessor: Stream error: $error');
      },
    );
    
    debugPrint('✅ MessageProcessor: Message subscription active');
  }

  /// Handle incoming messages with deduplication
  Future<void> _handleMessage(Message message) async {
    try {
      // Create a unique identifier for this message
      final messageId = _createMessageId(message);
      
      debugPrint('📨 MessageProcessor: Received message');
      debugPrint('   ID: $messageId');
      debugPrint('   Kind: ${message.kind}');
      debugPrint('   Election ID: ${message.electionId}');
      
      // Check if we've already processed this message
      if (_processedMessageIds.contains(messageId)) {
        debugPrint('⚠️ MessageProcessor: Message already processed, skipping');
        return;
      }
      
      // Mark message as processed
      _processedMessageIds.add(messageId);
      debugPrint('✅ MessageProcessor: Processing new message');
      
      // Process the message using BlindSignatureProcessor
      final processor = BlindSignatureProcessor.instance;
      final success = await processor.processMessage(message);
      
      debugPrint('🔄 MessageProcessor: Processing result: $success');
      
      if (success) {
        if (message.isTokenMessage) {
          debugPrint('🎫 MessageProcessor: Token message processed successfully');
        } else if (message.isErrorMessage) {
          debugPrint('❌ MessageProcessor: Error message processed');
        } else if (message.isVoteMessage) {
          debugPrint('🗳️ MessageProcessor: Vote message processed');
        }
      } else {
        debugPrint('❌ MessageProcessor: Failed to process message');
      }
      
      // Clean up old message IDs to prevent memory leaks
      _cleanupOldMessageIds();
      
    } catch (e) {
      debugPrint('❌ MessageProcessor: Error handling message: $e');
    }
  }

  /// Create a unique identifier for a message
  String _createMessageId(Message message) {
    // Use a combination of fields to create a unique ID
    // This helps detect duplicate messages from the same Gift Wrap event
    final components = [
      message.id,
      message.kind.toString(),
      message.electionId,
      message.payload.length.toString(),
    ];
    
    return components.join('|');
  }

  /// Clean up old message IDs to prevent memory leaks
  void _cleanupOldMessageIds() {
    // Keep only the last 100 message IDs to prevent memory leaks
    // This should be more than enough for normal operation
    if (_processedMessageIds.length > 100) {
      final excess = _processedMessageIds.length - 100;
      final toRemove = _processedMessageIds.take(excess).toList();
      for (final id in toRemove) {
        _processedMessageIds.remove(id);
      }
      debugPrint('🧹 MessageProcessor: Cleaned up $excess old message IDs');
    }
  }

  /// Stop the message processor and clean up resources
  void dispose() {
    debugPrint('🛑 MessageProcessor: Disposing');
    
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _processedMessageIds.clear();
    _isInitialized = false;
    
    debugPrint('✅ MessageProcessor: Disposed successfully');
  }

  /// Get debug info about the processor state
  Map<String, dynamic> getDebugInfo() {
    return {
      'isInitialized': _isInitialized,
      'hasSubscription': _messageSubscription != null,
      'processedMessageCount': _processedMessageIds.length,
      'processedMessageIds': _processedMessageIds.toList(),
    };
  }
}