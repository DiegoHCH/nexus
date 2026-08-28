import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/dispatcher.dart';
import 'package:nexus/features/remote/domain/remote_surface.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

// El despacho: lo que pasa entre que llega una petición y sale la respuesta.
//
// Se prueba **sin socket**, y por eso existe separado del servidor: lo peligroso de
// aquí es el orden —confirmar antes de ejecutar— y el reenvío, y las dos cosas se
// comprueban leyendo la lista de marcos que salen. Con un WebSocket de por medio
// habría que fiarse de los tiempos.

/// Una superficie que **apunta lo que le piden**, en orden.
///
/// La lista compartida con el guion de la prueba es lo que permite comprobar el
/// orden de verdad: no «el ack sale antes que el resultado» —que es fácil— sino
/// «el ack sale antes de que nadie toque la app», que es lo que importa.
class _Falsa implements RemoteSurface {
  _Falsa(this.diario);

  final List<String> diario;

  /// Con qué tope se lanzó el último encargo. `null` si no se lanzó ninguno.
  bool? topeRecibido;
  int? limiteRecibido;
  Object? fallara;

  final _existen = {'a', 'b'};

  void _mirar(String id) {
    if (!_existen.contains(id)) throw UnknownConversation(id);
  }

  @override
  Future<List<RemoteConversation>> conversations() async {
    diario.add('app:conversations');
    if (fallara != null) throw fallara!;
    return const [
      RemoteConversation(id: 'a', folder: '/tmp/uno', focused: true),
      RemoteConversation(id: 'b', folder: '/tmp/dos', focused: false),
    ];
  }

  @override
  Future<RemotePage<RemoteMessage>> history(
    String conversationId, {
    int cursor = 0,
    int limit = 50,
  }) async {
    diario.add('app:history($conversationId,$cursor,$limit)');
    _mirar(conversationId);
    limiteRecibido = limit;
    return const RemotePage(
      items: [RemoteMessage(mine: true, text: 'hola')],
      nextCursor: 7,
    );
  }

  @override
  Future<RemoteMeter> meter(String conversationId) async {
    diario.add('app:meter');
    _mirar(conversationId);
    return const RemoteMeter(
      model: 'opus',
      contextTokens: 500000,
      contextWindow: 1000000,
    );
  }

  @override
  Future<RemotePermission> permission(String conversationId) async {
    diario.add('app:permission');
    _mirar(conversationId);
    return const RemotePermission(folderCanWrite: true, remoteWriteUntil: null);
  }

  @override
  Future<void> sendErrand(
    String conversationId,
    String text, {
    required bool allowWrites,
  }) async {
    diario.add('app:sendErrand($text)');
    _mirar(conversationId);
    topeRecibido = allowWrites;
  }

  @override
  Future<void> stopErrand(String conversationId) async {
    diario.add('app:stopErrand');
    _mirar(conversationId);
  }

  @override
  Future<void> startVoice(String conversationId) async {
    diario.add('app:startVoice');
    _mirar(conversationId);
  }

  @override
  Future<void> stopVoice(String conversationId) async {
    diario.add('app:stopVoice');
    _mirar(conversationId);
  }

  @override
  Future<void> playbackFinished(String conversationId) async {
    diario.add('app:playbackFinished');
  }

  @override
  Future<void> silenceReply(String conversationId) async {
    diario.add('app:silenceReply');
  }

  @override
  Future<void> renameConversation(String conversationId, String name) async {
    diario.add('app:renameConversation:$name');
    _mirar(conversationId);
  }

  @override
  Future<void> closeConversation(String conversationId) async {
    diario.add('app:closeConversation');
    _mirar(conversationId);
  }

  // ── lo que salió de usar el teléfono de verdad ──

  /// Las carpetas que este Mac «tiene emparejadas».
  final carpetas = {'/tmp/uno', '/tmp/dos'};

  /// Los artifacts que existen, por su ruta.
  final documentos = {'/tmp/uno/informe.md': 'el informe entero'};

