import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';
import 'package:nexus/features/remote/domain/outbox.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:nexus/features/remote/presentation/pages/conversations_page.dart';
import 'package:nexus/features/remote/presentation/pages/utility_pages.dart';
import 'package:nexus/features/remote/presentation/providers/mirror_providers.dart';
import 'package:nexus/features/remote/presentation/providers/outbox_providers.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_drawer.dart';
import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

// El menú y las tres pantallas que hay detrás.
//
// **Nada de `pumpAndSettle` aquí**: espera a que no quede ninguna animación, y el orbe
// anima en bucle mientras la app viva — así que no termina nunca y la prueba muere por
// plazo en vez de por lo que estaba comprobando. Se usa un `pump` de duración fija,
// que es suficiente para que el cajón acabe de entrar.
//
// Lo que se vigila aquí no es el pixel: es **qué se pide al Mac y qué se dice antes de
// tocar**. Las tres pantallas hacen lo mismo —pedir una lista, enseñarla, dejar
// elegir— y en las tres hay algo que hay que decir antes: que retomar una viva lleva a
// la que hay, que un artifact pesa, que una carpeta está ocupada.

const _token = 'MDEyMzQ1Njc4OWFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3';

class _SocketFalso implements ChannelSocket {
  final _entrantes = StreamController<String>();
  final enviados = <Frame>[];
  final respuestas = <String, Map<String, Object?>>{};

  /// Respuestas **en orden** para un metodo que se pide varias veces, que es lo que
  /// hace el archivo al seguir el cursor. Se consumen de la primera a la ultima; cuando
  /// se acaban, manda `respuestas`.
  final porTurno = <String, List<Map<String, Object?>>>{};

  @override
  Stream<String> get entrantes => _entrantes.stream;

