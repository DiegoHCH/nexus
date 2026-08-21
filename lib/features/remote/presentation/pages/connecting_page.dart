import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_chrome.dart';

/// Mientras se busca el Mac.
///
/// El orbe **en `think`** y con horizonte: es el único elemento vivo del sistema, y
/// aquí está haciendo algo de verdad. En un estado de error va dormido —un orbe
/// girando bajo un «se perdió el enlace» promete trabajo que no está pasando— pero
/// esto es exactamente lo contrario: hay trabajo.
class ConnectingPage extends ConsumerWidget {
  const ConnectingPage({super.key, this.alCancelar});

  final VoidCallback? alCancelar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final pareja = ref.watch(pairingControllerProvider).value;

    return Scaffold(
      backgroundColor: colors.void_,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.s5,
            vertical: NexusSpacing.s4,
          ),
          child: Column(
            children: [
              // Mientras esta pantalla está en el aire, lo que afirma es
              // «conectando» — y el chip tiene que decir lo mismo. Si el enlace ya
              // conectó y solo seguimos aquí por el mínimo, el estado real diría
              // `Conectado` debajo de un «buscando tu Mac».
              const MobileChrome(enVezDe: LinkState.conectando),
              const Spacer(),
              // Con horizonte, al contrario que en las demás pantallas del teléfono:
              // el horizonte es lo que convierte al orbe en «trabajando» y no en un
              // adorno girando.
              const SizedBox(
                height: 260,
                child: NexusOrb(state: NexusOrbState.think),
              ),
              const Spacer(),
              Text(
                'BUSCANDO TU MAC',
                style: NexusTypography.label.copyWith(color: colors.mute),
              ),
              const SizedBox(height: NexusSpacing.s3),
              Text(
                // La dirección emparejada, que es el dato de verdad: el mockup pone
                // aquí `macbook-diego.local · red local`, y aquí no hay nombres ni red
                // local — hay una dirección de Tailscale y un puerto.
                pareja?.comoSeVe ?? '—',
                style: NexusTypography.data.copyWith(color: colors.mute),
              ),
              const SizedBox(height: NexusSpacing.s6),
              SizedBox(
                width: double.infinity,
                child: InkWell(
                  key: const ValueKey('cancelar-la-conexion'),
                  onTap: alCancelar,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      vertical: NexusSpacing.s4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: colors.rule2),
                    ),
                    child: Text(
                      'CANCELAR',
                      style: NexusTypography.label.copyWith(color: colors.mute),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: NexusSpacing.s4),
              Text(
                // El mockup dice «comprueba que ambos están en la misma red», que era
                // de cuando había red local. Lo que de verdad hay que comprobar es
                // Tailscale, en los dos aparatos — y es lo que falló la primera vez.
                'Si tarda, comprueba que Tailscale está activo\nen el teléfono y en el Mac.',
                textAlign: TextAlign.center,
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mantiene a su hijo en pantalla un rato mínimo.
///
/// Existe porque **una conexión rápida es un parpadeo**: en la misma red, el handshake
/// tarda menos de lo que dura un fotograma, así que la pantalla de «buscando tu Mac»
/// aparecía y desaparecía sin que se llegara a ver — y lo que queda es un salto raro
/// entre dos pantallas.
///
/// Un retardo artificial es normalmente una mala idea, y aquí hay una razón concreta
/// para hacerlo: el orbe **es** la respuesta a «qué está pasando», y sin tiempo para
/// dar una vuelta no responde nada. Se cuenta desde que se muestra, así que una
/// conexión lenta no espera de más — solo la rápida.
///
/// **Cinco segundos, y solo la primera vez.** El mínimo se arma al mostrarse por
/// primera vez y no se rearma: así se ve la animación completa al abrir la app, y un
/// corte de cobertura a media tarde no arrastra cinco segundos cada vez que vuelve —
/// que es lo que convertiría un detalle bonito en una molestia.
class MinimoEnPantalla extends StatefulWidget {
  const MinimoEnPantalla({
    super.key,
    required this.mostrar,
    required this.child,
    required this.despues,
    this.minimo = const Duration(seconds: 5),
  });

  /// Si la condición sigue pidiendo el hijo.
  final bool mostrar;

  final Widget child;

  /// Lo que va cuando se acaba.
  final Widget despues;

  final Duration minimo;

  @override
  State<MinimoEnPantalla> createState() => _MinimoEnPantallaState();
}

class _MinimoEnPantallaState extends State<MinimoEnPantalla> {
  DateTime? _desde;
  Timer? _reloj;
  var _cumplido = false;

  @override
  void initState() {
    super.initState();
    if (widget.mostrar) _empezar();
  }

  @override
  void didUpdateWidget(MinimoEnPantalla anterior) {
    super.didUpdateWidget(anterior);
    if (widget.mostrar && _desde == null) {
      _empezar();
    } else if (!widget.mostrar && _desde == null) {
      // Nunca hizo falta mostrarlo: no hay mínimo que cumplir.
      _cumplido = true;
    }
  }

  void _empezar() {
    _desde = DateTime.now();
    _cumplido = false;
    _reloj?.cancel();
    _reloj = Timer(widget.minimo, () {
      if (mounted) setState(() => _cumplido = true);
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Se sigue mostrando mientras la condición lo pida **o** mientras no se haya
    // cumplido el mínimo. Las dos cosas: si solo mirara la condición volvería el
    // parpadeo, y si solo mirara el reloj taparía una conexión que sigue fallando.
    if (widget.mostrar || !_cumplido) return widget.child;
    return widget.despues;
  }
}
