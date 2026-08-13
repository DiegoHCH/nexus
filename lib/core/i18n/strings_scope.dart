import 'package:flutter/widgets.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';

/// Deja los textos colgando del árbol, para que cualquier widget los alcance
/// con `context.strings` sin tener que ser un `Consumer`.
///
/// La mitad de la interfaz son `StatelessWidget` de adorno —una fila de la
/// columna de actividad, una etiqueta— y convertirlos todos en consumidores de
/// Riverpod para leer una palabra sería pagar mucho por poco.
class StringsScope extends InheritedWidget {
  const StringsScope({super.key, required this.strings, required super.child});

  final NexusStrings strings;

  static NexusStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StringsScope>();
    assert(scope != null, 'Falta un StringsScope por encima de este widget');
    return scope!.strings;
  }

  @override
  bool updateShouldNotify(StringsScope oldWidget) =>
      strings.runtimeType != oldWidget.strings.runtimeType;
}

extension StringsContext on BuildContext {
  NexusStrings get strings => StringsScope.of(this);
}
