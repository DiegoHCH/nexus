import 'package:flutter/material.dart';

/// Tokens de color de Nexus, tomados de `nexus-ui-mockups.html`.
///
/// Un solo acento (`cyan`): los colores de estado (`ok`/`warn`/`err`) son
/// señal, nunca decoración ni énfasis. Se expone como [ThemeExtension] para
/// que el resto de la app nunca hardcodee un color y el tema claro/oscuro
/// se resuelva solo con `Theme.of(context)`.
@immutable
class NexusColors extends ThemeExtension<NexusColors> {
  const NexusColors({
    required this.void_,
    required this.deep,
    required this.rise,
    required this.rule,
    required this.rule2,
    required this.ink,
    required this.mute,
    required this.faint,
    required this.cyan,
    required this.ok,
    required this.warn,
    required this.err,
    required this.scrim,
    required this.shadow,
  });

  /// Fondo casi negro con matiz azul (`--void`).
  final Color void_;

  /// Superficie (`--deep`).
  final Color deep;

  /// Superficie elevada: campos, paneles (`--rise`).
  final Color rise;

  /// Hairline tenue (`--rule`).
  final Color rule;

  /// Hairline visible (`--rule-2`).
  final Color rule2;

  /// Texto primario (`--ink`).
  final Color ink;

  /// Texto secundario (`--mute`).
  final Color mute;

  /// Texto terciario (`--faint`).
  final Color faint;

  /// Acento único: el cian del orbe (`--cyan`).
  final Color cyan;

  /// Señal de estado correcto (`--ok`).
  final Color ok;

  /// Señal de estado de atención (`--warn`).
  final Color warn;

  /// Señal de estado de error (`--err`).
  final Color err;

  /// Velo tras el que se atenúa contenido, p.ej. detrás de la barra
  /// superior (`--scrim`).
  final Color scrim;

  /// Color base para sombras de superficies elevadas (`--shadow`).
  final Color shadow;

  static const dark = NexusColors(
    void_: Color(0xFF04070D),
    deep: Color(0xFF080C15),
    rise: Color(0xFF0D1420),
    rule: Color(0xFF17202E),
    rule2: Color(0xFF222E40),
    ink: Color(0xFFE4EDF6),
    mute: Color(0xFF8496AD),
    faint: Color(0xFF54637A),
    cyan: Color(0xFF56E1EA),
    ok: Color(0xFF57C98A),
    warn: Color(0xFFE3B25C),
    err: Color(0xFFF06A62),
    scrim: Color(0xB8040710),
    shadow: Color(0xE6000000),
  );

  /// El tema claro no es una inversión automática del oscuro: el cian baja
  /// a `#0C7C88` por contraste AA y las señales de estado se oscurecen para
  /// seguir siendo legibles sobre fondo claro.
  static const light = NexusColors(
    void_: Color(0xFFE9EEF5),
    deep: Color(0xFFFFFFFF),
    rise: Color(0xFFF4F7FB),
    rule: Color(0xFFDCE4EE),
    rule2: Color(0xFFC3CEDC),
    ink: Color(0xFF08101C),
    mute: Color(0xFF4A5768),
    faint: Color(0xFF78869A),
    cyan: Color(0xFF0C7C88),
    ok: Color(0xFF1F7D51),
    warn: Color(0xFF8A6110),
    err: Color(0xFFB3352C),
    scrim: Color(0xB8E9EEF5),
    shadow: Color(0x730A192D),
  );

  @override
  NexusColors copyWith({
    Color? void_,
    Color? deep,
    Color? rise,
    Color? rule,
    Color? rule2,
    Color? ink,
    Color? mute,
    Color? faint,
    Color? cyan,
    Color? ok,
    Color? warn,
    Color? err,
    Color? scrim,
    Color? shadow,
  }) {
    return NexusColors(
      void_: void_ ?? this.void_,
      deep: deep ?? this.deep,
      rise: rise ?? this.rise,
      rule: rule ?? this.rule,
      rule2: rule2 ?? this.rule2,
      ink: ink ?? this.ink,
      mute: mute ?? this.mute,
      faint: faint ?? this.faint,
      cyan: cyan ?? this.cyan,
      ok: ok ?? this.ok,
      warn: warn ?? this.warn,
      err: err ?? this.err,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  NexusColors lerp(ThemeExtension<NexusColors>? other, double t) {
    if (other is! NexusColors) return this;
    return NexusColors(
      void_: Color.lerp(void_, other.void_, t)!,
      deep: Color.lerp(deep, other.deep, t)!,
      rise: Color.lerp(rise, other.rise, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      rule2: Color.lerp(rule2, other.rule2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      mute: Color.lerp(mute, other.mute, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      err: Color.lerp(err, other.err, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension NexusColorsContext on BuildContext {
  /// Acceso corto: `context.colors.cyan`.
  NexusColors get colors => Theme.of(this).extension<NexusColors>()!;
}
