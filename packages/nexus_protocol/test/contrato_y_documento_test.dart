import 'dart:io';

import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:test/test.dart';

// Que el código y `docs/PROTOCOL.md` no puedan separarse.
//
// El documento se escribió **antes** que el código y decide qué se expone por red;
// el código es lo que de verdad se ejecuta. Nada obliga a que digan lo mismo, y ese
// hueco es exactamente donde se cuela un método nuevo que nadie revisó — el triaje
// que en La Oficina costó 59 handlers.
//
// Así que esto lee el documento. Es la misma técnica que `diccionario_test.dart`:
// una prueba puede abrir un archivo, y así se cubren cosas que ningún tipo puede
// expresar.
void main() {
  final documento = File('../../docs/PROTOCOL.md');

  test('el documento se encuentra', () {
    // Antes de comprobar nada: sin esto, el día que el documento se mueva las
    // pruebas de abajo pasarían **sin mirar nada**, y un guardia ciego que dice que
    // todo va bien es peor que no tener guardia.
    expect(
      documento.existsSync(),
      isTrue,
      reason:
          'no está en ${documento.absolute.path}: si se movió, hay que '
          'arreglar esta ruta, no borrar la prueba',
    );
  });

  test('todo lo que se expone está autorizado en el documento', () {
    final texto = documento.readAsStringSync();
    // La sección que enumera lo que va al móvil.
    // En minúsculas los dos lados: el documento capitaliza al empezar cada punto
    // —«Mandar un encargo»— y esta prueba no es de ortografía.
    final expone = texto
        .substring(
          texto.indexOf('### Va al móvil'),
          texto.indexOf('### Se queda en el Mac'),
        )
        .toLowerCase();

    final sinRespaldo = <String>[];
    for (final m in RemoteMethod.values) {
      if (!expone.contains(m.enElDocumento.toLowerCase())) {
        sinRespaldo.add(m.name);
      }
    }

    expect(
      sinRespaldo,
      isEmpty,
      reason:
          'estos métodos existen en el código y el documento no los autoriza: '
          '${sinRespaldo.join(", ")}. O se añaden al documento con su motivo, o '
          'no se exponen',
    );
  });

  test('lo que se decidió dejar en el Mac no está expuesto', () {
    final texto = documento.readAsStringSync();
    final seQueda = texto
        .substring(texto.indexOf('### Se queda en el Mac'))
        .toLowerCase();

    for (final negado in DeniedOnPurpose.values) {
      // Está en el documento, en el lado correcto...
      expect(
        seQueda.contains(negado.enElDocumento.toLowerCase()),
        isTrue,
        reason:
            '«${negado.enElDocumento}» debería estar en el lado de lo que se '
            'queda en el Mac',
      );
      // ...y no existe como método.
      expect(
        RemoteMethod.tryParse(negado.name),
        isNull,
        reason:
            '${negado.name} se decidió que NO se expone, y existe como método',
      );
    }
  });

  test('el documento sigue diciendo lo que el código implementa', () {
    final texto = documento.readAsStringSync();
    // Cuatro afirmaciones del documento que aquí son código. Si alguna se reescribe
    // en el documento sin tocar el código —o al revés— esto lo dice.
    const afirmaciones = {
      'clientMsgId': 'la deduplicación se apoya en un id del cliente',
      'lastSeq': 'reconectar pide desde el último visto',
      'Host': 'se valida el origen del upgrade',
      'nunca en la URL': 'el token va en una cabecera',
    };
    for (final entrada in afirmaciones.entries) {
      expect(
        texto.contains(entrada.key),
        isTrue,
        reason:
            'el documento ya no menciona «${entrada.key}» — ${entrada.value}',
      );
    }
  });
}
