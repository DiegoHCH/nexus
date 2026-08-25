import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/remote/data/altavoz_del_movil.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/providers/voz_providers.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

/// En qué anda la respuesta hablada, aquí.
enum Reproduccion {
  /// Nada sonando.
  callada,

  /// Sonando ahora mismo.
  sonando,

  /// El usuario la calló y sigue leyendo. **No es lo mismo que `callada`**: aquí hubo
  /// una decisión, y mientras dure no se vuelve a sonar aunque sigan llegando trozos.
  silenciada,
}

final altavozProvider = Provider<Altavoz>((ref) {
  final altavoz = AltavozDelMovil();
  ref.onDispose(altavoz.soltar);
  return altavoz;
});

/// La respuesta hablada, cuando la pregunta salió de este teléfono.
///
/// El Mac decide **dónde** suena —la voz suena donde se preguntó— así que aquí no se
/// elige nada: si llegan trozos es que tocaba aquí, y se reproducen.
class ReproduccionController extends Notifier<Reproduccion> {
  StreamSubscription<Uint8List>? _deAudio;
  StreamSubscription<void>? _deDescartes;

  /// Lo que se espera con la cola vacía antes de dar la respuesta por terminada.
  static const _huecoQueYaEsFinal = Duration(milliseconds: 700);

  Timer? _esperandoElFinal;

  /// La conversación cuya respuesta está sonando. Hace falta para poder decir que
  /// terminó: el aviso viaja por el canal y el canal pregunta de cuál.
  String? _deQuien;

  @override
  Reproduccion build() {
    final enlace = ref.watch(channelLinkProvider);
    final altavoz = ref.watch(altavozProvider);

    // **Vaciarse no es haber terminado.**
    //
    // El servicio entrega la respuesta más rápido que en tiempo real, así que el audio
    // llega a rachas y la cola se queda a cero entre racha y racha. Avisando en cada
    // cero se decía «terminé» ocho veces por respuesta —medido—, el Mac dejaba de
    // esperar y cerraba la sesión por inactividad: **la respuesta se cortaba a mitad**.
    //
    // Terminar es quedarse a cero **y que no llegue nada más**. La espera es corta
    // porque los huecos dentro de una respuesta lo son —la cola se vacía porque suena
    // más rápido de lo que llega, no porque el servicio se haya callado— y pasarse solo
    // cuesta que la sesión viva un momento más de la cuenta.
    altavoz.alVaciarse = () {
      if (state != Reproduccion.sonando) return;
      _esperandoElFinal?.cancel();
      _esperandoElFinal = Timer(_huecoQueYaEsFinal, () {
        if (state != Reproduccion.sonando) return;
        state = Reproduccion.callada;
        _avisar(RemoteMethod.playbackFinished);
      });
    };

    _deAudio = enlace.audio.listen((pcm) {
      // Callada por decisión: los trozos que sigan llegando se tiran aquí en vez de
      // sonar. El Mac deja de mandarlos en cuanto le llega el aviso, pero los que ya
      // venían en vuelo no se pueden desandar.
      if (state == Reproduccion.silenciada) return;
      // Llegó más: lo de antes no era el final.
      _esperandoElFinal?.cancel();
      _esperandoElFinal = null;

      // **Y si el micrófono seguía abierto, se cierra.**
      //
      // Normalmente ya está cerrado —se cierra a mano y eso es lo que dispara la
      // respuesta— pero el servicio también contesta por su cuenta cuando ve silencio
      // suficiente, y ahí el micrófono sigue abierto. Sin esto, el teléfono se oiría a
      // sí mismo y se lo mandaría de vuelta: su cancelación de eco no cubre lo que sale
      // de su propio altavoz por esta ruta.
      //
      // Va aquí y no solo en el botón porque el botón cubre la intención y esto cubre
      // el caso: apagar la posibilidad en la pantalla no sirve si nadie la tocó.
      if (state != Reproduccion.sonando) _cerrarElMicrofono();

      state = Reproduccion.sonando;
      unawaited(altavoz.encolar(pcm));
    });

    // El Mac interrumpe: alguien habló encima, o se calló la respuesta desde aquí.
    _deDescartes = enlace.descartar.listen((_) {
      _esperandoElFinal?.cancel();
      _esperandoElFinal = null;
      unawaited(altavoz.tirar());
      if (state == Reproduccion.sonando) state = Reproduccion.callada;
    });

    ref.onDispose(() {
      _esperandoElFinal?.cancel();
      altavoz.alVaciarse = null;
      _deAudio?.cancel();
      _deDescartes?.cancel();
    });

    return Reproduccion.callada;
  }

  /// La conversación que está abierta, para poder decir de cuál es lo que suena.
  ///
  /// Se apunta y no se deduce: el teléfono puede tener varias en el espejo y solo la
  /// que está en pantalla es la que habla.
  void mirando(String conversationId) => _deQuien = conversationId;

  /// El usuario calló la respuesta y sigue leyendo. **No cancela el turno.**
  ///
  /// Se corta aquí **y** se le dice al Mac: cortarlo solo aquí dejaría al Mac gastando
  /// canal en audio que nadie va a oír, y decírselo solo a él dejaría sonando lo que ya
  /// venía en vuelo.
  Future<void> callar() async {
    if (state == Reproduccion.silenciada) return;
    state = Reproduccion.silenciada;
    _esperandoElFinal?.cancel();
    _esperandoElFinal = null;
    await ref.read(altavozProvider).tirar();
    await _avisar(RemoteMethod.silenceReply);
  }

  /// Vuelve a dejar sonar. La siguiente respuesta se oye: callar es de **esta**, no un
  /// ajuste que se queda puesto — un teléfono que se quedara mudo para siempre por un
  /// toque sería peor que uno que no calla.
  void volverAOir() {
    if (state == Reproduccion.silenciada) state = Reproduccion.callada;
  }

  void _cerrarElMicrofono() {
    final id = _deQuien;
    if (id == null) return;
    final voz = ref.read(vozProvider);
    if (voz != Voz.hablando && voz != Voz.abriendo) return;
    unawaited(ref.read(vozProvider.notifier).soltar(id));
  }

  Future<void> _avisar(RemoteMethod metodo) async {
    final id = _deQuien;
    if (id == null) return;
    try {
      await ref
          .read(channelLinkProvider)
          .pedir(metodo, params: {'conversation': id});
    } on LinkError catch (error) {
      // Se anota y no se reintenta a mano: la cola del enlace ya reintenta lo que hay
      // que reintentar, y de estos dos solo `silenceReply` lo es.
      debugPrint('no pude avisar de ${metodo.name}: $error');
    }
  }
}

final reproduccionProvider =
    NotifierProvider<ReproduccionController, Reproduccion>(
      ReproduccionController.new,
    );
