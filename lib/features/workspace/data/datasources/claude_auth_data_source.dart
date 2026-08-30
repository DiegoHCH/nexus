import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';

/// Entrar en una cuenta de Claude sin salir de Nexus.
///
/// **Se puede porque el CLI abre el navegador con vuelta a `localhost`.** Es lo
/// que decide que esto sea un botón y no un «copia este comando»: cuando
/// terminas de firmar en el navegador, el servidor que el propio CLI levantó
/// recoge el código y guarda la sesión él solo. Nexus no toca credenciales, no
/// las ve y no las guarda; solo lanza el proceso con el `CLAUDE_CONFIG_DIR` de
/// la cuenta que toca —que es justo la parte que a mano se olvida— y espera.
///
/// El CLI tiene un plan B para cuando el navegador no alcanza a localhost:
/// imprime otra URL y se queda esperando a que pegues un código. Por ahí no se
/// entra desde aquí, y por eso hay [_plazo]: sin él, un intento que nadie
/// termina dejaría un proceso esperando para siempre.
/// Cómo acabó el intento de entrar.
///
/// Tres y no un `String?`: agotarse el plazo **no es un fallo del CLI** —no
/// dijo nada, simplemente nadie terminó en el navegador— y contarlo como tal
/// pintaría un error rojo por haberte ido a comer. Quien lo lee necesita saber
/// si volver a intentarlo o si mirar qué se rompió.
enum ComoAcabo { entro, seAgotoElPlazo, fallo }

class ClaudeAuthDataSource {
  const ClaudeAuthDataSource();

  /// Lo que se espera a que termines en el navegador.
  ///
  /// Largo porque incluye lo que tardes tú: buscar la ventana, elegir cuenta,
  /// quizá un segundo factor. Y con final porque un proceso que espera un
  /// código que nadie va a pegar no se entera de que sobra.
  static const _plazo = Duration(minutes: 5);

  /// Abre el navegador y espera a que la sesión quede guardada.
  Future<({ComoAcabo como, String? detalle})> entrar(String? configDir) async {
    final Process proceso;
    try {
      proceso = await Process.start(
        await HerramientaExterna.rutaDeClaude(),
        ['auth', 'login'],
        environment: ClaudeEnvironment.forProfile(configDir),
        includeParentEnvironment: false,
      );
    } on ProcessException catch (e) {
      return (como: ComoAcabo.fallo, detalle: e.message);
    }

    // **No se cierra la entrada.** El resto de la app la cierra para que el CLI
    // no espere por si le escriben; aquí sí puede escribírsele —es el plan B
    // del código pegado— y cerrarla de golpe sería quitarle el suelo a un
    // camino que existe.
    final dicho = StringBuffer();
    final leido = proceso.stdout
        .transform(utf8.decoder)
        .listen(dicho.write)
        .asFuture<void>();
    final leidoErr = proceso.stderr
        .transform(utf8.decoder)
        .listen(dicho.write)
        .asFuture<void>();

    try {
      final salida = await proceso.exitCode.timeout(_plazo);
      await Future.wait([leido, leidoErr]);
      if (salida == 0) return (como: ComoAcabo.entro, detalle: null);
      final texto = dicho.toString().trim();
      return (
        como: ComoAcabo.fallo,
        detalle: texto.isEmpty ? 'El CLI salió con código $salida' : texto,
      );
    } on TimeoutException {
      proceso.kill();
      return (como: ComoAcabo.seAgotoElPlazo, detalle: null);
    }
  }
}
