import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/player_state.dart';
import '../models/lyrics.dart';

enum ConnectionStatus { disconnected, discovering, connecting, connected }

class NoctraClient extends ChangeNotifier {
  static const int defaultPort = 43821;
  static const int udpDiscoveryPort = 43822;
  static const String prefKeyHost = 'noctra_last_host';

  String _host = '10.83.223.201';
  int _port = defaultPort;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  RemotePlayerState _state = RemotePlayerState.initial();
  LyricsData? _lyrics;
  bool _disposed = false;
  Completer<void>? _pollCompleter;

  String get host => _host;
  int get port => _port;
  ConnectionStatus get status => _status;
  RemotePlayerState get state => _state;
  LyricsData? get lyrics => _lyrics;

  String get artworkUrl => 'http://$_host:$_port/api/artwork?t=${_state.seq}';

  NoctraClient() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHost = prefs.getString(prefKeyHost);
    if (savedHost != null && savedHost.isNotEmpty) {
      _host = savedHost;
    }
    // Attempt auto-discovery first, fallback to saved host
    unawaited(discoverAndConnect());
  }

  Future<void> setHost(String host, {int port = defaultPort}) async {
    _host = host.trim();
    _port = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKeyHost, _host);
    _startPolling();
  }

  Future<void> discoverAndConnect() async {
    _status = ConnectionStatus.discovering;
    notifyListeners();

    try {
      final discoveredIp = await _discoverViaUdp().timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );

      if (discoveredIp != null) {
        _host = discoveredIp;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefKeyHost, _host);
      }
    } catch (e) {
      debugPrint('[NoctraClient] Discovery error: $e');
    }

    _startPolling();
  }

  Future<String?> _discoverViaUdp() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final completer = Completer<String?>();
      final timer = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final msg = utf8.decode(datagram.data);
            if (msg.startsWith('NOCTRA_SERVER')) {
              timer.cancel();
              socket.close();
              if (!completer.isCompleted) {
                completer.complete(datagram.address.address);
              }
            }
          }
        }
      });

      final msg = utf8.encode('NOCTRA_DISCOVER');
      socket.send(msg, InternetAddress('255.255.255.255'), udpDiscoveryPort);

      return await completer.future;
    } catch (e) {
      debugPrint('[NoctraClient] UDP Discovery exception: $e');
      return null;
    }
  }

  void _startPolling() {
    _pollCompleter?.complete();
    _status = ConnectionStatus.connecting;
    notifyListeners();
    _runPollLoop();
  }

  Future<void> _runPollLoop() async {
    while (!_disposed) {
      try {
        final uri = Uri.parse('http://$_host:$_port/api/wait_state?seq=${_state.seq}');
        final res = await http.get(uri).timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
          final newState = RemotePlayerState.fromJson(jsonMap);

          final trackChanged = _state.title != newState.title ||
              _state.artist != newState.artist ||
              _state.seq == 0;

          _state = newState;
          _status = ConnectionStatus.connected;
          notifyListeners();

          if (trackChanged && _state.hasLyrics) {
            unawaited(fetchLyrics());
          }
        } else {
          _status = ConnectionStatus.disconnected;
          notifyListeners();
          await Future.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        if (_status != ConnectionStatus.disconnected) {
          _status = ConnectionStatus.disconnected;
          notifyListeners();
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> fetchLyrics() async {
    try {
      final uri = Uri.parse('http://$_host:$_port/api/lyrics');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.body.trim().isNotEmpty && res.body.trim() != 'null') {
        final jsonMap = jsonDecode(res.body) as Map<String, dynamic>;
        _lyrics = LyricsData.fromJson(jsonMap);
        notifyListeners();
      } else {
        _lyrics = null;
        notifyListeners();
      }
    } catch (_) {
      _lyrics = null;
      notifyListeners();
    }
  }

  Future<void> sendCommand(String command, [double? value]) async {
    try {
      final uri = Uri.parse('http://$_host:$_port/api/command');
      final body = jsonEncode({'command': command, 'value': value});
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[NoctraClient] Command error: $e');
    }
  }

  void togglePlay() => sendCommand('toggle');
  void play() => sendCommand('play');
  void pause() => sendCommand('pause');
  void next() => sendCommand('next');
  void previous() => sendCommand('prev');
  void toggleFavorite() => sendCommand('favorite');
  void toggleMute() => sendCommand('mute');
  void seek(double fraction) => sendCommand('seek', fraction.clamp(0.0, 1.0));
  void setVolume(double fraction) => sendCommand('vol', fraction.clamp(0.0, 1.0));

  @override
  void dispose() {
    _disposed = true;
    _pollCompleter?.complete();
    super.dispose();
  }
}
