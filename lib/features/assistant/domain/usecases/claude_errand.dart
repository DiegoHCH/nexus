/// Traduce lo que pide el modelo de voz a la instrucción que recibe Claude.
///
/// Vive aparte porque **cada herramienta necesita un encargo distinto**:
/// pasarle trabajo es reenviar la frase, pero crear una skill es un
/// procedimiento con sitio, formato y comprobación, y dejarlo a lo que el
/// modelo improvise produciría una carpeta distinta cada vez.
abstract final class ClaudeErrand {
  static const askTool = 'pedir_a_claude';
  static const skillTool = 'crear_skill';

  /// La tercera, y la única que **no produce un encargo para Claude**: la
  /// atiende el lanzador de Nexus. Por eso [forTool] devuelve `null` para ella
  /// igual que para una desconocida — quien la reconoce es la conversación, que
  /// es quien tiene el puerto.
  static const testTool = 'correr_prueba';

  /// El parte del día, dicho hablando: «dame el daily».
  ///
  /// **Sí acaba en Claude —lo redacta él— pero el encargo no se puede escribir
  /// aquí**: hay que ir a mirar qué conversaciones hubo el último día con
  /// trabajo y en qué carpetas, y eso es leer del disco. Por eso [forTool]
  /// también devuelve `null` para ella: la instrucción la monta el puerto, con
  /// el mismo material que usa el botón del menú, y así hablando y pulsando
  /// sale exactamente el mismo parte.
  static const parteTool = 'pedir_el_parte';

  /// Normaliza el nombre a lo que es una carpeta de skill: minúsculas y
  /// guiones medios.
  ///
  /// Hace falta porque el modelo no respeta el formato aunque se le pida: en
  /// la primera prueba devolvió `revisar_stocks` con guion bajo. Corregirlo
  /// aquí es más barato que confiar en que la próxima vez acierte, y evita
  /// carpetas con dos convenciones mezcladas.
  static String? skillName(String? raw) {
    final cleaned = (raw ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return cleaned.isEmpty ? null : cleaned;
  }

  /// `null` si la herramienta no se reconoce: mejor decírselo al modelo que
  /// inventarse un encargo con lo que haya llegado.
  static String? forTool(String name, Map<String, dynamic> arguments) {
    return switch (name) {
      askTool => (arguments['instruccion'] as String?)?.trim(),
      skillTool => _skillErrand(arguments),
      _ => null,
    };
  }

  /// Lo que el tracker pide de 3.3: que la genere, **que la pruebe** y que
  /// diga cómo invocarla.
  ///
  /// La prueba real —abrir una sesión que la use— no cabe dentro del propio
  /// encargo, así que aquí se pide lo verificable: que el archivo exista donde
  /// toca, que su frontmatter esté bien formado y que el nombre coincida con
  /// la carpeta. Es una comprobación de que quedó bien escrita, no de que
  /// resuelva el problema; llamarla «probada» a secas sería exagerar.
  static String? _skillErrand(Map<String, dynamic> arguments) {
    final name = skillName(arguments['nombre'] as String?);
    final purpose = (arguments['para_que'] as String?)?.trim();
    if (name == null || purpose == null || purpose.isEmpty) return null;

    return '''
Crea una skill de Claude Code en este proyecto, siguiendo estos pasos:

1. Escribe `.claude/skills/$name/SKILL.md` con frontmatter YAML que tenga
   `name: $name` y un `description` en una sola línea que diga qué hace y
   **cuándo hay que usarla** — esa descripción es lo único que se lee para
   decidir si la skill aplica, así que tiene que bastarse sola.
2. El cuerpo, en markdown, explica el procedimiento concreto para: $purpose
   Escríbelo para quien no tenga contexto: pasos, no intenciones.
3. Comprueba lo que escribiste: vuelve a leer el archivo, verifica que el
   frontmatter parsea, que `name` coincide con el nombre de la carpeta y que
   no quedó ningún marcador de plantilla sin rellenar.
4. Termina con una frase corta, para leerse en voz alta, diciendo que la skill
   quedó creada y cómo se invoca.

Si el permiso de escritura está en solo lectura, no lo intentes: dilo y para.
''';
  }
}
