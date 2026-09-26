import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Modelo con los metadatos de la actualización remota
class AppUpdateInfo {
  final String latestVersion;
  final int versionCode;
  final List<String> releaseNotes;
  final String downloadUrl;
  final bool forceUpdate;

  AppUpdateInfo({
    required this.latestVersion,
    required this.versionCode,
    required this.releaseNotes,
    required this.downloadUrl,
    this.forceUpdate = false,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    List<String> notes = [];
    if (json['releaseNotes'] is List) {
      notes = (json['releaseNotes'] as List).map((e) => e.toString()).toList();
    }
    return AppUpdateInfo(
      latestVersion: json['latestVersion'] ?? '2.4.8',
      versionCode: json['versionCode'] ?? 15,
      releaseNotes: notes,
      downloadUrl: json['downloadUrl'] ?? '/api/streaming/download-apk',
      forceUpdate: json['forceUpdate'] ?? false,
    );
  }
}

/// Servicio de actualización automática In-App (OTA) para VJ STREAM
class UpdateService {
  // Versión oficial instalada en la app sincronizada con pubspec.yaml
  static const String currentVersion = '2.4.8';
  static const int currentVersionCode = 15;

  static bool _hasCheckedThisSession = false;
  static bool _isDialogVisible = false;

  /// Marca una versión como pospuesta para evitar bucles al reabrir la app
  static Future<void> _markDismissed(int versionCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_dismissed_update_code', versionCode);
      await prefs.setInt('last_prompted_update_time', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Consulta el endpoint de versión y si detecta una versión superior, despliega el diálogo OLED
  static Future<void> checkUpdate(BuildContext context, {bool silent = true}) async {
    // Si es comprobación silenciosa y ya se comprobó en esta sesión, salir para evitar bucles
    if (silent && _hasCheckedThisSession) return;
    _hasCheckedThisSession = true;

    try {
      final baseUrl = ApiService().baseUrl;
      final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final uri = Uri.parse('$cleanBase/version');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final updateInfo = AppUpdateInfo.fromJson(data);

          // Si el código de versión remoto es estrictamente superior al actual
          if (updateInfo.versionCode > currentVersionCode) {
            // Prevención de bucle: si ya se pospuso esta versión hace menos de 6 horas, no insistir en silencio
            if (silent && !updateInfo.forceUpdate) {
              try {
                final prefs = await SharedPreferences.getInstance();
                final lastDismissedCode = prefs.getInt('last_dismissed_update_code') ?? 0;
                final lastPromptTime = prefs.getInt('last_prompted_update_time') ?? 0;
                final now = DateTime.now().millisecondsSinceEpoch;
                if (lastDismissedCode == updateInfo.versionCode && (now - lastPromptTime) < 6 * 3600 * 1000) {
                  return;
                }
              } catch (_) {}
            }

            if (context.mounted && !_isDialogVisible) {
              _showUpdateDialog(context, updateInfo);
            }
          } else if (!silent && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Color(0xFF1E1E1E),
                content: Text('Ya tienes la versión más reciente de VJ STREAM (v$currentVersion).'),
              ),
            );
          }
        }
      }
    } catch (_) {
      // En modo silencioso al iniciar la app, no interrumpimos al usuario si el backend no responde
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF2B0000),
            content: Text('No fue posible comprobar actualizaciones en este momento.'),
          ),
        );
      }
    }
  }

  /// Despliega el modal de actualización con estética oscura OLED y soporte D-Pad
  static void _showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    if (_isDialogVisible) return;
    _isDialogVisible = true;
    showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (dialogCtx) => _UpdateDialogWidget(updateInfo: info),
    ).then((_) {
      _isDialogVisible = false;
      _markDismissed(info.versionCode);
    });
  }
}

class _UpdateDialogWidget extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const _UpdateDialogWidget({required this.updateInfo});

  @override
  State<_UpdateDialogWidget> createState() => _UpdateDialogWidgetState();
}

class _UpdateDialogWidgetState extends State<_UpdateDialogWidget> {
  static const MethodChannel _installerChannel =
      MethodChannel('com.vjstream.vj_stream/apk_installer');

