import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/agenda/domain/usecases/la_voz_del_aviso.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';

// El aviso de una reunión, dicho por la sesión de voz y ya no por el TTS.
//
// 🔴 **Porque el TTS se agota y un aviso mudo no es un aviso.** El cupo diario
// del modelo de texto a voz del nivel gratuito es minúsculo —medido al sacar la
// 1.8.0: `RPD 13/10`— y con dos o tres reuniones ya no suena nada. El Live es el
// mismo servicio que sostiene las conversaciones y no se agota en uso normal.

class _Sesion implements VoiceSession {
  final _eventos = StreamController<VoiceEvent>.broadcast();
  final notas = <String>[];
  var cerrada = false;

  @override
  Stream<VoiceEvent> get events => _eventos.stream;

  @override
  void sendSystemNote(String text) => notas.add(text);

  @override
  Future<void> close() async => cerrada = true;

  void emite(VoiceEvent evento) => _eventos.add(evento);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Servicio implements VoiceGateway {
  _Servicio(this.sesion, {this.revienta = false});

  final _Sesion sesion;
  final bool revienta;
  PerfilDeVoz? conQuePerfil;

  @override
  Future<VoiceSession> connect({
    PerfilDeVoz perfil = const ComoUnaConversacion(),
  }) async {
    conQuePerfil = perfil;
    if (revienta) throw StateError('sin llave');
    return sesion;
  }

  @override
  Future<VoiceSession> resume() => connect();
}

void main() {
  late _Sesion sesion;
  late _Servicio servicio;

  setUp(() {
    sesion = _Sesion();
    servicio = _Servicio(sesion);
  });

  Future<void> vueltas([int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('se abre como aviso, con la frase literal dentro', () async {
    final dicho = LaVozDelAviso(servicio).decir('Reunión en cinco minutos.');
    await vueltas();

    final perfil = servicio.conQuePerfil;
    expect(perfil, isA<ComoUnAviso>());
    expect((perfil! as ComoUnAviso).frase, 'Reunión en cinco minutos.');

    sesion.emite(const VoiceTurnCompleted());
    await dicho;
  });

  test('devuelve el audio que dijo, y cierra la sesión', () async {
    final futuro = LaVozDelAviso(servicio).decir('Reunión en cinco minutos.');
    await vueltas();

    sesion.emite(const VoiceSessionReady());
    sesion.emite(VoiceReplyAudio(Uint8List.fromList([1, 2])));
    sesion.emite(VoiceReplyAudio(Uint8List.fromList([3])));
    sesion.emite(const VoiceTurnCompleted());

    final dicho = await futuro;
    expect(dicho.salio, isTrue);
    expect(dicho.pcm, [1, 2, 3]);

    // El cierre se suelta sin esperarlo —quien pide el aviso quiere el audio,
    // no la despedida—, así que se le da una vuelta al bucle.
    await vueltas();
    expect(sesion.cerrada, isTrue, reason: 'una sesión de un solo uso');
  });

  // 🔴 Y solo la señal, no la frase: lo que se manda por ahí llega como turno de
  // usuario, y con la frase dentro el modelo la comenta —«me pidieron que dijera
  // eso»—. La frase vive en la instrucción del setup.
  test('al estar lista solo se le da la señal de arranque', () async {
    final futuro = LaVozDelAviso(servicio).decir('Reunión en cinco minutos.');
    await vueltas();

    sesion.emite(const VoiceSessionReady());
    await vueltas();

    expect(sesion.notas, ['(inicio)']);

    sesion.emite(const VoiceTurnCompleted());
    await futuro;
  });

  test('un turno sin audio se cuenta como fallo, no como silencio', () async {
    final futuro = LaVozDelAviso(servicio).decir('Reunión en cinco minutos.');
    await vueltas();

    sesion.emite(const VoiceTurnCompleted());

    final dicho = await futuro;
    expect(dicho.salio, isFalse);
    expect(dicho.problema, 'no dijo nada');
  });

  test('si el servicio se cae, se dice por qué', () async {
    final futuro = LaVozDelAviso(servicio).decir('Reunión en cinco minutos.');
    await vueltas();

    sesion.emite(const VoiceSessionFailed('se cortó'));

    final dicho = await futuro;
    expect(dicho.salio, isFalse);
    expect(dicho.problema, 'se cortó');
  });

  // Aquí no hay nadie mirando la pantalla: un fallo sin recoger sería silencio,
  // que es justo lo que este aviso viene a evitar.
  test('y si ni se puede conectar, tampoco revienta', () async {
    final dicho = await LaVozDelAviso(
      _Servicio(sesion, revienta: true),
    ).decir('Reunión en cinco minutos.');

    expect(dicho.salio, isFalse);
    expect(dicho.problema, contains('sin llave'));
  });

  test('sin nada que decir no se abre ninguna sesión', () async {
    final dicho = await LaVozDelAviso(servicio).decir('   ');

    expect(dicho.salio, isFalse);
    expect(servicio.conQuePerfil, isNull);
  });
}
