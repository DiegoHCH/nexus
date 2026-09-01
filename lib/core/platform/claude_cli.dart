import 'dart:convert';
import 'dart:io';

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
  Future<bool> loggedIn(String? configDir) async {
    try {
      final result = await _run(await _donde(), [
        'auth',
        'status',
        '--json',
      ], environment: ClaudeEnvironment.forProfile(configDir));
      if (result.exitCode != 0) return false;
      final decoded = jsonDecode((result.stdout as String).trim());
      return decoded is Map<String, dynamic> && decoded['loggedIn'] == true;
    } on Exception {
      // Sin CLI alcanzable no se puede afirmar que no haya sesión, pero tampoco
      // leer el cupo. Se trata como «no hay sesión» porque es el único caso en
      // que el usuario tiene algo que hacer —iniciarla—, y equivocarse aquí
      // solo cuesta una frase, no un dato falso.
      return false;
    }
  }
}
