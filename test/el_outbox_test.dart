import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/outbox.dart';
import 'package:nexus/features/remote/domain/remote_mirror.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

// La cola de encargos y la caché.
//
// **Lo que hace útil el teléfono en el metro**, y solo es seguro por una decisión que
// se tomó dos piezas antes: el `clientMsgId` se crea con el encargo y no con el envío.
// Sin el deduplicador del Mac, un outbox es una máquina de escribir dos veces en tus
// archivos — así que casi todo lo de aquí es política: qué se reintenta, qué se tira, y
// cuándo.

void main() {
  var ahora = DateTime(2026, 8, 20, 10);
  Outbox montar({
    int maximo = 20,
    Duration caducidad = const Duration(hours: 2),
    int intentos = 5,
    List<PendingErrand> inicial = const [],
  }) => Outbox(
    maximo: maximo,
    caducidad: caducidad,
    intentosMaximos: intentos,
    reloj: () => ahora,
    inicial: inicial,
  );

  setUp(() => ahora = DateTime(2026, 8, 20, 10));

  group('encolar', () {
    test('guarda el encargo con su id y cuándo se escribió', () {
      final cola = montar();
      final encargo = cola.encolar(
        clientMsgId: 'e1',
        conversationId: 'c1',
        text: 'ordena la carpeta',
      )!;

      expect(encargo.clientMsgId, 'e1');
      expect(encargo.escritoEn, ahora);
      expect(cola.cuantos, 1);
    });

    test('con el tope lleno no se acepta más', () {
      final cola = montar(maximo: 2);
      for (var i = 0; i < 2; i++) {
        cola.encolar(clientMsgId: 'e$i', conversationId: 'c1', text: 'x');
      }

      // El tope es bajo a propósito: una cola larga escrita sin cobertura son veinte
      // encargos lanzados **de golpe** al reconectar, sobre un repo que ninguno vio.
      expect(
        cola.encolar(clientMsgId: 'e9', conversationId: 'c1', text: 'x'),
        isNull,
      );
      expect(cola.cuantos, 2);
    });

    test('sale de uno en uno y en orden', () {
      final cola = montar();
      cola.encolar(clientMsgId: 'e1', conversationId: 'c1', text: 'primero');
      cola.encolar(clientMsgId: 'e2', conversationId: 'c1', text: 'segundo');

      // Dos encargos de la misma conversación en paralelo se pisan el contexto —es
      // por lo que el escritorio los pone en cola— y en orden inverso harían lo
      // contrario de lo que se pidió.
      expect(cola.siguiente!.text, 'primero');
      cola.confirmar('e1');
      expect(cola.siguiente!.text, 'segundo');
    });
  });

  group('qué se reintenta y qué se tira', () {
    test('un fallo reintentable se queda, contando el intento', () {
      final cola = montar();
      cola.encolar(clientMsgId: 'e1', conversationId: 'c1', text: 'x');

      expect(cola.falloReintentable('e1'), isNull);
      expect(cola.cuantos, 1);
      expect(cola.siguiente!.intentos, 1);
      // Y sigue llevando el mismo id, que es lo único que separa reintentar de
      // ejecutar dos veces.
      expect(cola.siguiente!.clientMsgId, 'e1');
    });

    test('agotados los intentos, se tira', () {
      final cola = montar(intentos: 3);
      cola.encolar(clientMsgId: 'e1', conversationId: 'c1', text: 'x');

      expect(cola.falloReintentable('e1'), isNull);
      expect(cola.falloReintentable('e1'), isNull);
      // El intento se apunta **antes** de decidir: contándolo después, un fallo
      // permanente daría vueltas para siempre.
      expect(cola.falloReintentable('e1'), DiscardReason.demasiadosIntentos);
      expect(cola.vacio, isTrue);
    });

    test('un rechazo del Mac se tira a la primera', () {
      final cola = montar();
      cola.encolar(clientMsgId: 'e1', conversationId: 'c1', text: 'x');

      // «Esa conversación ya no está» no se arregla insistiendo, y reintentarlo es un
      // bucle contra un Mac que ya dijo que no.
      expect(cola.falloDefinitivo('e1'), DiscardReason.rechazado);
      expect(cola.vacio, isTrue);
    });
  });

  group('la caducidad', () {
    test('lo viejo se tira, y se puede decir qué', () {
      final cola = montar(caducidad: const Duration(hours: 2));
      cola.encolar(
        clientMsgId: 'viejo',
        conversationId: 'c1',
        text: 'de antes',
      );
      ahora = ahora.add(const Duration(hours: 3));
      cola.encolar(
        clientMsgId: 'nuevo',
        conversationId: 'c1',
        text: 'de ahora',
      );

      final fuera = cola.caducar();

      // Un encargo habla del repo tal como estaba al escribirlo: «sigue con lo de
      // antes» tres horas después se ejecuta sobre otra cosa.
      expect(fuera.map((e) => e.clientMsgId), ['viejo']);
      expect(cola.pendientes.map((e) => e.clientMsgId), ['nuevo']);
    });

    test('se cuenta desde que se escribió, no desde el último intento', () {
      final cola = montar(caducidad: const Duration(hours: 2), intentos: 99);
      cola.encolar(clientMsgId: 'e1', conversationId: 'c1', text: 'x');

      // Reintentando cada media hora durante tres.
      for (var i = 0; i < 6; i++) {
        ahora = ahora.add(const Duration(minutes: 30));
        cola.falloReintentable('e1');
      }

      // Al revés —contando desde el último intento— uno que reintenta cada minuto
      // **nunca caducaría**, que es justo el que más falta le hace.
      expect(cola.caducar(), hasLength(1));
      expect(cola.vacio, isTrue);
    });
  });

  group('sobrevivir a cerrar la app', () {
    test('la cola va y vuelve de JSON con el id intacto', () {
      final cola = montar();
      cola.encolar(
        clientMsgId: 'e1',
        conversationId: 'c1',
        text: 'con tildes ñ',
      );
      cola.falloReintentable('e1');

      final devuelta = montar(inicial: Outbox.leer(cola.toJson()));

      // **El id tiene que sobrevivir al viaje**, o al reintentar después de reabrir
      // la app el Mac no lo reconocería como reenvío y el encargo correría dos veces.
      final e = devuelta.siguiente!;
      expect(e.clientMsgId, 'e1');
      expect(e.text, 'con tildes ñ');
      expect(e.intentos, 1);
      expect(e.escritoEn, cola.pendientes.single.escritoEn);
    });

    test('una cola vacía va y vuelve vacía', () {
      expect(Outbox.leer(montar().toJson()), isEmpty);
    });
  });

  group('la caché del espejo', () {
    test('va y vuelve: lo que se guarda es lo que se lee', () {
      // **Aquí es donde una caché se rompe en silencio**: se guarda con unas claves y
      // se lee con otras, y el resultado es una pantalla en blanco al abrir sin red
      // — que se le echa a la red.
      final espejo = const RemoteMirror()
          .aplicar(
            const Event(
              seq: 1,
              kind: 'text',
              data: {'conversation': 'a', 'append': 'ya está'},
            ),
          )
          .aplicar(
            const Event(
              seq: 2,
              kind: 'meter',
              data: {
                'conversation': 'a',
                'model': 'opus',
                'contextTokens': 250000,
                'percent': 25,
              },
            ),
          )
          .aplicar(
            const Event(
              seq: 3,
              kind: 'activity',
              data: {
                'conversation': 'a',
                'steps': [
                  {'id': '1', 'text': 'escribiendo', 'writes': true},
                ],
              },
            ),
          )
          .conLista([
            {'id': 'a', 'folder': '/tmp/repo', 'focused': true},
          ]);

      final guardado = {
        'conversations': [for (final c in espejo.visibles) c.toJson()],
      };
      final devuelto = RemoteMirror.desdeSnapshot(
        Snapshot(seq: 0, data: guardado),
      );

      final antes = espejo.conversations['a']!;
      final despues = devuelto.conversations['a']!;
      expect(despues.reply, antes.reply);
      expect(despues.folder, antes.folder);
      expect(despues.percent, antes.percent);
      expect(despues.model, antes.model);
      expect(despues.steps.single.text, antes.steps.single.text);
      expect(despues.steps.single.writes, isTrue);
    });

    test('lo que no se sabe no se inventa al volver', () {
      final espejo = const RemoteMirror().aplicar(
        const Event(
          seq: 1,
          kind: 'turn',
          data: {'conversation': 'a', 'streaming': true},
        ),
      );
      final devuelto = RemoteMirror.desdeSnapshot(
        Snapshot(
          seq: 0,
          data: {
            'conversations': [for (final c in espejo.visibles) c.toJson()],
          },
        ),
      );

      // Sin carpeta y sin medidor: la caché no puede rellenar lo que nunca llegó, y
      // un porcentaje inventado es peor que ninguno.
      expect(devuelto.conversations['a']!.folder, isNull);
      expect(devuelto.conversations['a']!.percent, isNull);
      expect(devuelto.conversations['a']!.streaming, isTrue);
    });
  });
}
