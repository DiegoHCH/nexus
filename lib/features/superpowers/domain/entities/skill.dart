/// Una skill de Claude Code: una carpeta con un `SKILL.md`.
///
/// Lo que la hace útil es que el agente la activa **solo**: lee la descripción
/// de todas las que tiene y decide si esta aplica. Por eso la descripción no es
/// decorativa —es lo único que se mira para elegir— y por eso aquí se enseña,
/// aunque ocupe.
class Skill {
  const Skill({required this.id, required this.description});

  final String id;
  final String description;
}
