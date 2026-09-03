import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/features/assistant/domain/usecases/las_preguntas_en_pie.dart';
import 'package:nexus/features/assistant/domain/usecases/lo_que_se_contesta_al_permiso.dart';

/// El buzón de permisos, fuera del controlador de 2.159 líneas.
///
/// 🔴 **Las dos formas de romperlo no dejan rastro.** Un `Completer` contestado
/// dos veces lanza; uno que no se contesta nunca deja el turno de `claude -p`
/// esperando para siempre — sin error, sin log, sin nada que mirar: la
/// conversación se queda quieta y parece colgada.
void main() {
  PeticionDePermiso peticion(
    String id, {
    List<Map<String, dynamic>>? sugiere,
  }) => PeticionDePermiso(
    id: id,
    herramienta: 'Write',
    nombreVisible: 'Write',
    entrada: {'file_path': 'notas.md'},
    sugerencias: sugiere ?? const [],
  );

  group('quién espera y cómo se le suelta', () {
    test('contestar resuelve el futuro, una sola vez', () async {
      final buzon = LasPreguntasEnPie();
      final espera = buzon.abrir(peticion('r1'), cancelado: 'nadie contestó');

      expect(buzon.contestar('r1', const PermisoDenegado('no')), isTrue);
      expect(
        buzon.contestar('r1', const PermisoDenegado('otra vez')),
        isFalse,
        reason: 'el segundo complete lanzaría, y quien lo hace es la pantalla',
      );
      expect(await espera, isA<PermisoDenegado>());
      expect(buzon.hayAlguna, isFalse);
    });

    test('contestar una que no existe no revienta ni miente', () {
      expect(
        LasPreguntasEnPie().contestar('de-otra', const PermisoDenegado('no')),
        isFalse,
      );
    });

    // 🔴 La que cuelga el turno. Cerrar la conversación con preguntas en pie
    // tiene que soltarlas: si no, `claude -p` espera una respuesta que ya no
    // puede llegar.
    test('soltar todas contesta a las que quedaban', () async {
      final buzon = LasPreguntasEnPie();
      final una = buzon.abrir(peticion('r1'), cancelado: 'se cerró');
      final otra = buzon.abrir(peticion('r2'), cancelado: 'se cerró');

      buzon.soltarTodas();

      expect((await una as PermisoDenegado).motivo, 'se cerró');
      expect((await otra as PermisoDenegado).motivo, 'se cerró');
      expect(buzon.hayAlguna, isFalse);
    });

    test('soltar dos veces no lanza: una de las llamadas es del onDispose', () {
      final buzon = LasPreguntasEnPie();
      buzon.abrir(peticion('r1'), cancelado: 'se cerró');

      buzon.soltarTodas();

      expect(buzon.soltarTodas, returnsNormally);
    });

    test('soltar después de contestar tampoco', () async {
      final buzon = LasPreguntasEnPie();
      final espera = buzon.abrir(peticion('r1'), cancelado: 'se cerró');
      buzon.contestar('r1', const PermisoDenegado('no'));

      expect(buzon.soltarTodas, returnsNormally);
      expect((await espera as PermisoDenegado).motivo, 'no');
    });

    // El `request_id` lo pone el CLI y no debería repetirse. Si alguna vez lo
    // hace, pisar el completer viejo cuelga ese turno para siempre.
    test('un id repetido suelta al anterior en vez de perderlo', () async {
      final buzon = LasPreguntasEnPie();
      final primera = buzon.abrir(peticion('r1'), cancelado: 'reemplazada');
      buzon.abrir(peticion('r1'), cancelado: 'se cerró');

      expect((await primera as PermisoDenegado).motivo, 'reemplazada');
      expect(buzon.ids, ['r1']);
    });
  });

  group('qué se le devuelve al CLI', () {
    RespuestaDePermiso contestar(
      DecisionDePermiso decision, {
      List<Map<String, dynamic>>? sugiere,
    }) => LoQueSeContestaAlPermiso.de(
      decision,
      peticion('r1', sugiere: sugiere),
      motivoDenegado: 'dijo que no',
      motivoCancelado: 'nadie contestó',
    );

    test('conceder devuelve la entrada, sin permisos nuevos', () {
      final dado = contestar(DecisionDePermiso.concedido) as PermisoConcedido;

      expect(dado.entrada['file_path'], 'notas.md');
      expect(dado.permisosNuevos, isEmpty);
    });

    // 🔴 La diferencia que no falla, solo decepciona: sin las sugerencias,
    // «no me lo vuelvas a preguntar» se convierte en «vale, solo esta vez», y
    // quien lo sufre cree que el botón no hace nada.
    test('conceder todo devuelve las sugerencias que ofreció el CLI', () {
      final dado =
          contestar(
                DecisionDePermiso.concedidoTodo,
                sugiere: const [
                  {'type': 'addRules'},
                ],
              )
              as PermisoConcedido;

      expect(dado.permisosNuevos, [
        {'type': 'addRules'},
      ]);
    });

    test('sin sugerencias, conceder todo no inventa ninguna', () {
      final dado =
          contestar(DecisionDePermiso.concedidoTodo) as PermisoConcedido;

      expect(dado.permisosNuevos, isEmpty);
    });

    // Los dos motivos llegan al modelo **como el resultado de la herramienta**,
    // así que no son texto de log: es sobre lo que Claude decide qué hacer.
    test('denegar y cancelar no dicen lo mismo', () {
      expect(
        (contestar(DecisionDePermiso.denegado) as PermisoDenegado).motivo,
        'dijo que no',
      );
      expect(
        (contestar(DecisionDePermiso.cancelado) as PermisoDenegado).motivo,
        'nadie contestó',
      );
    });

    test('sin petición no se rompe: se contesta con lo que hay', () {
      final dado =
          LoQueSeContestaAlPermiso.de(
                DecisionDePermiso.concedido,
                null,
                motivoDenegado: 'no',
                motivoCancelado: 'nadie',
              )
              as PermisoConcedido;

      expect(dado.entrada, isEmpty);
    });
  });
}
