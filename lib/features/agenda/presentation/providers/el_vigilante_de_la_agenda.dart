import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/platform/notifications_channel.dart';
import 'package:nexus/features/agenda/data/datasources/agenda_data_source.dart';
import 'package:nexus/features/agenda/data/datasources/avisos_preferencias_data_source.dart';
import 'package:nexus/features/agenda/data/datasources/gemini_tts_data_source.dart';
import 'package:nexus/features/agenda/domain/entities/reunion.dart';
import 'package:nexus/features/agenda/domain/usecases/la_jornada.dart';
import 'package:nexus/features/agenda/domain/usecases/lo_que_toca_avisar.dart';
import 'package:nexus/features/assistant/data/repositories/audio_output_impl.dart';
import 'package:nexus/features/assistant/domain/repositories/la_agenda_de_hoy.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_preference_providers.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/remote/presentation/providers/channel_providers.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Cómo están los avisos de agenda.
@immutable
class Avisos {
  const Avisos({
    this.encendidos = false,
    this.minutos = 5,
    this.carpeta,
    this.cargado = false,
    this.ultimaLectura,
  });

  final bool encendidos;
  final int minutos;

  /// La carpeta emparejada cuya cuenta de Claude se usa para mirar el
  /// calendario. El conector vive en la cuenta, y en Nexus la cuenta la decide
  /// la carpeta.
  final String? carpeta;

  final bool cargado;

  /// Cuándo se leyó el calendario por última vez, para poder enseñarlo.
  ///
  /// Se enseña porque **la agenda en memoria envejece sin avisar**: si programas
  /// algo a media mañana, lo que hay guardado no lo sabe. Ver la hora de la
  /// lectura es lo que convierte eso en algo que puedes corregir en vez de en
  /// una ausencia silenciosa.
  final DateTime? ultimaLectura;

  bool get listos => encendidos && (carpeta?.isNotEmpty ?? false);

  Avisos copyWith({
    bool? encendidos,
    int? minutos,
    Object? carpeta = _nada,
    Object? ultimaLectura = _nada,
  }) => Avisos(
    encendidos: encendidos ?? this.encendidos,
    minutos: minutos ?? this.minutos,
    carpeta: carpeta == _nada ? this.carpeta : carpeta as String?,
    cargado: true,
    ultimaLectura: ultimaLectura == _nada
        ? this.ultimaLectura
        : ultimaLectura as DateTime?,
  );

  static const _nada = Object();
}

/// Lo único de Nexus que ocurre sin que se lo pidas.
///
/// 🔴 Y por eso nace **apagado**. Toda la app está construida sobre que el
/// trabajo lo disparas tú; una que empieza a hablarte sola el día que se
/// actualiza asusta, aunque lo que diga sea útil.
///
/// El reloj es local y la agenda se lee **una vez al día**: preguntar cada
/// pocos minutos serían casi trescientos `claude -p` diarios gastando tokens de
/// tu suscripción para releer lo mismo.
class ElVigilanteDeLaAgenda extends Notifier<Avisos> {
  Timer? _reloj;

  /// El ancla de la última lectura, no la hora en que ocurrió.
  ///
  /// 🔴 **Se lee al arrancar y otra vez al pasar por las ocho**, y no solo una
  /// vez al día. Anclarlo únicamente a las ocho dejaría sin avisos a quien abre
  /// la app a las siete; leer solo al arrancar deja fuera todo lo que se
  /// programe después. Con las dos, son como mucho dos consultas diarias y la
  /// mañana entra completa.
  ///
  /// Lo que ninguna de las dos arregla es lo que se programa a media mañana:
  /// para eso está [releer], que se pide a mano.
  DateTime? _leidoDesde;
  List<Reunion> _agenda = const [];
  final _yaAvisadas = <String>{};
  var _hablando = false;

  /// Cada cuánto se mira el reloj. Treinta segundos: con la ventana de cinco
  /// minutos, es imposible que una reunión entre y salga sin que se vea.
  static const _cadencia = Duration(seconds: 30);

  /// Cuánto se espera a que una sesión de voz calle antes de rendirse y dejarlo
  /// en notificación.
  static const esperaMaxima = Duration(seconds: 60);

  @override
  Avisos build() {
    ref.onDispose(() => _reloj?.cancel());
    unawaited(_cargar());
    return const Avisos();
  }

  Future<void> _cargar() async {
    final guardado = await const AvisosPreferenciasDataSource().leer();
    if (!ref.mounted) return;
    state = Avisos(
      encendidos: guardado.encendidos,
      minutos: guardado.minutos,
      carpeta: guardado.carpeta,
      cargado: true,
    );
    _arrancarOParar();
  }

  Future<void> cambiar({
    bool? encendidos,
    int? minutos,
    Object? carpeta,
  }) async {
    state = state.copyWith(
      encendidos: encendidos,
      minutos: minutos,
      carpeta: carpeta ?? Avisos._nada,
    );
    await const AvisosPreferenciasDataSource().escribir(
      encendidos: state.encendidos,
      minutos: state.minutos,
      carpeta: state.carpeta,
    );
    // La agenda de la cuenta anterior ya no vale.
    if (carpeta != null) {
      _olvidarLaAgenda();
    }
    _arrancarOParar();
  }

