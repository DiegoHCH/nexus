import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_chrome.dart';

/// Escribir la dirección y el token a mano.
///
/// **No es el plan B: es la misma ruta.** El QR transporta estos dos valores y nada
/// más, así que las dos producen el mismo emparejamiento y validan con la misma
/// función — el escáner solo ahorra teclear.
///
/// Y por eso se ve igual. La primera versión estaba hecha con Material —`FilledButton`,
/// campos con la línea de Material y un icono de pegar en cada uno— mientras la
/// pantalla de escanear seguía el sistema del proyecto: **dos pantallas de la misma
/// app, a un toque de distancia y con dos lenguajes distintos, se leen como dos apps**.
///
/// Los iconos de pegar se fueron con el rediseño y no se echan de menos: una pulsación
/// larga sobre el campo ya da el menú de pegar del sistema, que además es el gesto que
/// la gente ya conoce. El icono ocupaba sitio para ofrecer algo que ya estaba.
class PairingPage extends ConsumerStatefulWidget {
  const PairingPage({super.key});

  @override
  ConsumerState<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends ConsumerState<PairingPage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  PairingProblem? _problema;
  var _guardando = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  /// El aviso de Tailscale se calcula **mientras escribe**, no al guardar: llegar a
  /// «no conecta» y enterarse entonces es el camino largo.
  bool get _avisoDeTailscale {
    final leido = leerEmparejamiento(url: _url.text, token: _token.text);
    final pareja = leido.emparejamiento;
    return pareja != null && fueraDeTailscale(pareja.url);
  }

  Future<void> _emparejar() async {
    setState(() => _guardando = true);
    final problema = await ref
        .read(pairingControllerProvider.notifier)
        .emparejar(url: _url.text, token: _token.text);
    if (!mounted) return;
    setState(() {
      _problema = problema;
      _guardando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.void_,
      body: SafeArea(
        child: SingleChildScrollView(
          // Con scroll: al abrir el teclado, dos campos y un botón no caben en una
          // pantalla de 390 y el aviso de Tailscale se quedaba fuera justo cuando
          // aparecía.
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.s5,
            vertical: NexusSpacing.s4,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.vertical -
                  NexusSpacing.s8,
            ),
            child: Column(
              children: [
                const SizedBox(height: NexusSpacing.s5),
                Text(
                  'ESCRIBIR EL CÓDIGO A MANO',
                  style: NexusTypography.label.copyWith(color: colors.mute),
                ),
                const SizedBox(height: NexusSpacing.s5),
                Text(
                  'En el Mac: Ajustes → Móvil. Enciende el canal y copia la '
                  'dirección y el token.',
                  textAlign: TextAlign.center,
                  style: NexusTypography.subtitleMobile.copyWith(
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: NexusSpacing.s7),
                MobileField(
                  key: const ValueKey('campo-url'),
                  etiqueta: 'Dirección',
                  pista: '100.x.y.z:7845',
                  controlador: _url,
                  alEscribir: () => setState(() => _problema = null),
                ),
                const SizedBox(height: NexusSpacing.s5),
                MobileField(
                  key: const ValueKey('campo-token'),
                  etiqueta: 'Token',
                  pista: '43 caracteres',
                  controlador: _token,
                  alEscribir: () => setState(() => _problema = null),
                ),
                if (_problema != null) ...[
                  const SizedBox(height: NexusSpacing.s4),
                  _Aviso(
                    key: const ValueKey('problema'),
                    color: colors.err,
                    texto: _decir(_problema!),
                  ),
                ],
                if (_problema == null && _avisoDeTailscale) ...[
                  const SizedBox(height: NexusSpacing.s4),
                  _Aviso(
                    key: const ValueKey('aviso-tailscale'),
                    color: colors.warn,
                    // Avisa y **no bloquea**: el Mac solo escucha en Tailscale, así
                    // que esta dirección probablemente no conecte — pero quien tenga
                    // otro montaje sabe más que esta comprobación.
                    texto:
                        'Esa dirección no parece de Tailscale, y el Mac solo escucha '
                        'ahí. Puedes seguir, pero probablemente no conecte.',
                  ),
                ],
                // **Sin `Spacer` aquí.** Es un `Expanded`, y un `Expanded` dentro de
                // algo que hace scroll es una contradicción: el scroll ofrece altura
                // infinita y el flex quiere repartir la que sobra. Es el mismo fallo
                // que rompió la pantalla de Ajustes hace un rato — y lo repetí.
                const SizedBox(height: NexusSpacing.s8),
                WideAction(
                  key: const ValueKey('emparejar'),
                  texto: _guardando ? 'Guardando…' : 'Emparejar',
                  principal: true,
                  alTocar: _guardando ? null : _emparejar,
                ),
                const SizedBox(height: NexusSpacing.s4),
                Text(
                  'El teléfono no ejecuta nada:\ntodo corre en el Mac y se muestra '
                  'aquí.',
                  textAlign: TextAlign.center,
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _decir(PairingProblem problema) => switch (problema) {
    PairingProblem.urlIlegible => 'Esa dirección no se entiende.',
    PairingProblem.esquemaEquivocado =>
      'Eso parece la dirección de una web, no la del canal.',
    PairingProblem.faltaElPuerto =>
      'Falta el puerto. El canal escucha en el 7845.',
    PairingProblem.tokenCorto => 'Ese token está incompleto.',
    // No se ve escribiendo a mano —esto viene del escáner— pero el `switch` es
    // exhaustivo a propósito: un caso nuevo obliga a decidir qué se dice, en vez de
    // caer en un «error» genérico que nadie escribió.
    PairingProblem.noEsDeNexus => 'Ese código no es de Nexus.',
  };
}

class _Aviso extends StatelessWidget {
  const _Aviso({super.key, required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NexusSpacing.s3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        // 2px como todo lo demás: el radio grande de la primera versión era de
        // Material y se veía prestado al lado de la pantalla de escanear.
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(texto, style: NexusTypography.mono.copyWith(color: color)),
    );
  }
}
