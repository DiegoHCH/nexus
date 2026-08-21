import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';

/// Emparejar a mano: pegar la dirección y el token.
///
/// Es la primera forma y no un apaño mientras llega el QR. El QR transporta estos
/// mismos dos valores, así que lo que ahorra es teclear — y no se puede construir
/// antes de que exista esta pantalla, porque comprobarlo exige una cámara apuntando
/// a un Mac.
///
/// Los dos valores se copian de Ajustes → Móvil en el escritorio, que ya enseña la
/// dirección como texto seleccionable y tiene botón de copiar el token.
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
  /// «no conecta» y entonces enterarse es el camino largo.
  bool get _avisoDeTailscale {
    final leido = leerEmparejamiento(url: _url.text, token: _token.text);
    final pareja = leido.emparejamiento;
    return pareja != null && fueraDeTailscale(pareja.url);
  }

  Future<void> _pegarEn(TextEditingController campo) async {
    final datos = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = datos?.text;
    if (texto == null || texto.isEmpty) return;
    campo.text = texto.trim();
    setState(() => _problema = null);
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
    final texto = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.void_,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Emparejar con tu Mac',
                style: texto.headlineSmall?.copyWith(color: colors.ink),
              ),
              const SizedBox(height: 10),
              Text(
                'En el Mac: Ajustes → Móvil. Enciende el canal, copia la dirección '
                'y el token.',
                style: texto.bodyMedium?.copyWith(color: colors.mute),
              ),
              const SizedBox(height: 32),
              _Campo(
                key: const ValueKey('campo-url'),
                etiqueta: 'Dirección',
                pista: 'ws://100.x.y.z:7845',
                controlador: _url,
                alPegar: () => _pegarEn(_url),
                alEscribir: () => setState(() => _problema = null),
              ),
              const SizedBox(height: 20),
              _Campo(
                key: const ValueKey('campo-token'),
                etiqueta: 'Token',
                pista: '43 caracteres',
                controlador: _token,
                // **No se oculta con puntos.** Aquí hay que poder ver que se pegó
                // entero, y quien mira la pantalla es quien acaba de copiarlo de su
                // propio Mac. Ocultarlo protegería de nadie y estorbaría siempre.
                alPegar: () => _pegarEn(_token),
                alEscribir: () => setState(() => _problema = null),
              ),
              if (_problema != null) ...[
                const SizedBox(height: 20),
                _Aviso(
                  key: const ValueKey('problema'),
                  color: colors.err,
                  texto: _decir(_problema!),
                ),
              ],
              if (_problema == null && _avisoDeTailscale) ...[
                const SizedBox(height: 20),
                _Aviso(
                  key: const ValueKey('aviso-tailscale'),
                  color: colors.warn,
                  // Avisa y **no bloquea**: el Mac solo escucha en Tailscale, así
                  // que esta dirección probablemente no conecte — pero quien tenga
                  // otro montaje sabe más que esta comprobación.
                  texto: 'Esa dirección no parece de Tailscale, y el Mac solo '
                      'escucha ahí. Puedes seguir, pero probablemente no conecte.',
                ),
              ],
              const SizedBox(height: 32),
              FilledButton(
                key: const ValueKey('emparejar'),
                onPressed: _guardando ? null : _emparejar,
                child: Text(_guardando ? 'Guardando…' : 'Emparejar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _decir(PairingProblem problema) => switch (problema) {
    PairingProblem.urlIlegible => 'Esa dirección no se entiende.',
    PairingProblem.esquemaEquivocado =>
      'Tiene que empezar por ws:// — el canal no es una página web.',
    PairingProblem.faltaElPuerto =>
      'Falta el puerto. El canal escucha en el 7845.',
    PairingProblem.tokenCorto => 'Ese token está incompleto.',
  };
}

class _Campo extends StatelessWidget {
  const _Campo({
    super.key,
    required this.etiqueta,
    required this.pista,
    required this.controlador,
    required this.alPegar,
    required this.alEscribir,
  });

  final String etiqueta;
  final String pista;
  final TextEditingController controlador;
  final VoidCallback alPegar;
  final VoidCallback alEscribir;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.mute,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controlador,
                onChanged: (_) => alEscribir(),
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(color: colors.ink, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: pista,
                  hintStyle: TextStyle(color: colors.faint),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Pegar tiene su propio botón porque **es la única forma real de
            // rellenar esto**: nadie teclea 43 caracteres al azar, y el menú de
            // pegar del sistema pide una pulsación larga que no se ve.
            IconButton(
              onPressed: alPegar,
              icon: const Icon(Icons.content_paste),
              tooltip: 'Pegar',
              color: colors.accent,
            ),
          ],
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({super.key, required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        texto,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}
