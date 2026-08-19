import 'package:flutter/material.dart';

import 'nexus_colors.dart';
import 'nexus_radius.dart';
import 'nexus_typography.dart';

/// Construye los `ThemeData` claro y oscuro de Nexus a partir de los tokens
/// de [NexusColors] y la escala de [NexusTypography].
///
/// Los componentes propios del HUD (orbe, horizonte, franja de subtítulos)
/// no leen de aquí: leen [NexusColors] y [NexusTypography] directamente vía
/// `context.colors`. Este `ThemeData` es para que los widgets de Material
/// que sí usemos (inputs, scrollbars, tooltips) no desentonen.
abstract final class NexusTheme {
  static final ThemeData _dark = _build(NexusColors.dark, Brightness.dark);
  static final ThemeData _light = _build(NexusColors.light, Brightness.light);

  static ThemeData dark() => _dark;

  static ThemeData light() => _light;

  static ThemeData _build(NexusColors colors, Brightness brightness) {
    // Se especifican los tonos de superficie, `outline` y `tertiary` a mano
    // en vez de dejar que `fromSeed` los derive del cian: si no, widgets que
    // todavía no theming-eamos a propósito (Dialog, SnackBar, Drawer) usan
    // una paleta tonal algorítmica que no coincide con la progresión
    // void/deep/rise del mockup.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colors.cyan,
      brightness: brightness,
      surface: colors.deep,
      onSurface: colors.ink,
      onSurfaceVariant: colors.mute,
      primary: colors.cyan,
      onPrimary: colors.void_,
      primaryContainer: colors.rise,
      onPrimaryContainer: colors.cyan,
      secondary: colors.mute,
      secondaryContainer: colors.rise,
      onSecondaryContainer: colors.mute,
      error: colors.err,
      errorContainer: colors.rise,
      onErrorContainer: colors.err,
      outline: colors.rule2,
      outlineVariant: colors.rule,
      surfaceContainerLowest: colors.void_,
      surfaceContainerLow: colors.deep,
      surfaceContainer: colors.deep,
      surfaceContainerHigh: colors.rise,
      surfaceContainerHighest: colors.rise,
      tertiary: colors.warn,
      onTertiary: colors.void_,
      tertiaryContainer: colors.rise,
      onTertiaryContainer: colors.warn,
      inverseSurface: colors.ink,
      onInverseSurface: colors.void_,
      shadow: colors.shadow,
      scrim: colors.scrim,
      // Sin tinte de elevación: el mockup marca profundidad con hairlines,
      // no con un overlay de color encima de la superficie.
      surfaceTint: Colors.transparent,
    );

    // El sistema de Nexus solo define un estilo de label (10px, mono,
    // tracking .18em): labelMedium y labelSmall comparten esta misma
    // instancia a propósito, no es un duplicado sin querer.
    final labelStyle = NexusTypography.label.copyWith(color: colors.faint);
    final textTheme = TextTheme(
      displayLarge: NexusTypography.hero.copyWith(color: colors.ink),
      displayMedium: NexusTypography.subtitle.copyWith(color: colors.ink),
      displaySmall: NexusTypography.subtitleMobile.copyWith(color: colors.ink),
      headlineMedium: NexusTypography.title.copyWith(color: colors.ink),
      titleMedium: NexusTypography.brand.copyWith(color: colors.mute),
      bodyLarge: NexusTypography.lead.copyWith(color: colors.mute),
      bodyMedium: NexusTypography.body.copyWith(color: colors.ink),
      bodySmall: NexusTypography.mono.copyWith(color: colors.faint),
      labelLarge: NexusTypography.data.copyWith(color: colors.mute),
      labelMedium: labelStyle,
      labelSmall: labelStyle,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.void_,
      canvasColor: colors.void_,
      dividerColor: colors.rule,
      fontFamily: NexusTypography.sansFamily,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      focusColor: colors.cyan,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.void_,
        foregroundColor: colors.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colors.deep,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexusRadius.sm),
          side: BorderSide(color: colors.rule),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.rule,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.rise,
        hintStyle: NexusTypography.mono.copyWith(color: colors.faint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NexusRadius.sm),
          borderSide: BorderSide(color: colors.rule2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NexusRadius.sm),
          borderSide: BorderSide(color: colors.rule2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NexusRadius.sm),
          borderSide: BorderSide(color: colors.cyan, width: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colors.mute),
          textStyle: WidgetStatePropertyAll(NexusTypography.label),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NexusRadius.sm),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colors.mute),
          textStyle: WidgetStatePropertyAll(NexusTypography.label),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          side: WidgetStatePropertyAll(BorderSide(color: colors.rule2)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NexusRadius.sm),
            ),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(colors.cyan),
          foregroundColor: WidgetStatePropertyAll(colors.void_),
          textStyle: WidgetStatePropertyAll(
            NexusTypography.label.copyWith(fontWeight: FontWeight.w600),
          ),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NexusRadius.sm),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.rise,
          borderRadius: BorderRadius.circular(NexusRadius.sm),
          border: Border.all(color: colors.rule2),
        ),
        textStyle: NexusTypography.data.copyWith(color: colors.ink),
      ),
    );
  }
}
