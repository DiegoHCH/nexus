import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/gemini_live_data_source.dart';
import 'package:nexus/features/assistant/data/datasources/voice_preferences_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/gemini_voice_gateway.dart';
import 'package:nexus/features/assistant/domain/entities/nexus_voice.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_preference_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_session_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **La voz que elegiste, desde la primera sesión.**
///
/// 🔴 Reportado de oído: «cuando le pido algo por voz, en ocasiones responde con
/// otra voz y no con la que tengo configurada». Y era una carrera, no el
/// servicio: los ajustes de cómo suena nacen en su valor de fábrica y se leen
/// del disco un instante después de arrancar, mientras el timbre se fija en el
/// `setup` del socket y **no se renegocia**. Una sesión abierta en ese hueco se
/// queda con la voz de fábrica hasta que se cierre.
///
/// Lo que lo hacía intermitente: solo **una** de las tres puertas esperaba esa
/// lectura —la puerta del arranque—, así que la conversación y el aviso de
/// agenda salían con lo que hubiera. La espera se movió al gateway, que es por
/// donde pasan las tres.
class _DiscoLento extends VoicePreferencesDataSource {
  const _DiscoLento(this.voz, this.acento);

  final Completer<String?> voz;
  final Completer<String?> acento;

  @override
  Future<String?> read() => voz.future;

  @override
  Future<String?> readAccent() => acento.future;
}

GeminiVoiceGateway _gateway({
  String voz = 'Kore',
  Future<void> Function()? ajustes,
  void Function()? alLeerLaVoz,
}) => GeminiVoiceGateway(
  const GeminiLiveDataSource(),
  () async => 'una-llave',
  () {
    alLeerLaVoz?.call();
    return voz;
  },
  () => 'español',
  () => null,
  () => null,
  ajustes ?? () async {},
);

String? _timbreDe(Map<String, dynamic> setup) {
  final generacion = setup['generationConfig'] as Map<String, dynamic>;
  final habla = generacion['speechConfig'] as Map<String, dynamic>;
  final voz = habla['voiceConfig'] as Map<String, dynamic>;
  return (voz['prebuiltVoiceConfig'] as Map<String, dynamic>)['voiceName']
      as String?;
}

void main() {
  // Que la voz elegida llegue al sitio exacto donde el servicio la lee no
  // estaba comprobado en ninguna parte, y es lo único que separa «suena con la
  // que elegí» de «suena con la que el servicio quiera».
  group('el timbre elegido viaja al setup', () {
    test('en una conversación', () {
      final setup = _gateway(
        voz: 'Sulafat',
      ).elSetupDe(const ComoUnaConversacion());

      expect(_timbreDe(setup), 'Sulafat');
    });

    // Las tres puertas, una por una: el fallo de fondo fue justo que lo que
    // valía para una no valía para las otras dos.
    test('en la puerta del arranque', () {
      final setup = _gateway(
        voz: 'Sulafat',
      ).elSetupDe(const ComoLaPuerta(saludo: 'buenas', carpetas: ['nexus']));

      expect(_timbreDe(setup), 'Sulafat');
    });

    test('y en el aviso de agenda', () {
      final setup = _gateway(
        voz: 'Sulafat',
      ).elSetupDe(const ComoUnAviso('en cinco minutos, la daily'));

      expect(_timbreDe(setup), 'Sulafat');
    });
  });

  group('y no se abre una sesión antes de leer el disco', () {
    test('con la lectura pendiente, ni se pregunta qué voz es', () async {
      var leida = false;
      final gateway = _gateway(
        ajustes: () => Completer<void>().future, // nunca contesta
        alLeerLaVoz: () => leida = true,
      );

      var acabo = false;
      // Da igual cómo acabe —sesión o error—: lo que se comprueba es que no
      // llegó a empezar.
      unawaited(
        gateway
            .connect()
            .then<void>((_) {}, onError: (_) {})
            .whenComplete(() => acabo = true),
      );
      // Varias vueltas del bucle de eventos: si la espera no estuviera, con
      // esto ya habría leído la voz y estaría marcando el socket.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        leida,
        isFalse,
        reason: 'leer la voz antes del disco es leer la de fábrica',
      );
      expect(acabo, isFalse, reason: 'no hay sesión que abrir todavía');
    });
  });

  group('la espera de los ajustes que suenan', () {
    late Completer<String?> voz;
    late Completer<String?> acento;
    late ProviderContainer container;

    setUp(() {
      // Los nombres leen del disco por su cuenta, y también se esperan: con el
      // mock vacío contestan enseguida, que es lo que hace falta aquí.
      SharedPreferences.setMockInitialValues({});
      voz = Completer<String?>();
      acento = Completer<String?>();
      container = ProviderContainer(
        overrides: [
          voicePreferencesDataSourceProvider.overrideWithValue(
            _DiscoLento(voz, acento),
          ),
        ],
      );
    });
    tearDown(() => container.dispose());

    test('no termina mientras el disco no ha contestado', () async {
      var listo = false;
      unawaited(
        container.read(losAjustesQueSuenanProvider)().then((_) {
          listo = true;
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(listo, isFalse, reason: 'esperar a medias es no esperar');

      voz.complete('Sulafat');
      acento.complete(null);
      // Dos vueltas: una para cada lectura que se resuelve, y otra para el
      // `Future.wait` que las junta.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(listo, isTrue);
    });

    test(
      'y cuando termina, la voz ya es la elegida y no la de fábrica',
      () async {
        // Antes de esperar: lo que hay es el valor de fábrica, que es justo lo
        // que se oía.
        expect(container.read(voicePreferenceProvider), NexusVoice.fallback);

        voz.complete('Sulafat');
        acento.complete(null);
        await container.read(losAjustesQueSuenanProvider)();

        expect(container.read(voicePreferenceProvider).name, 'Sulafat');
      },
    );

    // El acento era el único de los tres que no se podía esperar: la voz y los
    // nombres ya tenían su espera desde antes.
    test('el acento también se espera, que era el que no se podía', () async {
      voz.complete(null);
      acento.complete('mx');
      await container.read(losAjustesQueSuenanProvider)();

      expect(container.read(elAcentoProvider).guardado, 'mx');
    });
  });
}
