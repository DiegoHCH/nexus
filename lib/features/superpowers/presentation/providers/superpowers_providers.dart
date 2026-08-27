import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/superpowers/data/datasources/mcp_data_source.dart';
import 'package:nexus/features/superpowers/data/datasources/plugins_data_source.dart';
import 'package:nexus/features/superpowers/data/datasources/skills_data_source.dart';
import 'package:nexus/features/superpowers/domain/entities/claude_plugin.dart';
import 'package:nexus/features/superpowers/domain/entities/skill.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';

final mcpDataSourceProvider = Provider<McpDataSource>(
  (ref) => const McpDataSource(),
);

/// Lo que hay puesto en esa cuenta. Instantáneo: sale del archivo.
final mcpServersProvider = FutureProvider.family<List<McpServer>, String>(
  (ref, configDir) => ref.watch(mcpDataSourceProvider).list(configDir),
);

/// Lo que el CLI ve de verdad, con la salud de cada uno y los conectores de la
/// cuenta de claude.ai incluidos.
///
/// Aparte del anterior y **no automático**: tarda casi un minuto porque
/// pregunta a cada servidor. Abrir una pantalla no puede costar eso, así que se
/// pide cuando se pulsa.
final mcpHealthProvider = FutureProvider.family<List<McpServer>?, String>(
  (ref, configDir) => ref.watch(mcpDataSourceProvider).check(configDir),
);

final skillsDataSourceProvider = Provider<SkillsDataSource>(
  (ref) => const SkillsDataSource(),
);

/// Las que ya tiene esa cuenta.
final installedSkillsProvider = FutureProvider.family<List<Skill>, String>(
  (ref, configDir) => ref.watch(skillsDataSourceProvider).installed(configDir),
);

/// Lo que trae un repo. La familia va por repo —no por cuenta— porque el
/// contenido de un repo es el mismo mires desde donde mires, y clonarlo dos
/// veces por cambiar de pestaña sería tirar la caché a la basura.
final repoSkillsProvider =
    FutureProvider.family<({List<Skill> skills, String? error}), String>(
      (ref, repo) => ref.watch(skillsDataSourceProvider).scan(repo),
    );

final pluginsDataSourceProvider = Provider<PluginsDataSource>(
  (ref) => const PluginsDataSource(),
);

/// Instalados y disponibles, en una sola lista: el CLI los da juntos y
/// separarlos en dos llamadas sería pedir dos veces lo mismo.
final pluginsProvider = FutureProvider.family<List<ClaudePlugin>, String>(
  (ref, configDir) => ref.watch(pluginsDataSourceProvider).list(configDir),
);

final marketplacesProvider = FutureProvider.family<List<Marketplace>, String>(
  (ref, configDir) =>
      ref.watch(pluginsDataSourceProvider).marketplaces(configDir),
);
