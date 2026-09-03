import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/entities/linea_de_registro.dart';

/// De dónde salen los registros del sistema de un dispositivo, y cómo se leen.
///
/// **Dos herramientas que no se parecen**, igual que con los emuladores: `adb`
/// en Android y `idevicesyslog` en iOS. Y una diferencia que importa para el
/// producto: `adb` ya está en la máquina de cualquiera que compile Android,
/// mientras que `idevicesyslog` viene de `libimobiledevice` y **es opcional** —
/// así que en iOS hay que saber decir «no está» en vez de fallar.
abstract final class LosRegistrosDelDispositivo {
  static const binarioAndroid = 'adb';
  static const binarioIos = 'idevicesyslog';

  static String binarioPara(PlataformaEmulador plataforma) =>
      switch (plataforma) {
        PlataformaEmulador.android => binarioAndroid,
        PlataformaEmulador.ios => binarioIos,
      };

  /// Con qué se pide el registro.
  ///
  /// En Android va `-v threadtime`, que es el único formato de los de `logcat`
  /// que trae **pid y tid** además del nivel y la etiqueta. Sin el pid no se
  /// puede separar lo de la app lanzada de lo de todo lo demás, y en un teléfono
  /// de verdad «todo lo demás» son cientos de líneas por minuto.
  ///
  /// [desdeAhora] tira lo que ya había en el búfer. Es lo que se quiere al
  /// engancharse a una corrida: el registro de Android guarda un rato largo, y
  /// abrirlo con quinientas líneas de antes hace que la primera de la app se
  /// pierda de vista.
  static List<String> argumentos({
    required PlataformaEmulador plataforma,
    required String deviceId,
    bool desdeAhora = true,
  }) => switch (plataforma) {
    PlataformaEmulador.android => [
      '-s',
      deviceId,
      'logcat',
      '-v',
      'threadtime',
      if (desdeAhora) ...['-T', '1'],
    ],
    // `-u` porque puede haber más de un aparato conectado, igual que el `-s` de
    // adb: sin él se engancha al primero que encuentre, que es el fallo que
    // nadie mira porque las líneas salen igual.
    PlataformaEmulador.ios => ['-u', deviceId],
  };

  /// Una línea, leída. `null` si no lo es.
  ///
  /// Se descarta en silencio y no se rompe nada: los dos formatos intercalan
  /// líneas que no son entradas —el `--------- beginning of main` de logcat, las
  /// continuaciones de un volcado de pila— y negarse por ellas dejaría la
  /// ventana vacía justo cuando algo se está cayendo.
  static LineaDeRegistro? leer(String linea) =>
      _leerAndroid(linea) ?? _leerIos(linea);

  /// `09-03 10:00:00.123  1234  1256 E AndroidRuntime: FATAL EXCEPTION`
  static final _android = RegExp(
    r'^\d{2}-\d{2} [\d:.]+\s+(\d+)\s+\d+\s+([VDIWEF])\s+([^:]*?):\s?(.*)$',
  );

  /// `Sep  3 10:00:00 iPhone Runner(Flutter)[1234] <Notice>: mensaje`
  static final _ios = RegExp(
    r'^\w{3}\s+\d+ [\d:]+ \S+ ([^\[]+)\[(\d+)\][^<]*<(\w+)>:\s?(.*)$',
  );

  static LineaDeRegistro? _leerAndroid(String linea) {
    final m = _android.firstMatch(linea);
    if (m == null) return null;
    return LineaDeRegistro(
      nivel: _nivelAndroid(m.group(2)!),
      etiqueta: m.group(3)!.trim(),
      texto: m.group(4)!,
      pid: int.tryParse(m.group(1)!),
    );
  }

  static LineaDeRegistro? _leerIos(String linea) {
    final m = _ios.firstMatch(linea);
    if (m == null) return null;
    return LineaDeRegistro(
      nivel: _nivelIos(m.group(3)!),
      etiqueta: m.group(1)!.trim(),
      texto: m.group(4)!,
      pid: int.tryParse(m.group(2)!),
    );
  }

  static NivelDeRegistro _nivelAndroid(String letra) => switch (letra) {
    'V' => NivelDeRegistro.verboso,
    'D' => NivelDeRegistro.depuracion,
    'W' => NivelDeRegistro.aviso,
    'E' => NivelDeRegistro.error,
    'F' => NivelDeRegistro.fatal,
    _ => NivelDeRegistro.info,
  };

  /// Los de iOS no coinciden con los de Android, y no se pueden traducir a ojo:
  /// `Notice` es lo normal ahí —no un aviso—, así que mapearlo a [aviso] por el
  /// nombre llenaría el filtro de ruido justo cuando se sube a «solo avisos».
  static NivelDeRegistro _nivelIos(String palabra) =>
      switch (palabra.toLowerCase()) {
        'debug' => NivelDeRegistro.depuracion,
        'warning' => NivelDeRegistro.aviso,
        'error' => NivelDeRegistro.error,
        'fault' || 'critical' => NivelDeRegistro.fatal,
        _ => NivelDeRegistro.info,
      };

  /// Lo que se queda en pantalla.
  ///
  /// [delProceso] es el pid de la app lanzada. Con él puesto, **una línea sin
  /// pid se queda igual**: los dos formatos tienen entradas sin él —el
  /// `beginning of crash` de logcat, por ejemplo— y esconderlas mientras se
  /// filtra por proceso es esconder justo el encabezado del volcado.
  static bool pasa(
    LineaDeRegistro linea, {
    NivelDeRegistro minimo = NivelDeRegistro.info,
    int? delProceso,
    String? conteniendo,
  }) {
    if (!linea.nivel.alMenos(minimo)) return false;
    if (delProceso != null && linea.pid != null && linea.pid != delProceso) {
      return false;
    }
    if (conteniendo != null && conteniendo.trim().isNotEmpty) {
      final busca = conteniendo.trim().toLowerCase();
      final donde = '${linea.etiqueta} ${linea.texto}'.toLowerCase();
      if (!donde.contains(busca)) return false;
    }
    return true;
  }
}
