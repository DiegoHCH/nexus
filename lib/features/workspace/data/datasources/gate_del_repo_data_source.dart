import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/features/workspace/data/datasources/marcas_por_rama.dart';

/// Cómo quedó el gate de un repositorio la última vez que corrió.
///
/// **Solo dos de estos se guardan en disco.** `corriendo` vive en memoria y muere con la
/// app a propósito: un estado «corriendo» persistido se queda ahí para siempre si la app
/// se cierra a mitad, y entonces la pantalla miente sobre algo que nadie está haciendo.
enum ResultadoDelGate {
  /// El repo declara gate y nadie lo ha corrido en esta rama.
  sinCorrer,

  /// Corriendo ahora. No se guarda.
  corriendo,

  /// Salió con 0.
  verde,

  /// Salió con otra cosa.
  rojo;

  bool get corrio => this == verde || this == rojo;
}

/// El permiso escrito para publicar con el gate caducado.
///
/// **Es la única llave que abre el freno del PR, y deja constancia.** No sirve para un
/// gate que no se ha corrido —ahí no hay nada que justificar, hay algo que hacer— ni para
/// uno en rojo, que no es una caducidad sino una respuesta.
///
/// Y caduca con el árbol, igual que el verde: si vale para siempre, escribirlo una vez
/// deja el freno abierto para el resto de la tarea.
@immutable
class PublicarIgual {
  const PublicarIgual({
    required this.motivo,
    required this.huella,
    this.cuando,
  });

  final String motivo;
  final String? huella;
  final DateTime? cuando;
}

/// El gate de una carpeta en una rama: qué comando es, cómo salió y sobre qué árbol.
///
/// **Verde es un número, no una afirmación.** Lo único que pone esto en verde es el código
/// de salida del proceso; no hay forma de escribirlo a mano, y es a propósito — una
/// declaración sin evidencia es un booleano con más pasos.
@immutable
class GateDelRepo {
  const GateDelRepo({
    required this.carpeta,
    this.rama,
    this.comando,
    this.resultado = ResultadoDelGate.sinCorrer,
    this.cuando,
    this.huella,
    this.salida,
    this.aviso,
    this.aunque,
  });

  final String carpeta;
  final String? rama;

  /// Lo que el repo declara en `.nexus-pruebas`, o `null` si no declara nada.
  ///
  /// Sin comando no hay gate y la interfaz no enseña nada: igual que las reglas, esto lo
  /// enciende el repositorio y no la instalación.
  final String? comando;

  final ResultadoDelGate resultado;
  final DateTime? cuando;

  /// El árbol sobre el que corrió, para poder saber si lo verde sigue cubriendo lo que hay.
  ///
  /// Es el `git stash create` que ya usa Nexus para acotar el diff de un encargo: un
  /// commit con lo que hay sin tocar nada. Sin esto, «verde» sería verde para siempre y
  /// bastaría con seguir escribiendo para que dejara de significar nada.
  final String? huella;

  /// La cola de lo que imprimió. Lo que importa de un gate rojo está al final.
  final String? salida;

  /// Lo que el archivo declaraba y no se va a hacer. Va con el gate y no en un registro
  /// aparte porque hay que leerlo justo donde se decide correrlo.
  final String? aviso;

  /// El motivo escrito para publicar sin volver a correrlo, si lo hay.
  final PublicarIgual? aunque;

  /// Si lo verde cubre el árbol que hay ahora mismo.
  ///
  /// Con la huella desconocida se responde que **no**: no saber si cubre y saber que no
  /// cubre se parecen lo bastante como para tratarlos igual, y equivocarse hacia el otro
  /// lado sería enseñar un verde que no se ha comprobado.
  bool cubre(String? huellaDeAhora) =>
      resultado == ResultadoDelGate.verde &&
      huella != null &&
      huellaDeAhora != null &&
      huella == huellaDeAhora;

  GateDelRepo copyWith({
    String? comando,
    ResultadoDelGate? resultado,
    DateTime? cuando,
    String? huella,
    String? salida,
    String? aviso,
    PublicarIgual? aunque,
    bool sinAunque = false,
  }) => GateDelRepo(
    carpeta: carpeta,
    rama: rama,
    comando: comando ?? this.comando,
    resultado: resultado ?? this.resultado,
    cuando: cuando ?? this.cuando,
    huella: huella ?? this.huella,
    salida: salida ?? this.salida,
    aviso: aviso ?? this.aviso,
    aunque: sinAunque ? null : (aunque ?? this.aunque),
  );
}

