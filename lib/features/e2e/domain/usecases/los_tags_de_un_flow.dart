/// La cabecera de un flow de Maestro: sus etiquetas y su `name:`.
///
/// **Para qué**: el tag `acct-<x>` es lo que dice con qué cuenta hay que correr ese
/// flow. Sin leerlo, Nexus tendría que preguntar la cuenta en cada pasada o correr
/// todo con una sola —que es justo lo que deja rojos que no significan nada—.
///
/// 🔴 **Solo se lee la cabecera, hasta el `---`.** Un flow de Maestro son dos
/// documentos YAML en un archivo: la cabecera con `appId`, `name` y `tags`, y
/// después de la línea `---` los pasos. Un paso puede tener texto arbitrario
/// —`inputText`, un comentario, un `assertVisible` con la palabra «tags»— y
/// mirarlo entero es cómo se acaba sacando una etiqueta de dentro de un tap.
///
/// **Sin paquete de YAML, y a propósito.** Mismo criterio que
/// `LasVariablesDelProyecto`: esto es una lista de palabras en la cabecera de un
/// archivo que escribimos nosotros, no un documento arbitrario. Lo que no se
/// entiende se ignora en vez de adivinarse.
abstract final class LosTagsDeUnFlow {
  /// El `name:` que declara el flow, o `null` si no declara ninguno.
  ///
  /// 🔴 **Maestro nombra con esto la carpeta de artefactos de la pasada**, no con
  /// el nombre del archivo: `01-login-error-flow.yaml` con `name: Login Error
  /// Flow` deja la carpeta `Login Error Flow`. Sin leerlo no se encuentran las
  /// capturas.
  static String? nombreDeclarado(String contenido) {
    for (final cruda in contenido.split('\n')) {
      if (cruda.trimRight() == '---') break;
      final linea = cruda.trim();
      if (linea.isEmpty || linea.startsWith('#')) continue;
      // Con la línea sin indentar: un `name:` sangrado es de otra cosa —el de un
      // `runFlow`, por ejemplo— y no el del documento.
      if (cruda.startsWith(' ') || cruda.startsWith('\t')) continue;
      if (!linea.startsWith('name:')) continue;
      final valor = _limpio(linea.substring('name:'.length));
      return valor.isEmpty ? null : valor;
    }
    return null;
  }

  /// Lee las etiquetas del contenido de un flow. Devuelve vacío si no declara.
  static Set<String> leer(String contenido) {
    final tags = <String>{};
    var enBloque = false;

    for (final cruda in contenido.split('\n')) {
      // El separador de documentos cierra la cabecera. De aquí abajo son pasos.
      if (cruda.trimRight() == '---') break;

      final linea = cruda.trim();
      if (linea.isEmpty || linea.startsWith('#')) continue;

      if (enBloque) {
        // Un guion al principio es otro elemento de la lista. Cualquier otra cosa
        // es una clave nueva y cierra el bloque.
        if (linea.startsWith('- ')) {
          final valor = _limpio(linea.substring(2));
          if (valor.isNotEmpty) tags.add(valor);
          continue;
        }
        enBloque = false;
      }

      if (!linea.startsWith('tags:')) continue;

      final resto = linea.substring('tags:'.length).trim();
      if (resto.isEmpty) {
        // `tags:` y la lista debajo, que es la forma que usa el repo.
        enBloque = true;
        continue;
      }
      // Forma en línea: `tags: [acct-pe, smoke]`.
      final dentro = resto.startsWith('[') && resto.endsWith(']')
          ? resto.substring(1, resto.length - 1)
          : resto;
      for (final trozo in dentro.split(',')) {
        final valor = _limpio(trozo);
        if (valor.isNotEmpty) tags.add(valor);
      }
    }

    return tags;
  }

  /// El prefijo que marca una etiqueta de cuenta.
  static const prefijoDeCuenta = 'acct-';

  /// Las claves de cuenta que pide un flow: `acct-pe` → `pe`.
  static Set<String> cuentasQuePide(String contenido) => {
    for (final tag in leer(contenido))
      if (tag.startsWith(prefijoDeCuenta) &&
          tag.length > prefijoDeCuenta.length)
        tag.substring(prefijoDeCuenta.length),
  };

  static String _limpio(String crudo) {
    var valor = crudo.trim();
    // Un comentario al final de la línea no es parte de la etiqueta.
    final almohadilla = valor.indexOf(' #');
    if (almohadilla > 0) valor = valor.substring(0, almohadilla).trim();
    if (valor.length >= 2) {
      final a = valor[0], b = valor[valor.length - 1];
      if ((a == '"' && b == '"') || (a == "'" && b == "'")) {
        valor = valor.substring(1, valor.length - 1);
      }
    }
    return valor.trim();
  }
}
