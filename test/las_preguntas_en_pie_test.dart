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

  _loQueSeDevuelveYLoQueNo();

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
    test('conceder todo devuelve las sugerencias de sesión del CLI', () {
      final dado =
          contestar(
                DecisionDePermiso.concedidoTodo,
                sugiere: const [
                  {
                    'type': 'setMode',
                    'mode': 'acceptEdits',
                    'destination': 'session',
                  },
                ],
              )
              as PermisoConcedido;

      expect(dado.permisosNuevos, [
        {'type': 'setMode', 'mode': 'acceptEdits', 'destination': 'session'},
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

/// Lo que «Permitir todo» devuelve al CLI, y lo que **no**.
///
/// 🔴 **Medido contra el binario el 6 de septiembre.** Al conceder un `Bash`, el
/// CLI ofrece tres salidas y una de ellas escribe en tu repositorio. Este es el
/// payload tal cual llegó, con `mkdir -p uno` como comando:
///
/// ```json
/// [{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"mkdir -p uno"}],
///   "behavior":"allow","destination":"localSettings"},
///  {"type":"addDirectories","directories":["…/repo"],"destination":"session"},
///  {"type":"setMode","mode":"acceptEdits","destination":"session"}]
/// ```
///
/// Devolviéndolo entero —que es lo que se hacía— aparece
/// `<repo>/.claude/settings.local.json` con `Bash(mkdir -p uno)` dentro. Y no
/// sirve para lo que se quería: con **solo** esa regla devuelta, el siguiente
/// comando —`mkdir -p dos`— volvió a preguntar. Lo que de verdad corta la
/// sangría es `setMode`, que es de sesión.
void _loQueSeDevuelveYLoQueNo() {
  /// El payload medido, literal.
  const medido = [
    {
      'type': 'addRules',
      'rules': [
        {'toolName': 'Bash', 'ruleContent': 'mkdir -p uno'},
      ],
      'behavior': 'allow',
      'destination': 'localSettings',
    },
    {
      'type': 'addDirectories',
      'directories': ['/tmp/repo'],
      'destination': 'session',
    },
    {'type': 'setMode', 'mode': 'acceptEdits', 'destination': 'session'},
  ];

  group('permitir todo, con el payload de verdad', () {
    PermisoConcedido concedeTodo() =>
        LoQueSeContestaAlPermiso.de(
              DecisionDePermiso.concedidoTodo,
              const PeticionDePermiso(
                id: 'r1',
                herramienta: 'Bash',
                nombreVisible: 'Bash',
                entrada: {'command': 'mkdir -p uno'},
                sugerencias: medido,
              ),
              motivoDenegado: 'no',
              motivoCancelado: 'se paró',
            )
            as PermisoConcedido;

    test('lo de sesión pasa: es lo que el botón promete', () {
      final tipos = [
        for (final una in concedeTodo().permisosNuevos) una['type'],
      ];

      expect(tipos, ['addDirectories', 'setMode']);
    });

    // 🔴 **Y lo que escribe en tu repositorio se queda fuera.** El botón dice «y
    // el resto de la sesión», no «y para siempre en este repositorio, en un
    // archivo que no abriste» — y en un repo del trabajo ese archivo se comparte.
    test('la regla que se escribe en disco no se devuelve', () {
      expect(
        concedeTodo().permisosNuevos.any((una) => una['type'] == 'addRules'),
        isFalse,
      );
      expect(LoQueSeContestaAlPermiso.loQueSeDescarta(medido), [
        'addRules → localSettings',
      ], reason: 'lo que se deja fuera se puede leer, no se adivina');
    });

    // El filtro es **el destino y no una lista de tipos**: así una salida nueva
    // del CLI que dure la sesión pasa sola, y una que escriba en disco no entra
    // por olvidarse de añadirla a una lista.
    test('un tipo nuevo de sesión pasa sin tocar nada', () {
      const inventado = {
        'type': 'algoQueNoExisteAun',
        'destination': 'session',
      };

      expect(LoQueSeContestaAlPermiso.loQueDuraLaSesion(inventado), isTrue);
      expect(
        LoQueSeContestaAlPermiso.loQueDuraLaSesion(const {
          'type': 'otro',
          'destination': 'userSettings',
        }),
        isFalse,
      );
    });
  });
}