/// Lee lo que el repo declara, corre el gate y recuerda cómo salió.
///
/// El estado va **en la cuenta y por rama**, en el mismo sitio y con la misma forma que la
/// firma del plan: `<CLAUDE_CONFIG_DIR>/nexus-pruebas/<carpeta>.json`, con las ramas
/// dentro. Dos motivos, y ninguno es la simetría: una corrida es de una tarea igual que
/// una firma —el gate de `develop` no dice nada de tu `feat/…`— y ahí es donde un gancho
/// podrá leerlo cuando toque frenar un `push`.
class GateDelRepoDataSource {
  const GateDelRepoDataSource();

  static const archivo = '.nexus-pruebas';

  /// Cuánta salida se guarda. La cola, que es donde un runner pone el resumen de lo que
  /// falló; el principio de un gate largo son cientos de líneas de nada.
  static const topeDeSalida = 4000;

  Directory _dir(String configDir) => Directory('$configDir/nexus-pruebas');

  /// El comando que declara el repo, o `null` si no declara ninguno.
  ///
  /// **Uno solo.** Un gate de varios comandos tiene varios códigos de salida, y entonces
  /// «verde» deja de ser un número y pasa a ser una interpretación. Si hacen falta dos se
  /// encadenan con `&&`, que es para lo que existe un intérprete de comandos — y así la
  /// decisión de qué cuenta como pasar la toma el repo y no nosotros.
  Future<({String? comando, String? aviso})> declarado(String carpeta) async {
    final lista = File('$carpeta/$archivo');
    if (!lista.existsSync()) return (comando: null, aviso: null);

    List<String> lineas;
    try {
      lineas = (await lista.readAsString())
          .split('\n')
          .map((linea) => linea.trim())
          .where((linea) => linea.isNotEmpty && !linea.startsWith('#'))
          .toList();
    } on FileSystemException {
      return (comando: null, aviso: null);
    }

    if (lineas.isEmpty) return (comando: null, aviso: null);
    return (
      comando: lineas.first,
      // Lo que sobra se dice en vez de ejecutarse en silencio. Quien escribió tres líneas
      // esperaba que corrieran las tres, y descubrir que solo corría una por un verde que
      // no cubría nada es el peor sitio para enterarse.
      aviso: lineas.length > 1
          ? 'Solo corre la primera línea de $archivo; las otras ${lineas.length - 1} se '
                'ignoran. Encadénalas con «&&» si tienen que correr todas.'
          : null,
    );
  }

  /// Lo guardado para esa carpeta y esa rama, ya con el comando declarado dentro.
  Future<GateDelRepo> leer(
    String configDir,
    String carpeta, {
    String? rama,
  }) async {
    final declarado = await this.declarado(carpeta);
    final vacio = GateDelRepo(
      carpeta: carpeta,
      rama: rama,
      comando: declarado.comando,
      aviso: declarado.aviso,
    );

    final guardado = await _guardado(configDir, carpeta);
    final ramas = guardado?['ramas'];
    if (ramas is! Map) return vacio;
    final suya = ramas[MarcasPorRama.clave(rama)];
    if (suya is! Map) return vacio;

    return vacio.copyWith(
      resultado: switch (suya['resultado']) {
        'verde' => ResultadoDelGate.verde,
        'rojo' => ResultadoDelGate.rojo,
        _ => ResultadoDelGate.sinCorrer,
      },
      cuando: switch (suya['cuando']) {
        final num s => DateTime.fromMillisecondsSinceEpoch(
          (s * 1000).round(),
          isUtc: true,
        ),
        _ => null,
      },
      huella: suya['huella'] as String?,
      salida: suya['salida'] as String?,
      aunque: switch (suya['aunque']) {
        final Map a when (a['motivo'] as String?)?.trim().isNotEmpty ?? false =>
          PublicarIgual(
            motivo: (a['motivo'] as String).trim(),
            huella: a['huella'] as String?,
            cuando: switch (a['cuando']) {
              final num s => DateTime.fromMillisecondsSinceEpoch(
                (s * 1000).round(),
                isUtc: true,
              ),
              _ => null,
            },
          ),
        _ => null,
      },
    );
  }

  /// Deja escrito por qué se publica sin volver a correr el gate.
  ///
  /// Se ata a la huella del momento porque si no, escribirlo una vez dejaría el freno
  /// abierto para el resto de la tarea — y entonces la justificación no justifica nada
  /// concreto, solo desactiva la puerta.
  Future<GateDelRepo> publicarIgual(
    String configDir,
    GateDelRepo gate, {
    required String motivo,
    required String? huella,
  }) async {
    final limpio = motivo.trim();
    if (limpio.isEmpty) return gate;
    final conMotivo = gate.copyWith(
      aunque: PublicarIgual(
        motivo: limpio,
        huella: huella,
        cuando: DateTime.now().toUtc(),
      ),
    );
    await guardar(configDir, conMotivo);
    return conMotivo;
  }

