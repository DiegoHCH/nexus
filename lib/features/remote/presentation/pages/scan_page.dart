import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:nexus/features/remote/domain/pairing_code.dart';
import 'package:nexus/features/remote/domain/tailscale.dart';
import 'package:nexus/features/remote/presentation/pages/pairing_page.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/widgets/corner_frame.dart';

/// Si este teléfono está en Tailscale, y con qué dirección.
///
/// Ocupa el sitio donde el mockup pone «Mac detectado en la red · 192.168.1.42». Eso
/// era descubrimiento por red local, que la decisión `lo1` descartó — pero el hueco
/// merece llevar algo cierto, y esto lo es: **es la comprobación que faltaba**. La
/// primera vez que se probó el canal de verdad, el teléfono no tenía Tailscale y la
/// pantalla solo podía decir «reconectando» sin fin. Aquí se ve antes de escanear.
final tailscaleDelTelefonoProvider = FutureProvider<String?>((ref) async {
  final dir = await Tailscale.buscar();
  return dir?.address;
});

/// Emparejar apuntando al código del Mac.
///
/// Sigue la **forma** del mockup Móvil 01 —rótulo arriba, la frase centrada, el visor
/// con escuadras, el chip, el dato en mono, el botón ancho abajo y el pie— y **no su
/// mecanismo**: allí hay descubrimiento por red local y aquí solo hay Tailscale.
///
/// **Escribirlo a mano no es el plan B: es la misma ruta.** Las dos producen el mismo
/// emparejamiento y validan con la misma función, así que el escáner solo ahorra
/// teclear 43 caracteres.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final _camara = MobileScannerController(
    // Solo QR. Con todos los formatos activos, el código de barras de un producto en
    // la mesa dispara una lectura que hay que descartar — y cada descarte es un
    // mensaje de error que nadie pidió.
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Se para en cuanto uno vale: sin esto la cámara sigue leyendo mientras la pantalla
  /// navega, y llegan tres emparejamientos iguales.
  var _yaVale = false;
  PairingProblem? _problema;

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  Future<void> _leido(BarcodeCapture captura) async {
    if (_yaVale) return;
    final texto = captura.barcodes.firstOrNull?.rawValue;
    if (texto == null || texto.isEmpty) return;

    final leido = PairingCode.leer(texto);
    if (leido.problema != null) {
      // Se dice y **se sigue escaneando**: lo más probable es que la cámara viera otro
      // QR de la mesa, y cerrar el escáner por eso obligaría a volver a abrirlo.
      if (mounted) setState(() => _problema = leido.problema);
      return;
    }

    _yaVale = true;
    await _camara.stop();
    final pareja = leido.emparejamiento!;
    await ref
        .read(pairingControllerProvider.notifier)
        .emparejar(url: pareja.url.toString(), token: pareja.token.value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tailscale = ref.watch(tailscaleDelTelefonoProvider);

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
              const SizedBox(height: NexusSpacing.s5),
              // Un rótulo y no un titular: el mockup pone el nombre de la pantalla en
              // mono, mayúsculas y con tracking — la frase de debajo es la que habla.
              Text(
                'EMPAREJAR CON TU MAC',
                style: NexusTypography.label.copyWith(color: colors.mute),
              ),
              const SizedBox(height: NexusSpacing.s5),
              Text(
                'Apunta al código que aparece en la pantalla de tu Mac.',
                textAlign: TextAlign.center,
                style: NexusTypography.subtitleMobile.copyWith(
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: NexusSpacing.s7),
              // El visor cuadrado y con escuadras. Cuadrado porque un QR lo es: un
              // visor ancho invita a encuadrarlo mal.
              SizedBox(
                width: 250,
                height: 250,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        width: 250,
                        height: 250,
                        child: MobileScanner(
                          key: const ValueKey('el-visor'),
                          controller: _camara,
                          onDetect: _leido,
                          errorBuilder: (context, error) =>
                              _SinCamara(error: error),
                        ),
                      ),
                    ),
                    const IgnorePointer(child: CornerFrame(lado: 250)),
                  ],
                ),
              ),
              const SizedBox(height: NexusSpacing.s5),
              _Tailscale(estado: tailscale),
              if (_problema != null) ...[
                const SizedBox(height: NexusSpacing.s4),
                Text(
                  _decir(_problema!),
                  key: const ValueKey('problema-del-codigo'),
                  textAlign: TextAlign.center,
                  style: NexusTypography.mono.copyWith(color: colors.warn),
                ),
              ],
              const Spacer(),
              // Ancho y abajo, como en el mockup: es la otra ruta entera, no un
              // enlace de socorro escondido.
              _BotonAncho(
                key: const ValueKey('a-mano'),
                texto: 'Escribir el código a mano',
                alTocar: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PairingPage()),
                ),
              ),
              const SizedBox(height: NexusSpacing.s4),
              Text(
                'El teléfono no ejecuta nada:\ntodo corre en el Mac y se muestra aquí.',
                textAlign: TextAlign.center,
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _decir(PairingProblem problema) => switch (problema) {
    // El caso frecuente, y por eso el mensaje no culpa a nadie: la cámara vio otro
    // código antes que el bueno.
    PairingProblem.noEsDeNexus => 'Ese código no es de Nexus. Sigue apuntando.',
    PairingProblem.tokenCorto => 'El código llegó incompleto. Prueba otra vez.',
    PairingProblem.urlIlegible ||
    PairingProblem.esquemaEquivocado ||
    PairingProblem.faltaElPuerto => 'Ese código de Nexus no se entiende.',
  };
}

