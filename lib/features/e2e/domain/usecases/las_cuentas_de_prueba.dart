import '../entities/cuenta_de_pruebas.dart';
import 'los_tags_de_un_flow.dart';

/// Con qué cuenta corre cada flow, y qué hacer cuando no hay ninguna que sirva.
///
/// **La regla sale de `run.sh` del repo, no de una idea nuestra.** Ahí el mapeo es
/// `<clave>|<config>|<tags que corren con esa config>`, y `any` «viaja con la cuenta
/// por defecto: no necesita cuenta, así que no merece una pasada propia». Se copia
/// esa semántica para que una pasada lanzada desde Nexus y otra lanzada desde la
/// terminal elijan lo mismo. Dos criterios distintos para el mismo flow es cómo se
/// acaba discutiendo si un rojo es real.
abstract final class LasCuentasDePrueba {
  /// La etiqueta que significa «me da igual la cuenta».
  static const cualquiera = 'any';

  /// La cuenta con la que hay que correr un flow, según lo que declare su cabecera.
  ///
  /// - Sin cuentas configuradas → `null`, y quien llame tiene que decirlo.
  /// - El flow no pide ninguna, o solo pide `any` → la primera de la lista, que es
  ///   la de por defecto.
  /// - El flow pide una que sí está → ésa.
  /// - El flow pide una que **no** está → `null`. No se cae a la de por defecto a
  ///   propósito: correr el flow colombiano con la cuenta peruana no da un error,
  ///   da un rojo que parece una regresión. Es peor que no correr.
  static CuentaDePruebas? paraElFlow({
    required String contenido,
    required List<CuentaDePruebas> cuentas,
  }) {
    if (cuentas.isEmpty) return null;

    final pedidas = LosTagsDeUnFlow.cuentasQuePide(contenido)
      ..remove(cualquiera);
    if (pedidas.isEmpty) return cuentas.first;

    for (final cuenta in cuentas) {
      if (cuenta.tags.any(pedidas.contains)) return cuenta;
    }
    return null;
  }

  /// Las claves que un flow pide y que ninguna cuenta cubre. Es lo que se le enseña
  /// a alguien cuando no se puede elegir: «este flow pide `acct-mx` y no tienes
  /// ninguna cuenta con esa etiqueta».
  static Set<String> sinCubrir({
    required String contenido,
    required List<CuentaDePruebas> cuentas,
  }) {
    final pedidas = LosTagsDeUnFlow.cuentasQuePide(contenido)
      ..remove(cualquiera);
    final cubiertas = <String>{for (final c in cuentas) ...c.tags};
    return pedidas.difference(cubiertas);
  }

  /// Una pasada por cuenta: qué flows le tocan a cada una.
  ///
  /// Es lo que hace `./run.sh` sin argumentos. El orden de las cuentas manda,
  /// porque la primera se lleva los `any` y los que no declaran nada.
  static Map<String, List<String>> repartir({
    required Map<String, String> flows,
    required List<CuentaDePruebas> cuentas,
  }) {
    final reparto = <String, List<String>>{
      for (final cuenta in cuentas) cuenta.clave: <String>[],
    };
    for (final entrada in flows.entries) {
      final cuenta = paraElFlow(contenido: entrada.value, cuentas: cuentas);
      // Un flow sin cuenta que lo cubra no se reparte: aparece como pendiente, no
      // se cuela en la pasada de otra.
      if (cuenta != null) reparto[cuenta.clave]!.add(entrada.key);
    }
    for (final lista in reparto.values) {
      lista.sort();
    }
    return reparto;
  }

  static List<Map<String, Object?>> aJson(List<CuentaDePruebas> cuentas) => [
    for (final cuenta in cuentas) cuenta.aJson(),
  ];

  static List<CuentaDePruebas> deJson(Object? crudo) {
    if (crudo is! List) return const [];
    final cuentas = <CuentaDePruebas>[];
    final vistas = <String>{};
    for (final entrada in crudo) {
      final cuenta = CuentaDePruebas.deJson(entrada);
      // Dos cuentas con la misma clave romperían el reparto en silencio: la
      // segunda pisaría la lista de la primera. Gana la primera.
      if (cuenta == null || !vistas.add(cuenta.clave)) continue;
      cuentas.add(cuenta);
    }
    return cuentas;
  }
}
