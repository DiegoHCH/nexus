import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/remote/data/channel_server.dart';
import 'package:nexus/features/remote/domain/event_log.dart';
import 'package:nexus/features/remote/domain/gatekeeper.dart';
import 'package:nexus/features/remote/domain/tailscale.dart';
import 'package:nexus/features/remote/presentation/providers/channel_token_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El puerto del canal.
///
/// Fijo y no elegido por el sistema, y hace falta que lo sea por dos razones: el
/// teléfono tiene que saber a dónde llamar sin que nadie se lo diga, y el `Host`
/// que el portero exige incluye el puerto — con uno efímero no se podría componer
/// antes de escuchar.
const canalPuerto = 7845;

/// En qué anda el canal.
@immutable
sealed class ChannelState {
  const ChannelState();
}

/// Apagado, que es como nace.
class ChannelOff extends ChannelState {
  const ChannelOff();
}

class ChannelStarting extends ChannelState {
  const ChannelStarting();
}

/// Escuchando, y dónde.
class ChannelOn extends ChannelState {
  const ChannelOn({required this.address, required this.port});

  final String address;
  final int port;

  /// Lo que hay que teclear en el teléfono.
  String get url => 'ws://$address:$port';
}

/// No se pudo encender, y por qué.
///
/// El motivo va en el estado y no en un registro: es lo único que la pantalla puede
/// convertir en algo que hacer.
class ChannelUnavailable extends ChannelState {
  const ChannelUnavailable(this.reason);

  final ChannelProblem reason;
}

enum ChannelProblem {
  /// No hay interfaz de Tailscale. Es el caso normal de la primera vez.
  noTailscale,

  /// El puerto está ocupado. Casi siempre: otra copia de Nexus abierta.
  portBusy,

  /// Cualquier otra cosa del sistema.
  unknown,
}

/// Enciende y apaga el canal, y recuerda la elección.
///
/// **Nace apagado**, y eso es una decisión: un socket escuchando es superficie de
/// ataque, y puede que el teléfono no se use nunca. Encenderlo es un acto
/// explícito.
///
/// Y la falta de Tailscale se cuenta **aquí, al encender**, no en la comprobación
/// de arranque. Meterla allí daría la lata a todo el mundo con una dependencia que
/// solo necesita quien use el móvil — el mismo criterio por el que la llave de
/// Gemini no bloquea el arranque.
class ChannelController extends Notifier<ChannelState> {
  static const _key = 'remote_channel_on';

  ChannelServer? _servidor;

  /// El registro de eventos vive aquí y no en el servidor: sobrevive a apagar y
  /// encender, así que un móvil que reconecta después de un reinicio del canal
  /// puede seguir pidiendo desde su `lastSeq` en vez de tragarse un snapshot.
  final EventLog _eventos = EventLog();

  EventLog get eventos => _eventos;
  ChannelServer? get servidor => _servidor;

  @override
  ChannelState build() {
    ref.onDispose(() => unawaited(_servidor?.stop()));
    unawaited(_alArrancar());
    return const ChannelOff();
  }

  /// Si estaba encendido la última vez, se vuelve a encender.
  ///
  /// Sin avisar de nada si falla: al arrancar la app nadie pidió esto ahora mismo,
  /// así que un cartel de error sería una interrupción por algo que no acabas de
  /// hacer. Queda en el estado, y la pantalla de Ajustes lo cuenta cuando se abre.
  Future<void> _alArrancar() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key) ?? false) await encender(recordar: false);
  }

  Future<void> encender({bool recordar = true}) async {
    if (_servidor != null) return;
    state = const ChannelStarting();

    final direccion = await ref.read(tailscaleAddressProvider)();
    if (direccion == null) {
      state = const ChannelUnavailable(ChannelProblem.noTailscale);
      // No se recuerda una elección que no se pudo cumplir: al siguiente arranque
      // volvería a intentarlo y a fallar, y el estado inicial diría «apagado» en
      // una pantalla que enseña un error. Mejor apagado de verdad.
      return;
    }

    // El token **antes** de escuchar, y `asegurar` en vez de `rotar`: si rotara
    // aquí, cada encendido invalidaría el teléfono ya emparejado.
    final token = await ref.read(channelTokenControllerProvider.notifier).asegurar();

    final servidor = ChannelServer(
      gatekeeper: Gatekeeper(
        token: token.value,
        // Con el puerto, que es lo que manda un cliente al conectar a un puerto no
        // estándar. Aquí está la razón de que el puerto sea fijo: sin saberlo antes
        // de escuchar, esto no se puede componer.
        hostEsperado: '${direccion.address}:$canalPuerto',
      ),
      log: _eventos,
      registro: (linea) => debugPrint('canal · $linea'),
    );

    try {
      await servidor.start(direccion: direccion, puerto: canalPuerto);
    } on SocketException catch (error) {
      debugPrint('el canal no pudo escuchar: ${error.message}');
      // El puerto ocupado se distingue porque tiene una causa concreta y
      // adivinable —otra copia de Nexus abierta— y las demás no.
      //
      // **Se reconocen dos mensajes y no un código**, porque medido resultó que hay
      // dos caminos distintos: si el que tiene el puerto es otro proceso, el error
      // viene del sistema («Address already in use»); si es este mismo proceso,
      // Dart lo detecta antes de llegar al sistema y devuelve `errorCode: -1` con
      // «the shared flag to bind() needs to be true». Fiarse del número habría
      // dejado el segundo caso como «fallo desconocido».
      final motivo = error.osError?.message ?? error.message;
      final ocupado =
          motivo.contains('Address already in use') ||
          motivo.contains('shared flag');
      state = ChannelUnavailable(
        ocupado ? ChannelProblem.portBusy : ChannelProblem.unknown,
      );
      return;
    }

    _servidor = servidor;
    state = ChannelOn(address: direccion.address, port: canalPuerto);
    if (recordar) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    }
  }

  Future<void> apagar() async {
    final servidor = _servidor;
    _servidor = null;
    await servidor?.stop();
    state = const ChannelOff();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, false);
  }

  /// Rotar el token **echa a quien esté dentro**.
  ///
  /// Y tiene que hacerlo: si las conexiones vivas sobrevivieran, rotar no
  /// revocaría nada hasta la siguiente reconexión — y quien rota lo hace justo
  /// porque quiere que alguien salga ya.
  Future<void> rotarToken() async {
    await ref.read(channelTokenControllerProvider.notifier).rotar();
    if (_servidor == null) return;
    await apagar();
    await encender();
  }
}

/// Buscar la dirección de Tailscale, inyectable.
///
/// Aparte para poder probar el encendido **sin Tailscale y con él**: en esta
/// máquina no está corriendo, y en CI menos.
final tailscaleAddressProvider = Provider<Future<InternetAddress?> Function()>(
  (ref) => Tailscale.buscar,
);

final channelControllerProvider =
    NotifierProvider<ChannelController, ChannelState>(ChannelController.new);
