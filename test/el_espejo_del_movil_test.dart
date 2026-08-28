import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/event_bridge.dart';
import 'package:nexus/features/remote/domain/event_log.dart';
import 'package:nexus/features/remote/domain/remote_mirror.dart';
import 'package:nexus/features/remote/domain/remote_surface.dart';
import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/presentation/providers/mirror_providers.dart';

// El espejo del teléfono: aplicar eventos para reconstruir lo que pasa en el Mac.
//
// **La prueba que importa es de ida y vuelta**, no clave por clave. El puente resta
// estados para producir eventos y el espejo aplica eventos para reconstruir estados:
// son dos lados del mismo acuerdo, y el fallo real no es «me equivoqué en una
// condición» sino «el puente manda `append` y el espejo lee `text`». Un juego de
// pruebas que comprueba cada lado con las claves que yo recuerde pasa en verde
// mientras los dos extremos hablan idiomas distintos.
//
// Así que se monta el puente de verdad, se le dan estados, y sus eventos —los de
// verdad, no unos escritos a mano— se aplican al espejo.

void main() {
  late EventLog registro;
  late List<Event> emitidos;
  late List<void Function()> ventanas;
  late EventBridge puente;

  setUp(() {
    registro = EventLog();
    emitidos = [];
    ventanas = [];
    puente = EventBridge(
      log: registro,
      publicar: emitidos.add,
      programar: (_, cerrar) => ventanas.add(cerrar),
    );
  });

  void pasarElTiempo() {
    final abiertas = [...ventanas];
    ventanas.clear();
    for (final cerrar in abiertas) {
      cerrar();
    }
  }

  /// Aplica al espejo todo lo que el puente haya emitido.
  RemoteMirror reflejar(RemoteMirror espejo) {
    var salida = espejo;
    for (final evento in emitidos) {
      salida = salida.aplicar(evento);
    }
    emitidos.clear();
    return salida;
  }

  ConversationView vista(
    String id, {
    bool streaming = false,
    String reply = '',
    String pregunta = '',
    bool vozAbierta = false,
    List<RemoteStep> pasos = const [],
    RemoteMeter medidor = const RemoteMeter(),
    String? error,
    String? aviso,
    NexusOrbState orbe = NexusOrbState.sleep,
    String titulo = 'un encargo',
  }) => ConversationView(
    conversationId: id,
    streaming: streaming,
    reply: reply,
    ask: pregunta,
    voice: vozAbierta,
    steps: pasos,
    meter: medidor,
    error: error,
    notice: aviso,
    orb: orbe,
    title: titulo,
  );

  group('ida y vuelta: lo que el puente manda, el espejo lo entiende', () {
    test('una respuesta que crece llega entera', () {
      var espejo = const RemoteMirror();

      // Como en la vida real: el texto llega a trozos y en ventanas distintas.
      for (final trozo in ['la casa ', 'está ', 'ordenada']) {
        puente.observar(vista('a', streaming: true, reply: _acumulado(trozo)));
        pasarElTiempo();
        espejo = reflejar(espejo);
      }

      expect(espejo.conversations['a']!.reply, 'la casa está ordenada');
    });

    test('un turno nuevo no se pega al anterior', () {
      var espejo = const RemoteMirror();
      puente.observar(vista('a', streaming: true, reply: 'la primera'));
      pasarElTiempo();
      espejo = reflejar(espejo);

      // Otro turno: el puente manda `replace`, y si el espejo lo ignorara se vería
      // «la primeraotra cosa» — que es el fallo concreto que esta pareja de piezas
      // existe para evitar.
      puente.observar(vista('a', streaming: true, reply: 'otra cosa'));
      pasarElTiempo();
      espejo = reflejar(espejo);

      expect(espejo.conversations['a']!.reply, 'otra cosa');
    });

    test('el turno, los pasos y el medidor cuadran', () {
      var espejo = const RemoteMirror();
      puente.observar(
        vista(
          'a',
          streaming: true,
          pasos: const [
            RemoteStep(
              id: '1',
              description: 'escribiendo el test',
              writes: true,
              done: false,
            ),
          ],
          medidor: const RemoteMeter(
            model: 'opus',
            contextTokens: 250000,
            contextWindow: 1000000,
          ),
        ),
      );
      pasarElTiempo();
      espejo = reflejar(espejo);

      final conv = espejo.conversations['a']!;
      expect(conv.streaming, isTrue);
      expect(conv.steps.single.text, 'escribiendo el test');
      expect(conv.steps.single.writes, isTrue);
      expect(conv.model, 'opus');
      // El porcentaje llega **calculado** y el espejo no lo recalcula: si lo hiciera
      // con una ventana asumida, repetiría el error que ya se cometió en el
      // escritorio —un millón enseñado al 88 % porque se supuso 200k—.
      expect(conv.percent, 25);
    });

    test('un error aparece y desaparece', () {
      var espejo = const RemoteMirror();
      puente.observar(vista('a', error: 'no se pudo'));
      pasarElTiempo();
      espejo = reflejar(espejo);
      expect(espejo.conversations['a']!.error, 'no se pudo');

      puente.observar(vista('a'));
      pasarElTiempo();
      espejo = reflejar(espejo);

      // Sin esto el aviso se queda en la pantalla del móvil para siempre. Y no es
      // gratis de expresar: un `null` en un `copyWith` no se distingue de «no lo
      // pases», así que borrar tiene que decirse aparte.
      expect(espejo.conversations['a']!.error, isNull);
    });

    // De punta a punta: el Mac lo pone en el estado, el puente lo emite, el
    // espejo lo recoge. Sin esto, el teléfono lanza encargos sin poder enterarse
    // de que las reglas del repositorio cambiaron bajo sus pies.
    test('un aviso llega al teléfono, y también se retira', () {
      var espejo = const RemoteMirror();
      puente.observar(vista('a', aviso: 'han cambiado las reglas'));
      pasarElTiempo();
      espejo = reflejar(espejo);
      expect(espejo.conversations['a']!.notice, 'han cambiado las reglas');

      puente.observar(vista('a'));
      pasarElTiempo();
      espejo = reflejar(espejo);

      expect(espejo.conversations['a']!.notice, isNull);
    });

    // Los dos a la vez, que es lo que pasa cuando un encargo falla justo el día
    // que cambiaron las reglas: son dos casillas y ninguna pisa a la otra.
    test('el aviso no pisa al error ni al revés', () {
      var espejo = const RemoteMirror();
      puente.observar(vista('a', error: 'no se pudo', aviso: 'y además esto'));
      pasarElTiempo();
      espejo = reflejar(espejo);

      expect(espejo.conversations['a']!.error, 'no se pudo');
      expect(espejo.conversations['a']!.notice, 'y además esto');
    });

    test('cerrar una conversación la quita del mapa y del orden', () {
      var espejo = const RemoteMirror();
      puente.observar(vista('a', reply: 'hola'));
      puente.observar(vista('b', reply: 'adiós'));
      pasarElTiempo();
      espejo = reflejar(espejo);
      expect(espejo.visibles, hasLength(2));

      puente.olvidar('a');
      espejo = reflejar(espejo);

      // De los dos sitios: dejarla en el orden pintaría un hueco, y dejarla en el
      // mapa la resucitaría al siguiente evento.
      expect(espejo.conversations.containsKey('a'), isFalse);
      expect(espejo.order, ['b']);
      expect(espejo.visibles.single.id, 'b');
    });

    test('tres conversaciones a la vez no se mezclan', () {
      // El tope de la app son tres, y trabajan en paralelo: es el caso normal, no un
      // extremo.
      var espejo = const RemoteMirror();
      puente.observar(vista('a', streaming: true, reply: 'uno'));
      puente.observar(vista('b', streaming: true, reply: 'dos'));
      puente.observar(vista('c', reply: 'tres'));
      pasarElTiempo();
      espejo = reflejar(espejo);

      expect(espejo.conversations['a']!.reply, 'uno');
      expect(espejo.conversations['b']!.reply, 'dos');
      expect(espejo.conversations['c']!.reply, 'tres');
      expect(espejo.conversations['c']!.streaming, isFalse);
    });
  });

  group('el snapshot', () {
    test('reemplaza y no mezcla', () {
      var espejo = const RemoteMirror();
      puente.observar(vista('vieja', reply: 'de antes'));
      pasarElTiempo();
      espejo = reflejar(espejo);

      puente.observar(vista('nueva', reply: 'de ahora'));
      pasarElTiempo();
      emitidos.clear();
      espejo = RemoteMirror.desdeSnapshot(puente.snapshot());

      // Un snapshot llega justo cuando lo que había puede estar mal, así que
      // fundirlo conservaría precisamente lo que se venía a tirar. Aquí las dos
      // existen en el Mac, así que las dos están — lo que se comprueba es que el
      // espejo sale **del snapshot** y no de sumarle lo anterior.
      expect(espejo.conversations.keys.toSet(), {'vieja', 'nueva'});
      expect(espejo.conversations['nueva']!.reply, 'de ahora');
    });

    test('lo que el puente pone en la foto, el espejo lo lee', () {
      puente.observar(
        vista(
          'a',
          streaming: true,
          reply: 'a medias',
          pasos: const [
            RemoteStep(
              id: '1',
              description: 'leyendo',
              writes: false,
              done: true,
            ),
          ],
          medidor: const RemoteMeter(
            model: 'opus',
            contextTokens: 100000,
            contextWindow: 200000,
          ),
          error: 'algo pasó',
        ),
      );
      pasarElTiempo();

      final espejo = RemoteMirror.desdeSnapshot(puente.snapshot());
      final conv = espejo.conversations['a']!;

      expect(conv.reply, 'a medias');
      expect(conv.streaming, isTrue);
      expect(conv.steps.single.done, isTrue);
      expect(conv.percent, 50);
      expect(conv.error, 'algo pasó');
    });
  });

  group('la lista de conversaciones', () {
    test('trae la carpeta sin borrar lo que se está escribiendo', () {
      var espejo = const RemoteMirror();
      puente.observar(vista('a', streaming: true, reply: 'a medio escribir'));
      pasarElTiempo();
      espejo = reflejar(espejo);

      espejo = espejo.conLista([
        {'id': 'a', 'folder': '/tmp/repo', 'focused': true},
      ]);

      // La lista dice **quién existe y su carpeta**, no lo que se está escribiendo.
      // Reemplazar borraría la respuesta a medias por haber refrescado la lista, y
      // refrescar es justo lo que hace el teléfono al volver a primer plano.
      expect(espejo.conversations['a']!.reply, 'a medio escribir');
      expect(espejo.conversations['a']!.folder, '/tmp/repo');
      expect(espejo.conversations['a']!.focused, isTrue);
    });

    test('la lista es la autoridad sobre quién existe', () {
      var espejo = const RemoteMirror();
      puente.observar(vista('a', reply: 'uno'));
      puente.observar(vista('fantasma', reply: 'ya no existe'));
      pasarElTiempo();
      espejo = reflejar(espejo);

      espejo = espejo.conLista([
        {'id': 'a', 'folder': '/tmp/repo'},
      ]);

      // Una conversación que el Mac ya cerró mientras el teléfono estaba sin red no
      // llega como evento `closed`: se nota al pedir la lista.
      expect(espejo.conversations.keys, ['a']);
    });

    test('el nombre cae a la ruta, y al id mientras no se sepa', () {
      var espejo = const RemoteMirror().aplicar(
        const Event(
          seq: 1,
          kind: 'turn',
          data: {'conversation': 'c1', 'streaming': true},
        ),
      );
      // Una conversación puede aparecer por un evento **antes** de saber su carpeta:
      // se abre en el Mac mientras el teléfono mira otra cosa. Enseñar el id es feo;
      // enseñar una tarjeta en blanco es peor.
      expect(espejo.conversations['c1']!.nombre, 'c1');

      espejo = espejo.conLista([
        {'id': 'c1', 'folder': '/tmp/repo'},
      ]);
      expect(espejo.conversations['c1']!.nombre, '/tmp/repo');
    });
  });

  group('tolerancia hacia adelante', () {
    test('un evento de una clase que no se conoce se ignora', () {
      final espejo = const RemoteMirror().aplicar(
        const Event(seq: 1, kind: 'algoDelFuturo', data: {'conversation': 'a'}),
      );

      // Es lo que permite que el Mac se actualice y añada eventos sin romper este
      // teléfono. Si esto lanzara, cada evento nuevo del servidor sería un cambio de
      // versión — y entonces nadie añadiría eventos.
      //
      // **Y no crea la conversación**, que era lo que esperaba esta prueba en su
      // primera versión: de un evento que no se entiende no se puede sacar nada que
      // enseñar, y crear la tarjeta pintaría una en blanco. Ignorar es ignorar.
      expect(espejo.vacio, isTrue);
    });

    test('un evento sin conversación no rompe nada', () {
      final espejo = const RemoteMirror().aplicar(
        const Event(seq: 1, kind: 'text', data: {'append': 'huérfano'}),
      );
      expect(espejo.vacio, isTrue);
    });
  });
  group('el nombre y la respuesta', () {
    test('el nombre llega por evento, no solo con la lista', () {
      // El fallo que esto ata: una conversacion abierta **desde el telefono** nace de
      // un evento, y los eventos no llevaban carpeta ni nombre. Lo que se veia en la
      // barra de titulo era su identificador — `1787575393339519-88753…`.
      final espejo = const RemoteMirror().aplicar(
        const Event(
          seq: 1,
          kind: 'title',
          data: {'conversation': 'a', 'title': 'de que trata el proyecto'},
        ),
      );

      expect(espejo.conversations['a']!.nombre, 'de que trata el proyecto');
    });

    test('el titulo manda sobre la carpeta', () {
      // Reconocer una conversacion por lo que le pediste funciona mejor que por donde
      // vive: dos conversaciones sobre el mismo repo se llaman igual.
      final espejo = const RemoteMirror()
          .conLista([
            {'id': 'a', 'folder': '/Users/alguien/proyectos/api'},
          ])
          .aplicar(
            const Event(
              seq: 1,
              kind: 'title',
              data: {'conversation': 'a', 'title': 'arregla el login'},
            ),
          );

      expect(espejo.conversations['a']!.nombre, 'arregla el login');
    });

    test('la respuesta en curso se reconoce cuando ya esta en el historial', () {
      // Se veia dos veces: como respuesta en curso y otra vez como turno del
      // historial, con dos estilos distintos — se lee como si hubiera contestado dos
      // veces.
      final conv = MirroredConversation(
        id: 'a',
        reply: 'la casa esta ordenada ',
        history: const [
          MirroredMessage(mine: true, text: 'ordena la casa'),
          MirroredMessage(mine: false, text: 'la casa esta ordenada'),
        ],
      );

      // Con el espacio del streaming al final: un espacio no es otra respuesta.
      expect(conv.respuestaYaEnHistorial, isTrue);

      final otra = conv.copyWith(reply: 'y el test pasa');
      expect(
        otra.respuestaYaEnHistorial,
        isFalse,
        reason: 'si es otra respuesta hay que verla, o desaparece del todo',
      );
    });
  });

  group('el léxico del orbe', () {
    test('el estado llega del Mac y el espejo lo guarda', () {
      // No se deduce de `streaming`: el micro abierto no es trabajo corriendo, y la voz
      // saliendo tampoco. De los cuatro estados, el telefono solo podia inferir dos.
      final espejo = const RemoteMirror().aplicar(
        const Event(
          seq: 1,
          kind: 'orb',
          data: {'conversation': 'a', 'state': 'listen'},
        ),
      );

      expect(espejo.conversations['a']!.orb, NexusOrbState.listen);
    });

    test('un estado que esta version no conoce deja el que habia', () {
      // Un movil viejo frente a un Mac nuevo tiene que seguir dibujando algo.
      final espejo = const RemoteMirror()
          .aplicar(
            const Event(
              seq: 1,
              kind: 'orb',
              data: {'conversation': 'a', 'state': 'think'},
            ),
          )
          .aplicar(
            const Event(
              seq: 2,
              kind: 'orb',
              data: {'conversation': 'a', 'state': 'bailando'},
            ),
          );

      expect(espejo.conversations['a']!.orb, NexusOrbState.think);
    });

    test('sin enlace no gira, diga lo que diga lo ultimo que llego', () {
      // **La pieza entera.** El espejo se queda con lo ultimo que supo, asi que si el
      // Mac estaba trabajando cuando se perdio la cobertura, el telefono seguiria
      // girando su orbe sobre una pantalla que dice «se perdio el enlace». Un orbe
      // girando promete trabajo que esta pasando, y aqui no esta pasando nada: el Mac
      // puede haber terminado, haber fallado o estar dormido.
      for (final estado in [
        LinkState.sinConexion,
        LinkState.reconectando,
        LinkState.noSeLlega,
        LinkState.rechazado,
      ]) {
        expect(
          orbeParaElMovil(enlace: estado, delMac: NexusOrbState.think),
          NexusOrbState.sleep,
          reason: 'con el enlace en $estado el orbe no puede prometer trabajo',
        );
      }
    });

    test('conectado, se respeta lo que dijo el Mac', () {
      for (final delMac in NexusOrbState.values) {
        expect(
          orbeParaElMovil(enlace: LinkState.conectado, delMac: delMac),
          delMac,
          reason: 'conectado, el orbe del telefono ES el del Mac',
        );
      }
    });
  });

  test('la pregunta se pinta una vez, no dos', () {
    // Llega por evento en cuanto se transcribe, y **tambien** aterriza en el historial
    // cuando se pide una pagina. Sin la comprobacion se veria dos veces seguidas, que
    // es el mismo fallo que ya tuvo la respuesta.
    const conv = MirroredConversation(id: 'a', ask: 'que reuniones tengo hoy');
    expect(conv.preguntaYaEnHistorial, isFalse);

    final conHistorial = conv.copyWith(
      history: const [
        MirroredMessage(mine: true, text: 'que reuniones tengo hoy'),
      ],
    );
    expect(conHistorial.preguntaYaEnHistorial, isTrue);

    // Y una pregunta distinta en el historial no la tapa.
    final otra = conv.copyWith(
      history: const [MirroredMessage(mine: true, text: 'otra cosa')],
    );
    expect(otra.preguntaYaEnHistorial, isFalse);
  });
}

String _texto = '';

/// Acumula el texto entre llamadas, como lo haría la app: el puente necesita la
/// respuesta **entera** para poder restar.
String _acumulado(String trozo) {
  _texto += trozo;
  return _texto;
}
