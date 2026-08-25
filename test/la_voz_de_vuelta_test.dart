import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/remote/domain/audio_output_compartido.dart';
import 'package:nexus/features/remote/domain/remote_audio_sink.dart';
import 'package:nexus/features/remote/domain/remote_voice_source.dart';

/// La voz de vuelta: que la respuesta suene **donde se preguntó**.
///
/// Es la simetria de la 4.4. Lo que se prueba aqui no es que suene —eso lo hace el
/// sistema operativo del telefono— sino las tres decisiones que se tomaron alrededor,
/// porque las tres salieron de problemas reales y las tres se pueden romper en silencio.
void main() {
  Uint8List pcm(int bytes) => Uint8List(bytes);

  group('el altavoz del telefono', () {
    late List<String> orden;
    late RemoteAudioSink altavoz;

    setUp(() {
      orden = [];
      altavoz = RemoteAudioSink(
        mandar: (p) => orden.add('mandar:${p.lengthInBytes}'),
        tirar: () => orden.add('tirar'),
      );
    });

    test('quien reproduce dice cuando termino, y no un reloj de aqui', () async {
      await altavoz.start();
      expect(await altavoz.pending(), Duration.zero);

      // 48.000 bytes son un segundo a 24 kHz mono de 16 bits.
      altavoz.enqueue(pcm(48000));
      expect(await altavoz.pending(), greaterThan(Duration.zero));

      // **Y sigue pendiente por mucho que pase el tiempo aqui**: la unica forma de que
      // deje de estarlo es que el telefono lo diga. Estimarlo por bytes y ritmo seria
      // adivinar el jitter de la red, y quedarse corto corta la ultima palabra.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await altavoz.pending(), greaterThan(Duration.zero));

      altavoz.terminoDeSonar();
      expect(await altavoz.pending(), Duration.zero);
    });

    test('callar deja de mandar audio, y el turno sigue', () async {
      await altavoz.start();
      altavoz.enqueue(pcm(4800));
      altavoz.callar();
      altavoz.enqueue(pcm(4800));

      // Se le dice al telefono que tire lo que tenga, y se deja de gastar canal en algo
      // que nadie va a oir.
      expect(orden, ['mandar:4800', 'tirar']);
      // Y la sesion no se queda esperando: callar no es «sigue sonando en silencio».
      expect(await altavoz.pending(), Duration.zero);
    });

    test('si el telefono se va, la voz se corta y no espera a nadie', () async {
      await altavoz.start();
      altavoz.enqueue(pcm(48000));
      expect(await altavoz.pending(), greaterThan(Duration.zero));

      altavoz.seFue();

      // **Sin esto la sesion se quedaria abierta para siempre** esperando un «ya
      // termine» de un telefono que no esta. Y no se manda nada mas: la respuesta se
      // estaba diciendo a quien no esta delante del Mac.
      expect(await altavoz.pending(), Duration.zero);
      altavoz.enqueue(pcm(4800));
      expect(orden, ['mandar:48000']);
    });

    test('y no se termina por los altavoces del Mac', () async {
      // La decision, dicha al reves: irse **no** es motivo para mudar la respuesta al
      // Mac. Soltarla en una habitacion vacia es peor que callarse, y el texto es lo
      // que se puede leer al volver.
      final mac = _AltavozDelMac();
      final fuente = RemoteVoiceSource()..abrir();
      final puerto = AudioOutputCompartido(
        local: mac,
        remoto: altavoz,
        fuente: fuente,
      );
      await puerto.start();
      puerto.enqueue(pcm(4800));
      altavoz.seFue();
      puerto.enqueue(pcm(4800));

      expect(mac.encolados, isEmpty, reason: 'la respuesta se mudo al Mac');
    });
  });

  group('la voz suena donde se pregunto', () {
    late _AltavozDelMac mac;
    late List<String> orden;
    late RemoteAudioSink telefono;

    setUp(() {
      mac = _AltavozDelMac();
      orden = [];
      telefono = RemoteAudioSink(
        mandar: (p) => orden.add('telefono:${p.lengthInBytes}'),
        tirar: () => orden.add('telefono:tirar'),
      );
    });

    AudioOutputCompartido puerto(RemoteVoiceSource fuente) =>
        AudioOutputCompartido(local: mac, remoto: telefono, fuente: fuente);

    test('si la pregunta vino del telefono, suena en el telefono', () async {
      final p = puerto(RemoteVoiceSource()..abrir());
      await p.start();
      p.enqueue(pcm(4800));

      expect(orden, ['telefono:4800']);
      expect(mac.encolados, isEmpty);
    });

    test('si vino del microfono del Mac, suena en el Mac', () async {
      final p = puerto(RemoteVoiceSource());
      await p.start();
      p.enqueue(pcm(4800));

      expect(mac.encolados, [4800]);
      expect(orden, isEmpty);
    });

    test('nunca suenan los dos', () async {
      // Este era el motivo que se daba para no bajar la voz —el telefono seria «una
      // segunda boca»— y **se cae con la propia regla**: hay un solo destino elegido.
      final p = puerto(RemoteVoiceSource()..abrir());
      await p.start();
      p.enqueue(pcm(4800));
      p.enqueue(pcm(4800));

      expect(mac.encolados, isEmpty);
      expect(orden, hasLength(2));
    });

    test('el destino se elige al arrancar y no en cada trozo', () async {
      // La fuente **se cierra a mitad**: pasa cuando el telefono se va, y tambien al
      // terminar la sesion anterior. Decidiendo por trozo, la respuesta se mudaria a
      // los altavoces del Mac justo cuando empieza a sonar — y eso es precisamente lo
      // que se decidio que no: se le estaba diciendo a quien no esta delante del Mac.
      //
      // Se usa `cerrar` y no `silenciar` a proposito: silenciar no apaga la fuente
      // —el flujo sigue vivo para que la sesion pueda contestar— asi que con el una
      // version que decidiera por trozo pasaria igual, y la prueba no probaria nada.
      // Se comprobo mutando el codigo, no razonandolo.
      final fuente = RemoteVoiceSource()..abrir();
      final p = puerto(fuente);
      await p.start();

      fuente.cerrar();
      p.enqueue(pcm(4800));

      expect(orden, ['telefono:4800']);
      expect(mac.encolados, isEmpty);
    });

    test('y la siguiente sesion vuelve a elegir', () async {
      final fuente = RemoteVoiceSource()..abrir();
      final p = puerto(fuente);
      await p.start();
      await p.stop();

      // Sin telefono sosteniendo, la voz vuelve al Mac. Si el destino se quedara
      // pegado, hablarle al Mac despues de hablarle al telefono sonaria en el telefono.
      fuente.cerrar();
      await p.start();
      p.enqueue(pcm(4800));

      expect(mac.encolados, [4800]);
    });
  });
}

/// El altavoz del Mac, solo para saber qué le llegó.
class _AltavozDelMac implements AudioOutput {
  final encolados = <int>[];
  var arrancado = false;

  @override
  Future<void> start() async => arrancado = true;

  @override
  void enqueue(Uint8List pcm) => encolados.add(pcm.lengthInBytes);

  @override
  Future<void> discard() async {}

  @override
  Future<Duration> pending() async => Duration.zero;

  @override
  Future<void> stop() async => arrancado = false;
}
