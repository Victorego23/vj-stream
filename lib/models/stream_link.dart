/// Modelo de datos para representar enlaces de streaming en VJ STREAM.
/// Incluye metadatos de calidad comercial (1080p, 4K, HDR, WEB-DL, BluRay)
/// y detección de audio en Español (Latino, Castellano, Dual).
class StreamLink {
  final String originalLink;
  final String streamUrl;
  final String filename;
  final int filesize;
  final String? mimeType;
  final bool streamable;
  final String qualityLabel;
  final String resolution;
  final String source;
  final bool isHdr;
  final String audioLanguage;
  final bool isSpanishAudio;
  final int rankScore;

  StreamLink({
    required this.originalLink,
    required this.streamUrl,
    required this.filename,
    required this.filesize,
    this.mimeType,
    this.streamable = true,
    this.qualityLabel = '1080p WEB-DL',
    this.resolution = '1080p',
    this.source = 'WEB-DL',
    this.isHdr = false,
    this.audioLanguage = 'Audio Original',
    this.isSpanishAudio = false,
    this.rankScore = 0,
  });

  factory StreamLink.fromJson(Map<String, dynamic> json) {
    return StreamLink(
      originalLink: json['originalLink'] ?? json['link'] ?? '',
      streamUrl: json['streamUrl'] ?? json['download'] ?? '',
      filename: json['filename'] ?? 'video.mp4',
      filesize: (json['filesize'] ?? 0) as int,
      mimeType: json['mimeType'],
      streamable: json['streamable'] == 1 || json['streamable'] == true,
      qualityLabel: json['qualityLabel'] ?? '1080p WEB-DL',
      resolution: json['resolution'] ?? '1080p',
      source: json['source'] ?? 'WEB-DL',
      isHdr: json['isHdr'] == true,
      audioLanguage: json['audioLanguage'] ?? 'Audio Original',
      isSpanishAudio: json['isSpanishAudio'] == true,
      rankScore: (json['rankScore'] ?? 0) as int,
    );
  }

  /// Convierte el tamaño en bytes a un formato legible (ej. "2.45 GB")
  String get formattedSize {
    if (filesize <= 0) return 'Desconocido';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double size = filesize.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }
}
