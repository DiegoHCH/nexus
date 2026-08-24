import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:nexus/features/remote/presentation/pages/conversation_page.dart';
import 'package:nexus/features/remote/presentation/pages/conversations_page.dart';
import 'package:nexus/features/remote/presentation/providers/mirror_providers.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/domain/outbox.dart';
import 'package:nexus/features/remote/presentation/providers/outbox_providers.dart';
import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_chrome.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';

// Las pantallas del teléfono, contra un socket falso.
//
// **Con el enlace de verdad y sin red**: el socket va detrás de una interfaz desde la
// pieza 2, así que aquí se ejercita el camino completo —marco que llega, espejo que se
// actualiza, pantalla que se redibuja— sin fingir ninguna capa intermedia. Un doble
// del espejo probaría mi idea de cómo llega la información, no cómo llega.

const _token = 'MDEyMzQ1Njc4OWFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3';

/// Un Mac falso que **siempre contesta**.
///
/// Contestar por defecto no es comodidad: cada petición arma dos plazos —el del `ack`
/// y el de la respuesta— y el arnés de widgets falla si al terminar la prueba queda
/// un temporizador vivo. Un socket que se calla deja los dos colgando en cada
/// prueba, y el fallo sale como «Pending timers» apuntando al enlace, que es el sitio
/// equivocado para buscar.
///
/// Así que el silencio hay que **pedirlo** —[sinContestar]—, que además es lo honesto:
/// un Mac que no contesta es un caso especial, no el normal.
class _SocketFalso implements ChannelSocket {
  final _entrantes = StreamController<String>();
  final enviados = <Frame>[];

  /// Qué devolver por método. Lo que no esté aquí se contesta vacío.
  final respuestas = <String, Map<String, Object?>>{};

  /// Métodos a los que **no** se contesta, para las pruebas que lo necesitan.
  final sinContestar = <String>{};

  @override
  Stream<String> get entrantes => _entrantes.stream;

  @override
  void enviar(String texto) {
    final marco = Frame.decode(texto);
    enviados.add(marco);
    if (marco is! Call || sinContestar.contains(marco.method)) return;
    // En un microtask: contestar dentro de `enviar` sería reentrar en el enlace
    // mientras todavía está registrando la petición.
    Future.microtask(() {
      recibe(Ack(id: marco.id));
      recibe(Result(id: marco.id, data: respuestas[marco.method] ?? const {}));
    });
  }

  @override
  Future<void> close() async {
    if (!_entrantes.isClosed) await _entrantes.close();
  }

  void recibe(Frame marco) {
    if (!_entrantes.isClosed) _entrantes.add(marco.encode());
  }

  bool pidio(String metodo) =>
      enviados.whereType<Call>().any((c) => c.method == metodo);

  Call ultima(String metodo) =>
      enviados.whereType<Call>().lastWhere((c) => c.method == metodo);
}

/// La cola en memoria: aquí no se prueba que se guarde —eso es su propia prueba—
/// sino que la pantalla pasa por ella.
class _ColaEnMemoria implements OutboxStore {
  List<PendingErrand> guardados = const [];

  @override
  Future<List<PendingErrand>> read() async => guardados;
  @override
  Future<void> write(List<PendingErrand> encargos) async =>
      guardados = encargos;
}

class _SinCache implements MirrorCache {
  @override
  Future<Map<String, Object?>?> read() async => null;
  @override
  Future<void> write(Map<String, Object?> foto) async {}
  @override
  Future<void> clear() async {}
}

