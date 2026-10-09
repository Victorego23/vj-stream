import 'package:flutter/material.dart';

/// Design Tokens oficiales para TOM TV conforme a la especificación técnica.
class TomTokens {
  TomTokens._();

  // ==========================================
  // PALETA DE COLORES (ROJO CARMESÍ & NEGRO CARBÓN)
  // ==========================================
  static const Color backgroundMain = Color(0xFF0E0E10); // Negro Carbón Profundo Estándar Smart TV
  static const Color surfaceCard = Color(0xFF161720);    // Tarjetas de contenido, banners y modales
  static const Color primaryAccent = Color(0xFFE50914);  // Rojo Neón Carmesí para tabs activas, botones y reproductor
  static const Color primaryAccentGlow = Color(0xFFFF2A4D); // Resplandor Rojo Neón
  static const Color textPrimary = Color(0xFFFFFFFF);    // Títulos y nombres de canales
  static const Color textSecondary = Color(0xFF8F92A1);  // Subtítulos EPG, etiquetas e IDs
  static const Color overlayScrim = Color(0xA6000000);   // rgba(0, 0, 0, 0.65) Oscurecimiento de modales
  
  static const Color accentRed = Color(0xFFFF2A4D);      // Icono Favoritos en perfil
  static const Color accentBlue = Color(0xFF40A9FF);     // Icono Historial en perfil
  static const Color accentGreen = Color(0xFF52C41A);    // Icono Compartir en perfil
  static const Color surfaceCardLight = Color(0xFF222330);
  static const Color dividerColor = Color(0x1FFFFFFF);

  // ==========================================
  // BORDES Y RADIOS
  // ==========================================
  static const double radiusSm = 6.0;   // Badges de canales y resoluciones
  static const double radiusMd = 12.0;  // Posters VOD y botones primarios
  static const double radiusLg = 16.0;  // Modales flotantes y tarjetas de perfil

  static final BorderRadius borderSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderPill = BorderRadius.circular(999);

  // ==========================================
  // ESTILOS DE TEXTO
  // ==========================================
  static const TextStyle titleBold = TextStyle(
    color: textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.2,
  );

  static const TextStyle bodyRegular = TextStyle(
    color: textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle captionSecondary = TextStyle(
    color: textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );
}