  /// Corre el gate y devuelve cómo quedó, ya guardado.
  ///
  /// Sin tope de tiempo: un gate tarda minutos y matarlo por impaciencia daría rojos que
  /// no son del código. Quien lo lanzó ve que está corriendo y puede seguir a lo suyo.
  ///
  /// `sh -c` porque lo declarado es una línea de intérprete —con `&&`, con variables— y
  /// partirla por espacios aquí rompería la mitad de los gates reales.
  Future<GateDelRepo> correr(
    String configDir,
    GateDelRepo gate, {
    String? huella,
  }) async {
    final comando = gate.comando;
    if (comando == null || comando.trim().isEmpty) return gate;

    final salida = StringBuffer();
    int codigo;
    try {
      final proceso = await Process.start(
        '/bin/sh',
        ['-c', comando],
        workingDirectory: gate.carpeta,
        environment: ClaudeEnvironment.forTools(),
      );
      // Los dos flujos juntos y en orden de llegada: separarlos deja el error de un
      // runner en una columna y la prueba que lo causó en la otra.
      final leyendo = [
        proceso.stdout.transform(utf8.decoder).forEach(salida.write),
        proceso.stderr.transform(utf8.decoder).forEach(salida.write),
      ];
      codigo = await proceso.exitCode;
      await Future.wait(leyendo);
    } on ProcessException catch (error) {
      salida.writeln(error.message);
      codigo = -1;
    }

    final texto = salida.toString();
    final resultado = gate.copyWith(
      // Una medición nueva deja sin sentido la justificación de la anterior: se va con
      // ella en vez de quedarse esperando a coincidir otra vez con el árbol.
      sinAunque: true,
      resultado: codigo == 0 ? ResultadoDelGate.verde : ResultadoDelGate.rojo,
      cuando: DateTime.now().toUtc(),
      huella: huella,
      salida: texto.length > topeDeSalida
          ? texto.substring(texto.length - topeDeSalida)
          : texto,
    );
    await guardar(configDir, resultado);
    return resultado;
  }

  /// Guarda **sin pisar las demás ramas**, por lo mismo que la firma del plan: otra
  /// ventana puede haber corrido el gate de otra rama de la misma carpeta.
  Future<void> guardar(String configDir, GateDelRepo gate) async {
    final dir = _dir(configDir)..createSync(recursive: true);
    final archivo = File(
      '${dir.path}/${MarcasPorRama.nombre(gate.carpeta)}.json',
    );

    final ramas = <String, Object?>{};
    final guardado = await _guardado(configDir, gate.carpeta);
    if (guardado?['ramas'] is Map) {
      ramas.addAll((guardado!['ramas'] as Map).cast<String, Object?>());
    }

    final clave = MarcasPorRama.clave(gate.rama);
    if (!gate.resultado.corrio) {
      ramas.remove(clave);
    } else {
      ramas[clave] = {
        'resultado': gate.resultado == ResultadoDelGate.verde
            ? 'verde'
            : 'rojo',
        if (gate.cuando != null)
          'cuando': gate.cuando!.millisecondsSinceEpoch ~/ 1000,
        if (gate.huella != null) 'huella': gate.huella,
        if (gate.salida != null) 'salida': gate.salida,
        if (gate.aunque case final aunque?)
          'aunque': {
            'motivo': aunque.motivo,
            if (aunque.huella != null) 'huella': aunque.huella,
            if (aunque.cuando != null)
              'cuando': aunque.cuando!.millisecondsSinceEpoch ~/ 1000,
          },
      };
    }

    await archivo.writeAsString(
      '${jsonEncode({'carpeta': gate.carpeta, 'ramas': ramas})}\n',
    );
  }

  Future<Map<String, Object?>?> _guardado(
    String configDir,
    String carpeta,
  ) async {
    final archivo = File(
      '${_dir(configDir).path}/${MarcasPorRama.nombre(carpeta)}.json',
    );
    if (!archivo.existsSync()) return null;
    try {
      final leido = jsonDecode(await archivo.readAsString());
      return leido is Map ? leido.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Todas las carpetas y ramas que tienen alguna corrida anotada.
  Future<Set<({String carpeta, String? rama})>> carpetasYRamas(
    String configDir,
  ) => MarcasPorRama.claves(_dir(configDir));

  /// Se lleva la corrida de esa rama. La usa la limpieza de corridas huérfanas.
  Future<void> borrar(String configDir, String carpeta, String? rama) =>
      MarcasPorRama.borrar(_dir(configDir), carpeta, rama);
}
