/// Modelo de Usuario según especificación técnica TOM TV (Sección 7)
class UserProfile {
  final String id;
  final String username;
  final bool isGuest;
  final String? clientCode;
  final String? email;
  final String? phone;
  final bool hasParentalPin;
  final bool isAdultContentEnabled;
  final bool isActivated;

  UserProfile({
    required this.id,
    this.username = 'Visitante',
    this.isGuest = true,
    this.clientCode,
    this.email,
    this.phone,
    this.hasParentalPin = false,
    this.isAdultContentEnabled = false,
    this.isActivated = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Visitante',
      isGuest: json['isGuest'] ?? true,
      clientCode: json['clientCode']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      hasParentalPin: json['hasParentalPin'] ?? false,
      isAdultContentEnabled: json['isAdultContentEnabled'] ?? false,
      isActivated: json['isActivated'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'isGuest': isGuest,
      'clientCode': clientCode,
      'email': email,
      'phone': phone,
      'hasParentalPin': hasParentalPin,
      'isAdultContentEnabled': isAdultContentEnabled,
      'isActivated': isActivated,
    };
  }
}