  @override
  void enviar(String texto) {
    final marco = Frame.decode(texto);
    enviados.add(marco);
    if (marco is! Call) return;
    Future.microtask(() {
      recibe(Ack(id: marco.id));
      final cola = porTurno[marco.method];
      final datos = (cola != null && cola.isNotEmpty)
          ? cola.removeAt(0)
          : (respuestas[marco.method] ?? const <String, Object?>{});
      recibe(Result(id: marco.id, data: datos));
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

class _ColaVacia implements OutboxStore {
  @override
  Future<List<PendingErrand>> read() async => const [];
  @override
  Future<void> write(List<PendingErrand> encargos) async {}
}

class _SinCache implements MirrorCache {
  @override
  Future<Map<String, Object?>?> read() async => null;
  @override
  Future<void> write(Map<String, Object?> foto) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  late _SocketFalso socket;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> conectado(
    WidgetTester tester, {
    Map<String, Map<String, Object?>> respuestas = const {},
  }) async {
    socket = _SocketFalso()..respuestas.addAll(respuestas);
    final c = ProviderContainer(
      overrides: [
        pairingStoreProvider.overrideWithValue(_Emparejado()),
        socketOpenerProvider.overrideWithValue((_) async => socket),
        outboxStoreProvider.overrideWithValue(_ColaVacia()),
        mirrorCacheProvider.overrideWithValue(_SinCache()),
      ],
    );
    addTearDown(c.dispose);

    await c.read(pairingControllerProvider.future);
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

  group('el menú', () {
    testWidgets('se abre desde el hamburguesa de la lista', (tester) async {
      final c = await conectado(tester);
      await tester.pumpWidget(app(c, const ConversationsPage()));
      await tester.pump();

      expect(find.byType(MobileDrawer), findsNothing);
      await tester.tap(find.byKey(const ValueKey('abrir-el-menu')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(MobileDrawer), findsOne);
    });

    testWidgets('lleva las cuatro entradas, y «olvidar» ya no está en la lista', (
      tester,
    ) async {
      final c = await conectado(tester);
      await tester.pumpWidget(app(c, const ConversationsPage()));
      await tester.pump();

      // Antes «Olvidar» vivía en la esquina de la pantalla principal: la única acción
      // destructiva, a un toque de todo lo demás. Ahora está en el menú y al final.
      expect(find.byKey(const ValueKey('olvidar')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('abrir-el-menu')));
      await tester.pump(const Duration(milliseconds: 400));

      for (final k in [
        'menu-nueva',
        'menu-archivo',
        'menu-artifacts',
        'menu-olvidar',
      ]) {
        expect(find.byKey(ValueKey(k)), findsOne, reason: k);
      }
    });

    testWidgets('no enseña el token, ni en trozos', (tester) async {
      final c = await conectado(tester);
      await tester.pumpWidget(app(c, const ConversationsPage()));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('abrir-el-menu')));
      await tester.pump(const Duration(milliseconds: 400));

      // Lo que identifica al Mac aquí es **dónde está**. El token no se enseña ni
      // recortado: en el escritorio se ve su huella porque hay que copiarlo alguna
      // vez, y aquí no hay ninguna razón para verlo.
      expect(find.text('100.64.0.1:7845'), findsOne);
      expect(find.textContaining(_token.substring(0, 6)), findsNothing);
    });
  });

  group('el archivo', () {
    Map<String, Map<String, Object?>> conArchivo() => {
      'archive': {
        'conversations': [
          {
            'id': 'a1',
            'folder': '/Users/alguien/proyectos/api',
            'title': 'revisa qué cambios tengo sin commitear',
            'turns': 14,
            'open': true,
          },
          {
            'id': 'a2',
            'folder': '/Users/alguien/personal/nexus',
            'title': 'ordena la carpeta',
            'turns': 6,
          },
        ],
      },
    };

    testWidgets('sigue el cursor hasta el final del archivo', (tester) async {
      // El fallo que esto ata: se pedia **una** pagina de 30 y se enseñaba lo que
      // cupiera. En el archivo medido hay 31 —23 de `private`, 7 de `work`, 1 del
      // almacen propio—, asi que ya se perdia una sin decirlo.
      final c = await conectado(tester, respuestas: const {});
      socket.porTurno['archive'] = [
        {
          'conversations': [
            {'id': 'p1', 'folder': '/x/uno', 'title': 'de la primera pagina'},
          ],
          'nextCursor': 30,
        },
        {
          'conversations': [
            {'id': 'p2', 'folder': '/x/dos', 'title': 'de la segunda pagina'},
          ],
        },
      ];

      await tester.pumpWidget(app(c, const ArchivePage()));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('de la primera pagina'), findsOne);
      expect(
        find.text('de la segunda pagina'),
        findsOne,
        reason: 'sin seguir el cursor, el telefono enseña menos que la Mac',
      );
      // Dos peticiones y **no tres**: cuando la respuesta no trae cursor, se para.
      // Si no, un archivo corto pediria diez veces la misma pagina vacia.
      final pedidas = socket.enviados.whereType<Call>().where(
        (c) => c.method == 'archive',
      );
      expect(pedidas.length, 2);
      expect(pedidas.last.params['cursor'], 30);
    });

    testWidgets('dice de que cuenta es cada una', (tester) async {
      // Sin esto la lista es indistinguible: dos cuentas pueden haber trabajado sobre
      // la misma carpeta, y entonces la ruta no separa nada.
      final c = await conectado(
        tester,
        respuestas: const {
          'archive': {
            'conversations': [
              {
                'id': 'a1',
                'folder': '/Users/alguien/personal/nexus',
                'title': 'la de trabajo',
                'turns': 3,
                'account': 'work',
              },
            ],
          },
        },
      );
      await tester.pumpWidget(app(c, const ArchivePage()));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('work'), findsOne);
    });

    testWidgets('lo pide al abrir y enseña cuál está viva', (tester) async {
      final c = await conectado(tester, respuestas: conArchivo());
      await tester.pumpWidget(app(c, const ArchivePage()));
      await tester.pump();
      await tester.pump();

      expect(socket.pidio('archive'), isTrue);
      expect(find.text('revisa qué cambios tengo sin commitear'), findsOne);
      // El chip de «abierta» existe para no ofrecer retomar algo que ya lo está.
      expect(find.text('ABIERTA'), findsOne);
      // Y la cola de la ruta, no la cabeza: en una pantalla estrecha el principio es
      // lo que todas comparten.
      expect(find.textContaining('…/proyectos/api'), findsOne);
    });

    testWidgets('tocar una manda resumeConversation con su id', (tester) async {
      final c = await conectado(
        tester,
        respuestas: {
          ...conArchivo(),
          'resumeConversation': {'conversation': 'viva'},
        },
      );
      await tester.pumpWidget(app(c, const ArchivePage()));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('archivada-a2')));
      await tester.pump();
      await tester.pump();

      expect(socket.ultima('resumeConversation').params['archived'], 'a2');
    });

    testWidgets('sin nada guardado lo dice, y no como un error', (
      tester,
    ) async {
      final c = await conectado(
        tester,
        respuestas: {
          'archive': {'conversations': <Object>[]},
        },
      );
      await tester.pumpWidget(app(c, const ArchivePage()));
      await tester.pump();
      await tester.pump();

      expect(find.text('Todavía no hay nada guardado.'), findsOne);
    });
  });

