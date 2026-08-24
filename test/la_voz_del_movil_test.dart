import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/remote/domain/remote_voice_source.dart';
import 'package:nexus/features/remote/domain/voice_input_compartido.dart';

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
}
