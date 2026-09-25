class LiveChannel {
  final String id;
  final String name;
  final String category;
  final String logoUrl;
  final String streamUrl;
  final String quality;
  final bool isActive;
  final int order;

  LiveChannel({
    required this.id,
    required this.name,
    this.category = 'Entretenimiento',
    this.logoUrl = '',
    required this.streamUrl,
    this.quality = '1080p HD',
    this.isActive = true,
    this.order = 999,
  });

  factory LiveChannel.fromJson(Map<String, dynamic> json) {
    return LiveChannel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Canal de TV',
      category: json['category']?.toString() ?? 'Entretenimiento',
      logoUrl: json['logoUrl']?.toString() ?? '',
      streamUrl: json['streamUrl']?.toString() ?? '',
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
      'quality': quality,
      'isActive': isActive,
      'order': order,
    };
  }
}