/// El chip y el dato del mockup, con lo único que aquí se puede saber de verdad.
class _Tailscale extends StatelessWidget {
  const _Tailscale({required this.estado});

  final AsyncValue<String?> estado;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (texto, dato, vivo) = switch (estado) {
      AsyncData(value: final String dir) => ('TAILSCALE ACTIVO', dir, true),
      // **Sin Tailscale no va a conectar**, y decirlo aquí es lo que evita el
      // «reconectando» sin explicación que costó una tarde de depuración.
      AsyncData() => (
        'SIN TAILSCALE EN ESTE TELÉFONO',
        'instálalo y entra con tu cuenta',
        false,
      ),
      AsyncError() => (
        'NO PUDE COMPROBAR TAILSCALE',
        'se verá al conectar',
        false,
      ),
      _ => ('COMPROBANDO TAILSCALE', '', false),
    };

    return Column(
      children: [
        Container(
          key: const ValueKey('tailscale-del-telefono'),
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.s3,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: vivo ? colors.accent.withValues(alpha: 0.4) : colors.rule2,
            ),
          ),
          child: Text(
            texto,
            style: NexusTypography.label.copyWith(
              color: vivo ? colors.accent : colors.warn,
            ),
          ),
        ),
        if (dato.isNotEmpty) ...[
          const SizedBox(height: NexusSpacing.s2),
          Text(dato, style: NexusTypography.data.copyWith(color: colors.mute)),
        ],
      ],
    );
  }
}

/// El botón ancho del mockup: borde fino, mono, mayúsculas, todo el ancho.
class _BotonAncho extends StatelessWidget {
  const _BotonAncho({super.key, required this.texto, required this.alTocar});

  final String texto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: alTocar,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.rule2),
          ),
          child: Text(
            texto.toUpperCase(),
            style: NexusTypography.label.copyWith(color: colors.mute),
          ),
        ),
      ),
    );
  }
}

/// Cuando no hay cámara o no se da permiso.
///
/// **Es un estado de verdad y no un hueco negro**, que es lo que sale por defecto. El
/// mockup dedica una pantalla entera a «sin micrófono» con esta forma —qué pasó, por
/// qué y qué se puede hacer— y esto es su equivalente para la cámara. La salida
/// existe justo debajo: escribirlo a mano no necesita permisos.
class _SinCamara extends StatelessWidget {
  const _SinCamara({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ColoredBox(
      color: colors.deep,
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.s4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'NO PUEDO USAR LA CÁMARA',
              key: const ValueKey('sin-camara'),
              style: NexusTypography.label.copyWith(color: colors.warn),
            ),
            const SizedBox(height: NexusSpacing.s3),
            Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'No le has dado permiso, así que escribe el código a mano.'
                  : 'Este teléfono no me deja abrirla. Escríbelo a mano.',
              textAlign: TextAlign.center,
              style: NexusTypography.mono.copyWith(color: colors.mute),
            ),
          ],
        ),
      ),
    );
  }
}
