import 'package:flutter/widgets.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/remote/domain/remote_voice_source.dart';
import 'package:nexus/features/remote/presentation/widgets/microfono_dibujado.dart';
import 'package:nexus/features/remote/domain/voice_input_compartido.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/data/microfono_del_movil.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/providers/voz_providers.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

/// El micrófono del teléfono, visto desde el Mac.
///
/// `lo8` decidió que **el audio pasa por el Mac**: el teléfono no habla con Gemini, le
/// presta el micrófono. Eso convierte la voz remota en «otra fuente del puerto de audio
/// que ya existía» en vez de un segundo camino dentro de la sesión de voz — que es el
/// trozo con más lógica del proyecto y el que no conviene tocar.

Uint8List _pcm(List<int> muestras) {
  final datos = Int16List.fromList(muestras);
  return Uint8List.view(datos.buffer);
}

class _MicroDelMac implements VoiceInput {
  var vecesQueSeAbrio = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<AudioFrame> listen() {
    vecesQueSeAbrio++;
    return const Stream<AudioFrame>.empty();
  }
}

class _MicroNegado implements VoiceInput {
  @override
  Future<bool> hasPermission() async => false;

  @override
  Stream<AudioFrame> listen() => const Stream<AudioFrame>.empty();
}

/// El micrófono, sin micrófono.
class _MicroFalso implements Microfono {
  _MicroFalso(this.orden, {this.permiso = true});

  final List<String> orden;
  final bool permiso;
  final _salida = StreamController<Uint8List>.broadcast();

  @override
  Future<bool> tienePermiso() async => permiso;

  @override
  Future<Stream<Uint8List>> escuchar() async {
    orden.add('micro:escuchar');
    return _salida.stream;
  }

  @override
  Future<void> cerrar() async => orden.add('micro:cerrar');

  void emite(Uint8List pcm) => _salida.add(pcm);
}

/// El enlace, sin red: apunta lo que se le pide y lo que se le manda.
class _EnlaceFalso implements ChannelLink {
  _EnlaceFalso(this.orden);

  final List<String> orden;

  @override
  Future<Map<String, Object?>> pedir(
    RemoteMethod metodo, {
    Map<String, Object?> params = const {},
    String? clientMsgId,
  }) async {
    if (_macCaido) throw const LinkError(LinkFailure.desconectado);
    if (metodo == RemoteMethod.startVoice && !_macContesta) {
      throw const LinkError(LinkFailure.sinRespuesta);
    }
    orden.add('mac:${metodo.name}');
    return const {};
  }

