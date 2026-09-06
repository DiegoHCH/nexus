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

  /// Lo que se le cuenta al encargo sobre la app que está corriendo.
  ///
  /// 🔴 **Esto es la mitad que faltaba, y puede ser la que más vale.** El
  /// dashboard local **no pide login** —es HTTP en el loopback— así que
  /// cualquier proceso de la máquina lo consulta, `claude -p` incluido. Con
  /// esto, «¿por qué se cayó?» deja de contestarse con suposiciones: se le
  /// pregunta a la app en qué pantalla está, qué providers tiene vivos y qué
  /// rutas registró.
  ///
  /// Se dice **qué hay y dónde**, no una lista de rutas: las rutas son de *ese*
  /// repositorio y cambian con él, así que enumerarlas aquí sería inventarle un
  /// contrato a la app de otro. Que las descubra preguntando, que es lo que un
  /// servidor de depuración sabe contestar.
  ///
  /// Y se dice el límite: **es una API con escritura** —mockear un endpoint,
  /// forzar un remote config, retener un loading— y eso pasa por el mismo
  /// permiso que todo lo demás.
  static String paraElPrompt({
    required int puerto,
    required String dispositivo,
  }) =>
      'La app de este proyecto está corriendo ahora mismo en $dispositivo, y '
      'trae su propia consola de depuración escuchando en ${urlDe(puerto)} '
      '(HTTP en el loopback, sin autenticación). Si te preguntan por qué algo '
      'se cae o en qué estado está la app, **pregúntale a ella** con `curl` en '
      'vez de suponerlo: expone una API de depuración y sabe decir en qué '
      'pantalla está, qué providers tiene vivos y qué rutas registró. Empieza '
      'por lo que la propia consola liste. Ojo: también tiene endpoints que '
      '**escriben** —mockear respuestas, forzar configuración remota—; esos '
      'cambian el comportamiento de la app que alguien está mirando, así que '
      'no los toques sin que te lo pidan.';
}
