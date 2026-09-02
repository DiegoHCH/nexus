import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// Una pregunta esperando respuesta, con el hilo por el que se contesta.
///
/// Los dos motivos vienen ya resueltos desde que se encola, y eso **no es
/// eficiencia**: se leen de `stringsProvider`, y negar puede ocurrir dentro de
/// un `onDispose` —al cerrarse la conversación— donde Riverpod prohíbe tocar
/// otro provider. Tomarlos aquí, en una llamada normal, es lo que hace que
/// contestar no dependa de poder leer nada.
class _EnEspera {
  _EnEspera(this.peticion, this.motivoDenegado, this.motivoCancelado);

  final PeticionDePermiso peticion;
  final String motivoDenegado;
  final String motivoCancelado;
  final completer = Completer<RespuestaDePermiso>();
}

/// Lo que Claude está pidiendo permiso para hacer, ahora mismo.
///
/// Existe para cruzar el hueco entre el puente y la pantalla: el encargo corre
/// en un `Notifier` que no tiene `BuildContext` y no puede abrir un diálogo, y
/// el diálogo no puede alcanzar el `stdin` del proceso. Esto es el buzón entre
/// los dos.
///
/// **Es una cola y no un hueco de uno**, y eso no es previsión: Claude pide
/// varias herramientas en el mismo turno —dos escrituras seguidas son lo
/// normal— y con un solo hueco la segunda sobreescribía a la primera. La que
/// perdía el hueco se quedaba con su `Completer` sin completar, o sea con el
/// CLI esperando una respuesta que ya no iba a llegar: el turno colgado, sin
/// error y sin nada en pantalla.
///
/// Global y no por conversación a propósito: hay una ventana y un diálogo a la
/// vez, así que dos encargos en marcha comparten la fila en vez de pelearse por
/// el frente.
class ElPermisoPendiente extends Notifier<PeticionDePermiso?> {
  final _cola = <_EnEspera>[];

  @override
  PeticionDePermiso? build() {
    // Al cerrarse esto no queda nadie para contestar: mejor negar que dejar
    // procesos esperando.
    //
    // **Y solo se sueltan, no se toca el estado.** Asignar `state` desde un
    // `onDispose` revienta con el mismo assert que impedía leer providers ahí,
    // y encima no serviría de nada: el provider se está muriendo, nadie va a
    // volver a mirarlo.
    ref.onDispose(_soltarLaFila);
    return null;
  }

  /// Pone la pregunta en la fila y devuelve la respuesta cuando la haya.
  Future<RespuestaDePermiso> preguntar(PeticionDePermiso peticion) {
    final strings = ref.read(stringsProvider);
    final espera = _EnEspera(
      peticion,
      strings.permisoDenegadoMotivo,
      strings.permisoCanceladoMotivo,
    );
    _cola.add(espera);
    state = _cola.first.peticion;
    return espera.completer.future;
  }

  /// Adelante, solo con esto.
  void conceder() {
    if (_cola.isEmpty) return;
    _contesta(PermisoConcedido(_cola.first.peticion.entrada));
  }

  /// Adelante, y deja de preguntar lo mismo en esta sesión.
  ///
  /// Lo que se aplica lo propone el CLI en la propia petición; aquí no se
  /// inventa ninguna regla, solo se le devuelve la suya.
  void concederTodo() {
    if (_cola.isEmpty) return;
    final peticion = _cola.first.peticion;
    _contesta(
      PermisoConcedido(peticion.entrada, permisosNuevos: peticion.sugerencias),
    );
  }

  /// No.
  ///
  /// El motivo se manda en el idioma de la app porque **lo lee el modelo**: le
  /// llega como el resultado de la herramienta, marcado como error, y es sobre
  /// eso sobre lo que decide qué hacer después.
  void denegar() {
    if (_cola.isEmpty) return;
    _contesta(PermisoDenegado(_cola.first.motivoDenegado));
  }

  /// Niega todo lo que quedara en la fila.
  ///
  /// Se llama al parar el encargo: el proceso se va a morir, pero mientras siga
  /// vivo hay que contestarle. Y sobre todo hay que completar los `Completer`,
  /// que si no dejan `await` colgados en el datasource.
  void descartarTodo() {
    if (_cola.isEmpty) return;
    _soltarLaFila();
    state = null;
  }

  /// Contesta que no a todo y vacía la fila, sin tocar el estado.
  void _soltarLaFila() {
    for (final espera in _cola) {
      if (!espera.completer.isCompleted) {
        espera.completer.complete(PermisoDenegado(espera.motivoCancelado));
      }
    }
    _cola.clear();
  }

  void _contesta(RespuestaDePermiso respuesta) {
    final espera = _cola.removeAt(0);
    if (!espera.completer.isCompleted) espera.completer.complete(respuesta);
    // La siguiente de la fila pasa al frente, y si no hay ninguna el diálogo
    // se cierra solo: la pantalla mira este valor.
    state = _cola.isEmpty ? null : _cola.first.peticion;
  }
}

final elPermisoPendienteProvider =
    NotifierProvider<ElPermisoPendiente, PeticionDePermiso?>(
      ElPermisoPendiente.new,
    );
