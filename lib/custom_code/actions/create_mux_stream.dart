// Automatic FlutterFlow imports
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

// Create a custom action to make a POST request to 'https://api.mux.com/video/v1/live-streams'. Use Header 'Authorization' with value 'Basic ZWE4Y2RjZWEtODgyNi00M2U1LTk1ZmMtY2RkMDNkMDJhOTQ0OkRxaVpZWTN1L0J3NkZXOGc3ckVla0t0QXAwaFpfN0dabTI1MnZ5NFA5c3E0QzEvc2JOQTZ4NG4yNTFaVDlLUWlydUJPUm5jSk00ZQ==' and 'Content-Type: application/json'. The body should be a JSON with 'playback_policy' as ['public'] and 'new_asset_settings' with 'playback_policy' as ['public']. Return the response body as JSON.
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<dynamic> createMuxStream() async {
  final url = Uri.parse('https://api.mux.com/video/v1/live-streams');

  // A tua chave que funcionou no ReqBin
  const String auth =
      'Basic ZWE4Y2RjZWEtODgyNi00M2U1LTk1ZmMtY2RkMDNkMDJhOTQ0OkRxaVpZWTN1L0J3NkZXOGc3ckVla0t0QXAwaFpfN0dabTI1MnZ5NFA5c3E0QzEvc2JOQTZ4NG4yNTFaVDlLUWlydUJPUm5jSk00ZQ==';

  try {
    final response = await http.post(
      url,
      headers: {
        'Authorization': auth,
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'playback_policy': ['public'],
        'new_asset_settings': {
          'playback_policy': ['public'],
        },
      }),
    );

    // Se o Mux responder qualquer coisa, nós queremos ver o quê
    return json.decode(response.body);
  } catch (e) {
    // Se der erro de rede, ele vai dizer exatamente o que é
    return {'error_de_rede': e.toString()};
  }
}
