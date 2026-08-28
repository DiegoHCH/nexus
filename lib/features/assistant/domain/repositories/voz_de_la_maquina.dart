/// Oír y hablar sin salir del Mac.
///
/// La fase 1 del plan de la voz propia: lo único que puede cerrar del todo la
/// contra de que hablarle a Nexus manda a Google tu micrófono y lo que Claude
/// leyó del repositorio. El techo de caracteres acotó lo segundo; esto es lo que
/// puede quitar los dos.
///
/// **Todavía no sustituye a nada.** Es el banco donde se contesta la pregunta
/// que decide si el plan sigue: ¿entiende el reconocimiento del sistema un
/// encargo técnico, con nombres de archivo y palabras en inglés? Si no, el plan
/// muere aquí y habrá costado unos días en vez de un mes.
abstract class VozDeLaMaquina {
  /// Si esta máquina reconoce voz **sin salir a la red**.
  ///
  /// No es «si hay reconocedor»: casi todos los Mac tienen uno y casi todos lo
  /// resuelven en los servidores de Apple, que sería cambiar un tercero por
  /// otro. Lo que se pregunta es lo único que le da sentido a esto.
  Future<bool> disponible();

  /// El permiso de reconocimiento, que **no es el del micrófono**: son dos
  /// permisos distintos del sistema y este hay que pedirlo aparte.
  Future<bool> pedirPermiso();

  /// Escucha una frase y devuelve lo que entendió.
  ///
  /// Una frase y no un flujo: la fase 1 no lleva turnos ni interrupciones, y
  /// construirlos antes de saber si esto entiende algo sería edificar sobre una
  /// pregunta sin contestar.
  Future<String> escuchar();

  /// Lo lee en voz alta con la voz del sistema.
  Future<void> decir(String texto);

  /// Corta lo que esté diciendo.
  Future<void> callar();
}
