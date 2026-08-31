/// Guarda la llave de Gemini cifrada en la máquina. Solo viaja hacia Google
/// para sostener la sesión Live (2.1/2.2); nunca sale por ningún otro canal.
abstract class GeminiKeyStore {
  Future<String?> read();

  Future<void> save(String key);

  /// La borra del llavero.
  ///
  /// Faltaba, y era el único secreto de la app sin forma de quitarlo: los del
  /// canal y la frase de escritura ya tenían su `clear()`. Sin esto, cambiarla
  /// era sobrescribirla y **quitarla del todo obligaba a abrir Acceso a
  /// Llaveros** — que es pedirle a alguien que hurgue en el llavero de su Mac
  /// para deshacer algo que hizo desde una pantalla de Ajustes.
  Future<void> clear();
}
