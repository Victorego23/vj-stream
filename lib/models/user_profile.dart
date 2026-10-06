/// Modelo de Usuario según especificación técnica TOM TV (Sección 7)
class UserProfile {
  final String id;
  final String username;
  final bool isGuest;
  final String? email;
  final String? phone;
  final bool hasParentalPin;
  final bool isAdultContentEnabled;

  UserProfile({
    required this.id,
    this.username = 'Visitante',
    this.isGuest = true,
    this.email,
    this.phone,
    this.hasParentalPin = false,
    this.isAdultContentEnabled = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '966484682',
      username: json['username']?.toString() ?? 'Visitante',
      isGuest: json['isGuest'] ?? true,
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      hasParentalPin: json['hasParentalPin'] ?? false,
      isAdultContentEnabled: json['isAdultContentEnabled'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'isGuest': isGuest,
      'email': email,
      'phone': phone,
      'hasParentalPin': hasParentalPin,
      'isAdultContentEnabled': isAdultContentEnabled,
    };
  }
}
