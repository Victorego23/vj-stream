class LiveChannel {
  final String id;
  final String name;
  final String category;
  final String logoUrl;
  final String streamUrl;
  final List<String> sources;
  final String quality;
  final bool isActive;
  final int order;

  LiveChannel({
    required this.id,
    required this.name,
    this.category = 'Entretenimiento',
    this.logoUrl = '',
    required this.streamUrl,
    List<String>? sources,
    this.quality = '1080p HD',
    this.isActive = true,
    this.order = 999,
  }) : sources = (sources != null && sources.isNotEmpty)
            ? sources
            : (streamUrl.isNotEmpty ? [streamUrl] : []);

  factory LiveChannel.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    final parsedSources = <String>[];
    if (rawSources is List) {
      for (final s in rawSources) {
        if (s != null && s.toString().trim().isNotEmpty) {
          parsedSources.add(s.toString().trim());
        }
      }
    }

    final rawStreamUrl = json['streamUrl']?.toString().trim() ?? '';
    if (parsedSources.isEmpty && rawStreamUrl.isNotEmpty) {
      parsedSources.add(rawStreamUrl);
    }

    final effectiveStreamUrl = parsedSources.isNotEmpty ? parsedSources.first : rawStreamUrl;

    return LiveChannel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Canal de TV',
      category: json['category']?.toString() ?? 'Entretenimiento',
      logoUrl: json['logoUrl']?.toString() ?? '',
      streamUrl: effectiveStreamUrl,
      sources: parsedSources,
      quality: json['quality']?.toString() ?? '1080p HD',
      isActive: json['isActive'] != false,
      order: json['order'] is int ? json['order'] : 999,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'logoUrl': logoUrl,
      'streamUrl': streamUrl,
      'sources': sources,
      'quality': quality,
      'isActive': isActive,
      'order': order,
    };
  }
}
