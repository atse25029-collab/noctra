class RemotePlayerState {
  final String title;
  final String artist;
  final String album;
  final double position;
  final double duration;
  final bool isPlaying;
  final bool isBuffering;
  final String accent;
  final bool isLiked;
  final double volume;
  final bool isMuted;
  final bool hasArtwork;
  final bool hasLyrics;
  final int seq;

  const RemotePlayerState({
    required this.title,
    required this.artist,
    required this.album,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isBuffering,
    required this.accent,
    required this.isLiked,
    required this.volume,
    required this.isMuted,
    required this.hasArtwork,
    required this.hasLyrics,
    required this.seq,
  });

  factory RemotePlayerState.initial() => const RemotePlayerState(
        title: 'No track playing',
        artist: 'Connect to Noctra',
        album: '',
        position: 0,
        duration: 0,
        isPlaying: false,
        isBuffering: false,
        accent: '#6b8afd',
        isLiked: false,
        volume: 0.8,
        isMuted: false,
        hasArtwork: false,
        hasLyrics: false,
        seq: 0,
      );

  factory RemotePlayerState.fromJson(Map<String, dynamic> json) {
    return RemotePlayerState(
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? '',
      position: (json['position'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      isPlaying: json['playing'] as bool? ?? false,
      isBuffering: json['buffering'] as bool? ?? false,
      accent: json['accent'] as String? ?? '#6b8afd',
      isLiked: json['liked'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 0.8,
      isMuted: json['muted'] as bool? ?? false,
      hasArtwork: json['has_artwork'] as bool? ?? false,
      hasLyrics: json['has_lyrics'] as bool? ?? false,
      seq: (json['seq'] as num?)?.toInt() ?? 0,
    );
  }
}
