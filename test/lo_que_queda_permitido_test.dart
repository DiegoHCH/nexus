import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/features/assistant/domain/usecases/lo_que_queda_permitido.dart';

/// **Qué queda permitido al pulsar «Permitir Bash», y por qué no bastaba con lo
/// que ofrece el CLI.**
///
/// 🔴 Reportado por un compañero, con la pantalla delante: «cada cosa que hace
/// pide permiso, para leer una imagen, para todo». En la captura hay dos
/// preguntas de `Bash` seguidas con su «✔ lo permitiste, y el resto de la
/// sesión» encima, y una tercera pidiendo lo mismo.
///
/// Las sugerencias de aquí abajo están **medidas contra el binario 2.1.258**,
/// pidiéndole dos comandos seguidos: es lo que el CLI ofrece de verdad para un
/// `Bash`, y ninguna de las tres cubre el comando siguiente.
const _loQueOfreceElCli = [
  {
    'type': 'addRules',
    'rules': [
      {'toolName': 'Bash', 'ruleContent': 'touch uno.txt'},
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

PeticionDePermiso _peticion({
  String herramienta = 'Bash',
  String comando = 'touch uno.txt',
}) => PeticionDePermiso(
  id: 'r1',
  herramienta: herramienta,
  nombreVisible: herramienta,
  entrada: {'command': comando},
  sugerencias: _loQueOfreceElCli,
);

void main() {
  // 🔴 **El interruptor de abajo ES el permiso.** Reportado dos veces, la
  // segunda sin rodeos: «es confuso que diga puede editar pero ande pidiendo
  // permisos; si tiene el permiso de puede editar debería dejar lanzar bash sin
  // solicitar permisos». Lo que se mantiene es la línea que este repo ya tenía:
  // lo que sale de la máquina no lo concede una carpeta.
  group('con la carpeta en «puede editar»', () {
    test('lo de casa no pregunta', () {
      for (final herramienta in const ['Bash', 'Write', 'Edit', 'Read']) {
        expect(
          LoQueQuedaPermitido.sinPreguntar(
            puedeEditar: true,
            peticion: _peticion(herramienta: herramienta),
          ),
          isTrue,
          reason: herramienta,
        );
      }
    });

    // Un correo enviado o un mensaje en un canal no se deshacen borrando un
    // archivo, y no es lo que concede «puede editar en esta carpeta».
    test('pero lo que sale de la máquina sí', () {
      expect(
        LoQueQuedaPermitido.sinPreguntar(
          puedeEditar: true,
          peticion: _peticion(
            herramienta: 'mcp__claude_ai_Gmail__send_message',
          ),
        ),
        isFalse,
      );
      expect(
        LoQueQuedaPermitido.esDeFuera(
          _peticion(herramienta: 'mcp__g66__jira_create_issue'),
        ),
        isTrue,
        reason: 'por el prefijo del protocolo, no por una lista que mantener',
      );
    });

    test('y sin poder editar se pregunta todo', () {
      expect(
        LoQueQuedaPermitido.sinPreguntar(
          puedeEditar: false,
          peticion: _peticion(),
        ),
        isFalse,
      );
    });
  });

  group('qué queda permitido', () {
    test('«todo» deja la herramienta permitida', () {
      expect(
        LoQueQuedaPermitido.laHerramientaDe(
          DecisionDePermiso.concedidoTodo,
          _peticion(),
        ),
        'Bash',
      );
    });

    // La diferencia entre los dos botones es exactamente esta: «solo esta vez»
    // no deja nada puesto.
    test('y «solo esta vez» no deja nada', () {
      for (final decision in const [
        DecisionDePermiso.concedido,
        DecisionDePermiso.denegado,
        DecisionDePermiso.cancelado,
      ]) {
        expect(
          LoQueQuedaPermitido.laHerramientaDe(decision, _peticion()),
          isNull,
          reason: '$decision',
        );
      }
    });

    test('sin petición no se apunta nada', () {
      expect(
        LoQueQuedaPermitido.laHerramientaDe(
          DecisionDePermiso.concedidoTodo,
          null,
        ),
        isNull,
      );
    });
  });

  group('la siguiente vez', () {
    // 🔴 **Por herramienta y no por argumentos**, que es todo el punto: la queja
    // era «pide permiso para cada cosa», y contestar solo al comando idéntico la
    // deja igual — es justo lo que hace el `addRules` del CLI, que concede
    // «touch uno.txt» y vuelve a preguntar por «touch dos.txt».
    test('no se pregunta otra vez, aunque el comando sea otro', () {
      const permitidas = {'Bash'};

      expect(
        LoQueQuedaPermitido.yaLoDijiste(
          _peticion(comando: 'touch dos.txt'),
          permitidas,
        ),
        isTrue,
      );
    });

    test('pero otra herramienta sí pregunta', () {
      const permitidas = {'Bash'};

      expect(
        LoQueQuedaPermitido.yaLoDijiste(
          _peticion(herramienta: 'Write'),
          permitidas,
        ),
        isFalse,
      );
    });

    test('y sin nada permitido, se pregunta todo', () {
      expect(LoQueQuedaPermitido.yaLoDijiste(_peticion(), const {}), isFalse);
    });

    // Lo que se le contesta desatasca **esta** llamada y nada más: el modo de la
    // sesión es de quien lo concedió, y tocarlo aquí sería conceder dos cosas
    // con un solo botón.
    test('se contesta con su entrada y sin permisos nuevos', () {
      final respuesta =
          LoQueQuedaPermitido.laRespuesta(_peticion(comando: 'touch dos.txt'))
              as PermisoConcedido;

      expect(respuesta.entrada['command'], 'touch dos.txt');
      expect(respuesta.permisosNuevos, isEmpty);
    });
  });

  // Lo que hacía falta arreglar, dicho como prueba: lo que el CLI ofrece **no**
  // cubre el comando siguiente ni un `Read` de fuera de la carpeta.
  group('por qué no bastaba lo del CLI', () {
    test('su regla es el comando literal, y se escribe en disco', () {
      final regla = _loQueOfreceElCli.first;

      expect(regla['destination'], 'localSettings');
      expect(
        (regla['rules']! as List).first,
        containsPair('ruleContent', 'touch uno.txt'),
        reason: 'el comando entero: el siguiente no lo cubre',
      );
    });

    test('y su modo concede ediciones, no comandos', () {
      final modo = _loQueOfreceElCli.last;

      expect(modo['mode'], 'acceptEdits');
      expect(
        modo['mode'],
        isNot('bypassPermissions'),
        reason: 'nada de lo que ofrece cubre un Bash ni un Read de fuera',
      );
    });
  });
}
