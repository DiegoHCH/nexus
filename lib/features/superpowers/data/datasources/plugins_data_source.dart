import 'dart:io';

import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/features/superpowers/domain/entities/claude_plugin.dart';
import 'package:nexus/features/superpowers/domain/usecases/plugin_command.dart';

/// Los plugins de una cuenta, todo por el CLI.
///
/// Aquí no hay atajo por archivo como en los MCP: los plugins se resuelven
/// contra los marketplaces, que se clonan y se actualizan solos. Leer el estado
/// del disco sería reimplementar eso.
class PluginsDataSource {
  const PluginsDataSource();

  Future<List<ClaudePlugin>> list(String configDir) async {
    // `--available` además de `--json`: sin él, el CLI devuelve solo los
    // instalados y en otra forma. Comprobado contra el binario.
    final output = await _run(configDir, [
      'plugin',
      'list',
      '--available',
      '--json',
    ]);
    return output == null ? const [] : PluginCommand.parseList(output);
  }

  Future<List<Marketplace>> marketplaces(String configDir) async {
    final output = await _run(configDir, [
      'plugin',
      'marketplace',
      'list',
      '--json',
    ]);
    return output == null ? const [] : PluginCommand.parseMarketplaces(output);
  }

  /// El inventario de un plugin y su coste de contexto proyectado.
  ///
  /// Solo funciona con los **instalados** —comprobado: con uno del catálogo
  /// contesta «no encontrado»—, así que es para decidir si merece la pena
  /// conservarlo, no si merece la pena traerlo. Sale en texto plano y así se
  /// enseña: inventarle una estructura sería adivinar.
  Future<String?> details(String configDir, String name) =>
      _run(configDir, ['plugin', 'details', name]);

  Future<String?> install(String configDir, String id) =>
      _act(configDir, PluginCommand.install(id));

  Future<String?> uninstall(String configDir, String id) =>
      _act(configDir, PluginCommand.uninstall(id));

  Future<String?> setEnabled(
    String configDir,
    String id, {
    required bool enabled,
  }) => _act(configDir, PluginCommand.setEnabled(id, enabled: enabled));

  Future<String?> update(String configDir, String id) =>
      _act(configDir, PluginCommand.update(id));

  Future<String?> addMarketplace(String configDir, String source) =>
      _act(configDir, PluginCommand.addMarketplace(source));

  Future<String?> removeMarketplace(String configDir, String name) =>
      _act(configDir, PluginCommand.removeMarketplace(name));

  /// `null` si salió bien, el error del CLI si no.
  Future<String?> _act(String configDir, List<String>? args) async {
    if (args == null) return 'Datos inválidos';
    try {
      final result = await Process.run(
        'claude',
        args,
        environment: ClaudeEnvironment.forProfile(configDir),
        includeParentEnvironment: false,
      );
      if (result.exitCode == 0) return null;
      final error = '${result.stderr}'.trim();
      return error.isEmpty ? '${result.stdout}'.trim() : error;
    } on ProcessException catch (error) {
      return error.message;
    }
  }

  Future<String?> _run(String configDir, List<String> args) async {
    try {
      final result = await Process.run(
        'claude',
        args,
        environment: ClaudeEnvironment.forProfile(configDir),
        includeParentEnvironment: false,
      );
      return result.exitCode == 0 ? '${result.stdout}' : null;
    } on ProcessException {
      return null;
    }
  }
}