  final FocusNode _updateButtonFocus = FocusNode();
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _downloadMessage;
  bool _downloadFinished = false;
  String? _apkFilePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateButtonFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _updateButtonFocus.dispose();
    super.dispose();
  }

  Future<void> _launchInstaller(String filePath) async {
    if (!Platform.isAndroid) {
      if (mounted) {
        setState(() {
          _downloadMessage = '¡Actualización descargada!\nArchivo guardado en: $filePath';
        });
      }
      return;
    }

    try {
      final bool? success = await _installerChannel.invokeMethod<bool>(
        'installApk',
        {'filePath': filePath},
      );
      if (success == true) {
        if (mounted) {
          setState(() {
            _downloadMessage = 'Iniciando instalación del sistema. Por favor confirma en la pantalla.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadMessage = 'Archivo descargado en:\n$filePath\nPuedes abrirlo para instalarlo.';
        });
      }
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _downloadMessage = 'Conectando con el servidor para descargar VJ STREAM v${widget.updateInfo.latestVersion}...';
    });

    IOSink? sink;
    try {
      final origin = ApiService().serverOrigin;
      final downloadPath = widget.updateInfo.downloadUrl;
      final fullUrl = downloadPath.startsWith('http')
          ? downloadPath
          : (downloadPath.startsWith('/') ? '$origin$downloadPath' : '$origin/$downloadPath');

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(fullUrl));
      final response = await client.send(request);

      if (response.statusCode >= 400) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _downloadMessage = 'No fue posible iniciar la descarga (código HTTP ${response.statusCode}).';
          });
        }
        return;
      }

      final totalBytes = (response.contentLength != null && response.contentLength! > 0)
          ? response.contentLength!
          : 154 * 1024 * 1024;
      int receivedBytes = 0;

      // Guardar el APK en el almacenamiento temporal/caché local del dispositivo
      final tempDir = Directory.systemTemp;
      final apkFile = File('${tempDir.path}/vj_stream_update.apk');
      if (apkFile.existsSync()) {
        try {
          apkFile.deleteSync();
        } catch (_) {}
      }
      sink = apkFile.openWrite();
      _apkFilePath = apkFile.absolute.path;

      response.stream.listen(
        (chunk) {
          sink?.add(chunk);
          receivedBytes += chunk.length;
          if (mounted) {
            setState(() {
              _progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
              final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
              final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
              _downloadMessage = 'Descargando actualización: $mbReceived MB de $mbTotal MB (${(_progress * 100).toInt()}%)';
            });
          }
        },
        onDone: () async {
          try {
            await sink?.flush();
            await sink?.close();
            sink = null;
          } catch (_) {}

          if (mounted) {
            setState(() {
              _isDownloading = false;
              _downloadFinished = true;
              _downloadMessage = '¡Descarga completada con éxito! Abriendo instalador de Android...';
            });
          }

          // Ejecutar instalación nativa de inmediato
          if (_apkFilePath != null) {
            await _launchInstaller(_apkFilePath!);
          }
        },
        onError: (err) async {
          try {
            await sink?.close();
            sink = null;
          } catch (_) {}
          if (mounted) {
            setState(() {
              _isDownloading = false;
              _downloadMessage = 'Hubo un inconveniente durante la descarga. Intenta nuevamente.';
            });
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadMessage = 'Error de conexión al descargar la actualización.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141414),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2A2A2A), width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con logo VJ STREAM
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE50914), Color(0xFF990000)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66E50914),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Text(
                      'VJ STREAM',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.greenAccent, width: 0.8),
                    ),
                    child: const Text(
                      'OTA UPDATE',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Título y Versión
              const Text(
                '¡Nueva Versión Disponible!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Versión ${widget.updateInfo.latestVersion} (Actual instalada: v${UpdateService.currentVersion})',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),

              // Lista de Novedades
              const Text(
                'Novedades y Mejoras del Sistema:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D0D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1F1F1F)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.updateInfo.releaseNotes.map((note) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        note,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // Barra de progreso si está descargando
              if (_isDownloading || _downloadFinished || _downloadMessage != null) ...[
                if (_isDownloading)
                  LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: const Color(0xFF222222),
                    color: const Color(0xFFE50914),
                    minHeight: 6,
                  ),
                const SizedBox(height: 8),
                Text(
                  _downloadMessage ?? '',
                  style: TextStyle(
                    color: _downloadFinished ? Colors.greenAccent : Colors.white70,
                    fontSize: 12,
                    fontWeight: _downloadFinished ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Botones de acción con soporte Smart TV D-Pad
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!widget.updateInfo.forceUpdate && !_isDownloading)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Más Tarde', style: TextStyle(color: Colors.white54)),
                    ),
                  const SizedBox(width: 12),
                  Focus(
                    focusNode: _updateButtonFocus,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space) {
                          if (!_isDownloading) {
                            if (_downloadFinished) {
                              if (_apkFilePath != null) {
                                _launchInstaller(_apkFilePath!);
                              } else {
                                Navigator.of(context).pop();
                              }
                            } else {
                              _startDownload();
                            }
                          }
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isDownloading
                          ? null
                          : () {
                              if (_downloadFinished) {
                                if (_apkFilePath != null) {
                                  _launchInstaller(_apkFilePath!);
                                } else {
                                  Navigator.of(context).pop();
                                }
                              } else {
                                _startDownload();
                              }
                            },
                      icon: Icon(
                        _downloadFinished ? Icons.system_update_rounded : Icons.system_update_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: Text(
                        _downloadFinished
                            ? 'Instalar Ahora'
                            : (_isDownloading ? 'Descargando...' : 'Actualizar Ahora'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
