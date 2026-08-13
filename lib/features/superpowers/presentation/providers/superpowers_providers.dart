import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/superpowers/data/datasources/mcp_data_source.dart';
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
