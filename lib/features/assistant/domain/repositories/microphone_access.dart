/// En qué situación está el permiso del micrófono.
///
/// Tres estados y no un booleano porque **piden cosas distintas de quien lee**:
/// [denied] se arregla en Ajustes del sistema, y [notAsked] se arregla
/// preguntando. Decir lo mismo en los dos casos manda a la gente al sitio
/// equivocado — a buscar un interruptor que todavía no existe.
enum MicrophoneStatus { granted, denied, notAsked }

/// Consulta el permiso **sin pedirlo**.
///
/// Vive aparte de `VoiceInput` a propósito: ahí el método que hay pide acceso, y
/// eso está bien donde el usuario acaba de pulsar «Solicitar», pero no para mirar
/// el estado antes de abrir la voz. Y como interfaz propia, los dobles de prueba
/// de `VoiceInput` que ya existen no tienen que cambiar.
abstract class MicrophoneAccess {
  Future<MicrophoneStatus> status();
}