class _Emparejado implements PairingStore {
  @override
  Future<Pairing?> read() async => Pairing(
    url: Uri.parse('ws://100.64.0.1:7845'),
    token: const ChannelToken(_token),
  );
  @override
  Future<void> write(Pairing pairing) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  late _SocketFalso socket;
  late _ColaEnMemoria cola;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> conectado(
    WidgetTester tester, {
    Map<String, Map<String, Object?>> respuestas = const {},
    Set<String> sinContestar = const {},
  }) async {
    socket = _SocketFalso()
      ..respuestas.addAll(respuestas)
      ..sinContestar.addAll(sinContestar);
    cola = _ColaEnMemoria();
    final c = ProviderContainer(
      overrides: [
        pairingStoreProvider.overrideWithValue(_Emparejado()),
        socketOpenerProvider.overrideWithValue((_) async => socket),
        outboxStoreProvider.overrideWithValue(cola),
        mirrorCacheProvider.overrideWithValue(_SinCache()),
        // Ids fijos: la prueba de que **el mismo id sobrevive al reintento** no se
        // puede escribir contra un generador que cambia solo.
        clientMsgIdProvider.overrideWithValue(() => 'enc-1'),
      ],
    );
    addTearDown(c.dispose);

    await c.read(pairingControllerProvider.future);
    // El espejo tiene que estar escuchando **antes** de conectar, o se pierden los
    // primeros eventos.
    c.read(mirrorProvider);
    unawaited(c.read(channelLinkProvider).conectar());
    await tester.pump(Duration.zero);
    socket.recibe(const Welcome(protocol: ProtocolRange.mine, seq: 0));
    await tester.pump(Duration.zero);
    return c;
  }

