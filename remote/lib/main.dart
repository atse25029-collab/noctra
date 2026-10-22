import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/noctra_client.dart';
import 'utils/color_utils.dart';
import 'widgets/connection_sheet.dart';
import 'widgets/lyrics_sheet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090A0F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const NoctraRemoteApp());
}

class NoctraRemoteApp extends StatelessWidget {
  const NoctraRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noctra Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6B8AFD),
          surface: Color(0xFF14161F),
        ),
      ),
      home: const RemoteHomePage(),
    );
  }
}

class RemoteHomePage extends StatefulWidget {
  const RemoteHomePage({super.key});

  @override
  State<RemoteHomePage> createState() => _RemoteHomePageState();
}

class _RemoteHomePageState extends State<RemoteHomePage> {
  late final NoctraClient _client;
  double? _scrubPosition;

  @override
  void initState() {
    super.initState();
    _client = NoctraClient();
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _client,
      builder: (context, _) {
        final state = _client.state;
        final accent = parseAccentColor(state.accent);
        final isConnected = _client.status == ConnectionStatus.connected;

        final double currentPos = _scrubPosition ?? state.position;
        final double dur = state.duration > 0 ? state.duration : 1.0;
        final double progress = (currentPos / dur).clamp(0.0, 1.0);

        return Scaffold(
          body: Stack(
            children: [
              // Ambient Radial Background Glow
              AnimatedContainer(
                duration: const Duration(milliseconds: 700),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.4),
                    radius: 1.2,
                    colors: [
                      accent.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    children: [
                      // Top Navigation Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => ConnectionSheet.show(context, _client),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isConnected
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFFEF4444),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isConnected
                                                  ? const Color(0xFF22C55E)
                                                  : const Color(0xFFEF4444))
                                              .withValues(alpha: 0.5),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isConnected ? 'Noctra Client' : 'Offline',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.lyrics_rounded,
                                  color: state.hasLyrics ? Colors.white : Colors.white24,
                                ),
                                tooltip: 'Synced Lyrics',
                                onPressed: state.hasLyrics
                                    ? () => LyricsSheet.show(context, _client)
                                    : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.tune_rounded, color: Colors.white70),
                                tooltip: 'Connection Settings',
                                onPressed: () => ConnectionSheet.show(context, _client),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Center Album Art Card (Flexible and Responsive)
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    color: const Color(0xFF14161F),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        blurRadius: 40,
                                        offset: const Offset(0, 20),
                                      ),
                                      BoxShadow(
                                        color: accent.withValues(alpha: 0.12),
                                        blurRadius: 30,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(27),
                                    child: isConnected && state.hasArtwork
                                        ? Image.network(
                                            _client.artworkUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) => _buildFallbackArt(accent),
                                          )
                                        : _buildFallbackArt(accent),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Track Metadata & Favorite Heart
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  state.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  state.artist.isNotEmpty ? state.artist : 'Connect to Noctra on PC',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              state.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: state.isLiked ? const Color(0xFFEF4444) : Colors.white60,
                              size: 28,
                            ),
                            tooltip: 'Favorite',
                            onPressed: isConnected ? () => _client.toggleFavorite() : null,
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Progress Scrubber & Timestamps
                      Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                              thumbColor: Colors.white,
                              overlayColor: Colors.white.withValues(alpha: 0.1),
                            ),
                            child: Slider(
                              value: progress,
                              onChanged: (val) {
                                setState(() {
                                  _scrubPosition = val * state.duration;
                                });
                              },
                              onChangeEnd: (val) {
                                _client.seek(val);
                                setState(() {
                                  _scrubPosition = null;
                                });
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  formatDuration(currentPos),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text(
                                  formatDuration(state.duration),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Transport Playback Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, size: 36),
                            color: Colors.white,
                            onPressed: isConnected ? () => _client.previous() : null,
                          ),
                          GestureDetector(
                            onTap: isConnected ? () => _client.togglePlay() : null,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Icon(
                                state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 38,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, size: 36),
                            color: Colors.white,
                            onPressed: isConnected ? () => _client.next() : null,
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Volume Slider Card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                state.isMuted || state.volume == 0
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                              onPressed: isConnected ? () => _client.toggleMute() : null,
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                  activeTrackColor: Colors.white.withValues(alpha: 0.7),
                                  inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                                  thumbColor: Colors.white,
                                ),
                                child: Slider(
                                  value: state.isMuted ? 0.0 : state.volume.clamp(0.0, 1.0),
                                  onChanged: isConnected ? (v) => _client.setVolume(v) : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFallbackArt(Color accent) {
    return Center(
      child: Icon(
        Icons.music_note_rounded,
        size: 72,
        color: accent.withValues(alpha: 0.4),
      ),
    );
  }
}
