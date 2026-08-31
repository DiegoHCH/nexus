import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

import 'package:nexus/core/design_system/nexus_colors.dart';

/// Cómo se pinta el código en la conversación.
///
/// **Los colores salen de la paleta de Nexus, no de un tema enlatado.** Es la
/// decisión que sostiene todo lo demás: un tema de resaltado importado trae sus
/// propios hexadecimales, así que no conoce el claro ni el oscuro ni el acento
/// que hayas elegido en la rueda — pegaría en la mitad de los casos y en la otra
/// se leería como pegado con cinta. Con cuatro tonos que ya existen —[accent],
/// [ok], [warn], [err]— y tres neutros, el resaltado cambia de tema solo.
///
/// ## Dos contenidos que se llaman igual
///
/// Lo que escribe Claude es Dart, YAML, JSON o shell, y eso lo resuelve una
/// gramática. Pero la salida de un `!git` **no es un lenguaje**: `git status` no
/// tiene sintaxis y `git diff` la tiene pero no es de ningún lenguaje. Para esa
/// mitad, «verse como en un editor» significa otra cosa —lo añadido en verde, lo
/// quitado en rojo, los tramos marcados— y la hace [_comoUnDiff].
abstract final class ElResaltadoDelCodigo {
  /// Los lenguajes que se nombran en un cercado y significan «esto es un diff».
  ///
  /// `diff` es el que pone Claude; los otros dos llegan del `!`, donde el
  /// lenguaje no lo escribe nadie y lo deduce [lenguajeDe].
  static const _diffs = {'diff', 'patch', 'git'};

  /// El árbol de estilos de un bloque, ya con el lenguaje resuelto.
  ///
  /// [lenguaje] es lo que venía en el cercado, o `null` si no venía nada. Sin
  /// lenguaje **no se adivina con la gramática**: `highlight` acepta detectar
  /// solo, y detectando sobre la salida de `git status` pinta palabras al azar
  /// —«on», «branch», «modified» son palabras clave de algo— que es peor que no
  /// pintar. Sin lenguaje se pinta plano, salvo que parezca un diff.
  static TextSpan enSpans(
    String codigo, {
    required String? lenguaje,
    required NexusColors colores,
    required TextStyle base,
  }) {
    final cual = lenguaje?.toLowerCase();

    if (_diffs.contains(cual) || (cual == null && pareceUnDiff(codigo))) {
      return _comoUnDiff(codigo, colores: colores, base: base);
    }
    if (cual == null) return TextSpan(text: codigo, style: base);

    // Un lenguaje que no conoce **no es un fallo**: `parse` cae a `plaintext` en
    // vez de lanzar, comprobado en su código. El `try` cubre lo otro —una
    // gramática que se atraganta con su propio texto— porque un bloque de código
    // no puede tumbar la conversación en la que está.
    try {
      final resultado = highlight.parse(codigo, language: cual);
      return TextSpan(
        style: base,
        children: [
          for (final nodo in resultado.nodes ?? const <Node>[])
            _delNodo(nodo, colores: colores, base: base),
        ],
      );
    } on Object {
      return TextSpan(text: codigo, style: base);
    }
  }

  /// Si esto tiene pinta de diff sin que nadie lo haya dicho.
  ///
  /// Se pide una **cabecera de diff de verdad** y no solo líneas que empiecen por
  /// `+` o `-`: una lista con guiones, un YAML o un trozo de shell las tienen a
  /// montones, y pintarlos de rojo porque empiezan por `-` sería exactamente el
  /// tipo de adivinanza que estropea más de lo que arregla.
  static bool pareceUnDiff(String codigo) {
    for (final linea in codigo.split('\n')) {
      if (linea.startsWith('diff --git ') ||
          linea.startsWith('@@ ') ||
          linea.startsWith('--- a/') ||
          linea.startsWith('+++ b/')) {
        return true;
      }
    }
    return false;
  }

  /// El lenguaje que declara el cercado, sacado de la clase que pone markdown.
  ///
  /// Llega como `language-dart`, y `null` cuando el cercado venía pelado — que es
  /// lo normal en la salida del `!`, donde el cercado lo pone Nexus.
  static String? lenguajeDe(String? clase) {
    if (clase == null) return null;
    for (final trozo in clase.split(' ')) {
      if (trozo.startsWith('language-')) {
        final nombre = trozo.substring('language-'.length).trim();
        if (nombre.isNotEmpty) return nombre;
      }
    }
    return null;
  }