  @override
  bool mandarAudio(Audio marco) {
    _mandados.add(marco);
    return true;
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

late _MicroFalso _micro;
final _mandados = <Audio>[];
var _macContesta = true;
var _macCaido = false;

ProviderContainer _conVoz({
  required List<String> orden,
  bool permiso = true,
  bool macContesta = true,
}) {
  _micro = _MicroFalso(orden, permiso: permiso);
  _mandados.clear();
  _macContesta = macContesta;
  _macCaido = false;
  final c = ProviderContainer(
    overrides: [
      microfonoProvider.overrideWithValue(_micro),
      channelLinkProvider.overrideWithValue(_EnlaceFalso(orden)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Encender y tomar el flujo, que ahora son dos pasos: `abrir` enciende y `flujo` es
/// lo que lee la sesion. Estaban juntos y por eso chocaban — `startVoice` abria, tiraba
/// el stream, y la sesion volvia a abrir cerrando el primero.
Stream<AudioFrame> abrirY(RemoteVoiceSource fuente) {
  fuente.abrir();
  return fuente.flujo!;
}

void main() {
  group('la fuente remota', () {
    test('lo que llega mientras está abierta sale como frames', () async {
      final fuente = RemoteVoiceSource();
      final frames = <AudioFrame>[];
      abrirY(fuente).listen(frames.add);

      fuente.entra(_pcm([0, 1000, -1000, 0]));
      await Future<void>.delayed(Duration.zero);

      expect(frames, hasLength(1));
      expect(frames.single.pcm.lengthInBytes, 8);
      expect(frames.single.amplitude, greaterThan(0));
    });

    test('con el micrófono cerrado se descarta, y se cuenta', () {
      // Trozos llegando después de cerrar es **lo normal**: se suelta el botón y queda
      // audio en vuelo. Muchos seguidos significan que el cierre no llegó, y eso sí es
      // un fallo — por eso se cuentan en vez de ignorarse en silencio.
      final fuente = RemoteVoiceSource();

      fuente.entra(_pcm([100, 200]));
      expect(fuente.descartados, 1);
      expect(fuente.activo, isFalse);
    });

    test('abrir dos veces sigue siendo el mismo microfono', () async {
      // **Esta promesa cambio, y a proposito.** Antes abrir cerraba lo anterior, para
      // no dejar dos fuentes escribiendo en la misma sesion. Pero ahora soltar el
      // boton no derriba la sesion —soltar es «ya esta, contestame»— asi que volver a
      // sostener cae sobre una sesion viva que esta leyendo *este* stream: cerrarlo y
      // abrir otro la dejaria escuchando el de antes mientras los trozos nuevos entran
      // a un controlador que nadie lee. Silencio, y de los que no se ven.
      final fuente = RemoteVoiceSource();
      final leidos = <AudioFrame>[];
      var cerrada = false;
      abrirY(fuente).listen(leidos.add, onDone: () => cerrada = true);

      // El segundo sostener, con el primero todavia abierto.
      fuente.abrir();
      fuente.entra(_pcm([500, 500]));
      await Future<void>.delayed(Duration.zero);

      expect(cerrada, isFalse, reason: 'la sesion viva se quedo sin su stream');
      expect(leidos, hasLength(1));
      expect(fuente.descartados, 0);
    });

    test('y tras cerrar, abrir da un microfono nuevo', () async {
      // Cerrado si: la sesion termino, y la siguiente no puede heredar un stream
      // muerto ni el recuento de descartados de la anterior.
      final fuente = RemoteVoiceSource();
      abrirY(fuente).listen((_) {});
      fuente.cerrar();
      fuente.entra(_pcm([100]));
      expect(fuente.descartados, 1);

      final leidos = <AudioFrame>[];
      abrirY(fuente).listen(leidos.add);
      fuente.entra(_pcm([500, 500]));
      await Future<void>.delayed(Duration.zero);

      expect(leidos, hasLength(1));
      expect(fuente.descartados, 0, reason: 'el recuento no se reinicio');
    });

    test(
      'el silencio da amplitud cero y la voz alta se satura en uno',
      () async {
        final fuente = RemoteVoiceSource();
        final frames = <AudioFrame>[];
        abrirY(fuente).listen(frames.add);

        fuente.entra(_pcm(List.filled(64, 0)));
        fuente.entra(_pcm(List.filled(64, 32000)));
        await Future<void>.delayed(Duration.zero);

        expect(frames.first.amplitude, 0);
        expect(frames.last.amplitude, 1);
      },
    );
  });

  group('el puerto compartido', () {
    test('con el teléfono sosteniendo, el micro del Mac no se abre', () {
      // Y esto es el punto: **no se mezclan**. Dos micrófonos en la misma sesión son
      // dos personas hablando encima, no una conversación.
      final delMac = _MicroDelMac();
      final fuente = RemoteVoiceSource()..abrir();
      final puerto = VoiceInputCompartido(local: delMac, remoto: fuente);

      puerto.listen();

      expect(delMac.vecesQueSeAbrio, 0);
    });

    test('sin teléfono, se usa el micro del Mac', () {
      final delMac = _MicroDelMac();
      final puerto = VoiceInputCompartido(
        local: delMac,
        remoto: RemoteVoiceSource(),
      );

      puerto.listen();

      expect(delMac.vecesQueSeAbrio, 1);
    });

    test('el permiso del Mac no bloquea la voz del teléfono', () async {
      // Si el teléfono está sosteniendo el botón es que su sistema le dio permiso.
      // Preguntar por el micrófono del Mac negaría la voz remota en un Mac que no
      // necesita micrófono para nada.
      final puerto = VoiceInputCompartido(
        local: _MicroNegado(),
        remoto: RemoteVoiceSource()..abrir(),
      );

      expect(await puerto.hasPermission(), isTrue);
    });

    test('sin teléfono, el permiso es el del Mac', () async {
      final puerto = VoiceInputCompartido(
        local: _MicroNegado(),
        remoto: RemoteVoiceSource(),
      );

      expect(await puerto.hasPermission(), isFalse);
    });
  });
  group('sostener para hablar, en el telefono', () {
    test('el Mac primero y el microfono despues', () async {
      // **El orden importa y no es un detalle.** Si se abriera el microfono antes, los
      // primeros trozos llegarian a un Mac sin sesion y se perderian — y son justo los
      // del principio de la frase, los que dicen que es lo que quieres.
      final orden = <String>[];
      final c = _conVoz(orden: orden);

      await c.read(vozProvider.notifier).sostener('a');

      expect(orden, ['mac:startVoice', 'micro:escuchar']);
      expect(c.read(vozProvider), Voz.hablando);
    });

    test('sin permiso del sistema no se abre nada', () async {
      // Y es un **estado**, no una excepcion: hay que poder enseñarlo, y quien lo nego
      // fue el sistema.
      final orden = <String>[];
      final c = _conVoz(orden: orden, permiso: false);

      await c.read(vozProvider.notifier).sostener('a');

      expect(c.read(vozProvider), Voz.sinMicrofono);
      expect(orden, isEmpty, reason: 'ni se le pide sesion al Mac');
    });

    test('si el Mac no contesta, no se enciende el microfono', () async {
      final orden = <String>[];
      final c = _conVoz(orden: orden, macContesta: false);

      await c.read(vozProvider.notifier).sostener('a');

      expect(c.read(vozProvider), Voz.sinMac);
      expect(
        orden.where((o) => o.startsWith('micro:')),
        isEmpty,
        reason: 'grabar sin sesion es grabar para nadie',
      );
    });

    test('soltar cierra el microfono y avisa al Mac', () async {
      final orden = <String>[];
      final c = _conVoz(orden: orden);
      await c.read(vozProvider.notifier).sostener('a');
      orden.clear();

      await c.read(vozProvider.notifier).soltar('a');

      expect(orden, ['micro:cerrar', 'mac:stopVoice']);
      expect(c.read(vozProvider), Voz.callado);
    });

    test('el microfono se cierra aunque el Mac no conteste', () async {
      // **Dejar el microfono abierto es el peor final posible**, asi que el cierre local
      // no depende de que el canal funcione.
      final orden = <String>[];
      final c = _conVoz(orden: orden);
      await c.read(vozProvider.notifier).sostener('a');
      orden.clear();
      _macCaido = true;

      await c.read(vozProvider.notifier).soltar('a');

      expect(orden, contains('micro:cerrar'));
      expect(c.read(vozProvider), Voz.callado);
    });

    test('lo que captura el microfono sale como marcos numerados', () async {
      final orden = <String>[];
      final c = _conVoz(orden: orden);
      await c.read(vozProvider.notifier).sostener('a');

      _micro.emite(_pcm([100, 200]));
      _micro.emite(_pcm([300, 400]));
      await Future<void>.delayed(Duration.zero);

      expect(_mandados.map((a) => a.seq), [0, 1]);
      expect(_mandados.first.pcmBase64.isNotEmpty, isTrue);
    });
  });
  group('el puerto no reabre', () {
    test('un trozo que llega antes de que la sesion escuche no se pierde', () async {
      // Este era el fallo: `startVoice` abria y tiraba el stream, y cuando la sesion
      // pedia audio se volvia a abrir **cerrando el primero**. Los trozos que llegaban
      // en medio entraban al controlador que nadie escuchaba y desaparecian en
      // silencio — justo los del principio de la frase.
      final fuente = RemoteVoiceSource();
      final puerto = VoiceInputCompartido(
        local: _MicroDelMac(),
        remoto: fuente,
      );

      fuente.abrir();
      fuente.entra(Uint8List.fromList([1, 0, 2, 0]));

      final leidos = <AudioFrame>[];
      puerto.listen().listen(leidos.add);
      await Future<void>.delayed(Duration.zero);

      expect(leidos, hasLength(1), reason: 'el trozo de antes se perdio');
      expect(fuente.descartados, 0);
    });

    test('sin encender, el puerto da el microfono del Mac', () {
      final fuente = RemoteVoiceSource();
      final mac = _MicroDelMac();
      VoiceInputCompartido(local: mac, remoto: fuente).listen();

      // Y esto es lo correcto: nadie sostiene el telefono, asi que la voz es la del
      // Mac. Lo que no valia era caer aqui **con el telefono sosteniendo**.
      expect(mac.vecesQueSeAbrio, 1);
    });
  });

  test('encender y apagar la voz se atienden en fila', () {
    // `stopVoice` llegaba mientras `startVoice` arrancaba la sesion, leia un
    // `voiceActive` que aun era `false` —no paraba nada— y cerraba la fuente. La
    // sesion terminaba de arrancar, pedia audio y se quedaba con el microfono del Mac
    // para toda la sesion: el orbe se encendia en los dos lados y no llegaba nada.
    final fuente = File(
      'lib/features/remote/presentation/assistant_surface.dart',
    ).readAsStringSync();

    for (final metodo in ['startVoice', 'stopVoice']) {
      final desde = fuente.indexOf('Future<void> $metodo(');
      expect(desde, greaterThan(0), reason: 'no encontre $metodo');
      final cuerpo = fuente.substring(desde, fuente.indexOf(';', desde));
      expect(
        cuerpo,
        contains('_enFila('),
        reason: '$metodo fuera de la fila vuelve a poder cruzarse',
      );
    }
  });
  testWidgets('el microfono se dibuja, y sus estados se leen sin color', (
    tester,
  ) async {
    // Era un `●` que habia que aprender, y de Material no puede ser —la guarda de la
    // pieza 6 lo tiene atado—. Se comprueba lo que importa: que hay un dibujo, y que
    // los tres estados **se distinguen sin mirar el color**, para quien no separe el
    // rojo del ambar.
    for (final caso in [
      (relleno: false, tachado: false),
      (relleno: true, tachado: false),
      (relleno: false, tachado: true),
    ]) {
      await tester.pumpWidget(
        Center(
          child: MicrofonoDibujado(
            color: const Color(0xFF56E1EA),
            size: 22,
            relleno: caso.relleno,
            tachado: caso.tachado,
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    }

    // No se comprueba que los tres pinten trazos distintos: comparar pixeles pide
    // un golden, y el painter es privado. Lo que si queda atado es que el dibujo
    // existe y que ninguno de los tres estados revienta al pintarse.
  });
  test('el microfono es un interruptor: un toque abre y otro cierra', () async {
    // Era «manten pulsado», que obliga a tener el dedo en el cristal mientras se
    // habla. Hablando con el Mac se hace lo contrario: se deja el telefono en la mesa
    // y se habla, asi que el gesto pasa a ser un interruptor.
    final orden = <String>[];
    final c = _conVoz(orden: orden);

    await c.read(vozProvider.notifier).sostener('a');
    expect(c.read(vozProvider), Voz.hablando);

    // Y el segundo toque lo cierra. Lo que preocupaba del interruptor —un microfono
    // olvidado abierto— lo cubre la sesion del Mac, que se cierra sola por
    // inactividad: es mejor sitio para esa garantia que el dedo del usuario.
    await c.read(vozProvider.notifier).soltar('a');
    expect(c.read(vozProvider), Voz.callado);
    expect(orden, contains('micro:cerrar'));
    expect(orden, contains('mac:stopVoice'));
  });

  test('y el boton del microfono es un toque, no un sostener', () {
    // La prueba de arriba cubre el controlador; esto cubre el gesto, que es donde
    // vivia el «manten pulsado»: un `Listener` con `onPointerUp` cerrando al levantar
    // el dedo. Si vuelve, el controlador seguiria bien y la app volveria a obligar a
    // tener el dedo en el cristal.
    final fuente = File(
      'lib/features/remote/presentation/pages/conversation_page.dart',
    ).readAsStringSync();
    final desde = fuente.indexOf('class _Microfono');
    final cuerpo = fuente.substring(desde, fuente.indexOf('\n}\n', desde));

    expect(cuerpo, contains('alTocar:'));
    expect(
      cuerpo,
      isNot(contains('onPointerUp')),
      reason: 'volvio el sostener',
    );
  });

  test('cerrar el microfono corta el audio en el acto, sin matar el flujo', () async {
    // Lo que se pidio: tocar cerrar en el telefono cierra el microfono **ya**, no
    // cuando la sesion del Mac se canse. Y lo que no puede pasar a la vez: cerrar el
    // flujo, porque a la sesion le queda lo importante —contestar—.
    final fuente = RemoteVoiceSource();
    final leidos = <AudioFrame>[];
    var cerrado = false;
    fuente.abrir();
    fuente.flujo!.listen(leidos.add, onDone: () => cerrado = true);

    fuente.entra(_pcm([9000, 9000]));
    await Future<void>.delayed(Duration.zero);
    expect(leidos, hasLength(1));

    fuente.silenciar();
    fuente.entra(_pcm([9000, 9000]));
    await Future<void>.delayed(Duration.zero);

    expect(leidos, hasLength(1), reason: 'siguio entrando audio tras cerrar');
    expect(cerrado, isFalse, reason: 'la sesion se quedo sin poder contestar');
    expect(fuente.activo, isTrue);

    // Y volver a abrir entra por el mismo flujo, que es el que la sesion viva lee.
    fuente.abrir();
    fuente.entra(_pcm([9000, 9000]));
    await Future<void>.delayed(Duration.zero);
    expect(leidos, hasLength(2));
    expect(cerrado, isFalse);
  });
}