  void _arrancarOParar() {
    _reloj?.cancel();
    if (!state.listos) return;
    _reloj = Timer.periodic(_cadencia, (_) => unawaited(_mirar()));
    unawaited(_mirar());
  }

  Future<void> _mirar() async {
    if (!state.listos || _hablando) return;
    final ahora = DateTime.now();
    await _leerSiHaceFalta(ahora);
    if (!ref.mounted) return;

    final tocan = LoQueTocaAvisar.ahora(
      _agenda,
      cuando: ahora,
      antes: Duration(minutes: state.minutos),
      yaAvisadas: _yaAvisadas,
    );
    if (tocan.isEmpty) return;

    // Una cada vez. Dos reuniones a la misma hora son dos avisos seguidos, no
    // dos voces encima.
    final reunion = tocan.first;
    _yaAvisadas.add(reunion.id);
    await _avisar(reunion, ahora);
  }

  /// Vuelve a preguntarle al calendario ahora mismo.
  ///
  /// Existe porque la agenda en memoria **no se entera de lo que se programe
  /// después**: una reunión puesta a media mañana no está en lo que se leyó al
  /// arrancar. Se pide a mano en vez de sondear cada pocos minutos, que serían
  /// casi trescientas consultas diarias para releer lo mismo.
  Future<void> releer() async {
    _olvidarLaAgenda();
    await _leerSiHaceFalta(DateTime.now());
  }

  /// Lo que hay hoy, sin salir a preguntarlo otra vez.
  ///
  /// La agenda ya está leída —hizo falta para poder avisar— así que contestar
  /// es mirar en memoria. `null` si no hay nada que mirar: con los avisos
  /// apagados o sin carpeta no hay agenda, y entonces quien pregunta sigue por
  /// el camino largo en vez de recibir un «no tengo» que sería mentira.
  Future<String?> loDeHoy() async {
    if (!state.listos) return null;
    final ahora = DateTime.now();
    await _leerSiHaceFalta(ahora);
    if (!ref.mounted) return null;

    final s = ref.read(stringsProvider);
    // Fuera de jornada la agenda está borrada, y decir «no tienes reuniones»
    // sería mentir sobre un día que sí las tuvo. Se dice lo que pasa, y queda
    // el botón de actualizar para quien la quiera igual.
    if (!LaJornada.dentro(ahora)) return s.agendaFueraDeJornada;
    final reuniones = [
      for (final reunion in _agenda)
        if (reunion.esUnaReunion) reunion,
    ]..sort((a, b) => a.comienza.compareTo(b.comienza));
    if (reuniones.isEmpty) return s.agendaVacia;

    return [
      s.agendaDeHoy(reuniones.length),
      for (final reunion in reuniones)
        '- ${_laHora(reunion.comienza)} · ${reunion.titulo}',
    ].join('\n');
  }

  static String _laHora(DateTime cuando) =>
      '${cuando.hour.toString().padLeft(2, '0')}:'
      '${cuando.minute.toString().padLeft(2, '0')}';

  /// Suelta un aviso de mentira, ahora mismo.
  ///
  /// 🔴 **Existe porque esto no se puede probar de otra forma.** Un aviso
  /// depende de que tengas una reunión dentro de cinco minutos, así que sin
  /// esto la única manera de saber si funciona —o de oír a qué volumen suena, o
  /// de descubrir que falta la llave— es esperar a que te pase de verdad. Y el
  /// día que te pase de verdad es justo el día en que no quieres descubrir que
  /// no funcionaba.
  ///
  /// Recorre el mismo camino que uno real: la misma llave, la misma voz, los
  /// mismos dos altavoces y la misma espera si estás hablando. Lo único que se
  /// salta es el calendario.
  Future<void> probar() {
    final ahora = DateTime.now();
    return _avisar(
      Reunion(
        id: 'prueba-${ahora.microsecondsSinceEpoch}',
        titulo: ref.read(stringsProvider).avisoDePrueba,
        comienza: ahora.add(Duration(minutes: state.minutos)),
        invitados: 1,
      ),
      ahora,
    );
  }

  void _olvidarLaAgenda() {
    _leidoDesde = null;
    _agenda = const [];
    _yaAvisadas.clear();
  }

  Future<void> _leerSiHaceFalta(DateTime ahora) async {
    final ancla = LaJornada.anclaPara(ahora);
    // Fuera de jornada no se lee y **no se conserva**: lo que quedara en
    // memoria sería la lista de un día que terminó, y sirve para contestar mal.
    if (ancla == null) {
      if (_agenda.isNotEmpty) _olvidarLaAgenda();
      return;
    }
    if (_leidoDesde == ancla) return;
    final carpeta = state.carpeta;
    if (carpeta == null) return;

    final leida = await const AgendaDataSource().delDia(
      DateTime(ahora.year, ahora.month, ahora.day),
      carpeta: carpeta,
      configDir: _cuentaDe(carpeta),
    );
    if (!ref.mounted) return;
    _agenda = leida;
    _leidoDesde = ancla;
    state = state.copyWith(ultimaLectura: DateTime.now());
    // Un día nuevo empieza sin memoria de lo avisado: los identificadores son
    // del calendario y no se repiten, pero dejar crecer el conjunto para
    // siempre es una fuga lenta que nadie va a mirar.
    _yaAvisadas.removeWhere((id) => !leida.any((r) => r.id == id));
  }

