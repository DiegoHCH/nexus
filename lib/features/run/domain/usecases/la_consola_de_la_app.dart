/// La consola de depuración que **la app se levanta a sí misma**.
///
/// 🔴 **Esto no construye ninguna consola.** La app del trabajo ya trae un
/// servidor de depuración dentro —rutas registradas, estado de la pantalla,
/// providers en vivo, mockeo de endpoints— y hasta ahora llegar a él era abrir
/// el túnel a mano y luego el navegador. Lo único que falta es traerlo dentro,
/// como se trajeron los documentos y los registros.
///
/// Dos cosas se sacan de lo que ya pasa por delante, y ninguna se inventa:
///
/// - **Si hay consola** lo dice la configuración elegida del `launch.json`, que
///   `LectorDeConfigs` ya traduce a `--dart-define`. Sin el flag no se hace
///   nada: no todas las apps traen esto, y desde luego no en cualquier entorno.
/// - **En qué puerto** lo dice la app al arrancar, en su propio banner. El
///   `9777` es de **ese** repositorio y no una constante nuestra: cablearlo
///   sería acertar hoy y fallar el día que alguien lo cambie, con un fallo que
///   además no diría por qué.
abstract final class LaConsolaDeLaApp {
  /// El `--dart-define` que la enciende.
  static const elFlag = 'ENABLE_DEBUG_SERVER';

  /// Si la configuración elegida trae la consola encendida.
  ///
  /// Se mira el valor y no solo el nombre: `ENABLE_DEBUG_SERVER=false` está en
  /// los `launch.json` de verdad —el entorno de producción lo apaga— y tratarlo
  /// como encendido abriría un túnel a un puerto donde no hay nadie.
  static bool laEnciende(List<String> args) {
    for (final arg in args) {
      final defineDe = _elDefine.firstMatch(arg);
      if (defineDe == null) continue;
      if (defineDe.group(1)?.toLowerCase() == 'true') return true;
    }
    return false;
  }

  static final _elDefine = RegExp('$elFlag=([^\\s]+)', caseSensitive: false);

  /// El puerto que la app dice que abrió, si esta línea lo dice.
  ///
  /// Se acepta `localhost` y `127.0.0.1` porque las dos formas salen en la
  /// práctica, y se pide el `http://` delante para no confundir un puerto con
  /// cualquier número separado por dos puntos —una traza con `Perfil.kt:9777`
  /// no es un banner—.
  static int? puertoEn(String linea) {
    final donde = _elBanner.firstMatch(linea);
    if (donde == null) return null;
    final puerto = int.tryParse(donde.group(1) ?? '');
    // Los puertos de verdad y no cualquier número: un `http://localhost:0` no
    // lleva a ninguna parte, y por encima de 65535 no es un puerto.
    if (puerto == null || puerto <= 0 || puerto > 65535) return null;
    return puerto;
  }

  static final _elBanner = RegExp(
    r'https?://(?:localhost|127\.0\.0\.1):(\d{1,5})',
    caseSensitive: false,
  );

  /// A dónde apunta la ventana, ya en la máquina: el túnel deja el puerto del
  /// dispositivo en el mismo número de aquí.
  static String urlDe(int puerto) => 'http://localhost:$puerto';
}
