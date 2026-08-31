import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/claude_usage_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Los modelos que se pueden pedir por su alias.
///
/// Se guardan los alias y no los nombres completos a propósito: `opus` sigue
/// apuntando al último Opus cuando salga otro, y fijar `claude-opus-5` dejaría
/// la app pidiendo un modelo viejo para siempre.
enum ClaudeModel {
  fable('fable', 'Fable 5'),
  opus('opus', 'Opus 5'),
  sonnet('sonnet', 'Sonnet 5'),
  haiku('haiku', 'Haiku 4.5');

  const ClaudeModel(this.alias, this.label);

  final String alias;
  final String label;

  static ClaudeModel? fromStored(String? value) {
    for (final model in values) {
      if (model.alias == value) return model;
    }
    return null;
  }

  /// El que el CLI tiene puesto, que viene con su nombre largo:
  /// `claude-opus-5[1m]` es `opus`. Se busca el alias dentro del nombre en vez
  /// de una tabla de nombres completos, que habría que ampliar con cada modelo
  /// nuevo — y quedaría en blanco justo el día que salga uno.
  static ClaudeModel? fromCliName(String? value) {
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase();
    for (final model in values) {
      if (lower.contains(model.alias)) return model;
    }
    return null;
  }
}

/// Cuánto razona antes de contestar.
enum ClaudeEffort {
  low('low'),
  medium('medium'),
  high('high'),
  xhigh('xhigh'),
  max('max');

  const ClaudeEffort(this.flag);

  final String flag;

  static ClaudeEffort? fromStored(String? value) {
    for (final effort in values) {
      if (effort.flag == value) return effort;
    }
    return null;
  }
}

/// Lo que el CLI tiene configurado en ese perfil. Sirve para que los botones
/// digan el modelo de verdad en vez de «el del sistema».
final claudeDefaultsProvider =
    FutureProvider.family<({String? model, String? effort}), String?>((
      ref,
      configDir,
    ) {
      final home = Platform.environment['HOME'] ?? '';
      return const ClaudeProfilesDataSource().defaults(
        configDir ?? '$home/.claude',
      );
    });

/// El cupo de la suscripción **de la cuenta que va a trabajar**, no de la de
/// fábrica: si esta carpeta corre con `work`, el cupo que importa es el de
/// `work`. Se refresca al abrir el panel, no en bucle: es una llamada de red y
/// el dato cambia despacio.
final claudeUsageProvider =
    FutureProvider.family<({ClaudeUsage? usage, UsageState state}), String?>(
      (ref, configDir) =>
          const ClaudeUsageDataSource().read(configDir: configDir),
    );

/// Lo último que reportó el CLI para cada cuenta.
///
/// Existe porque un perfil puede **no fijar modelo** en su `settings.json`
/// —`private` no lo hace— y entonces no había nada que enseñar hasta que
/// corriera un turno: el botón decía «Modelo» y parecía roto. Con esto, en
/// cuanto ha corrido uno, la barra sabe con qué se está trabajando aunque
/// reinicies la app.
class SeenModels extends Notifier<Map<String, String>> {
  static const _key = 'seen_models';

  @override
  Map<String, String> build() {
    unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return;
    // Sale con `unawaited`: si la pantalla se fue mientras tanto, el proveedor
    // ya no existe y esto lanzaria en vez de no hacer nada.
    if (!ref.mounted) return;
    state = decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<void> remember(String? configDir, String model) async {
    if (model.isEmpty) return;
    final key = configDir ?? 'por-defecto';
    if (state[key] == model) return;
    state = {...state, key: model};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state));
  }
}

final seenModelsProvider = NotifierProvider<SeenModels, Map<String, String>>(
  SeenModels.new,
);
