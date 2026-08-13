import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';

/// Cuánto llevas gastado de tu suscripción.
@immutable
class ClaudeUsage {
  const ClaudeUsage({
    required this.account,
    required this.fiveHourPercent,
    required this.weeklyPercent,
    this.fiveHourResetsAt,
    this.weeklyResetsAt,
  });

  /// De qué cuenta son estos números — `work`, `private`, «por defecto»—.
  ///
  /// Se dice siempre, y no solo cuando hay varias: el cupo es de una cuenta
  /// concreta, y una cifra sin dueño invita a leerla como la de la que estabas
  /// mirando.
  final String account;

  final int fiveHourPercent;
  final int weeklyPercent;
  final DateTime? fiveHourResetsAt;
  final DateTime? weeklyResetsAt;
}

/// Lee el cupo de la suscripción por el mismo sitio que la app de la barra de
/// menús: el endpoint OAuth, con el token que Claude Code guarda en el llavero.
///
/// Hace falta porque el medidor de la conversación cuenta **contexto**, que es
/// otra cosa: puedes tener la ventana medio vacía y el cupo de la semana en las
/// últimas. Y con tres conversaciones en paralelo eso se agota tres veces más
/// rápido.
class ClaudeUsageDataSource {
  const ClaudeUsageDataSource();

  /// `null` cuando no se puede saber, que es distinto de cero: sin sesión en
  /// ese perfil, con el token caducado o sin red, lo honesto es no dibujar una
  /// barra vacía que se leería como «no has gastado nada».
  ///
  /// Y es **de la cuenta que se pide, o de ninguna**. Antes, si esa no servía,
  /// se caía a otra: enseñaba el cupo de `work` estando en `private`, que es
  /// justo el número que no había que mirar.
  Future<ClaudeUsage?> read({String? configDir}) async {
    final home = Platform.environment['HOME'] ?? '';
    final dir = (configDir == null || configDir.isEmpty)
        ? '$home/.claude'
        : configDir;
    final token = await _tokenFor(dir);
    if (token == null) return null;
    final account = _accountName(dir);

    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.https('api.anthropic.com', '/api/oauth/usage'),
      );
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set('anthropic-beta', 'oauth-2025-04-20');

      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      // Un error de la API también trae JSON parseable —401 por token vencido,
      // 5xx—, así que sin mirar el código se guardaría un cero como si fuera
      // una medición. Solo un 200 cuenta.
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ClaudeUsage(
        account: account,
        fiveHourPercent: _percent(decoded['five_hour']),
        weeklyPercent: _percent(decoded['seven_day']),
        fiveHourResetsAt: _resetsAt(decoded['five_hour']),
        weeklyResetsAt: _resetsAt(decoded['seven_day']),
      );
    } on Exception {
      return null;
    } finally {
      client.close();
    }
  }

  static int _percent(Object? bucket) {
    if (bucket is! Map<String, dynamic>) return 0;
    return ((bucket['utilization'] as num?) ?? 0).round();
  }

  static DateTime? _resetsAt(Object? bucket) {
    if (bucket is! Map<String, dynamic>) return null;
    final raw = bucket['resets_at'] as String?;
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  static String _accountName(String configDir) {
    final name = configDir.split('/').last;
    return name.startsWith('.claude-') ? name.substring(8) : 'por defecto';
  }

  /// La caducidad se mira aquí en vez de dejar que la API conteste 401: es una
  /// petición de red menos, y sobre todo permite distinguir «esta cuenta no
  /// tiene sesión» de «el servicio no responde».
  Future<String?> _tokenFor(String configDir) async {
    final services = [
      ClaudeProfilesDataSource.keychainService(configDir),
      // El perfil por defecto puede guardar la credencial sin sufijo, de antes
      // de que Claude Code separara cuentas.
      if (configDir.endsWith('/.claude')) 'Claude Code-credentials',
    ];

    for (final name in services) {
      final result = await Process.run('security', [
        'find-generic-password',
        '-s',
        name,
        '-w',
      ]);
      if (result.exitCode != 0) continue;
      try {
        final decoded = jsonDecode((result.stdout as String).trim());
        if (decoded is! Map<String, dynamic>) continue;
        final oauth = decoded['claudeAiOauth'];
        if (oauth is! Map<String, dynamic>) continue;
        final expires = (oauth['expiresAt'] as num?)?.toInt() ?? 0;
        if (expires < DateTime.now().millisecondsSinceEpoch) continue;
        final token = oauth['accessToken'] as String?;
        if (token != null && token.isNotEmpty) return token;
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}
