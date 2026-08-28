import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/domain/repositories/correr_una_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/la_prueba_que_se_pide.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// El puerto [CorrerUnaPrueba], atado al lanzador de verdad: el mismo del panel.
///
/// Vive en el cableado y no en el dominio porque necesita el `Ref`, y todo lo
/// que decide de verdad —qué prueba se pidió— está en
/// [LaPruebaQueSePide], que no lo necesita y por eso se puede probar sola.
///
/// **Los textos van en español y a pelo**, como los de [ClaudeErrand]: no se
/// pintan en ninguna pantalla, se le entregan al modelo para que los cuente, y
/// el modelo narra en el idioma en el que le estén hablando.
class CorrerUnaPruebaDesdeLaVoz implements CorrerUnaPrueba {
  const CorrerUnaPruebaDesdeLaVoz(this._ref);

  final Ref _ref;

  @override
  Future<String> loQuePidieron(String pedido) async {
    final carpeta = _ref.read(workspaceControllerProvider).active;
    if (carpeta == null) {
      return 'No hay ninguna carpeta emparejada, así que no sé de qué proyecto '
          'serían las pruebas.';
    }
    final proyecto = carpeta.workingDirectory;

    final pruebas = await _ref.read(pruebasProvider(proyecto).future);
    if (pruebas.isEmpty) {
      return 'No he encontrado ninguna prueba en este proyecto.';
    }

    final cual = LaPruebaQueSePide.cual(pedido, [
      for (final prueba in pruebas) prueba.nombre,
    ]);

    switch (cual) {
      // Se dicen las que hay, y no solo que no está: quien lo pidió acaba de
      // decir un nombre que se parecía al bueno, y oír la lista es lo que le
      // deja acertar a la segunda.
      case NingunaSeParece(:final hay):
        return 'No tengo ninguna prueba que se llame así. Las que hay son: '
            '${_enumerar(hay)}.';

      // Preguntar y no elegir: adivinar aquí no da un error, da una prueba
      // distinta corriendo delante de todos.
      case VariasSeParecen(:final flows):
        return 'Se parecen varias: ${_enumerar(flows)}. ¿Cuál de ellas?';

      case LaPruebaEs(:final flow):
        final donde = _ref.read(elDispositivoProvider);
        if (donde == null) {
          return 'No tengo claro dónde correrla: enciende un dispositivo, o '
              'elige uno en el panel si hay varios.';
        }

        final error = await _ref
            .read(pruebaEnMarchaProvider.notifier)
            .lanzar(
              prueba: pruebas.firstWhere((prueba) => prueba.nombre == flow),
              proyecto: proyecto,
              deviceId: donde,
              perfil: 'local',
            );

        return error == null
            ? 'Lanzada «$flow». Se ve en la pantalla, paso a paso.'
            : 'No he podido lanzar «$flow»: $error';
    }
  }

  /// «a, b y c», que es como se dice una lista en voz alta.
  static String _enumerar(List<String> cosas) {
    if (cosas.length == 1) return cosas.single;
    return '${cosas.sublist(0, cosas.length - 1).join(', ')} y ${cosas.last}';
  }
}

/// Uno para toda la app: no tiene estado y lo que usa son providers.
final correrUnaPruebaProvider = Provider<CorrerUnaPrueba>(
  CorrerUnaPruebaDesdeLaVoz.new,
);
