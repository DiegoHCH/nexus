import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/features/run/domain/entities/mensaje_del_daemon.dart';
import 'package:nexus/features/run/domain/usecases/lineas_del_daemon.dart';
import 'package:nexus/features/run/domain/usecases/peticiones_pendientes.dart';
import 'package:nexus/features/run/domain/usecases/protocolo_del_daemon.dart';

/// Un `flutter run --machine` vivo, con su canal abierto.
///
/// **El primer proceso de vida larga de esta app.** Todo lo que lanzaba Nexus
/// hasta ahora era `Process.run`: arranca, termina, devuelve. Esto no: vive
/// mientras la app viva, hay que leerle la salida línea a línea y escribirle por
/// stdin. Lo más parecido que había es `ClaudeCliDataSource`, que hace
/// `Process.start` y entrega un `Stream` del `stream-json` de `claude -p`; de ahí
/// sale la forma, con una diferencia que importa: **aquí el stdin no se cierra**,
/// porque por ahí van las recargas.
class CorridaViva {
  CorridaViva._(this._proceso, this._peticiones, this.onEvento, this.onRegistro);

  final Process _proceso;
  final PeticionesPendientes _peticiones;

  /// Lo que cuenta el daemon. Quien escuche traduce a estado.
  final void Function(EventoDelDaemon evento) onEvento;

  /// Todo lo demás: la salida del compilador, los avisos, lo que imprima la app.
  final void Function(String linea) onRegistro;

  /// `null` mientras no haya llegado `app.start`.
  String? appId;

  /// Si el cierre lo pedimos nosotros.
  ///
  /// **Sin esto, parar bien se cuenta como un fallo**: el proceso sale con código
  /// distinto de cero al cerrarse la app, y quien mira el código diría que se
  /// cayó. Es el mismo arreglo que hay en `la-oficina`.
  var parando = false;

  /// Lanza `flutter run --machine` y engancha su salida.
  ///
  /// [args] son los de la configuración del `launch.json`, ya traducidos y con
  /// las variables sustituidas: aquí no se interpreta ninguno.
  static Future<CorridaViva?> arrancar({
    required String flutter,
    required String proyecto,
    required String deviceId,
    required List<String> args,
    required void Function(EventoDelDaemon evento) onEvento,
    required void Function(String linea) onRegistro,
    required void Function(String? motivo) onFin,
  }) async {
    final Process proceso;
    try {
      proceso = await Process.start(
        flutter,
        ['run', '--machine', '-d', deviceId, ...args],
        workingDirectory: proyecto,
        environment: ClaudeEnvironment.forTools(),
        includeParentEnvironment: false,
      );
    } on ProcessException {
      return null;
    }

    final peticiones = PeticionesPendientes(
      escribir: (linea) => proceso.stdin.write(linea),
    );
    final viva = CorridaViva._(proceso, peticiones, onEvento, onRegistro);

    // **El stdin NO se cierra**, al contrario que con `claude -p`. Ahí se cierra
    // para que no espere entrada que nadie va a mandar; aquí es el canal por el
    // que se pide recargar y parar.
    final lineas = LineasDelDaemon();
    proceso.stdout.transform(utf8.decoder).listen(
      (trozo) {
        for (final mensaje in lineas.add(trozo)) {
          viva._reparte(mensaje);
        }
      },
      onDone: () {
        if (lineas.cierra() case final ultimo?) viva._reparte(ultimo);
      },
    );

    // stderr entero como registro: ahí sale lo de Gradle y lo de CocoaPods, que
    // es lo que se lee cuando algo no compila.
    proceso.stderr
        .transform(utf8.decoder)
        .listen((trozo) => onRegistro(trozo.trimRight()));

    unawaited(
      proceso.exitCode.then((codigo) {
        // Nadie va a contestar ya: se libera a quien esperase una recarga en vez
        // de dejarlo colgado hasta el plazo.
        peticiones.cierra();
        onFin(
          viva.parando || codigo == 0
              ? null
              : 'flutter run terminó con código $codigo',
        );
      }),
    );

    return viva;
  }

  void _reparte(MensajeDelDaemon mensaje) {
    switch (mensaje) {
      case EventoDelDaemon():
        if (mensaje.nombre == 'app.start') {
          appId = mensaje.params['appId'] as String?;
        }
        onEvento(mensaje);
      case RespuestaDelDaemon():
        // Si no era de nadie, es información y se enseña como registro en vez de
        // tirarse en silencio.
        if (!_peticiones.recibe(mensaje)) {
          onRegistro('respuesta sin dueño: id ${mensaje.id}');
        }
      case RegistroDelDaemon():
        if (mensaje.texto.trim().isNotEmpty) onRegistro(mensaje.texto);
    }
  }

  /// Recargar (o reiniciar, con [completa]).
  ///
  /// Sin `appId` todavía no hay a quién pedírselo, y eso **no es un fallo**: es
  /// que sigue compilando. Se dice así.
  Future<({bool ok, String? error})> recargar({required bool completa}) {
    final id = appId;
    if (id == null) {
      return Future.value((ok: false, error: 'Todavía está compilando'));
    }
    return _peticiones.pedir(
      (n) => ProtocoloDelDaemon.peticionDeRecarga(n, id, completa: completa),
    );
  }

  /// Parar por el daemon, no matando el proceso.
  ///
  /// Así la app se cierra sola en el dispositivo y el otro lado avisa con
  /// `app.stop`. Matar el proceso la dejaría abierta y sin nadie que lo cuente.
  ///
  /// Si no hay `appId` —murió antes de arrancar— entonces sí se mata: es lo único
  /// que queda.
  Future<({bool ok, String? error})> parar() async {
    parando = true;
    final id = appId;
    if (id == null) {
      _proceso.kill();
      return (ok: true, error: null);
    }
    return _peticiones.pedir(
      (n) => ProtocoloDelDaemon.peticionDeParada(n, id),
    );
  }
}