  group('las carpetas', () {
    testWidgets('dice cuál está ocupada y cuál es de solo lectura', (
      tester,
    ) async {
      final c = await conectado(
        tester,
        respuestas: {
          'folders': {
            'folders': [
              {'path': '/Users/alguien/uno', 'canWrite': true, 'busy': true},
              {'path': '/Users/alguien/dos', 'canWrite': false},
              {'path': '/Users/alguien/tres', 'canWrite': true},
            ],
          },
        },
      );
      await tester.pumpWidget(app(c, const FoldersPage()));
      await tester.pump();
      await tester.pump();

      // Las dos cosas se dicen **antes** de abrir: empezar en una de solo lectura y
      // descubrirlo al primer encargo es trabajo para tirar, y una ocupada no se puede
      // abrir dos veces — el escritorio no lo permite.
      expect(find.text('OCUPADA'), findsOne);
      expect(find.text('SOLO LECTURA'), findsOne);
    });

    testWidgets('la ocupada no se puede tocar; la libre sí', (tester) async {
      final c = await conectado(
        tester,
        respuestas: {
          'folders': {
            'folders': [
              {'path': '/Users/alguien/uno', 'canWrite': true, 'busy': true},
              {'path': '/Users/alguien/tres', 'canWrite': true},
            ],
          },
          'openConversation': {'conversation': 'nueva'},
        },
      );
      await tester.pumpWidget(app(c, const FoldersPage()));
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('carpeta-/Users/alguien/uno')),
      );
      await tester.pump();
      expect(socket.pidio('openConversation'), isFalse);

      await tester.tap(
        find.byKey(const ValueKey('carpeta-/Users/alguien/tres')),
      );
      await tester.pump();
      await tester.pump();
      expect(
        socket.ultima('openConversation').params['folder'],
        '/Users/alguien/tres',
      );
    });
  });

  group('los artifacts', () {
    testWidgets('lo que no es texto lo dice y no se puede tocar', (
      tester,
    ) async {
      // Un `.png` por un canal de texto no da una imagen: da un error de codificacion.
      // Antes se descubria al abrir, y el telefono se quedaba con un fallo generico.
      final c = await conectado(
        tester,
        respuestas: const {
          'artifacts': {
            'artifacts': [
              {'id': '/tmp/mockup.png', 'name': 'mockup.png', 'bytes': 90000},
            ],
          },
        },
      );
      await tester.pumpWidget(app(c, const ArtifactsPage()));
      await tester.pump();
      await tester.pump();

      // Se enseña igual: esconderlo deja preguntandose si falta algo.
      expect(find.text('mockup.png'), findsOne);
      expect(find.text('SOLO EN LA MAC'), findsOne);

      await tester.tap(find.byKey(const ValueKey('artifact-/tmp/mockup.png')));
      await tester.pump();
      expect(
        socket.pidio('artifact'),
        isFalse,
        reason: 'tocarlo solo podia acabar en un fallo, asi que no se toca',
      );
    });

    testWidgets('los botones separan por cuenta', (tester) async {
      final c = await conectado(
        tester,
        respuestas: const {
          'artifacts': {
            'artifacts': [
              {
                'id': '/a/w.html',
                'name': 'de-work.html',
                'bytes': 10,
                'text': true,
                'account': 'work',
              },
              {
                'id': '/a/p.html',
                'name': 'de-private.html',
                'bytes': 10,
                'text': true,
                'account': 'private',
              },
            ],
          },
        },
      );
      await tester.pumpWidget(app(c, const ArtifactsPage()));
      await tester.pump();
      await tester.pump();

      // De partida, todo — y de cada uno se ve de quien es.
      expect(find.text('de-work.html'), findsOne);
      expect(find.text('de-private.html'), findsOne);

      await tester.tap(find.byKey(const ValueKey('cuenta-work')));
      await tester.pump();

      expect(find.text('de-work.html'), findsOne);
      expect(
        find.text('de-private.html'),
        findsNothing,
        reason: 'los botones tienen que filtrar de verdad, no solo pintarse',
      );
    });

    testWidgets('la lista enseña el peso, y el contenido se pide aparte', (
      tester,
    ) async {
      final c = await conectado(
        tester,
        respuestas: {
          'artifacts': {
            'artifacts': [
              {
                'id': '/tmp/informe.md',
                'name': 'informe.md',
                'bytes': 14336,
                // Lo manda el Mac: es quien sabe si eso se puede leer como texto.
                'text': true,
              },
            ],
          },
          'artifact': {'content': '# El informe\n\nTodo bien.'},
        },
      );
      await tester.pumpWidget(app(c, const ArtifactsPage()));
      await tester.pump();
      await tester.pump();

      expect(find.text('informe.md'), findsOne);
      // El peso delante: abrir uno grande con datos móviles es una decisión.
      expect(find.text('14 KB'), findsOne);
      // Y el contenido **no** se pidió con la lista: la lista se pide siempre y el
      // contenido casi nunca.
      expect(socket.pidio('artifact'), isFalse);

      await tester.tap(find.byKey(const ValueKey('artifact-/tmp/informe.md')));
      // Dos tiempos: uno para que la ruta acabe de entrar y otro para que el
      // proveedor resuelva. El contenido **no llega con la lista** —es otra petición—
      // así que un solo pump enseña la pantalla todavía preguntando.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump();

      expect(socket.ultima('artifact').params['artifact'], '/tmp/informe.md');
      expect(find.textContaining('Todo bien.'), findsOne);
    });
  });
}
