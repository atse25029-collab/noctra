import 'package:flutter/material.dart';
import '../services/noctra_client.dart';
import '../models/lyrics.dart';

class LyricsSheet extends StatefulWidget {
  final NoctraClient client;

  const LyricsSheet({super.key, required this.client});

  static void show(BuildContext context, NoctraClient client) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LyricsSheet(client: client),
    );
  }

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _findActiveLineIndex(List<LyricLine> lines, double currentPos) {
    if (lines.isEmpty) return -1;
    for (int i = lines.length - 1; i >= 0; i--) {
      if (currentPos >= lines[i].time) {
        return i;
      }
    }
    return 0;
  }

  void _scrollToIndex(int index, int totalLines) {
    if (!_scrollController.hasClients || index < 0) return;
    const itemHeight = 56.0;
    final targetOffset = (index * itemHeight) - 160.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final clamped = targetOffset.clamp(0.0, maxScroll);

    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.client,
      builder: (context, _) {
        final state = widget.client.state;
        final lyrics = widget.client.lyrics;
        final lines = lyrics?.lines ?? [];
        final activeIndex = _findActiveLineIndex(lines, state.position);

        if (activeIndex != _lastActiveIndex && activeIndex >= 0) {
          _lastActiveIndex = activeIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToIndex(activeIndex, lines.length);
          });
        }

        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: const Color(0xFF0C0E14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    const Icon(Icons.lyrics_rounded, color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Lyrics',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    if (lyrics != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          lyrics.level == 'word' ? 'Word-synced' : 'Line-synced',
                          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: lines.isEmpty
                    ? Center(
                        child: Text(
                          'No lyrics available for this track',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 15),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                        itemCount: lines.length,
                        itemBuilder: (context, index) {
                          final line = lines[index];
                          final isActive = index == activeIndex;
                          final distance = (index - activeIndex).abs();

                          final double opacity = isActive
                              ? 1.0
                              : distance == 1
                                  ? 0.45
                                  : distance == 2
                                      ? 0.25
                                      : 0.15;

                          final double scale = isActive ? 1.05 : 1.0;

                          return GestureDetector(
                            onTap: () {
                              if (state.duration > 0) {
                                widget.client.seek(line.time / state.duration);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              transform: Matrix4.diagonal3Values(scale, scale, 1.0),
                              child: Text(
                                line.text,
                                style: TextStyle(
                                  fontSize: isActive ? 22 : 18,
                                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                                  color: Colors.white.withValues(alpha: opacity),
                                  letterSpacing: -0.3,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
