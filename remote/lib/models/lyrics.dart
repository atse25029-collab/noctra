class LyricLine {
  final double time; // in seconds
  final String text;

  const LyricLine({required this.time, required this.text});

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      time: (json['time'] as num?)?.toDouble() ?? 0.0,
      text: json['text'] as String? ?? '',
    );
  }
}

class LyricsData {
  final List<LyricLine> lines;
  final String level;

  const LyricsData({required this.lines, required this.level});

  factory LyricsData.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] as List<dynamic>? ?? [];
    final lines = rawLines
        .map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
        .where((l) => l.text.trim().isNotEmpty)
        .toList();
    return LyricsData(
      lines: lines,
      level: json['level'] as String? ?? 'line',
    );
  }
}
