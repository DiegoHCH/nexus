import 'dart:async';
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

/// Modelo y esfuerzo elegidos. `null` en cualquiera de los dos significa **lo
/// que ya tenga configurado el CLI**, que es lo correcto por defecto: Nexus no
/// es el único sitio desde el que se usa Claude, y pisar su configuración desde
/// aquí sorprendería en la terminal.
class ModelPreference extends Notifier<(ClaudeModel?, ClaudeEffort?)> {
  static const _modelKey = 'claude_model';
  static const _effortKey = 'claude_effort';

  @override
  (ClaudeModel?, ClaudeEffort?) build() {
    unawaited(_load());
    return (null, null);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = (
      ClaudeModel.fromStored(prefs.getString(_modelKey)),
      ClaudeEffort.fromStored(prefs.getString(_effortKey)),
    );
  }

  Future<void> selectModel(ClaudeModel? model) async {
    state = (model, state.$2);
    final prefs = await SharedPreferences.getInstance();
    if (model == null) {
      await prefs.remove(_modelKey);
    } else {
      await prefs.setString(_modelKey, model.alias);
    }
  }

  Future<void> selectEffort(ClaudeEffort? effort) async {
    state = (state.$1, effort);
    final prefs = await SharedPreferences.getInstance();
    if (effort == null) {
      await prefs.remove(_effortKey);
    } else {
      await prefs.setString(_effortKey, effort.flag);
    }
  }
}

final modelPreferenceProvider =
    NotifierProvider<ModelPreference, (ClaudeModel?, ClaudeEffort?)>(
      ModelPreference.new,
    );

/// El cupo de la suscripción **de la cuenta que va a trabajar**, no de la de
/// fábrica: si esta carpeta corre con `work`, el cupo que importa es el de
/// `work`. Se refresca al abrir el panel, no en bucle: es una llamada de red y
/// el dato cambia despacio.
final claudeUsageProvider = FutureProvider.family<ClaudeUsage?, String?>(
  (ref, configDir) => const ClaudeUsageDataSource().read(configDir: configDir),
);

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