  /// Un diff, con el sentido que ya tienen [NexusColors.ok] y [NexusColors.err].
  ///
  /// Se reutiliza la pareja semántica en vez de inventar un verde y un rojo de
  /// sintaxis: lo añadido y lo quitado **son** un acierto y un error en el mismo
  /// idioma visual que usa el resto de la app, y así los dos temas ya están
  /// resueltos.
  static TextSpan _comoUnDiff(
    String codigo, {
    required NexusColors colores,
    required TextStyle base,
  }) {
    final lineas = codigo.split('\n');
    return TextSpan(
      style: base,
      children: [
        for (var i = 0; i < lineas.length; i++)
          TextSpan(
            text: i == lineas.length - 1 ? lineas[i] : '${lineas[i]}\n',
            style: base.copyWith(color: _colorDeLaLinea(lineas[i], colores)),
          ),
      ],
    );
  }

  static Color _colorDeLaLinea(String linea, NexusColors colores) {
    // El orden importa: `+++` y `---` son cabecera, no contenido añadido ni
    // quitado, así que se miran **antes** que `+` y `-`. Al revés, cada archivo
    // de un diff estrenaría una línea verde y otra roja que no son cambios.
    if (linea.startsWith('+++') || linea.startsWith('---')) return colores.mute;
    if (linea.startsWith('@@')) return colores.accent;
    if (linea.startsWith('diff --git ') ||
        linea.startsWith('index ') ||
        linea.startsWith('new file') ||
        linea.startsWith('deleted file') ||
        linea.startsWith('rename ')) {
      return colores.mute;
    }
    if (linea.startsWith('+')) return colores.ok;
    if (linea.startsWith('-')) return colores.err;
    return colores.ink;
  }

  static TextSpan _delNodo(
    Node nodo, {
    required NexusColors colores,
    required TextStyle base,
  }) {
    final estilo = _estiloDe(nodo.className, colores: colores, base: base);
    final hijos = nodo.children;
    if (hijos == null || hijos.isEmpty) {
      return TextSpan(text: nodo.value ?? '', style: estilo);
    }
    return TextSpan(
      style: estilo,
      children: [
        for (final hijo in hijos)
          _delNodo(hijo, colores: colores, base: estilo),
      ],
    );
  }

  /// El mapa de tipos de token a la paleta.
  ///
  /// Curado y corto a propósito. `highlight` emite decenas de clases y cubrirlas
  /// todas con siete colores acabaría en un arcoíris donde nada destaca: lo que
  /// hace legible un bloque es que **tres o cuatro cosas** salten y el resto sea
  /// texto. Lo que no está aquí se pinta como texto normal, que es la respuesta
  /// correcta y no una omisión.
  static TextStyle _estiloDe(
    String? clase, {
    required NexusColors colores,
    required TextStyle base,
  }) => switch (clase) {
    // Lo que estructura: las palabras del lenguaje.
    'keyword' ||
    'built_in' ||
    'type' ||
    'literal' ||
    'selector-tag' ||
    'tag' ||
    'meta-keyword' => base.copyWith(color: colores.accent),
    // Los datos: cadenas y números, que es lo que uno busca con la vista.
    'string' ||
    'regexp' ||
    'symbol' ||
    'char.escape' => base.copyWith(color: colores.ok),
    'number' => base.copyWith(color: colores.warn),
    // Los nombres propios del código.
    'title' ||
    'title.class' ||
    'title.function' ||
    'class' ||
    'function' ||
    'name' => base.copyWith(color: colores.ink, fontWeight: FontWeight.w600),
    // Lo accesorio, atenuado: si un comentario compite con el código, gana el
    // comentario y se lee mal justo lo que se vino a leer.
    'comment' || 'quote' || 'doctag' => base.copyWith(
      color: colores.faint,
      fontStyle: FontStyle.italic,
    ),
    'meta' ||
    'meta-string' ||
    'attr' ||
    'attribute' ||
    'params' ||
    'variable' => base.copyWith(color: colores.mute),
    'deletion' => base.copyWith(color: colores.err),
    'addition' => base.copyWith(color: colores.ok),
    _ => base,
  };
}