  Widget app(ProviderContainer c, Widget pantalla) => UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: NexusTheme.dark(), home: pantalla),
  );

  group('la lista', () {
    testWidgets('al conectar pide la lista sola', (tester) async {
      final c = await conectado(tester);
      await tester.pumpWidget(app(c, const ConversationsPage()));
      await tester.pump();

      // La carpeta de cada conversación sale de la lista, no del snapshot: sin
      // pedirla, las tarjetas se llamarían por su identificador.
      expect(socket.pidio('conversations'), isTrue);
    });

    testWidgets('sin nada abierto no se dibuja un error', (tester) async {
      final c = await conectado(
        tester,
        respuestas: {
          'conversations': {'conversations': <Object>[]},
        },
      );
      await tester.pumpWidget(app(c, const ConversationsPage()));
      await tester.pump();
      await tester.pump();

      // Un Mac sin conversaciones abiertas es lo normal a diario, no un fallo.
      expect(find.text('Nada abierto en el Mac'), findsOneWidget);
    });

    testWidgets('enseña la cola de la ruta, no la cabeza', (tester) async {
      final c = await conectado(
        tester,
        respuestas: {
          'conversations': {
            'conversations': [
              {
                'id': 'a',
                'folder': '/Users/alguien/proyectos/api',
                'focused': true,
              },
            ],
          },
        },
      );
      await tester.pumpWidget(app(c, const ConversationsPage()));
      await tester.pump();
      await tester.pump();

      // En una pantalla estrecha, el principio de una ruta absoluta es lo que todas
      // tienen en común.
      expect(find.text('…/proyectos/api'), findsOneWidget);
    });

    testWidgets('un evento aparece en la tarjeta sin pedir nada', (
      tester,
    ) async {
      final c = await conectado(
        tester,
        respuestas: {
          'conversations': {
            'conversations': [
              {'id': 'a', 'folder': '/tmp/repo'},
            ],
          },
        },
      );
      await tester.pumpWidget(app(c, const ConversationsPage()));
      await tester.pump();
      await tester.pump();

      socket.recibe(
        const Event(
          seq: 1,
          kind: 'turn',
          data: {'conversation': 'a', 'streaming': true},
        ),
      );
      socket.recibe(
        const Event(
          seq: 2,
          kind: 'activity',
          data: {
            'conversation': 'a',
            'steps': [
              {'id': '1', 'text': 'leyendo el repo'},
            ],
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      // **Esto es lo que la fase entera venía a conseguir**: la pantalla se mueve
      // sola, sin que el teléfono pregunte.
      expect(find.text('leyendo el repo'), findsOneWidget);
    });
  });

  group('la conversación', () {
    Future<ProviderContainer> conUna(
      WidgetTester tester, {
      Map<String, Map<String, Object?>> respuestas = const {},
    }) async {
      final c = await conectado(tester, respuestas: respuestas);
      await tester.pumpWidget(
        app(c, const ConversationPage(conversationId: 'a')),
      );
      socket.recibe(
        const Snapshot(
          seq: 5,
          data: {
            'conversations': [
              {
                'id': 'a',
                'folder': '/tmp/repo',
                'reply': 'ya está ordenado',
                'meter': {
                  'contextTokens': 250000,
                  'contextWindow': 1000000,
                  'percent': 25,
                },
              },
            ],
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      return c;
    }

    testWidgets('vacía, el orbe es el contenido; con turnos, se aparta', (
      tester,
    ) async {
      // Vacía no hay nada que tapar y lo unico que hay que decir es «aqui esta el
      // asistente, esperando». Con texto en pantalla, un orbe grande detras de los
      // parrafos se lee como suciedad sobre el texto.
      final c = await conectado(tester);
      await tester.pumpWidget(
        app(c, const ConversationPage(conversationId: 'a')),
      );
      socket.recibe(
        const Snapshot(
          seq: 5,
          data: {
            'conversations': [
              {'id': 'a', 'folder': '/tmp/repo'},
            ],
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      final vacia = tester.getSize(find.byType(NexusOrb));
      expect(
        vacia.height,
        greaterThan(300),
        reason: 'vacia, el orbe es el contenido',
      );

      // Llega un turno: el orbe se aparta a la banda de arriba.
      socket.recibe(
        const Event(
          seq: 6,
          kind: 'text',
          data: {'conversation': 'a', 'append': 'ya está ordenado'},
        ),
      );
      await tester.pump();
      await tester.pump();

      final conTexto = tester.getSize(find.byType(NexusOrb));
      expect(
        conTexto.height,
        lessThan(vacia.height),
        reason: 'con algo que leer, el orbe no puede estar detras del texto',
      );
    });

    testWidgets('la respuesta no se pinta dos veces', (tester) async {
      // Lo que se veia en el telefono: el mismo texto como respuesta en curso y otra
      // vez como turno del historial, con dos estilos distintos — se lee como si el
      // asistente hubiera contestado dos veces.
      //
      // La regla vive en el espejo y esta probada alli; esto comprueba que **la
      // pantalla la usa**, que es lo que faltaba: quitarla del `if` pasaba todo.
      final c = await conectado(tester);
      await tester.pumpWidget(
        app(c, const ConversationPage(conversationId: 'a')),
      );
      socket.recibe(
        const Snapshot(
          seq: 5,
          data: {
            'conversations': [
              {
                'id': 'a',
                'folder': '/tmp/repo',
                'reply': 'ya está ordenado',
                'history': [
                  {'mine': true, 'text': 'ordena la casa'},
                  {'mine': false, 'text': 'ya está ordenado'},
                ],
              },
            ],
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('ya está ordenado'), findsOne);
    });

    Future<ProviderContainer> conUnaSinContestar(
      WidgetTester tester,
      Set<String> callados,
    ) async {
      final c = await conectado(tester, sinContestar: callados);
      await tester.pumpWidget(
        app(c, const ConversationPage(conversationId: 'a')),
      );
      socket.recibe(
        const Snapshot(
          seq: 5,
          data: {
            'conversations': [
              {'id': 'a', 'folder': '/tmp/repo', 'reply': 'ya está ordenado'},
            ],
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      return c;
    }

    testWidgets('enseña la respuesta y el medidor que mandó el Mac', (
      tester,
    ) async {
      await conUna(tester);

      expect(find.text('ya está ordenado'), findsOneWidget);
      // 25 y no un número recalculado aquí: la ventana depende de la variante del
      // modelo, y calcularlo en el teléfono es repetir el error del escritorio.
      expect(find.text('25 %'), findsOneWidget);
    });

    testWidgets('el permiso se pregunta al abrir', (tester) async {
      await conUna(tester);
      expect(socket.pidio('permission'), isTrue);
      expect(socket.ultima('permission').params['conversation'], 'a');
    });

    testWidgets('nace en solo lectura, y lo dice', (tester) async {
      await conUna(
        tester,
        respuestas: {
          'permission': {'folderCanWrite': true},
        },
      );
      await tester.pump();
      await tester.pump();

      // Sin frase abierta no se puede escribir, y **se dice antes de teclear el
      // encargo**: enterarse después de redactarlo es hacer trabajo para tirarlo.
      // Se comprueba el estado del interruptor y no un texto: ahora se ven los dos
      // lados a la vez —«Solo leer» y «Puede editar» están siempre en pantalla— asi
      // que buscar una de las dos etiquetas no distingue en cual esta.
      expect(
        tester
            .widget<PermissionToggle>(find.byKey(const ValueKey('permiso')))
            .puedeEditar,
        isFalse,
      );
    });

    testWidgets('la carpeta en solo lectura gana, aunque la frase esté abierta', (
      tester,
    ) async {
      // **El caso donde el AND importa**, y la prueba de arriba no lo alcanzaba:
      // allí no llegaba fecha, así que con AND o sin él salía solo lectura. Aquí
      // la ventana está abierta y la carpeta no concede — y romper el AND haría
      // que la pantalla prometiera una edición que el encargo no va a poder hacer.
      //
      // Se vio al romper el código a propósito y ver la prueba seguir en verde.
      final c = await conUna(
        tester,
        respuestas: {
          'permission': {
            'folderCanWrite': false,
            'remoteWriteUntil': '2099-01-01T00:00:00.000',
          },
        },
      );
      await tester.pump();
      await tester.pump();

      expect(c.read(writePermissionProvider).value, isNull);
      // Se comprueba el estado del interruptor y no un texto: ahora se ven los dos
      // lados a la vez —«Solo leer» y «Puede editar» están siempre en pantalla— asi
      // que buscar una de las dos etiquetas no distingue en cual esta.
      expect(
        tester
            .widget<PermissionToggle>(find.byKey(const ValueKey('permiso')))
            .puedeEditar,
        isFalse,
      );
    });

    testWidgets('mandar un encargo llega como sendErrand', (tester) async {
      final c = await conUna(tester);
      // La cola tiene que estar construida antes de mandar.
      await c.read(outboxProvider.future);
      await tester.enterText(
        find.byKey(const ValueKey('encargo')),
        'ordena la carpeta',
      );
      await tester.tap(find.byKey(const ValueKey('mandar')));
      await tester.pump();
      await tester.pump();

      // Va por la cola **también con cobertura**, y sale al instante: si el camino
      // con red fuera otro, habría dos formas de mandar y solo una llevaría el
      // `clientMsgId` guardado.
      expect(socket.ultima('sendErrand').params['text'], 'ordena la carpeta');
      expect(socket.ultima('sendErrand').params['conversation'], 'a');
      expect(socket.ultima('sendErrand').id, 'enc-1');
    });

    testWidgets('mientras trabaja, el botón es detener y no mandar', (
      tester,
    ) async {
      await conUna(tester);
      socket.recibe(
        const Event(
          seq: 6,
          kind: 'turn',
          data: {'conversation': 'a', 'streaming': true},
        ),
      );
      await tester.pump();
      await tester.pump();

      // Mandar otro encima es lo que en el escritorio pone el segundo encargo en
      // cola, y en un teléfono eso se hace sin darse cuenta.
      expect(find.byKey(const ValueKey('detener')), findsOneWidget);
      expect(find.byKey(const ValueKey('mandar')), findsNothing);
    });

    testWidgets('un rechazo del Mac saca el encargo de la cola', (
      tester,
    ) async {
      // Antes de la cola, esta prueba miraba el aviso en pantalla. Ahora lo que
      // importa es otra cosa: un rechazo que **no se arregla insistiendo** tiene que
      // salir de la cola, o el teléfono lo reintenta en bucle contra un Mac que ya
      // dijo que no.
      final c = await conUnaSinContestar(tester, {'sendErrand'});
      await c.read(outboxProvider.future);
      await tester.enterText(find.byKey(const ValueKey('encargo')), 'algo');
      await tester.tap(find.byKey(const ValueKey('mandar')));
      await tester.pump();
      await tester.pump();

      final peticion = socket.ultima('sendErrand');
      socket.recibe(Ack(id: peticion.id));
      socket.recibe(
        Failure(id: peticion.id, code: 'unknownConversation', message: 'ya no'),
      );
      await tester.pump();
      await tester.pump();

      expect(c.read(outboxProvider).value, isEmpty);
    });

    testWidgets('lo que espera salir se ve en la pantalla', (tester) async {
      // Un encargo escrito sin cobertura que no se ve por ninguna parte se da por
      // perdido y se vuelve a escribir.
      final c = await conUnaSinContestar(tester, {'sendErrand'});
      await c.read(outboxProvider.future);
      await tester.enterText(
        find.byKey(const ValueKey('encargo')),
        'esto está esperando',
      );
      await tester.tap(find.byKey(const ValueKey('mandar')));
      await tester.pump();
      await tester.pump();

      // Se deja pasar el plazo del `ack`, que es lo que ocurre de verdad cuando el
      // Mac no contesta: el enlace lo da por «pudo no llegar» y el encargo **se queda
      // en la cola**. Además cierra los dos temporizadores, que si no el arnés se
      // queja con razón.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      expect(find.byKey(const ValueKey('esperando')), findsOneWidget);
      expect(find.text('esto está esperando'), findsOneWidget);
    });

    testWidgets('si el Mac la cierra, se dice en vez de dejar la pantalla', (
      tester,
    ) async {
      final c = await conUna(tester);
      // El 6 y no el 7: el snapshot dejó la cuenta en 5, y saltarse uno hace que el
      // enlace lo descarte y pida resync — que es exactamente lo que debe hacer.
      // Esta prueba se equivocaba, no el enlace.
      socket.recibe(
        const Event(seq: 6, kind: 'closed', data: {'conversation': 'a'}),
      );
      await tester.pump();
      await tester.pump();

      expect(
        // El molde de estados lo dice en dos partes —titulo y cuerpo— en vez de en
        // una linea gris centrada, asi que se busca el titulo.
        find.text('Esta conversación ya no está abierta'),
        findsOneWidget,
      );
      expect(c.read(mirrorProvider).vacio, isTrue);
    });
  });

  group('la frase de escritura', () {
    testWidgets('cada código dice algo distinto que hacer', (tester) async {
      final c = await conectado(tester, sinContestar: {'unlockWrites'});
      final permiso = c.read(writePermissionProvider.notifier);

      // Los tres del contrato, y los tres llevan a acciones distintas: ir al Mac,
      // teclear otra vez, o esperar. Un solo mensaje para los tres no sirve.
      for (final (codigo, _) in [
        ('noPhrase', 'ir al Mac'),
        ('wrongPhrase', 'teclear otra vez'),
        ('tooManyAttempts', 'esperar'),
      ]) {
        final futuro = permiso.abrir('lo-que-sea');
        await tester.pump(Duration.zero);
        final peticion = socket.ultima('unlockWrites');
        socket.recibe(Ack(id: peticion.id));
        socket.recibe(Failure(id: peticion.id, code: codigo, message: 'no'));
        expect(await futuro, codigo);
      }
    });

    testWidgets('la frase buena abre la ventana', (tester) async {
      final c = await conectado(tester, sinContestar: {'unlockWrites'});
      final permiso = c.read(writePermissionProvider.notifier);
      final hasta = DateTime(2026, 8, 20, 18, 30);

      final futuro = permiso.abrir('ábreme-la-puerta');
      await tester.pump(Duration.zero);
      final peticion = socket.ultima('unlockWrites');
      socket.recibe(Ack(id: peticion.id));
      socket.recibe(
        Result(id: peticion.id, data: {'until': hasta.toIso8601String()}),
      );

      expect(await futuro, isNull);
      expect(c.read(writePermissionProvider).value, hasta);
    });

    testWidgets('la frase no se manda en ningún otro sitio', (tester) async {
      const secreta = 'sesamo-abrete-9';
      final c = await conectado(tester, sinContestar: {'unlockWrites'});
      final futuro = c.read(writePermissionProvider.notifier).abrir(secreta);
      await tester.pump(Duration.zero);
      final peticion = socket.ultima('unlockWrites');
      socket.recibe(Ack(id: peticion.id));
      socket.recibe(Result(id: peticion.id, data: const {'until': null}));
      await futuro;

      // Solo en `unlockWrites`. Que el teléfono no la guarde es la mitad; la otra
      // es que no viaje pegada a nada más.
      final conLaFrase = socket.enviados
          .where((f) => f.encode().contains(secreta))
          .toList();
      expect(conLaFrase, hasLength(1));
      expect((conLaFrase.single as Call).method, 'unlockWrites');
    });
  });
}
