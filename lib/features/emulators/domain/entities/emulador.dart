/// En qué plataforma corre un emulador.
///
/// Dos y no una lista abierta: `flutter emulators` solo devuelve `android` e
/// `ios`, y lo que se hace con cada uno para saber si está arriba o para
/// cerrarlo **no se parece en nada** —adb en uno, simctl en el otro—. Un tercer
/// valor tendría que traer sus dos herramientas.
enum PlataformaEmulador {
  android,
  ios;

  static PlataformaEmulador? desde(String texto) => switch (texto.toLowerCase()) {
    'android' => PlataformaEmulador.android,
    'ios' => PlataformaEmulador.ios,
    _ => null,
  };

  /// La plataforma tal como la nombra `flutter devices`, que **no es la misma
  /// palabra**: ahí un móvil Android es `android-arm64` y un iPhone es `ios`, y
  /// además aparecen `darwin` y `web-javascript`, que no son teléfonos.
  static PlataformaEmulador? desdeObjetivo(String objetivo) {
    final texto = objetivo.toLowerCase();
    if (texto.startsWith('android')) return PlataformaEmulador.android;
    if (texto.startsWith('ios')) return PlataformaEmulador.ios;
    return null;
  }
}

/// Un emulador de Android o un simulador de iOS, con si está arriba.
class Emulador {
  const Emulador({
    required this.id,
    required this.nombre,
    required this.fabricante,
    required this.plataforma,
    this.corriendo = false,
    this.deviceId,
  });

  /// El identificador que entiende `flutter emulators --launch`.
  final String id;

  /// Cómo se llama para una persona. `Medium Phone API 36.1` frente a
  /// `Medium_Phone_API_36.1`.
  final String nombre;

  final String fabricante;
  final PlataformaEmulador plataforma;

  /// Si está arriba ahora mismo.
  ///
  /// **No lo dice `flutter emulators`**: esa lista es el catálogo y no el estado.
  /// Sale de cruzarla con las herramientas de cada plataforma, y por eso este
  /// campo se rellena aparte en vez de venir del parseo.
  final bool corriendo;

  /// El dispositivo con el que se cierra, cuando está arriba.
  ///
  /// Solo Android, y ahí está el motivo de que exista: **no hay ningún
  /// identificador común entre un emulador y el dispositivo que resulta de
  /// arrancarlo**. `Medium_Phone_API_36.1` se convierte en `emulator-5554`, y
  /// para matarlo hace falta el segundo. En iOS no se necesita porque se apagan
  /// todos de una vez.
  final String? deviceId;

  Emulador conEstado({required bool corriendo, String? deviceId}) => Emulador(
    id: id,
    nombre: nombre,
    fabricante: fabricante,
    plataforma: plataforma,
    corriendo: corriendo,
    deviceId: deviceId,
  );
}

/// Un teléfono de verdad enchufado al Mac.
///
/// **Aparte de [Emulador] y no un campo suyo**, porque el verbo no es el mismo:
/// un emulador se arranca y se cierra; uno de estos ya está, y lo único que se
/// puede hacer con él es usarlo. Meterlos en la misma lista con un botón apagado
/// sería enseñar un botón que nunca sirve.
class DispositivoConectado {
  const DispositivoConectado({
    required this.id,
    required this.nombre,
    required this.plataforma,
  });

  /// Lo que entiende `-d`: el número de serie en Android, el UDID en iOS.
  final String id;

  /// Como se llama a sí mismo. En Android suele ser el código de modelo
  /// —`24069PC21G`— y no el nombre comercial: es lo que reporta el aparato, y
  /// traducirlo pediría una tabla de modelos que caduca sola.
  final String nombre;

  final PlataformaEmulador plataforma;
}
