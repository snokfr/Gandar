/// A concrete, playable audio stream resolved for a [Track].
///
/// Reminder: extractor URLs are signed and short-lived. Treat [url] as
/// temporary and re-resolve when it expires.
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    required this.videoId,
    required this.container,
    this.bitrate = 0,
    this.sizeBytes = 0,
    this.headers = const {},
    this.expiresAt,
    this.title,
  });

  /// Direct media URL (e.g. a `googlevideo.com` audio-only URL).
  final String url;

  /// The YouTube video id this maps to. Cached permanently against the
  /// Spotify track id so returning songs resolve instantly.
  final String videoId;

  /// `m4a`, `webm`, etc.
  final String container;

  final int bitrate;
  final int sizeBytes;

  /// Extra headers required by some stream URLs (e.g. an origin/referer pair).
  final Map<String, String> headers;

  final DateTime? expiresAt;
  final String? title;

  /// Best-effort local file extension for the cached file.
  String get fileExtension => container.isEmpty ? 'm4a' : container;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  @override
  String toString() => 'ResolvedStream($videoId, $container, ${bitrate}bps)';
}
