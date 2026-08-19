/// Un plugin de Claude Code: skills, agentes y comandos repartidos juntos.
class ClaudePlugin {
  const ClaudePlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.marketplace,
    required this.installs,
    required this.enabled,
    required this.installed,
  });

  /// `nombre@marketplace`, que es como lo pide el CLI para instalarlo: dos
  /// marketplaces pueden traer uno con el mismo nombre.
  final String id;

  final String name;
  final String description;
  final String marketplace;

  /// Cuánta gente lo tiene. Es lo único parecido a una señal de calidad que hay
  /// entre 287 candidatos, así que ordena la lista.
  final int installs;

  final bool enabled;
  final bool installed;
}

/// De dónde salen los plugins.
class Marketplace {
  const Marketplace({required this.name, required this.repo});

  final String name;
  final String repo;
}