  @override
  Future<RemotePage<ArchivedConversation>> archive({
    int cursor = 0,
    int limit = 30,
  }) async {
    diario.add('app:archive($cursor,$limit)');
    final todas = [
      for (var i = 0; i < 5; i++)
        ArchivedConversation(
          id: 'arch$i',
          folder: '/tmp/uno',
          title: 'lo que se pidio $i',
          when: DateTime(2026, 8, 20, 10 + i),
          turns: i,
          open: i == 0,
        ),
    ];
    final trozo = todas.skip(cursor).take(limit).toList();
    return RemotePage(
      items: trozo,
      nextCursor: cursor + trozo.length >= todas.length
          ? null
          : cursor + trozo.length,
    );
  }

  @override
  Future<String> resumeConversation(String archivedId) async {
    diario.add('app:resume($archivedId)');
    if (!archivedId.startsWith('arch')) throw UnknownConversation(archivedId);
    // La viva puede no ser la del archivo: si su carpeta ya tenia una abierta, se
    // devuelve esa.
    return 'a';
  }

  @override
  Future<List<RemoteFolder>> folders() async {
    diario.add('app:folders');
    return [
      for (final c in carpetas)
        RemoteFolder(path: c, canWrite: c == '/tmp/uno', busy: c == '/tmp/uno'),
    ];
  }

  @override
  Future<String> openConversation(String folderPath) async {
    diario.add('app:openConversation($folderPath)');
    if (!carpetas.contains(folderPath)) throw UnknownConversation(folderPath);
    return 'nueva';
  }

  @override
  Future<List<RemoteArtifact>> artifacts() async {
    diario.add('app:artifacts');
    return [
      for (final ruta in documentos.keys)
        RemoteArtifact(
          id: ruta,
          name: ruta.split('/').last,
          when: DateTime(2026, 8, 20),
          bytes: documentos[ruta]!.length,
        ),
    ];
  }

  /// Un documento que existe y no cabe por el canal. Lo decide la app, no el
  /// despacho: aquí solo se comprueba cómo se cuenta.
  String? demasiadoGrande;

  @override
  Future<String> artifact(String artifactId) async {
    diario.add('app:artifact($artifactId)');
    if (artifactId == demasiadoGrande) {
      throw ArtifactTooLarge(artifactId, 3 * 1024 * 1024);
    }
    final contenido = documentos[artifactId];
    if (contenido == null) throw UnknownConversation(artifactId);
    return contenido;
  }
}

class _Frases implements WritePhraseStore {
  _Frases([this._guardada]);

  WritePhrase? _guardada;
  int lecturas = 0;

  @override
  Future<WritePhrase?> read() async {
    lecturas++;
    return _guardada;
  }

  @override
  Future<void> write(WritePhrase phrase) async => _guardada = phrase;
  @override
  Future<void> clear() async => _guardada = null;
}

