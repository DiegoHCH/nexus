import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';

/// Cómo se llama una cuenta de Claude **para quien la mira**.
///
/// 🔴 **Pedido en tres reglas, después de descubrir que el correo estaba a la
/// vista:** «si la cuenta dice en la organización Global66 - Tech, que aparezca
/// Global66; si tiene otra, algo parecido a lo que aparece como organización; y
/// si es algo diferente, algo como Mi Perfil».
///
/// Y tiene más fondo que ponerle una etiqueta bonita: el nombre que había era
/// el del **directorio** —`work`, `private`—, que es una decisión de
/// instalación y no dice de quién es la cuenta. En el Mac donde se midió,
/// `.claude` y `.claude-work` resultaron ser **la misma cuenta** —mismo correo,
/// misma organización— así que «la de siempre» y «work» eran dos nombres para
/// lo mismo. Con la organización delante, eso se ve.
///
/// Las tres reglas, en el orden en que se aplican:
///
/// 1. **Una organización de empresa** da su nombre, sin el departamento:
///    «Global66 - Tech» → «Global66». Lo que va detrás del guion es el equipo, y
///    en una pestaña de cuatro caracteres de ancho estorba más que informa.
/// 2. **Una organización personal no es una organización.** Claude Code la
///    escribe como «alguien@gmail.com's Organization» para una cuenta de pago
///    individual: eso no es un sitio donde trabajes, es tu cuenta. Ahí va el
///    nombre de «lo mío».
/// 3. **Y sin datos, el de siempre**: una cuenta creada y nunca usada no tiene
///    de dónde sacar un nombre, y suponerlo sería inventarlo.
abstract final class ElNombreDeLaCuenta {
  /// El nombre de la empresa a partir de su organización, o `null` si esa
  /// organización es personal —o no hay—.
  static String? deLaEmpresa(String? organizacion, {String? correo}) {
    final cruda = organizacion?.trim();
    if (cruda == null || cruda.isEmpty) return null;
    if (esPersonal(cruda, correo: correo)) return null;

    // Lo de antes del guion separado por espacios: es como Claude Code escribe
    // el departamento —«Global66 - Tech»— y quien mira una pestaña quiere la
    // empresa, no el equipo. Un guion **sin** espacios no se toca: puede ser
    // parte del nombre («Mercado-Libre»).
    final corte = RegExp(r'\s[-–—]\s').firstMatch(cruda);
    final nombre = corte == null
        ? cruda
        : cruda.substring(0, corte.start).trim();
    return nombre.isEmpty ? null : nombre;
  }

  /// Si esa organización es en realidad una cuenta personal.
  ///
  /// Dos señales, y las dos salen de lo que escribe Claude Code de verdad: la
  /// organización lleva el correo dentro —«alguien@gmail.com's Organization»— o
  /// acaba en «'s Organization», que es como nombra a la de un individuo.
  static bool esPersonal(String organizacion, {String? correo}) {
    final baja = organizacion.toLowerCase();
    if (baja.endsWith("'s organization")) return true;
    if (baja.endsWith('’s organization')) return true;
    final suyo = correo?.trim().toLowerCase();
    return suyo != null && suyo.isNotEmpty && baja.contains(suyo);
  }

  /// Cómo llamar a [cuenta], con los dos textos que pone quien la enseña.
  ///
  /// [mia] es el nombre de una cuenta personal y [general] el de una cuenta de
  /// la que no se sabe nada — los dos vienen de fuera porque son de interfaz y
  /// el idioma se elige en Ajustes.
  static String de(
    ClaudeProfile cuenta, {
    required String general,
    required String mia,
  }) {
    if (deLaEmpresa(cuenta.organizacion, correo: cuenta.correo)
        case final empresa?) {
      return empresa;
    }
    if (cuenta.organizacion case final organizacion?) {
      if (esPersonal(organizacion, correo: cuenta.correo)) return mia;
    }
    // Sin organización pero con nombre de directorio —una cuenta que existe y
    // en la que nunca se entró—: al menos se distingue de las demás.
    if (!cuenta.esLaDeSiempre && cuenta.name.isNotEmpty) return cuenta.name;
    return general;
  }

  /// Los nombres de todas, **desambiguados**.
  ///
  /// 🔴 **Hace falta porque dos perfiles pueden ser la misma cuenta.** Está
  /// medido: en este Mac `.claude` y `.claude-work` tienen el mismo correo y la
  /// misma organización, así que las dos pestañas se llamarían «Global66» y no
  /// habría forma de saber cuál se está tocando — y lo que se toca ahí instala
  /// servidores y skills. Cuando dos coinciden, cada una lleva detrás el nombre
  /// de su directorio, que es lo único que de verdad las separa.
  static List<String> paraTodas(
    List<ClaudeProfile> cuentas, {
    required String general,
    required String mia,
  }) {
    final nombres = [
      for (final cuenta in cuentas) de(cuenta, general: general, mia: mia),
    ];
    final cuantas = <String, int>{};
    for (final nombre in nombres) {
      cuantas[nombre] = (cuantas[nombre] ?? 0) + 1;
    }
    return [
      for (final (indice, nombre) in nombres.indexed)
        if ((cuantas[nombre] ?? 0) > 1)
          '$nombre (${ClaudeProfile.nameFromPath(cuentas[indice].path) ?? general})'
        else
          nombre,
    ];
  }
}
