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
    // Los instalados pisan a los disponibles cuando el mismo plugin sale en las
    // dos listas — pero **fundiéndose** con lo que ya había, no borrándolo: ver
    // [_fundidos].
    for (final item in installed is List ? installed : const []) {
      for (final plugin in _one(item, installed: true)) {
        final delCatalogo = byId[plugin.id];
        byId[plugin.id] = delCatalogo == null
            ? plugin
            : _fundidos(plugin, delCatalogo);
      }
    }

    // El nombre desempata, y no es cosmético: los instalados llegan sin
    // `installCount`, así que empatan todos a cero y `List.sort` no promete ser
    // estable. Sin el desempate, la lista de plugins puestos se reordenaba sola
    // entre recargas.
    final plugins = byId.values.toList()
      ..sort((a, b) {
        final porInstalaciones = b.installs.compareTo(a.installs);
        return porInstalaciones != 0
            ? porInstalaciones
            : a.name.compareTo(b.name);
      });
    return plugins;
  }

  /// 🔴 **Las dos listas no nombran las cosas igual, y por eso los instalados
  /// se caían enteros.**
  ///
  /// Esto leía `name ?? pluginId` y descartaba lo que no tuviera nombre. Medido
  /// contra el binario, un instalado llega así —sin `name` y sin `pluginId`—:
  ///
  ///     {"id":"flash-flutter@flash-g66","version":"0.2.179","scope":"user",
  ///      "enabled":true,"installPath":"…","installedAt":"…"}
  ///
  /// O sea que `name` salía vacío para **todos** los instalados y la guarda los
  /// tiraba. El fallback de [parseList] tampoco los rescataba, porque el
  /// `available` de este CLI **excluye lo ya puesto** —comprobado: con
  /// `flash-flutter` instalado, el catálogo trae `flashmemory` del mismo
  /// marketplace y a él no—. Resultado: un plugin puesto no aparecía en
  /// ninguna de las dos listas de la pantalla, y su versión no existía en
  /// ninguna parte de la app.
  ///
  /// El nombre y el marketplace se derivan del identificador cuando no vienen,
  /// que es lo que hace el propio CLI al pedirlos: `flash-flutter@flash-g66`
  /// ya dice las dos cosas.
  static Iterable<ClaudePlugin> _one(Object? item, {required bool installed}) {
    if (item is! Map) return const [];
    final id = '${item['pluginId'] ?? item['id'] ?? item['name'] ?? ''}';
    if (id.isEmpty) return const [];
    final partes = id.split('@');
    return [
      ClaudePlugin(
        id: id,
        name: '${item['name'] ?? partes.first}',
        description: '${item['description'] ?? ''}',
        marketplace:
            '${item['marketplaceName'] ?? (partes.length > 1 ? partes.last : '')}',
        version: item['version'] == null ? null : '${item['version']}',
        installs: (item['installCount'] as num?)?.toInt() ?? 0,
        enabled: item['enabled'] != false,
        installed: installed,
      ),
    ];
  }

  /// Lo puesto manda en estado y versión; el catálogo, en lo que solo él sabe.
  ///
  /// Hace falta porque las dos entradas del mismo plugin traen mitades
  /// distintas: la instalada sabe la versión y si está apagado, y la del
  /// catálogo la descripción y cuánta gente lo tiene. El sobrescribir a secas
  /// que había aquí se quedaba con la mitad instalada y perdía la descripción,
  /// así que un plugin puesto se enseñaba sin una línea que dijera qué hace.
  static ClaudePlugin _fundidos(ClaudePlugin puesto, ClaudePlugin catalogo) =>
      ClaudePlugin(
        id: puesto.id,
        name: puesto.name.isEmpty ? catalogo.name : puesto.name,
        description: puesto.description.isEmpty
            ? catalogo.description
            : puesto.description,
        marketplace: puesto.marketplace.isEmpty
            ? catalogo.marketplace
            : puesto.marketplace,
        version: puesto.version ?? catalogo.version,
        installs: puesto.installs == 0 ? catalogo.installs : puesto.installs,
        enabled: puesto.enabled,
        installed: true,
      );

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
