import 'package:flutter/foundation.dart';

/// Un gancho de los que Nexus trae: un script que el CLI llama solo, en un momento
/// exacto de su trabajo.
///
/// **Es la tercera clase de superpoder y la que faltaba.** Un MCP le da manos, una skill
/// le da un procedimiento — y las dos las usa el modelo *si decide usarlas*. Un gancho no
/// se decide: el CLI lo ejecuta, y por eso es lo único que puede poner una regla delante
/// de una edición o negarla. Es también la diferencia entre una regla que se cumple la
/// mitad de las veces y una que se cumple.
///
/// Van **en la cuenta**, nunca en el repo. Un `settings.json` dentro de un repo
/// compartido lo hereda todo el equipo, y eso cambiaría el comportamiento del CLI de
/// otras personas sin que lo hayan pedido. Aquí el mecanismo es de quien lo instala y lo
/// enciende la carpeta: `.nexus-reglas` para las reglas por capa, el interruptor de
/// Permisos para el plan.
@immutable
class NexusHook {
  const NexusHook({
    required this.id,
    required this.event,
    required this.matcher,
    this.timeout = 10,
  });

  /// El nombre del script, sin extensión. Es también su identidad en `settings.json`:
  /// una entrada es nuestra si su comando apunta a `nexus-hooks/<id>.py`.
  final String id;

  /// El evento del CLI: `PreToolUse`, `UserPromptSubmit`…
  final String event;

  /// Qué herramientas lo disparan.
  final String matcher;

  /// Segundos. Un gancho que se cuelga bloquea el turno entero, así que esto no es un
  /// detalle: diez segundos es de sobra para leer archivos de texto del disco.
  final int timeout;

  /// Dentro del bundle de la app.
  String get asset => 'assets/hooks/$id.py';

  /// Dónde queda instalado en una cuenta.
  ///
  /// Carpeta propia y no sueltos junto a `settings.json`: así se ve de un vistazo qué
  /// puso Nexus ahí y qué puso otra cosa, y quitarlo todo es borrar una carpeta.
  String rutaEn(String configDir) => '$configDir/nexus-hooks/$id.py';

  /// Los que Nexus reparte hoy.
  ///
  /// Una lista escrita a mano y no un escaneo de la carpeta de assets: son dos, cada uno
  /// necesita un `matcher` distinto que no se deduce del archivo, y un catálogo que se
  /// adivina es un catálogo que un día instala algo que no debía.
  static const catalogo = <NexusHook>[
    NexusHook(
      id: 'inyectar_reglas',
      event: 'PreToolUse',
      matcher: 'Edit|Write|MultiEdit|NotebookEdit',
    ),
    NexusHook(
      id: 'exigir_plan',
      event: 'PreToolUse',
      matcher: 'Edit|Write|MultiEdit|NotebookEdit',
    ),
    NexusHook(
      id: 'frenar_publicacion',
      event: 'PreToolUse',
      // Sobre `Bash` y no sobre las herramientas de edición: lo que hay que mirar es un
      // comando, y el CLI abre un PR corriendo `gh`.
      matcher: 'Bash',
      // Más que los otros porque este pregunta a git por el árbol entero, y en un repo
      // grande un `stash create` no es instantáneo. Diez segundos serían un gancho que
      // se rinde justo donde más falta hace.
      timeout: 30,
    ),
  ];

  static NexusHook? porId(String id) =>
      catalogo.where((hook) => hook.id == id).firstOrNull;
}

/// Cómo está un gancho en una cuenta.
///
/// Son cuatro y no dos porque **media instalación es un estado real y silencioso**: el
/// archivo puede estar y el `settings.json` no llamarlo —o al revés, si alguien editó el
/// archivo a mano— y entonces no pasa nada de nada sin un solo error. Ese es exactamente
/// el final que estos ganchos existen para evitar, así que tiene que tener nombre.
enum EstadoDelGancho {
  /// Ni el archivo ni la entrada. No hace nada, y eso es coherente.
  ausente,

  /// Una de las dos mitades falta. No hace nada, y eso **no** se ve.
  aMedias,

  /// Puesto y llamado, pero con una copia distinta a la que trae esta versión de Nexus.
  desactualizado,

  /// Puesto, llamado, y es el de esta versión.
  alDia;

  /// Si el CLI lo está ejecutando de verdad.
  bool get funciona =>
      this == EstadoDelGancho.alDia || this == EstadoDelGancho.desactualizado;
}
