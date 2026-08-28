import 'package:flutter/widgets.dart';
import 'package:nexus/core/i18n/strings/arranque_strings.dart';
import 'package:nexus/core/i18n/strings/documentos_strings.dart';
import 'package:nexus/core/i18n/strings/ejecucion_strings.dart';
import 'package:nexus/core/i18n/strings/estadisticas_strings.dart';
import 'package:nexus/core/i18n/strings/historial_strings.dart';
import 'package:nexus/core/i18n/strings/nucleo_strings.dart';
import 'package:nexus/core/i18n/strings/pruebas_strings.dart';
import 'package:nexus/core/i18n/strings/superpoderes_strings.dart';

/// Todo lo que la interfaz dice, en los dos idiomas.
///
/// Un diccionario con getters y no archivos `.arb` generados, y la razón sigue
/// siendo la misma: **el compilador avisa de lo que falte**. Añadir un texto
/// obliga a traducirlo, y eso no lo da `gen_l10n` gratis. Si algún día hay que
/// traducir a un tercer idioma o meter plurales de verdad, ese es el momento de
/// cambiar, no antes.
///
/// El español manda: es el idioma en que está escrito el producto y en el que se
/// piensan los textos. El inglés se traduce de él.
///
/// ## Por qué está partido
///
/// La premisa que justificaba tenerlo todo en un archivo estaba escrita aquí
/// mismo: «~120 textos de una app de una sola pantalla grande». Hoy son **506**
/// en 3.244 líneas, y era el archivo más grande del repositorio con diferencia.
/// El razonamiento seguía siendo bueno; el número que lo sostenía, no.
///
/// Se parte por lo que ya lo agrupaba —los comentarios de sección que tenía
/// dentro— y **no se cambia ni un texto**. Cada archivo lleva los tres a la vez:
/// lo que se declara y sus dos traducciones. Van juntos porque lo que se rompe
/// es la terna —añadir un texto y olvidar un idioma—, y tenerlos al lado hace
/// que el hueco se vea al escribirlo en vez de al compilar.
///
/// La garantía no cambia: [NexusStringsEs] y [NexusStringsEn] siguen teniendo
/// que implementar [NexusStrings] entera, y eso lo sigue exigiendo el
/// compilador. Un `mixin` al que le falte un texto no compila.
@immutable
abstract class NexusStrings
    with
        NucleoStrings,
        EstadisticasStrings,
        SuperpoderesStrings,
        PruebasStrings,
        DocumentosStrings,
        HistorialStrings,
        EjecucionStrings,
        ArranqueStrings {
  const NexusStrings();

  static const supported = [Locale('es'), Locale('en')];

  static NexusStrings of(Locale locale) => locale.languageCode == 'en'
      ? const NexusStringsEn()
      : const NexusStringsEs();
}

class NexusStringsEs extends NexusStrings
    with
        NucleoStringsEs,
        EstadisticasStringsEs,
        SuperpoderesStringsEs,
        PruebasStringsEs,
        DocumentosStringsEs,
        HistorialStringsEs,
        EjecucionStringsEs,
        ArranqueStringsEs {
  const NexusStringsEs();
}

class NexusStringsEn extends NexusStrings
    with
        NucleoStringsEn,
        EstadisticasStringsEn,
        SuperpoderesStringsEn,
        PruebasStringsEn,
        DocumentosStringsEn,
        HistorialStringsEn,
        EjecucionStringsEn,
        ArranqueStringsEn {
  const NexusStringsEn();
}
