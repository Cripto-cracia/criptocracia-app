import 'dart:convert';
import 'dart:typed_data';
import 'package:blind_rsa_signatures/blind_rsa_signatures.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoterSessionService {
  static const _nonceKey = 'voter_nonce';
  static const _blindingResultKey = 'voter_blinding_result';

  static Future<void> saveSession(
    Uint8List nonce,
    BlindingResult result,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nonceKey, base64.encode(nonce));
    await prefs.setString(_blindingResultKey, jsonEncode(result.toJson()));
  }

  static Future<Uint8List?> getNonce() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_nonceKey);
    if (data == null) return null;
    return base64.decode(data);
  }

  static Future<BlindingResult?> getBlindingResult() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_blindingResultKey);
    if (data == null) return null;
    return BlindingResult.fromJson(jsonDecode(data));
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nonceKey);
    await prefs.remove(_blindingResultKey);
  }
}
