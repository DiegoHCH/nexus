import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/remote/domain/remote_voice_source.dart';
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

void main() {
  group('la fuente remota', () {
    test('lo que llega mientras está abierta sale como frames', () async {
      final fuente = RemoteVoiceSource();
      final frames = <AudioFrame>[];
      fuente.abrir().listen(frames.add);

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

    test('abrir dos veces no deja dos micrófonos', () async {
      // Pasa cuando se pierde el `stopVoice`. Dejar el primero colgado serían dos
      // fuentes escribiendo en la misma sesión.
      final fuente = RemoteVoiceSource();
      final primera = <AudioFrame>[];
      var primeraCerrada = false;
      fuente.abrir().listen(primera.add, onDone: () => primeraCerrada = true);

      final segunda = <AudioFrame>[];
      fuente.abrir().listen(segunda.add);
      fuente.entra(_pcm([500, 500]));
      await Future<void>.delayed(Duration.zero);

      expect(primeraCerrada, isTrue);
      expect(primera, isEmpty);
      expect(segunda, hasLength(1));
    });

    test(
      'el silencio da amplitud cero y la voz alta se satura en uno',
      () async {
        final fuente = RemoteVoiceSource();
        final frames = <AudioFrame>[];
        fuente.abrir().listen(frames.add);

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
}
