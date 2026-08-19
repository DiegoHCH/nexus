/// Guarda la llave de Gemini cifrada en la máquina. Solo viaja hacia Google
/// para sostener la sesión Live (2.1/2.2); nunca sale por ningún otro canal.
abstract class GeminiKeyStore {
  Future<String?> read();

  Future<void> save(String key);
}
