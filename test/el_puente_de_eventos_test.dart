import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/event_bridge.dart';
import 'package:nexus/features/remote/domain/event_log.dart';
import 'package:nexus/features/remote/domain/remote_surface.dart';
import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

// El puente: de lo que pasa en la app a eventos numerados.
//
// El temporizador se inyecta y **no se duerme**. Agrupar es tiempo, y probarlo con
// temporizadores de verdad significaría 100 ms por prueba y aceptar que alguna falle
// de vez en cuando en una máquina cargada. Aquí las ventanas se cierran a mano, y lo
// que se comprueba es lo que sale por cada una.

void main() {
  late EventLog registro;
  late List<Event> publicados;
  late List<void Function()> ventanas;
  late EventBridge puente;

  setUp(() {
    registro = EventLog();
    publicados = [];
    ventanas = [];
    puente = EventBridge(
      log: registro,
      publicar: publicados.add,
      programar: (_, cerrar) => ventanas.add(cerrar),
    );
  });

  /// Cierra todas las ventanas abiertas.
  void pasarElTiempo() {
    final abiertas = [...ventanas];
    ventanas.clear();
    for (final cerrar in abiertas) {
      cerrar();
    }
  }

  ConversationView vista(
    String id, {
    bool streaming = false,
    String reply = '',
    List<RemoteStep> pasos = const [],
    RemoteMeter medidor = const RemoteMeter(),
    String? error,
    NexusOrbState orbe = NexusOrbState.sleep,
  }) => ConversationView(
    conversationId: id,
    streaming: streaming,
    reply: reply,
    steps: pasos,
    meter: medidor,
    error: error,
    orb: orbe,
  );

  List<Event> deTipo(String kind) =>
      publicados.where((e) => e.kind == kind).toList();

  group('agrupar', () {
    test('cuarenta fragmentos salen como un solo evento', () async {
      // El caso real: `claude -p` escupe la respuesta en trozos pequeños. El
      // escritorio pinta cada uno porque le sale gratis; por red, cuarenta eventos
      // para una frase son cuarenta envíos y la batería lo nota.
      var texto = '';
      for (final trozo in 'la casa está ordenada y el test pasa'.split(' ')) {
        texto += '$trozo ';
        puente.observar(vista('a', streaming: true, reply: texto));
      }

      // Antes de cerrar la ventana no ha salido nada: eso es agrupar.
      expect(publicados, isEmpty);

      pasarElTiempo();

      expect(deTipo('text'), hasLength(1));
      expect(
        deTipo('text').single.data['append'],
        'la casa está ordenada y el test pasa ',
      );
    });

    test('solo se manda lo que falta, no la respuesta entera', () async {
      puente.observar(vista('a', streaming: true, reply: 'hola'));
      pasarElTiempo();
      puente.observar(vista('a', streaming: true, reply: 'hola, qué tal'));
      pasarElTiempo();

      // Ahí está el ahorro: la segunda ventana manda cuatro palabras, no la frase
      // otra vez. Con una respuesta larga, la diferencia es todo.
      expect(deTipo('text').map((e) => e.data['append']), [
        'hola',
        ', qué tal',
      ]);
    });

    test('una ventana por conversación: nadie espera al reloj de otro', () async {
      puente.observar(vista('a', streaming: true, reply: 'uno'));
      puente.observar(vista('b', streaming: true, reply: 'dos'));

      // Dos ventanas abiertas, no una compartida. Con una global, la conversación
      // que cambia justo después de un vaciado se comería la ventana entera.
      expect(puente.ventanasAbiertas, 2);
      pasarElTiempo();

      expect(deTipo('text').map((e) => e.data['conversation']).toSet(), {
        'a',
        'b',
      });
    });

    test('sin cambios no sale ningún evento', () async {
      puente.observar(vista('a', reply: 'igual'));
      pasarElTiempo();
      publicados.clear();

      puente.observar(vista('a', reply: 'igual'));
      pasarElTiempo();

      // Es la consecuencia de restar en vez de acumular: repetir la misma foto no
      // genera tráfico. Con deltas, cada repetición sería un envío.
      expect(publicados, isEmpty);
    });
  });

  group('un turno nuevo no se pega al anterior', () {
    test('si la respuesta no crece, se reemplaza', () async {
      puente.observar(
        vista('a', streaming: true, reply: 'la primera respuesta'),
      );
      pasarElTiempo();
      publicados.clear();

      // Empieza otro turno: el búfer se vació y la respuesta es otra.
      puente.observar(vista('a', streaming: true, reply: 'otra cosa'));
      pasarElTiempo();

      final evento = deTipo('text').single;
      // **Sin esto el teléfono enseñaría «la primera respuestaotra cosa».** No es un
      // caso raro: pasa en cada segundo encargo de la conversación.
      expect(evento.data['replace'], isTrue);
      expect(evento.data['append'], 'otra cosa');
    });

    test('vaciar la respuesta también se cuenta', () async {
      puente.observar(vista('a', reply: 'algo'));
      pasarElTiempo();
      publicados.clear();

      puente.observar(vista('a', reply: ''));
      pasarElTiempo();

      final evento = deTipo('text').single;
      expect(evento.data['replace'], isTrue);
      expect(evento.data['append'], '');
    });
  });

  group('lo demás que viaja', () {
    test('empezar y terminar el turno', () async {
      puente.observar(vista('a', streaming: true));
      pasarElTiempo();
      puente.observar(vista('a'));
      pasarElTiempo();

      expect(deTipo('turn').map((e) => e.data['streaming']), [true, false]);
    });

    test('los pasos van enteros, no en diff', () async {
      puente.observar(
        vista(
          'a',
          pasos: const [
            RemoteStep(
              id: '1',
              description: 'leyendo',
              writes: false,
              done: true,
            ),
            RemoteStep(
              id: '2',
              description: 'escribiendo',
              writes: true,
              done: false,
            ),
          ],
        ),
      );
      pasarElTiempo();

      final pasos = deTipo('activity').single.data['steps']! as List;
      expect(pasos, hasLength(2));
      // `writes` viaja porque es lo que el teléfono pinta distinto: es su única
      // forma de avisar de que algo está tocando archivos.
      expect((pasos.last as Map)['writes'], isTrue);
      expect((pasos.first as Map)['done'], isTrue);
    });

    test('un paso que solo cambia de estado también se manda', () async {
      const antes = RemoteStep(
        id: '1',
        description: 'leyendo',
        writes: false,
        done: false,
      );
      puente.observar(vista('a', pasos: const [antes]));
      pasarElTiempo();
      publicados.clear();

      puente.observar(
        vista(
          'a',
          pasos: const [
            RemoteStep(
              id: '1',
              description: 'leyendo',
              writes: false,
              done: true,
            ),
          ],
        ),
      );
      pasarElTiempo();

      // Misma longitud y mismo id: comparar solo el tamaño de la lista habría dejado
      // el paso girando para siempre en el teléfono.
      expect(deTipo('activity'), hasLength(1));
    });

    test('el medidor viaja con el porcentaje resuelto', () async {
      puente.observar(
        vista(
          'a',
          medidor: const RemoteMeter(
            model: 'opus',
            contextTokens: 250000,
            contextWindow: 1000000,
          ),
        ),
      );
      pasarElTiempo();

      expect(deTipo('meter').single.data['percent'], 25);
    });

    test('el error aparece y también desaparece', () async {
      puente.observar(vista('a', error: 'no se pudo'));
      pasarElTiempo();
      puente.observar(vista('a'));
      pasarElTiempo();

      // La segunda noticia es igual de importante: sin ella el aviso se quedaría en
      // la pantalla del móvil para siempre.
      expect(deTipo('error').map((e) => e.data['message']), [
        'no se pudo',
        null,
      ]);
    });

    test('cerrar una conversación se avisa', () async {
      puente.observar(vista('a', reply: 'hola'));
      pasarElTiempo();
      puente.olvidar('a');

      expect(deTipo('closed').single.data['conversation'], 'a');
    });
  });

  group('la numeración', () {
    test('cada evento lleva su número, y no se repiten', () async {
      puente.observar(vista('a', streaming: true, reply: 'hola', error: 'ups'));
      puente.observar(vista('b', streaming: true, reply: 'adiós'));
      pasarElTiempo();

      final numeros = publicados.map((e) => e.seq).toList();
      expect(numeros, numeros.toSet().toList(), reason: 'sin repetidos');
      expect(numeros, List.generate(numeros.length, (i) => i + 1));
      // Y el registro lo sabe, que es lo que va en la bienvenida.
      expect(registro.lastSeq, numeros.last);
    });

    test('lo emitido queda para poder reenviarlo', () async {
      puente.observar(vista('a', streaming: true, reply: 'hola'));
      pasarElTiempo();

      // Reconectar es «mándame desde el 0», no «mándame todo».
      expect(registro.desde(0), hasLength(publicados.length));
    });
  });

  group('el snapshot', () {
    test('sale de lo mismo que se mandó', () async {
      puente.observar(vista('a', streaming: true, reply: 'hola'));
      puente.observar(vista('b', reply: 'adiós'));
      pasarElTiempo();

      final foto = puente.snapshot();
      final lista = foto.data['conversations']! as List;

      expect(foto.seq, registro.lastSeq);
      expect(lista, hasLength(2));
      expect([
        for (final c in lista) (c as Map)['reply'],
      ], containsAll(['hola', 'adiós']));
    });

    test('una conversación cerrada desaparece de la foto', () async {
      puente.observar(vista('a', reply: 'hola'));
      pasarElTiempo();
      puente.olvidar('a');

      // Sin olvidarla, el snapshot seguiría contando conversaciones muertas mientras
      // la app siga abierta — y el teléfono las pintaría.
      expect(puente.snapshot().data['conversations'], isEmpty);
    });

    test('lo que no ha salido todavía no está en la foto', () async {
      puente.observar(vista('a', reply: 'todavía en la ventana'));

      // El snapshot y los eventos tienen que contar lo mismo. Si la foto incluyera lo
      // que aún no se ha mandado, quien la recibe vería un estado más nuevo que su
      // `seq` — y al llegar el evento lo aplicaría dos veces.
      expect(puente.snapshot().data['conversations'], isEmpty);
    });
  });

  group('cerrar', () {
    test('no se manda nada de una ventana que ya no interesa', () async {
      puente.observar(vista('a', reply: 'a medias'));
      puente.cerrar();
      pasarElTiempo();

      // Apagar el canal con una ventana abierta llamaría a difundir sobre un socket
      // ya cerrado.
      expect(publicados, isEmpty);
      expect(puente.ventanasAbiertas, 0);
    });

    test('observar después de cerrar no abre ventanas', () async {
      puente.cerrar();
      puente.observar(vista('a', reply: 'tarde'));

      expect(puente.ventanasAbiertas, 0);
      expect(ventanas, isEmpty);
    });
  });

  group('el orbe', () {
    test('sale cuando cambia, y solo cuando cambia', () {
      puente.observar(vista('a', orbe: NexusOrbState.sleep));
      pasarElTiempo();
      publicados.clear();

      puente.observar(vista('a', orbe: NexusOrbState.think));
      // El puente agrupa: nada sale hasta que la ventana se cierra.
      pasarElTiempo();
      expect(deTipo('orb').single.data, {
        'conversation': 'a',
        'state': 'think',
      });

      // Otra vez el mismo: nada. El puente manda cambios, no latidos.
      publicados.clear();
      puente.observar(vista('a', orbe: NexusOrbState.think));
      pasarElTiempo();
      expect(deTipo('orb'), isEmpty);
    });

    test('el publicador reenvia el estado del Mac, no uno inventado', () {
      // El hueco que esto tapa: el puente puede mandar el orbe perfectamente y el
      // publicador rellenarlo con una constante. Compila, las dos pruebas de arriba
      // pasan —el puente hace su trabajo— y el telefono dibuja siempre dormido. Se vio
      // sabotenadolo: ninguna prueba se enteraba.
      //
      // Es una comprobacion sobre el codigo porque el publicador escucha providers de
      // la app entera; levantarlos aqui costaria mas que lo que mide.
      final publicador = File(
        'lib/features/remote/presentation/event_publisher.dart',
      ).readAsStringSync();

      expect(
        publicador,
        contains('orb: hud.orbState'),
        reason:
            'el orbe del telefono tiene que SER el del Mac; en cuanto se calcula '
            'aqui otra cosa, son dos orbes que se desincronizan',
      );
    });

    test('va aparte del turno, no dentro', () {
      // `streaming` y el orbe cambian en momentos distintos —el micro se abre sin que
      // haya nada corriendo— y meterlos en el mismo evento haria que uno arrastrara al
      // otro: el telefono no podria distinguir «empezo a trabajar» de «te escucho».
      puente.observar(vista('a'));
      pasarElTiempo();
      publicados.clear();

      puente.observar(vista('a', orbe: NexusOrbState.listen));
      pasarElTiempo();

      expect(deTipo('orb'), hasLength(1));
      expect(
        deTipo('turn'),
        isEmpty,
        reason: 'escuchar no es un turno: nada empezo a correr',
      );
    });
  });
}
