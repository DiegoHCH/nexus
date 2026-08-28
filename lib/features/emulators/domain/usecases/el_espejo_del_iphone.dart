import 'dart:io';

/// Cómo se puede ver la pantalla de un iPhone de verdad.
enum ComoVerElIphone {
  /// Duplicado de iPhone, de macOS. **Espejo y control**, inalámbrico.
  duplicado,

  /// QuickTime. Espejo por cable, **sin control**.
  quickTime,
}

/// Ver la pantalla de un iPhone físico, con lo que trae macOS.
///
/// **No hay un scrcpy para iOS y no puede haberlo**: el sistema no deja inyectar
/// eventos desde fuera ni exponer la pantalla a un cliente cualquiera. Así que aquí
/// no se elige entre construir o lanzar: solo se puede lanzar, y solo estas dos.
///
/// **Y esto no va al panel de pruebas.** Maestro no maneja un iPhone físico —solo
/// simuladores—, así que un espejo de iOS sirve para mirar y no para probar. En
/// Android el espejo acompaña a una corrida; aquí no hay corrida a la que acompañar.
///
/// Las dos se complementan y por eso están las dos:
///
/// - **Duplicado** da control, pero exige el mismo Apple ID, el teléfono bloqueado
///   y cerca, y **no deja elegir dispositivo**: abre el iPhone emparejado.
/// - **QuickTime** no da control, pero no depende del Apple ID, funciona con el
///   teléfono desbloqueado y sí distingue dispositivos — eso sí, la fuente se elige
///   dentro de QuickTime, no la podemos preseleccionar desde fuera.
abstract final class ElEspejoDelIphone {
  /// El binario del sistema que abre una app. Siempre está en macOS.
  static const binario = 'open';

  /// Dónde vive cada app. Se comprueba que exista antes de ofrecerla: Duplicado de
  /// iPhone llegó en macOS 15, así que en una anterior el botón solo podría fallar.
  static const donde = {
    ComoVerElIphone.duplicado: '/System/Applications/iPhone Mirroring.app',
    ComoVerElIphone.quickTime: '/System/Applications/QuickTime Player.app',
  };

  /// El nombre con el que `open -a` la encuentra.
  static const comoSeLlama = {
    ComoVerElIphone.duplicado: 'iPhone Mirroring',
    ComoVerElIphone.quickTime: 'QuickTime Player',
  };

  static List<String> argumentos(ComoVerElIphone como) => [
    '-a',
    comoSeLlama[como]!,
  ];

  /// Si esa app está en esta máquina.
  ///
  /// [existe] entra como parámetro por lo mismo que en [BinarioEnElPath]: lo que se
  /// puede romper al editar esto es el mapa de rutas, no `Directory`.
  static bool hay(ComoVerElIphone como, {bool Function(String ruta)? existe}) =>
      (existe ?? (ruta) => Directory(ruta).existsSync())(donde[como]!);

  /// Las que se pueden ofrecer aquí y ahora.
  static List<ComoVerElIphone> lasQueHay({
    bool Function(String ruta)? existe,
  }) => [
    for (final como in ComoVerElIphone.values)
      if (hay(como, existe: existe)) como,
  ];
}
