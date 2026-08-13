import 'package:flutter/foundation.dart';

/// Los tres datos que el HUD enseña arriba a la derecha: qué modelo, cuántos
/// tokens y cuánto contexto lleva ocupado.
///
/// El diseño los llama «datos honestos» y ese es justo el punto: los mockups
/// llegaron a decir `claude-4-sonnet` cuando ya no existía. Aquí el modelo es
/// **el que reporta el CLI**, y los tokens los que devuelve su `usage` — nada
/// se escribe a mano.
@immutable
class SessionMeter {
  const SessionMeter({this.model, this.turnTokens, this.contextTokens});

  final String? model;
  final int? turnTokens;
  final int? contextTokens;

  /// El identificador trae variantes entre corchetes —`claude-opus-5[1m]`— que
  /// dicen el tamaño de ventana, no el modelo. Para leerlo de un vistazo
  /// sobra, así que se enseña limpio y el corchete se usa para la ventana.
  String? get displayModel {
    final value = model;
    if (value == null) return null;
    final bracket = value.indexOf('[');
    return bracket == -1 ? value : value.substring(0, bracket);
  }

  /// Ventana de contexto del modelo, en tokens.
  ///
  /// Se deduce del propio identificador: la variante `[1m]` es la de un millón
  /// y el resto de la familia usa 200k. Si algún día cambia, este es el único
  /// sitio que hay que tocar — y por eso el porcentaje no se enseña cuando no
  /// hay dato de tokens, en vez de dibujar un cero tranquilizador.
  int get contextWindow =>
      (model?.contains('[1m]') ?? false) ? 1000000 : 200000;

  int? get contextPercent {
    final used = contextTokens;
    if (used == null || used <= 0) return null;
    return ((used / contextWindow) * 100).round();
  }

  /// Cuánto de la ventana va ocupado, de 0 a 1. Lo que llena el círculo.
  double get contextFraction {
    final used = contextTokens;
    if (used == null || used <= 0) return 0;
    return (used / contextWindow).clamp(0.0, 1.0);
  }

  /// `63,3k / 1,0M (6 %)`.
  ///
  /// Las tres cifras juntas y no solo el porcentaje: un 6 % no dice si te queda
  /// margen para pegar un archivo entero — depende de si la ventana es de 200k
  /// o de un millón, y eso cambia con el modelo que tenga puesto la carpeta.
  String? get contextLabel {
    final used = contextTokens;
    if (used == null || used <= 0) return null;
    return '${_short(used)} / ${_short(contextWindow)} '
        '(${contextPercent ?? 0} %)';
  }

  /// `63,3k`, `1,0M`. La coma decimal es la española, como en el resto del HUD.
  static String _short(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1).replaceAll('.', ',')}M';
    }
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
    }
    return '$tokens';
  }

  /// `12,4k` como en el mockup: la coma decimal es la española.
  String? get tokensLabel {
    final tokens = turnTokens;
    if (tokens == null || tokens <= 0) return null;
    if (tokens < 1000) return '$tokens';
    return '${(tokens / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
  }

  SessionMeter copyWith({String? model, int? turnTokens, int? contextTokens}) {
    return SessionMeter(
      model: model ?? this.model,
      turnTokens: turnTokens ?? this.turnTokens,
      contextTokens: contextTokens ?? this.contextTokens,
    );
  }
}
