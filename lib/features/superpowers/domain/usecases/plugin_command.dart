import 'dart:convert';

import 'package:nexus/features/superpowers/domain/entities/claude_plugin.dart';

/// Cómo se le habla al CLI de plugins y cómo se lee lo que contesta.
abstract final class PluginCommand {
  /// Un identificador puede ser `nombre` o `nombre@marketplace`.
  static bool validId(String id) =>
      RegExp(r'^[\w.-]{1,64}(@[\w.-]{1,64})?$').hasMatch(id);

  /// Siempre alcance **user**: aquí se configura la cuenta. El alcance de
  /// proyecto lo decide el repo con su propio archivo, no esta pantalla.
  static List<String>? install(String id) =>
      validId(id) ? ['plugin', 'install', id, '-s', 'user'] : null;

  static List<String>? uninstall(String id) =>
      validId(id) ? ['plugin', 'uninstall', id, '-s', 'user'] : null;

  static List<String>? setEnabled(String id, {required bool enabled}) =>
      validId(id)
      ? ['plugin', enabled ? 'enable' : 'disable', id, '-s', 'user']
      : null;

  /// `-y` porque no hay terminal al otro lado: si el marketplace cambió el
  /// comando de instalación, el CLI se quedaría esperando una confirmación que
  /// nadie puede darle y el botón parecería colgado.
  static List<String>? update(String id) =>
      validId(id) ? ['plugin', 'update', id, '-s', 'user', '-y'] : null;

  static List<String>? addMarketplace(String source) {
    final clean = source.trim();
    if (clean.isEmpty || RegExp(r'\s').hasMatch(clean)) return null;
    return ['plugin', 'marketplace', 'add', clean];
  }

  static List<String>? removeMarketplace(String name) =>
      RegExp(r'^[\w.-]{1,64}$').hasMatch(name)
      ? ['plugin', 'marketplace', 'remove', name]
      : null;

  /// `list --available --json`, que es la forma que **sí** trae las dos listas.
  ///
  /// Medido contra el binario: `list --json` a secas devuelve un array plano de
  /// instalados, y solo con `--available` aparece el objeto con `installed` y
  /// `available`. Dar por hecha la segunda forma habría dejado la pantalla
  /// vacía sin error ninguno.
  static List<ClaudePlugin> parseList(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }

    if (decoded is List) {
      return [for (final item in decoded) ..._one(item, installed: true)];
    }
    if (decoded is! Map) return const [];

    final installed = decoded['installed'];
    final available = decoded['available'];
    final byId = <String, ClaudePlugin>{};
    for (final item in available is List ? available : const []) {
      for (final plugin in _one(item, installed: false)) {
        byId[plugin.id] = plugin;
      }
    }
    // Los instalados pisan a los disponibles: el mismo plugin sale en las dos
    // listas, y lo que interesa saber de él es que ya lo tienes.
    for (final item in installed is List ? installed : const []) {
      for (final plugin in _one(item, installed: true)) {
        byId[plugin.id] = plugin;
      }
    }

    final plugins = byId.values.toList()
      ..sort((a, b) => b.installs.compareTo(a.installs));
    return plugins;
  }

  static Iterable<ClaudePlugin> _one(Object? item, {required bool installed}) {
    if (item is! Map) return const [];
    final name = '${item['name'] ?? item['pluginId'] ?? ''}';
    if (name.isEmpty) return const [];
    return [
      ClaudePlugin(
        id: '${item['pluginId'] ?? name}',
        name: name,
        description: '${item['description'] ?? ''}',
        marketplace: '${item['marketplaceName'] ?? ''}',
        installs: (item['installCount'] as num?)?.toInt() ?? 0,
        enabled: item['enabled'] != false,
        installed: installed,
      ),
    ];
  }

  static List<Marketplace> parseMarketplaces(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];

    return [
      for (final item in decoded)
        if (item is Map && item['name'] != null)
          Marketplace(
            name: '${item['name']}',
            // `repo` o `source`, lo que traiga. **No** `installLocation`:
            // comprobado en este Mac, apunta a directorios de perfil que ya no
            // existen —quedó de antes de renombrarlos—, así que enseñarlo sería
            // enseñar una ruta falsa.
            repo: '${item['repo'] ?? item['source'] ?? ''}',
          ),
    ];
  }

  /// Filtra por lo escrito, mirando nombre y descripción.
  ///
  /// Hace falta de verdad: el marketplace oficial trae 287, y una lista de 287
  /// sin buscador no es una lista, es un muro.
  static List<ClaudePlugin> search(List<ClaudePlugin> plugins, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return plugins;
    return [
      for (final plugin in plugins)
        if (plugin.name.toLowerCase().contains(needle) ||
            plugin.description.toLowerCase().contains(needle))
          plugin,
    ];
  }
}
