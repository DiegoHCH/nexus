import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';

/// Lo que se le puede preguntar al CLI **sobre sí mismo**: si está y si esa
/// cuenta tiene sesión.
///
/// Vive en `core` y no dentro de una feature porque lo van a usar dos: el
/// arranque, para no dejar entrar a una app que no puede trabajar, y el lector
/// del cupo, que ya lo necesitaba. Ahí estaba enterrado como método privado, y
/// dos copias de esto se separan en cuanto una cambie.
///
/// El lanzador se inyecta para poder probarlo: con `Process.run` de verdad, la
/// prueba dependería de que la máquina tenga —o no tenga— Claude Code
/// instalado, que es justo el caso que hay que cubrir en los dos sentidos.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

class ClaudeCli {
  ClaudeCli({ProcessRunner? run, Future<String> Function()? donde})
    : _run = run ?? Process.run,
      _donde = donde ?? HerramientaExterna.rutaDeClaude;

  final ProcessRunner _run;

  /// Cómo se averigua **dónde** está el binario.
  ///
  /// 🔴 **Esto se lanzaba por nombre, y ahí estuvo el bug que bloqueó la primera
  /// instalación ajena.** `Process.run('claude', …)` deja que el sistema lo
  /// resuelva con el PATH que se le inyecta, y ese PATH son cuatro carpetas
  /// fijas: no cubre a quien tiene Claude dentro de una versión de Node de fnm,
  /// nvm o volta — o sea, a cualquier dev de front.
  ///
  /// [HerramientaExterna] existe justo para esto y ya sabía buscar en los
  /// gestores de versiones y preguntarle al shell del usuario. Lo que faltaba
  /// era que **la pantalla que bloquea la entrada** usara la misma respuesta que
  /// los encargos: se arregló el lanzar y no el comprobar, así que la app
  /// seguía diciendo «no está instalado» a alguien que lo tenía.
  ///
  /// Se inyecta por el mismo motivo que [_run]: para poder probar **con qué
  /// ruta** se lanza, que es lo que ningún test miraba.
  final Future<String> Function() _donde;

  /// Si el binario se resuelve **y arranca**.
  ///
  /// Se le pide la versión en vez de buscarlo con `which`: lo que importa no es
  /// que el archivo exista, es que se pueda ejecutar. Y va por ruta absoluta,
  /// resuelta por [HerramientaExterna]: el PATH inyectado no basta —es la trampa
  /// de `v3` a medio resolver— porque una app de GUI no hereda el de la shell y
  /// las cuatro carpetas fijas no son donde vive todo el mundo.
  Future<bool> installed() async {
    try {
      final result = await _run(await _donde(), [
        '--version',
      ], environment: ClaudeEnvironment.forTools());
      return result.exitCode == 0;
    } on Exception {
      return false;
    }
  }

  /// Si esa cuenta tiene sesión, **según el CLI**.
  ///
  /// Se le pregunta a él y no se deduce del llavero porque el llavero solo dice
  /// cuándo vence el acceso, no si hay cuenta: con el acceso vencido y el
  /// refresco bueno —lo normal tras unas horas sin usarla— mirar la caducidad
  /// concluye «no hay sesión», que es falso.
  ///
  /// `auth status --json` contesta en **0,25 s medidos**. Y de paso puede hacer
  /// que el CLI renueve el token, que es justo lo que nos vendría bien.
  Future<bool> loggedIn(String? configDir) async =>
      await sesion(configDir) == EstadoDeSesion.hay;

  /// Si esa cuenta tiene sesión, **en tres estados y no en dos**.
  ///
  /// 🔴 **«No pude preguntar» no es «no hay sesión», y confundirlos bloqueó a la
  /// primera persona ajena que instaló Nexus.** Le dijo «ninguna cuenta tiene
  /// sesión abierta» —con su consejo de abrir una terminal y escribir `claude`—
  /// a alguien cuyo `claude auth status --json` contestaba `loggedIn: true` en
  /// esa misma terminal.
  ///
  /// Aquí había un `return false` para el fallo, con este motivo escrito: «es el
  /// único caso en que el usuario tiene algo que hacer —iniciarla—, y
  /// equivocarse aquí solo cuesta una frase». Las dos mitades eran falsas: no
  /// tenía nada que hacer porque ya la tenía, y no costó una frase sino la
  /// entrada a la app.
  ///
  /// Y la app ya tenía la respuesta escrita dos archivos más allá, en
  /// `CheckResult`: «"no está" y "no se pudo preguntar" piden cosas distintas de
  /// quien lee: la primera se arregla instalando algo, la segunda no se arregla
  /// — se vuelve a intentar». Eso es exactamente esto.
  Future<EstadoDeSesion> sesion(String? configDir) async {
    try {
      final result = await _run(await _donde(), [
        'auth',
        'status',
        '--json',
      ], environment: ClaudeEnvironment.forProfile(configDir));

      if (result.exitCode != 0) {
        _anota(configDir, 'código ${result.exitCode}', result.stderr);
        return EstadoDeSesion.noSeSabe;
      }

      final decoded = jsonDecode((result.stdout as String).trim());
      if (decoded is! Map<String, dynamic>) {
        _anota(configDir, 'contestó algo que no es un objeto', result.stdout);
        return EstadoDeSesion.noSeSabe;
      }
      // Y aquí sí: el CLI contestó, y dijo que no. Eso es un «no» de verdad, y
      // es el único caso en que tiene sentido mandar a iniciar sesión.
      if (decoded['loggedIn'] == true) return EstadoDeSesion.hay;
      _anota(configDir, 'el CLI dice que no hay sesión', decoded['authMethod']);
      return EstadoDeSesion.noHay;
    } on Exception catch (e) {
      _anota(configDir, 'no se pudo preguntar', e);
      return EstadoDeSesion.noSeSabe;
    }
  }

  /// Deja en el registro **qué contestó**, que es lo que no había.
  ///
  /// Sin esto, averiguar por qué la app creía que no había sesión costó seis
  /// rondas de comandos a una persona que solo quería instalarla. Una línea aquí
  /// convierte eso en abrir la app una vez y mirar el log.
  static void _anota(String? configDir, String que, Object? detalle) {
    final cuenta = configDir == null || configDir.isEmpty
        ? 'la de siempre'
        : configDir.split('/').last;
    final cola = detalle == null || '$detalle'.trim().isEmpty
        ? ''
        : ' · ${'$detalle'.trim().split('\n').first}';
    debugPrint('sesión · $cuenta · $que$cola');
  }
}

/// Lo que se sabe de la sesión de una cuenta.
///
/// Tres y no un `bool` por lo mismo que `CheckResult`: **«no hay» se arregla
/// iniciando sesión y «no se sabe» no se arregla** — se vuelve a intentar, o se
/// deja pasar. Tratarlos igual es lo que le dijo a alguien que iniciara una
/// sesión que ya tenía.
enum EstadoDeSesion { hay, noHay, noSeSabe }
