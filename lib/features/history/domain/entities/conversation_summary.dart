import 'package:flutter/foundation.dart';

/// Lo que hace falta saber de una conversación **sin abrirla**: quién la tuvo,
/// cuándo, sobre qué carpeta y cuántos turnos.
///
/// Existe porque listar y leer no cuestan lo mismo. Antes toda la app hablaba
/// de [ConversationRecord], que lleva los mensajes dentro, así que enseñar una
/// lista de treinta conversaciones obligaba a leer y parsear las treinta
/// enteras — y eso pasa **en cada turno**, porque al archivar se refresca la
/// lista. Con esto, la lista cuesta la cabecera de cada nota y el detalle se
/// paga solo al abrir una.
///
/// [ConversationRecord] sigue siendo la conversación de verdad. Esto es su
/// ficha.
@immutable
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.folderPath,
    required this.startedAt,
    required this.title,
    required this.turns,
    this.profileName,
    this.sourcePath,
    this.model,
    this.contextTokens,
  });

  final String id;
  final String folderPath;
  final DateTime startedAt;

  /// Ya resuelto, no deducido al vuelo. Quien escribe la ficha tiene los
  /// mensajes delante; quien la lee, no.
  final String title;

  /// Cuántos mensajes tiene. Es lo que enseña la lista para distinguir «esto
  /// fue una pregunta» de «esto fue una tarde entera».
  final int turns;

  /// Con qué cuenta de Claude se trabajó — `work`, `private`— o `null` con la
  /// de siempre.
  final String? profileName;

  /// El archivo del que se leyó, cuando vino de una carpeta o un vault. Es lo
  /// que distingue una ficha que se completa leyendo una nota del disco de una
  /// que se completa con el almacén de la app.
  final String? sourcePath;

  final String? model;
  final int? contextTokens;

  /// El nombre de la carpeta, que es como se llama el proyecto en todos lados.
  String get projectName => projectNameOf(folderPath);

  /// Compartido con [ConversationRecord]: las dos cosas nombran el proyecto por
  /// la última carpeta de la ruta, y tenerlo escrito dos veces era pedir que un
  /// día dejaran de coincidir.
  static String projectNameOf(String folderPath) {
    final parts = folderPath.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? 'sin-proyecto' : parts.last;
  }
}