  Future<void> _avisar(Reunion reunion, DateTime ahora) async {
    _hablando = true;
    try {
      final s = ref.read(stringsProvider);
      final frase = LoQueTocaAvisar.comoSeDice(
        reunion,
        cuando: ahora,
        plantilla: s.reunionEnMinutos,
        ahoraMismo: s.reunionAhora,
      );

      // 🔴 Si hay una sesión de voz abierta, se espera a que calle. Es la
      // decisión que evita tocar el motor duplex: dos audios no se mezclan
      // nunca, así que la parte que cancela el eco se queda como está.
      if (!await _esperarSilencio()) {
        await _soloNotificar(reunion.titulo, frase);
        return;
      }
      if (!ref.mounted) return;

      final llave = await ref.read(geminiKeyStoreProvider).read();
      if (!ref.mounted) return;
      if (llave == null || llave.isEmpty) {
        await _soloNotificar(reunion.titulo, frase);
        return;
      }

      final dicho = await const GeminiTtsDataSource().decir(
        llave: llave,
        frase: frase,
        voz: ref.read(voicePreferenceProvider).name,
      );
      if (!ref.mounted) return;
      if (!dicho.salio) {
        debugPrint('agenda · no se pudo decir el aviso: ${dicho.problema}');
        await _soloNotificar(reunion.titulo, frase);
        return;
      }

      await _sonarEnLosDos(dicho.pcm!);
      // El aviso de macOS va **además** de la voz: si estabas en otra sala, la
      // frase se la lleva el aire y la notificación sigue ahí al volver.
      await NotificationsChannel.notify(title: reunion.titulo, body: frase);
    } finally {
      _hablando = false;
    }
  }

  /// 🔴 **En los dos, y es una excepción a la regla del canal.**
  ///
  /// El canal decide dónde suena la respuesta con «suena donde se preguntó, así
  /// que nunca suenan los dos». Un aviso no se pregunta desde ningún sitio, así
  /// que esa regla no lo cubre — y la salida elegida es sonar en ambos, porque
  /// el aviso existe para sacarte de donde estés y no se sabe si estás delante
  /// del Mac. El precio, aceptado: si estás al lado de los dos, se oye doble.
  ///
  /// Al teléfono solo llega si está conectado: `RemoteAudioSink` se traga el
  /// trozo cuando no hay socket, que es exactamente lo que hay que hacer con
  /// audio sin conexión.
  Future<void> _sonarEnLosDos(Uint8List pcm) async {
    final delMac = AudioOutputImpl(ref.read(nativeAudioDataSourceProvider));
    await delMac.start();
    delMac.enqueue(pcm);

    final delMovil = ref.read(remoteAudioSinkProvider);
    await delMovil.start();
    delMovil.enqueue(pcm);

    // Sin esperar a que termine no se puede parar el motor sin cortar a media
    // palabra — es la misma razón por la que `pending()` existe.
    await Future<void>.delayed(await delMac.pending());
  }

  Future<void> _soloNotificar(String titulo, String frase) =>
      NotificationsChannel.notify(title: titulo, body: frase);

  /// Espera a que ninguna conversación tenga la voz abierta. `false` si se
  /// agota el plazo.
  Future<bool> _esperarSilencio() async {
    final hasta = DateTime.now().add(esperaMaxima);
    while (_hayVozAbierta()) {
      if (DateTime.now().isAfter(hasta)) return false;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!ref.mounted) return false;
    }
    return true;
  }

  bool _hayVozAbierta() => ref
      .read(conversationsProvider)
      .items
      .any((c) => ref.read(assistantControllerProvider(c.id)).voiceActive);

  String? _cuentaDe(String carpeta) => ClaudeProfile.nameFromPath(
    ref
        .read(workspaceControllerProvider)
        .folders
        .where((f) => f.path == carpeta)
        .firstOrNull
        ?.claudeProfile,
  );
}

final elVigilanteDeLaAgendaProvider =
    NotifierProvider<ElVigilanteDeLaAgenda, Avisos>(ElVigilanteDeLaAgenda.new);

/// El puerto que usa la conversación, hablando o escribiendo.
final laAgendaDeHoyProvider = Provider<LaAgendaDeHoy>(
  (ref) => _LaAgendaDelVigilante(ref),
);

class _LaAgendaDelVigilante implements LaAgendaDeHoy {
  const _LaAgendaDelVigilante(this._ref);

  final Ref _ref;

  @override
  Future<String?> deHoy() =>
      _ref.read(elVigilanteDeLaAgendaProvider.notifier).loDeHoy();
}
