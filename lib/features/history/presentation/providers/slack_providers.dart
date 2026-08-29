import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/history/data/datasources/slack_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adónde va el parte, y con qué permiso.
///
/// **El token vive en el llavero y su valor no sale de ahí**, igual que la
/// llave de Gemini y el de Notion: aquí solo se sabe si está. El destino sí es
/// una preferencia normal — es un identificador de Slack, no un secreto.
class SlackConfig {
  const SlackConfig({this.hayToken = false, this.destino, this.proyecto});

  final bool hayToken;

  /// A quién se le manda: tu propio identificador de usuario para que llegue a
  /// tu conversación contigo, o el de un canal.
  final String? destino;

  /// De qué proyecto se cuenta el trabajo. `null` = de todos.
  ///
  /// **No es comodidad, es sitio**: el parte va al Slack de un equipo concreto,
  /// y sin esto lo que hiciste en tus proyectos personales —o en otro repo del
  /// mismo trabajo— acabaría contado en ese daily.
  final String? proyecto;

  bool get listo => hayToken && (destino ?? '').trim().isNotEmpty;

  SlackConfig copyWith({
    bool? hayToken,
    String? destino,
    String? proyecto,
    bool sinProyecto = false,
  }) => SlackConfig(
    hayToken: hayToken ?? this.hayToken,
    destino: destino ?? this.destino,
    proyecto: sinProyecto ? null : (proyecto ?? this.proyecto),
  );
}

class SlackController extends Notifier<SlackConfig> {
  static const _tokenKey = 'slack_token';
  static const _destinoKey = 'slack_destino';
  static const _proyectoKey = 'slack_proyecto';

  @override
  SlackConfig build() {
    unawaited(_cargar());
    return const SlackConfig();
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    String? token;
    try {
      token = await ref.read(secureStorageDataSourceProvider).read(_tokenKey);
    } on Object {
      // El llavero puede negarse —permisos, otro login— y eso no puede tumbar
      // los ajustes: lo que se pierde es saber si hay token, no la pantalla.
      token = null;
    }
    if (!ref.mounted) return;
    state = SlackConfig(
      hayToken: (token ?? '').isNotEmpty,
      destino: prefs.getString(_destinoKey),
      proyecto: prefs.getString(_proyectoKey),
    );
  }

  Future<void> guardarToken(String token) async {
    await ref
        .read(secureStorageDataSourceProvider)
        .write(_tokenKey, token.trim());
    state = state.copyWith(hayToken: token.trim().isNotEmpty);
  }

  Future<void> guardarDestino(String destino) async {
    final limpio = destino.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_destinoKey, limpio);
    state = state.copyWith(destino: limpio);
  }

  /// De qué proyecto se cuenta el trabajo. `null` vuelve a «todos».
  Future<void> guardarProyecto(String? proyecto) async {
    final prefs = await SharedPreferences.getInstance();
    if (proyecto == null || proyecto.isEmpty) {
      await prefs.remove(_proyectoKey);
      state = state.copyWith(sinProyecto: true);
      return;
    }
    await prefs.setString(_proyectoKey, proyecto);
    state = state.copyWith(proyecto: proyecto);
  }

  /// Manda un texto por la puerta de Slack. Devuelve el motivo si no salió.
  ///
  /// **Lee el token en el momento y no lo guarda en el estado**: un secreto que
  /// vive en memoria acaba en un volcado, en un registro o en una captura de
  /// pantalla de alguien depurando.
  Future<String?> mandar(String texto) async {
    final destino = state.destino;
    if (destino == null || destino.trim().isEmpty) {
      return 'falta a quién mandarlo';
    }
    final token = await ref
        .read(secureStorageDataSourceProvider)
        .read(_tokenKey);
    return const SlackApi().mandar(
      token: token ?? '',
      destino: destino,
      texto: texto,
    );
  }
}

final slackControllerProvider = NotifierProvider<SlackController, SlackConfig>(
  SlackController.new,
);
