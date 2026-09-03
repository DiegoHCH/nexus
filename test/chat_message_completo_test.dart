import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un campo nuevo en [ChatMessage] se guarda, o se dice por qué no.
///
/// Esta prueba existe porque el mismo fallo pasó **cuatro veces**: los cambios
/// de git, los pasos del encargo, los adjuntos y el permiso nacieron los cuatro
/// viviendo solo en memoria, y los cuatro se descubrieron igual —cerrando la
/// app y volviendo a abrir la conversación—. Los tres comentarios que quedaron
/// en `local_conversation_store` lo cuentan: «vivía solo en memoria», «el mismo
/// fallo que ya tuvieron los cambios», «mismo motivo que los cambios, un grado
/// peor».
///
/// Que se repita cuatro veces dice que el problema no es el descuido: es que
/// **añadir un campo no obliga a nada**. Una prueba de ida y vuelta con los
/// campos de hoy tampoco obligaría —pasaría igual de verde con un campo nuevo
/// sin guardar—, así que esto mira la fuente: los campos que `ChatMessage`
/// declara contra los que el almacén escribe.
///
/// Es fea a propósito. La alternativa es descubrirlo otra vez en producción.
void main() {
  /// Lo que no se guarda, y el motivo. Añadir aquí es una decisión que se toma
  /// mirando esta prueba fallar, no un sitio donde esconder un olvido.
  const noSeGuardan = <String, String>{
    'streaming':
        'es de mientras se escribe: un mensaje guardado nunca está a medias, '
        'y `_sealLast` lo cierra antes de archivar',
  };

  test('todo campo de ChatMessage se guarda, o está declarado como que no', () {
    final fuente = File(
      'lib/features/assistant/presentation/state/chat_message.dart',
    ).readAsStringSync();

    final clase = fuente.substring(fuente.indexOf('class ChatMessage {'));
    final campos = RegExp(
      r'^  final [\w<>?, ]+ (\w+);',
      multiLine: true,
    ).allMatches(clase).map((m) => m.group(1)!).toList();

    expect(
      campos,
      isNotEmpty,
      reason:
          'si esto sale vacío es que cambió la forma de declarar, no que '
          'no haya campos — arregla la expresión antes de creerte el verde',
    );

    final almacen = File(
      'lib/features/history/data/datasources/local_conversation_store.dart',
    ).readAsStringSync();

    for (final campo in campos) {
      if (noSeGuardan.containsKey(campo)) continue;
      expect(
        almacen.contains('message.$campo'),
        isTrue,
        reason:
            'ChatMessage.$campo no se escribe en local_conversation_store. '
            'O se guarda —y se lee en `_mensajeDe`—, o se añade a '
            '`noSeGuardan` con el motivo. Un campo que solo vive en memoria '
            'desaparece al cerrar la app, y eso ya pasó cuatro veces.',
      );
    }
  });

  test('lo que se declara como que no se guarda sigue existiendo', () {
    final fuente = File(
      'lib/features/assistant/presentation/state/chat_message.dart',
    ).readAsStringSync();

    for (final campo in noSeGuardan.keys) {
      expect(
        fuente.contains('  final bool $campo;') ||
            RegExp(
              '^  final [\\w<>?, ]+ $campo;',
              multiLine: true,
            ).hasMatch(fuente),
        isTrue,
        reason:
            '$campo ya no es un campo de ChatMessage: sobra en `noSeGuardan`, '
            'y dejarlo ahí taparía un campo nuevo que se llamara igual',
      );
    }
  });
}
