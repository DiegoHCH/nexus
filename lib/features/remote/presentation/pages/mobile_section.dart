import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/remote/presentation/providers/channel_providers.dart';
import 'package:nexus/features/remote/presentation/providers/channel_token_providers.dart';
import 'package:nexus/features/remote/presentation/providers/write_phrase_providers.dart';

/// El canal del teléfono: encenderlo, ver dónde escucha, y rotar el token.
///
/// Esta sección estaba **listada y apagada** desde el principio, como recordatorio de
/// una fase que no existía. Ya existe entera: el canal se enciende, acepta conexiones,
/// atiende peticiones y cuenta lo que pasa, y hay una app de teléfono que habla con él.
///
/// Lo que se dice aquí ahora es **lo que hace falta para usarla** —emparejar pegando
/// estos dos valores, y Tailscale en los dos aparatos— porque eso es lo que la primera
/// prueba real demostró que faltaba decir: sin Tailscale en el teléfono el paquete no
/// sale del wifi, y la pantalla del móvil solo podía decir «reconectando».
class MobileSection extends ConsumerWidget {
  const MobileSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final estado = ref.watch(channelControllerProvider);
    final control = ref.read(channelControllerProvider.notifier);

    // **El scroll, aquí y solo aquí.** El primer intento fue envolver el hueco donde
    // Ajustes pinta cualquier seccion, y eso rompio las que llenan el alto a
    // proposito —historial, permisos, voz, superpoderes usan `Expanded` en su raiz—:
    // un `Expanded` dentro de algo que hace scroll es una contradiccion, y Flutter la
    // rechaza. El arreglo estrecho es el correcto: esta seccion creció hasta no caber,
    // y es la unica que se corta.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.channelTitle,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s2),
          Text(
            strings.channelExplainer,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s5),
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.channelSwitch,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
              ),
              Switch(
                key: const ValueKey('interruptor-del-canal'),
                value: estado is ChannelOn || estado is ChannelStarting,
                onChanged: (encender) =>
                    encender ? control.encender() : control.apagar(),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.s5),
          switch (estado) {
            ChannelOff() => const SizedBox.shrink(),
            ChannelStarting() => _Nota(strings.channelStarting),
            final ChannelOn on => _Encendido(url: on.url),
            final ChannelUnavailable no => _Problema(no.reason),
          },
          const SizedBox(height: NexusSpacing.s7),
          const _Frase(),
          const SizedBox(height: NexusSpacing.s7),
          // Dicho sin rodeos y no en letra pequeña al final: quien enciende esto hoy
          // no tiene con qué conectarse.
          Container(
            decoration: BoxDecoration(
              color: colors.deep,
              border: Border.all(color: colors.rule),
              borderRadius: BorderRadius.circular(NexusRadius.sm),
            ),
            padding: const EdgeInsets.all(NexusSpacing.s5),
            child: Text(
              strings.channelNoPhoneYet,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dónde escucha, y el token para llegar.
class _Encendido extends ConsumerWidget {
  const _Encendido({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final token = ref.watch(channelTokenControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.channelListeningAt,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        SelectableText(
          url,
          key: const ValueKey('direccion-del-canal'),
          style: NexusTypography.mono.copyWith(color: colors.accent),
        ),
        const SizedBox(height: NexusSpacing.s5),
        Text(
          strings.channelToken,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        // **La huella y no el token.** Se enseña entero solo al copiarlo, porque
        // esta pantalla se comparte en capturas y en pantallas compartidas más de
        // lo que parece — y un secreto de 43 caracteres a la vista es un secreto
        // que ya viajó.
        Row(
          children: [
            Text(
              token.value?.fingerprint ?? '—',
              style: NexusTypography.mono.copyWith(color: colors.mute),
            ),
            const SizedBox(width: NexusSpacing.s4),
            if (token.value case final actual?)
              TextButton(
                key: const ValueKey('copiar-el-token'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: actual.value)),
                child: Text(strings.channelCopyToken),
              ),
            TextButton(
              key: const ValueKey('rotar-el-token'),
              onPressed: ref
                  .read(channelControllerProvider.notifier)
                  .rotarToken,
              child: Text(strings.channelRotateToken),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.channelRotateWarning,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
      ],
    );
  }
}

class _Problema extends StatelessWidget {
  const _Problema(this.reason);

  final ChannelProblem reason;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    return Container(
      key: const ValueKey('problema-del-canal'),
      decoration: BoxDecoration(
        color: colors.deep,
        border: Border.all(color: colors.warn),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      padding: const EdgeInsets.all(NexusSpacing.s5),
      child: Text(
        // Cada problema con **lo que hay que hacer**, no solo con lo que pasó.
        switch (reason) {
          ChannelProblem.noTailscale => strings.channelNeedsTailscale,
          ChannelProblem.portBusy => strings.channelPortBusy,
          ChannelProblem.unknown => strings.channelUnknownProblem,
        },
        style: NexusTypography.body.copyWith(color: colors.mute),
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
    texto,
    style: NexusTypography.mono.copyWith(color: context.colors.faint),
  );
}

/// La frase de escritura: si existe, y cómo cambiarla. **Nunca cuál es.**
///
/// Ni siquiera su huella, al contrario que el token. El token hay que copiarlo al
/// teléfono alguna vez, así que enseñarlo tiene un para qué; la frase se teclea de
/// memoria y no hay ninguna razón para que aparezca en esta pantalla — que se
/// comparte en capturas más de lo que parece.
class _Frase extends ConsumerWidget {
  const _Frase();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final definida = ref.watch(writePhraseControllerProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.phraseTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.phraseExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s4),
        Row(
          children: [
            // `Expanded` y no un `Spacer` detrás: el texto de «sin definir» es una
            // frase entera, y con ancho libre empujaba los botones fuera de la
            // columna —desbordaba 14 px, lo dijo la prueba que abre las secciones
            // antes de que nadie lo viera—. Así el texto cede y los botones se
            // quedan donde tienen que estar.
            Expanded(
              child: Text(
                definida ? strings.phraseDefined : strings.phraseMissing,
                key: const ValueKey('estado-de-la-frase'),
                style: NexusTypography.data.copyWith(
                  // Sin frase no es un error —es el estado por defecto y el
                  // seguro— así que se dice en el tono de un dato, no de una
                  // advertencia.
                  color: definida ? colors.ink : colors.mute,
                ),
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            if (definida)
              TextButton(
                key: const ValueKey('quitar-la-frase'),
                onPressed: ref
                    .read(writePhraseControllerProvider.notifier)
                    .borrar,
                child: Text(strings.phraseRemove),
              ),
            TextButton(
              key: const ValueKey('definir-la-frase'),
              onPressed: () => _PhraseDialog.open(context),
              child: Text(
                definida ? strings.phraseChange : strings.phraseDefine,
              ),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.phraseChangeWarning,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
      ],
    );
  }
}

/// Donde se teclea. Con el mínimo comprobado **antes** de guardar, y dicho al
/// intentarlo en vez de como advertencia previa: una regla que se lee antes de
/// escribir se olvida al escribir.
class _PhraseDialog extends ConsumerStatefulWidget {
  const _PhraseDialog();

  static Future<void> open(BuildContext context) =>
      showDialog<void>(context: context, builder: (_) => const _PhraseDialog());

  @override
  ConsumerState<_PhraseDialog> createState() => _PhraseDialogState();
}

class _PhraseDialogState extends ConsumerState<_PhraseDialog> {
  final _campo = TextEditingController();
  bool _corta = false;

  /// Si se está viendo la frase. **Nace tapada**: se destapa a propósito, no por
  /// defecto — que es lo que hace que el ojo sea una ayuda y no una fuga.
  bool _visible = false;

  @override
  void dispose() {
    // Se limpia a mano: el texto es un secreto y no tiene por qué seguir en
    // memoria después de cerrar la modal.
    _campo.clear();
    _campo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final vale = await ref
        .read(writePhraseControllerProvider.notifier)
        .definir(_campo.text);
    if (!vale) {
      setState(() => _corta = true);
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;

    return Dialog(
      backgroundColor: colors.rise,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.rule2),
        borderRadius: BorderRadius.circular(NexusRadius.md),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(NexusSpacing.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.phraseTitle,
                style: NexusTypography.subtitle.copyWith(color: colors.ink),
              ),
              const SizedBox(height: NexusSpacing.s5),
              TextField(
                key: const ValueKey('campo-de-la-frase'),
                controller: _campo,
                autofocus: true,
                obscureText: !_visible,
                onSubmitted: (_) => _guardar(),
                style: NexusTypography.mono.copyWith(color: colors.ink),
                decoration: InputDecoration(
                  // **El ojo hace falta justo aquí y no en el teléfono.** Esta es la
                  // pantalla donde la frase se *define*: teclearla a ciegas y
                  // equivocarse deja una frase que después no se puede averiguar —el
                  // Mac la guarda y no la vuelve a enseñar—, así que la única salida
                  // sería redefinirla sin saber que eso era lo que pasaba. En el móvil
                  // se teclea una ya conocida, y allí sí conviene taparla: se teclea a
                  // veces delante de gente.
                  suffixIcon: IconButton(
                    key: const ValueKey('ver-la-frase'),
                    onPressed: () => setState(() => _visible = !_visible),
                    icon: Icon(
                      _visible ? Icons.visibility_off : Icons.visibility,
                      size: 17,
                    ),
                    color: colors.mute,
                  ),
                ),
              ),
              if (_corta) ...[
                const SizedBox(height: NexusSpacing.s3),
                Text(
                  strings.phraseTooShort,
                  key: const ValueKey('frase-corta'),
                  style: NexusTypography.mono.copyWith(color: colors.warn),
                ),
              ],
              const SizedBox(height: NexusSpacing.s6),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(strings.cancel),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('guardar-la-frase'),
                    onPressed: _guardar,
                    child: Text(strings.phraseSave),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
