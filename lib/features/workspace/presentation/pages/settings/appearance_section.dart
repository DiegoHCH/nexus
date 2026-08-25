import 'package:flutter/material.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/settings_chooser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/design_system/accent_preference.dart';
import 'package:nexus/core/design_system/accent_wheel.dart';
import 'package:nexus/core/design_system/theme_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';

/// Apariencia: claro u oscuro, y el color de acento.
///
/// `AccentDialog` es la única pública: la abre el botón de aquí, pero es una modal
/// que tiene sentido poder abrir desde otro sitio.

/// El idioma de la app — y de lo que te responden.
///
/// Existe porque la regla del proyecto pide español e inglés como mínimo, y
/// hasta ahora la interfaz estaba escrita a mano en español. Cambiarlo aquí
/// cambia también cómo contestan los modelos: una app en inglés con una voz que
/// responde en español sería lo peor de los dos mundos.
/// Claro u oscuro, elegido a mano.
///
/// Va aparte del idioma aunque compartan forma: son dos preferencias de la app
/// y meterlas en la misma pantalla obligaría a leerse una para cambiar la otra.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final choice = ref.watch(themeControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.themeTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.themeExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        SettingsChooser<ThemeChoice>(
          value: choice,
          options: ThemeChoice.values,
          label: (option) => switch (option) {
            ThemeChoice.system => strings.themeSystem,
            ThemeChoice.light => strings.themeLight,
            ThemeChoice.dark => strings.themeDark,
          },
          onSelected: ref.read(themeControllerProvider.notifier).select,
        ),
        const SizedBox(height: NexusSpacing.s7),
        Text(
          strings.accentTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.accentExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        const _AccentButton(),
      ],
    );
  }
}

/// El botón del color: un círculo con el acento puesto.
///
/// Un botón y no la rueda a la vista: la rueda ocupa media pantalla y solo se
/// necesita el rato en que se elige. Aquí queda el color que hay, y se toca para
/// cambiarlo.
///
/// El círculo enseña el tono **con el que se está pintando ahora**, no el que se
/// eligió en la rueda: son distintos —el brillo se ajusta al tema— y enseñar el
/// otro dejaría el botón de un color que no aparece en ningún sitio de la app.
class _AccentButton extends ConsumerWidget {
  const _AccentButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final acento = ref.watch(accentControllerProvider);
    final puesto = acento.forBrightness(Theme.of(context).brightness);

    return Semantics(
      button: true,
      label: '${strings.accentPick}: ${_nombre(acento.name, strings)}',
      child: InkWell(
        key: const ValueKey('abrir-rueda-de-color'),
        onTap: () => AccentDialog.open(context),
        borderRadius: BorderRadius.circular(NexusRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.s3,
            vertical: NexusSpacing.s3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: puesto,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.rule2),
                ),
              ),
              const SizedBox(width: NexusSpacing.s4),
              Text(
                _nombre(acento.name, strings),
                style: NexusTypography.data.copyWith(color: colors.ink),
              ),
              const SizedBox(width: NexusSpacing.s3),
              // El hexadecimal al lado del nombre: el nombre es aproximado —el
              // matiz manda y nombrar un color con exactitud es imposible— y esto
              // es el dato exacto para quien lo quiera.
              Text(
                acento.hex,
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El nombre del acento, del diccionario.
String _nombre(AccentName nombre, NexusStrings strings) => switch (nombre) {
  AccentName.red => strings.accentNameRed,
  AccentName.orange => strings.accentNameOrange,
  AccentName.amber => strings.accentNameAmber,
  AccentName.lime => strings.accentNameLime,
  AccentName.green => strings.accentNameGreen,
  AccentName.emerald => strings.accentNameEmerald,
  AccentName.cyan => strings.accentNameCyan,
  AccentName.blue => strings.accentNameBlue,
  AccentName.indigo => strings.accentNameIndigo,
  AccentName.violet => strings.accentNameViolet,
  AccentName.magenta => strings.accentNameMagenta,
  AccentName.rose => strings.accentNameRose,
  AccentName.grey => strings.accentNameGrey,
};

/// La rueda, en una modal.
///
/// El color se lleva en estado local mientras se arrastra y se confirma **al
/// soltar**, no en cada movimiento. No es por suavidad: cada acento nuevo arma un
/// `ThemeData` entero y lo guarda, así que confirmar en cada píxel del arrastre
/// dejaría cientos de temas en memoria por un solo gesto.
class AccentDialog extends ConsumerStatefulWidget {
  const AccentDialog({super.key});

  static Future<void> open(BuildContext context) =>
      showDialog<void>(context: context, builder: (_) => const AccentDialog());

  @override
  ConsumerState<AccentDialog> createState() => _AccentDialogState();
}

class _AccentDialogState extends ConsumerState<AccentDialog> {
  Color? _arrastrando;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final guardado = ref.watch(accentControllerProvider);
    final actual = _arrastrando ?? guardado.chosen;
    final acento = Accent(actual);

    return Dialog(
      backgroundColor: colors.rise,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.rule2),
        borderRadius: BorderRadius.circular(NexusRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.accentTitle,
              style: NexusTypography.subtitle.copyWith(color: colors.ink),
            ),
            const SizedBox(height: NexusSpacing.s5),
            Center(
              child: AccentWheel(
                value: actual,
                onChanged: (color) => setState(() => _arrastrando = color),
                onSettled: (color) {
                  setState(() => _arrastrando = null);
                  ref.read(accentControllerProvider.notifier).select(color);
                },
              ),
            ),
            const SizedBox(height: NexusSpacing.s5),
            Row(
              children: [
                Text(
                  _nombre(acento.name, strings),
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                const SizedBox(width: NexusSpacing.s3),
                Text(
                  acento.hex,
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
                const Spacer(),
                AccentPreview(accent: acento),
              ],
            ),
            const SizedBox(height: NexusSpacing.s4),
            // Se explica el ajuste **aquí**, junto a las dos muestras: sin esto,
            // elegir un violeta muy oscuro y verlo salir claro en el orbe se lee
            // como que la app ignoró la elección.
            Text(
              strings.accentAdjusted,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
            const SizedBox(height: NexusSpacing.s5),
            Row(
              children: [
                // Solo cuando hay algo que deshacer, como la fila del aviso en el
                // menú de la barra: un botón que casi siempre está apagado es un
                // hueco muerto que hay que leer cada vez para descartarlo.
                if (guardado != Accent.cyan)
                  TextButton(
                    key: const ValueKey('volver-al-color-original'),
                    // El color con el que se instala la app, que es el del icono:
                    // volver a él es volver a que todo case.
                    onPressed: () => ref
                        .read(accentControllerProvider.notifier)
                        .select(Accent.cyan.chosen),
                    child: Text(strings.accentReset),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(strings.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