void main() {
  late List<String> diario;
  late _Falsa app;
  late _Frases frases;
  late WriteUnlock permiso;
  late Dispatcher despacho;

  var ahora = DateTime(2026, 8, 20, 10);

  setUp(() {
    diario = [];
    app = _Falsa(diario);
    frases = _Frases();
    permiso = WriteUnlock(reloj: () => ahora);
    despacho = Dispatcher(surface: app, unlock: permiso, phrases: frases);
  });

  /// Atiende y **anota los marcos en el mismo diario que la app**, para poder leer
  /// el orden entre los dos.
  Future<List<Frame>> atender(Call peticion) async {
    final salida = <Frame>[];
    await for (final marco in despacho.attend(peticion)) {
      diario.add('sale:${marco.runtimeType}');
      salida.add(marco);
    }
    return salida;
  }

  Call pedir(
    RemoteMethod metodo, {
    String id = 'm1',
    Map<String, Object?>? con,
  }) => Call(id: id, method: metodo.name, params: con ?? const {});

  group('el orden: confirmar antes de ejecutar', () {
    test('el ack sale antes de que nadie toque la app', () async {
      await atender(pedir(RemoteMethod.conversations));

      // No basta «ack antes que result»: eso también se cumpliría ejecutando
      // primero y confirmando después. Lo que se comprueba es que el ack sale
      // **antes de tocar la app**, que es lo que hace que un encargo de tres
      // minutos se confirme al instante.
      expect(diario, ['sale:Ack', 'app:conversations', 'sale:Result']);
    });

    test('el ack de una petición nueva no dice que sea repetida', () async {
      final salida = await atender(pedir(RemoteMethod.conversations));
      expect((salida.first as Ack).duplicate, isFalse);
    });
  });

  group('el reenvío', () {
    test('se confirma y NO se vuelve a ejecutar', () async {
      final primera = pedir(
        RemoteMethod.sendErrand,
        con: {'conversation': 'a', 'text': 'ordena la carpeta'},
      );
      await atender(primera);
      diario.clear();

      // El mismo `id`: es lo que manda un móvil que reconectó sin haber recibido la
      // confirmación.
      final salida = await atender(primera);

      expect((salida.single as Ack).duplicate, isTrue);
      // **Lo que importa de toda esta pieza**: la app no se toca la segunda vez. Con
      // `acceptEdits` de por medio, ejecutarlo dos veces escribe dos veces.
      expect(diario, ['sale:Ack']);
    });

    test('un id distinto con el mismo texto sí se ejecuta', () async {
      const texto = {'conversation': 'a', 'text': 'lo mismo'};
      await atender(pedir(RemoteMethod.sendErrand, id: 'm1', con: texto));
      await atender(pedir(RemoteMethod.sendErrand, id: 'm2', con: texto));

      // No se deduplica por contenido: repetir a mano el mismo encargo es algo que
      // se hace, y negárselo sería adivinar que se equivocó.
      expect(diario.where((l) => l.startsWith('app:sendErrand')).length, 2);
    });

    test(
      'lo recordado caduca, para que la memoria no crezca sin tope',
      () async {
        var reloj = DateTime(2026, 8, 20, 10);
        final corto = Dispatcher(
          surface: app,
          unlock: permiso,
          phrases: frases,
          dedupe: Deduplicator(
            ttl: const Duration(minutes: 10),
            reloj: () => reloj,
          ),
        );
        final peticion = pedir(RemoteMethod.conversations);
        await corto.attend(peticion).toList();

        reloj = reloj.add(const Duration(minutes: 11));
        final tarde = await corto.attend(peticion).toList();

        // Pasado el plazo se atiende como nueva. Es correcto: un id de hace once
        // minutos ya no es un reenvío de nada.
        expect((tarde.first as Ack).duplicate, isFalse);
        expect(tarde.last, isA<Result>());
      },
    );
  });

  group('lo que no se puede atender', () {
    test(
      'un método que este Mac no conoce: error, y la conexión sigue',
      () async {
        final salida = await atender(Call(id: 'm1', method: 'pedirElOro'));

        expect(salida.last, isA<Failure>());
        expect((salida.last as Failure).code, 'unknownMethod');
        // Y no se toca la app.
        expect(diario.any((l) => l.startsWith('app:')), isFalse);
      },
    );

    test('una conversación que ya no está: se dice cuál', () async {
      final salida = await atender(
        pedir(RemoteMethod.meter, con: {'conversation': 'fantasma'}),
      );

      final fallo = salida.last as Failure;
      expect(fallo.code, 'unknownConversation');
      // El id va en el mensaje: es lo que permite al teléfono saber **qué** tarjeta
      // quitar de la pantalla, en vez de recargar la lista entera.
      expect(fallo.message, contains('fantasma'));
    });

    test('sin el parámetro obligatorio: badParams, no un cuelgue', () async {
      final salida = await atender(pedir(RemoteMethod.meter));
      expect((salida.last as Failure).code, 'badParams');
    });

    test('un encargo vacío no llega a la app', () async {
      final salida = await atender(
        pedir(
          RemoteMethod.sendErrand,
          con: {'conversation': 'a', 'text': '   '},
        ),
      );

      expect((salida.last as Failure).code, 'badParams');
      expect(app.topeRecibido, isNull);
    });

    test('lo inesperado se contesta igual, y además se relanza', () async {
      app.fallara = StateError('se rompió algo por dentro');

      final salida = <Frame>[];
      await expectLater(
        () async {
          await for (final m in despacho.attend(
            pedir(RemoteMethod.conversations),
          )) {
            salida.add(m);
          }
        },
        // Se relanza para que quede en el registro del Mac…
        throwsA(isA<StateError>()),
      );

      // …pero el teléfono **ya recibió su respuesta** antes de eso. Sin ella se
      // quedaría esperando para siempre, que se lee como «el Mac no responde».
      expect(salida.last, isA<Failure>());
      expect((salida.last as Failure).code, 'internal');
      // Y sin contar por dentro qué se rompió.
      expect((salida.last as Failure).message, isNot(contains('se rompió')));
    });
  });

  group('los métodos', () {
    test('las conversaciones, con cuál tiene el foco', () async {
      final salida = await atender(pedir(RemoteMethod.conversations));
      final datos = (salida.last as Result).data;
      final lista = datos['conversations']! as List;

      expect(lista, hasLength(2));
      expect((lista.first as Map)['folder'], '/tmp/uno');
      expect((lista.first as Map)['focused'], isTrue);
    });

    test('el medidor viaja con el porcentaje ya calculado', () async {
      final salida = await atender(
        pedir(RemoteMethod.meter, con: {'conversation': 'a'}),
      );

      // La razón de que viaje resuelto: la mitad de un millón es 50 %, y calcularlo
      // en el teléfono con una ventana asumida de 200k daría 100 %. Ese error ya se
      // cometió una vez en esta app.
      expect((salida.last as Result).data['percent'], 50);
    });

    test('el historial pasa el cursor y devuelve por dónde seguir', () async {
      final salida = await atender(
        pedir(
          RemoteMethod.history,
          con: {'conversation': 'a', 'cursor': 20, 'limit': 10},
        ),
      );

      expect(diario, contains('app:history(a,20,10)'));
      expect((salida.last as Result).data['nextCursor'], 7);
    });

    test('un límite enorme se recorta, no se obedece', () async {
      await atender(
        pedir(
          RemoteMethod.history,
          con: {'conversation': 'a', 'limit': 100000},
        ),
      );

      // El límite lo manda el cliente, así que el tope tiene que estar aquí: la
      // paginación protege al teléfono, esto protege al Mac de que se la pidan.
      expect(app.limiteRecibido, Dispatcher.maxPagina);
    });

    test('un número que llega como texto se entiende', () async {
      await atender(
        pedir(RemoteMethod.history, con: {'conversation': 'a', 'limit': '5'}),
      );

      // Un cliente mal escrito no es un ataque. Lo que no se hace es seguir con
      // basura: eso sí es badParams.
      expect(app.limiteRecibido, 5);
    });

    test('y uno que no es un número es badParams', () async {
      final salida = await atender(
        pedir(
          RemoteMethod.history,
          con: {'conversation': 'a', 'limit': 'muchos'},
        ),
      );
      expect((salida.last as Failure).code, 'badParams');
    });

    test('detener contesta que se detuvo', () async {
      final salida = await atender(
        pedir(RemoteMethod.stopErrand, con: {'conversation': 'a'}),
      );
      expect((salida.last as Result).data['stopped'], isTrue);
      expect(diario, contains('app:stopErrand'));
    });
  });

  group('lo que salió de usar el teléfono', () {
    test('abrir solo vale en una carpeta que el Mac ya tenga', () async {
      // **Esta es la línea que separa esto de emparejar.** El motivo de que emparejar
      // se quede en el escritorio es que por red se elegiría a ciegas cualquier ruta
      // del disco; sin esta comprobación, este método sería exactamente eso.
      final buena = await atender(
        pedir(RemoteMethod.openConversation, con: {'folder': '/tmp/uno'}),
      );
      expect((buena.last as Result).data['conversation'], 'nueva');

      final ajena = await atender(
        pedir(
          RemoteMethod.openConversation,
          id: 'm2',
          con: {'folder': '/Users/otro/secretos'},
        ),
      );
      expect((ajena.last as Failure).code, 'unknownConversation');
    });

    test('un artifact fuera de la lista no se lee', () async {
      // Sin esto, el id seria una ruta libre y el metodo se convertiria en «leer
      // cualquier archivo del Mac» — que es lo que ningun metodo de este canal puede
      // ser.
      final fuera = await atender(
        pedir(RemoteMethod.artifact, con: {'artifact': '/etc/passwd'}),
      );
      expect((fuera.last as Failure).code, 'unknownConversation');
    });

    // Un documento de cientos de megas es un pico de memoria en el Mac y un marco
    // de WebSocket que el teléfono traga entero por 4G. Es el mismo tipo de límite
    // que la paginación ya se puso, y aquí faltaba.
    test('un artifact que no cabe se dice, y se dice cuánto ocupa', () async {
      app.demasiadoGrande = '/x/enorme.md';

      final salida = await atender(
        pedir(RemoteMethod.artifact, con: {'artifact': '/x/enorme.md'}),
      );

      final fallo = salida.last as Failure;
      expect(fallo.code, 'artifactTooLarge');
      // El tamaño en el mensaje: «es muy grande» sin un número deja a quien
      // pregunta sin saber si son dos megas o doscientos.
      expect(fallo.message, contains('3072 KB'));
      // Y la salida que ya existe para los binarios, que es la misma: el Mac.
      expect(fallo.message, contains('se abre en el Mac'));
    });

    test('el archivo pagina y dice cuál ya está abierta', () async {
      final salida = await atender(
        pedir(RemoteMethod.archive, con: {'limit': 2}),
      );
      final datos = (salida.last as Result).data;
      final lista = datos['conversations']! as List;

      expect(lista, hasLength(2));
      // Ofrecer «retomar» algo que ya esta vivo llevaria a abrir una segunda sobre la
      // misma carpeta, que el escritorio no permite.
      expect((lista.first as Map)['open'], isTrue);
      expect(datos['nextCursor'], 2);
    });

    test('retomar devuelve la conversación viva, no la del archivo', () async {
      final salida = await atender(
        pedir(RemoteMethod.resumeConversation, con: {'archived': 'arch3'}),
      );
      expect((salida.last as Result).data['conversation'], 'a');
    });

    test('las carpetas dicen si escriben y si están ocupadas', () async {
      final salida = await atender(pedir(RemoteMethod.folders));
      final lista = (salida.last as Result).data['folders']! as List;

      // Las dos cosas se mandan para poder avisar **antes** de abrir: empezar en una
      // de solo lectura y descubrirlo al primer encargo es trabajo para tirar.
      final uno =
          lista.firstWhere((f) => (f as Map)['path'] == '/tmp/uno') as Map;
      expect(uno['canWrite'], isTrue);
      expect(uno['busy'], isTrue);
    });

    test('sin el parámetro obligatorio: badParams', () async {
      final salida = await atender(pedir(RemoteMethod.openConversation));
      expect((salida.last as Failure).code, 'badParams');
    });
  });

  group('el tope de escritura del encargo', () {
    const encargo = {'conversation': 'a', 'text': 'arregla el test'};

    test('sin frase abierta, el encargo va en solo lectura', () async {
      await atender(pedir(RemoteMethod.sendErrand, con: encargo));
      expect(app.topeRecibido, isFalse);
    });

    test('con la ventana abierta, el encargo puede escribir', () async {
      frases = _Frases(const WritePhrase('ábreme-la-puerta'));
      despacho = Dispatcher(surface: app, unlock: permiso, phrases: frases);

      await atender(
        pedir(
          RemoteMethod.unlockWrites,
          id: 'llave',
          con: {'phrase': 'ábreme-la-puerta'},
        ),
      );
      await atender(pedir(RemoteMethod.sendErrand, con: encargo));

      expect(app.topeRecibido, isTrue);
    });

    test('cuando la ventana caduca, vuelve a solo lectura', () async {
      frases = _Frases(const WritePhrase('ábreme-la-puerta'));
      despacho = Dispatcher(surface: app, unlock: permiso, phrases: frases);
      await atender(
        pedir(
          RemoteMethod.unlockWrites,
          id: 'llave',
          con: {'phrase': 'ábreme-la-puerta'},
        ),
      );

      ahora = ahora.add(WriteGrant.duracion + const Duration(minutes: 1));
      await atender(pedir(RemoteMethod.sendErrand, id: 'tarde', con: encargo));

      // La caducidad tiene que notarse **en el encargo**, no solo al consultar el
      // permiso: si solo se comprobara al abrir la ventana, un móvil que la abrió
      // hace una hora seguiría escribiendo.
      expect(app.topeRecibido, isFalse);
    });
  });

  group('abrir la escritura con la frase', () {
    const buena = 'ábreme-la-puerta';

    setUp(() {
      frases = _Frases(const WritePhrase(buena));
      despacho = Dispatcher(surface: app, unlock: permiso, phrases: frases);
    });

    Future<List<Frame>> intentar(String frase, {String id = 'k'}) => atender(
      pedir(RemoteMethod.unlockWrites, id: id, con: {'phrase': frase}),
    );

    test('la frase buena concede, y dice hasta cuándo', () async {
      final salida = await intentar(buena);
      final datos = (salida.last as Result).data;

      expect(
        DateTime.parse(datos['until']! as String),
        ahora.add(WriteGrant.duracion),
      );
      expect(permiso.puedeEscribir, isTrue);
    });

    test('la frase mala no concede', () async {
      final salida = await intentar('no-es-esta-8');
      expect((salida.last as Failure).code, 'wrongPhrase');
      expect(permiso.puedeEscribir, isFalse);
    });

    test('sin frase definida en el Mac se dice eso, y no «no es esa»', () async {
      frases = _Frases();
      despacho = Dispatcher(surface: app, unlock: permiso, phrases: frases);

      final salida = await intentar('lo-que-sea-8');

      // El código distingue los dos casos porque el teléfono tiene que enseñar
      // cosas distintas: «define una frase en el Mac» no es «te equivocaste».
      expect((salida.last as Failure).code, 'noPhrase');
    });

    test('demasiados intentos cierra la puerta', () async {
      for (var i = 0; i < permiso.intentos; i++) {
        await intentar('mal-$i-aaaa', id: 'k$i');
      }
      final salida = await intentar(buena, id: 'kFinal');

      // Y ni la frase buena entra: si el acierto saltara el límite, el límite no
      // limitaría nada — es justo lo que consigue quien acaba adivinándola.
      expect((salida.last as Failure).code, 'tooManyAttempts');
      expect(permiso.puedeEscribir, isFalse);
    });

    test('la frase se lee de la caja en cada intento, no se cachea', () async {
      await intentar(buena, id: 'k1');
      await intentar(buena, id: 'k2');

      // Si se cacheara, cambiarla en Ajustes no cerraría la puerta hasta reiniciar.
      expect(frases.lecturas, 2);
    });

    test('la frase NUNCA sale en un marco de respuesta', () async {
      const secreta = 'sesamo-abrete-9';
      frases = _Frases(const WritePhrase(secreta));
      despacho = Dispatcher(surface: app, unlock: permiso, phrases: frases);

      final todos = [
        ...await intentar(secreta, id: 'ok'),
        ...await intentar('otra-cosa-9', id: 'mal'),
      ];

      // **Y el caso que de verdad puede filtrarla**: la frase buena rechazada.
      //
      // La primera versión de esta prueba solo mandaba la frase mala, y por eso no
      // pillaba nada — en ese camino lo que se podría interpolar es la equivocada,
      // que no es ningún secreto. Se vio al romper el código a propósito: el
      // mensaje delataba la frase y la prueba seguía en verde. El agujero es el
      // límite de intentos, que rechaza **la buena** y por tanto la tiene en la
      // mano al escribir el error.
      final segundo = WriteUnlock(intentos: 1, reloj: () => ahora);
      final conTope = Dispatcher(
        surface: app,
        unlock: segundo,
        phrases: frases,
      );
      Future<List<Frame>> conElTope(String frase, String id) => conTope
          .attend(
            Call(
              id: id,
              method: RemoteMethod.unlockWrites.name,
              params: {'phrase': frase},
            ),
          )
          .toList();

      await conElTope('gastar-el-cupo', 't1');
      final rechazada = await conElTope(secreta, 't2');
      expect((rechazada.last as Failure).code, 'tooManyAttempts');
      todos.addAll(rechazada);

      // Se comprueba sobre el JSON ya codificado, que es lo que de verdad sale por
      // el cable — no sobre los campos que yo recuerde mirar.
      for (final marco in todos) {
        expect(
          marco.encode(),
          isNot(contains(secreta)),
          reason: '${marco.runtimeType} lleva la frase dentro',
        );
      }
    });
  });
}
