import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/features/remote/presentation/providers/mirror_providers.dart';

/// Abrir la escritura con la frase.
///
/// Es la decisión 2.4 del contrato, ya corregida: el diseño original pedía confirmar
/// **en el escritorio**, y eso volvía imposible el caso principal —estando fuera no
/// hay nadie delante del Mac—. La frase cumple el requisito de verdad, exigir algo
/// que quien robe el teléfono no tenga, sin exigir además tu presencia.
///
/// **El teléfono no la guarda nunca.** Se teclea cuando hace falta y la verifica el
/// Mac; eso es lo que hace que llevarse el teléfono no baste para escribir.
Future<void> mostrarFraseDeEscritura(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.deep,
      isScrollControlled: true,
      builder: (_) => const _Hoja(),
    );

class _Hoja extends ConsumerStatefulWidget {
  const _Hoja();

  @override
  ConsumerState<_Hoja> createState() => _HojaState();
}

class _HojaState extends ConsumerState<_Hoja> {
  final _frase = TextEditingController();
  String? _codigo;
  var _probando = false;

  @override
  void dispose() {
    _frase.dispose();
    super.dispose();
  }

  Future<void> _probar() async {
    setState(() => _probando = true);
    final codigo = await ref
        .read(writePermissionProvider.notifier)
        .abrir(_frase.text);
    if (!mounted) return;
    setState(() {
      _codigo = codigo;
      _probando = false;
    });
    if (codigo == null) Navigator.of(context).pop();
  }

  /// Cada código dice **algo distinto que hacer**. Un solo «no se pudo» dejaría a
  /// quien lo lee sin saber si teclear otra vez, ir al Mac, o esperar.
  String _decir(String codigo) => switch (codigo) {
    'noPhrase' => 'No hay frase definida. Ponla en el Mac: Ajustes → Móvil.',
    'wrongPhrase' => 'Esa no es la frase.',
    'tooManyAttempts' => 'Demasiados intentos. Prueba en unos minutos.',
    _ => 'No se pudo abrir la escritura.',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texto = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Abrir la escritura',
            style: texto.titleMedium?.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Tu frase no se guarda en el teléfono. La comprueba el Mac, y la '
            'ventana dura 30 minutos.',
            style: texto.bodySmall?.copyWith(color: colors.mute),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('frase'),
            controller: _frase,
            // **Oculta, al contrario que el token.** El token se pega desde tu propio
            // Mac y hay que ver que entró entero; la frase se teclea, y se teclea a
            // veces delante de gente.
            obscureText: true,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: colors.ink),
            onSubmitted: (_) => _probar(),
            decoration: const InputDecoration(hintText: 'Tu frase'),
          ),
          if (_codigo != null) ...[
            const SizedBox(height: 14),
            Text(
              _decir(_codigo!),
              key: const ValueKey('fallo-de-la-frase'),
              style: texto.bodySmall?.copyWith(color: colors.err),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('abrir-escritura'),
            onPressed: _probando ? null : _probar,
            child: Text(_probando ? 'Comprobando…' : 'Abrir'),
          ),
        ],
      ),
    );
  }
}
