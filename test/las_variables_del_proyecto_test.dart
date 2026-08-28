import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/las_variables_del_proyecto.dart';

/// Las credenciales de un proyecto, leídas de su `.env.local`.
///
/// **Ningún valor de estas pruebas se parece a una credencial de verdad**, y eso es
/// a propósito: un test es un archivo que se lee en un PR público.
void main() {
  group('leer el archivo', () {
    test('una clave por línea', () {
      final v = LasVariablesDelProyecto.leer('UNO=primero\nDOS=segundo\n');
      expect(v, {'UNO': 'primero', 'DOS': 'segundo'});
    });

    test('los comentarios y las líneas vacías no cuentan', () {
      final v = LasVariablesDelProyecto.leer(
        '# esto es un comentario\n\nUNO=primero\n   \n',
      );
      expect(v, {'UNO': 'primero'});
    });

    test('las comillas envolventes se quitan', () {
      final v = LasVariablesDelProyecto.leer(
        'UNO="con espacios"\nDOS=\'otra\'\n',
      );
      expect(v, {'UNO': 'con espacios', 'DOS': 'otra'});
    });

    test('una comilla suelta es parte del valor', () {
      final v = LasVariablesDelProyecto.leer('UNO=no"cierra\n');
      expect(v['UNO'], 'no"cierra');
    });

    test('un valor con un igual dentro se queda entero', () {
      // Se corta en el primer `=` y no en todos: un valor en base64 acaba en `=`.
      final v = LasVariablesDelProyecto.leer('UNO=a=b=c\n');
      expect(v['UNO'], 'a=b=c');
    });

    test('lo que no se entiende se ignora, no se adivina', () {
      final v = LasVariablesDelProyecto.leer(
        'sin igual\n=sin clave\n1MALA=x\nCON GUION-MALO=x\nBUENA=si\n',
      );
      expect(v, {'BUENA': 'si'});
    });

    test('un archivo vacío no es un error', () {
      expect(LasVariablesDelProyecto.leer(''), isEmpty);
    });
  });

  group('qué variables nombra un flow', () {
    test('la forma simple se reconoce', () {
      final usa = LasVariablesDelProyecto.queNombra(
        'appId: com.x\n---\n- inputText: \${CORREO}\n- inputText: \${CLAVE}\n',
      );
      expect(usa, {'CORREO', 'CLAVE'});
    });

    test('de una expresión no se saca nada, a propósito', () {
      // Sacar de `${A == "B"}` qué es nombre y qué cadena pide un analizador. Para
      // avisar de lo que falta vale con lo inequívoco.
      final usa = LasVariablesDelProyecto.queNombra(
        '- assertTrue: \${A == "B"}',
      );
      expect(usa, isEmpty);
    });
  });

  group('qué se le pasa a la prueba', () {
    const variables = {'CORREO': 'a@b.c', 'CLAVE': 'x', 'OTRA_COSA': 'y'};

    test('solo las que el flow menciona, no el archivo entero', () {
      // Pasar todo metería en el `argv` credenciales que esta prueba no usa.
      final para = LasVariablesDelProyecto.paraElFlow(
        yaml: '- inputText: \${CORREO}\n',
        variables: variables,
      );
      expect(para.keys, ['CORREO']);
    });

    test('una expresión también las recibe', () {
      final para = LasVariablesDelProyecto.paraElFlow(
        yaml: '- assertTrue: \${CLAVE == "x"}',
        variables: variables,
      );
      expect(para.keys, ['CLAVE']);
    });

    test('sin variables, nada', () {
      expect(
        LasVariablesDelProyecto.paraElFlow(
          yaml: '- launchApp',
          variables: variables,
        ),
        isEmpty,
      );
    });
  });

  group('las que faltan', () {
    test('se nombran, para poder decirlo antes de correr', () {
      // Sin esto, Maestro escribe el literal `${CORREO}` en el campo y la prueba
      // muere tres pasos después, en un sitio que no tiene que ver.
      final faltan = LasVariablesDelProyecto.faltan(
        yaml: '- inputText: \${CORREO}\n- inputText: \${CLAVE}\n',
        tiene: const {'CLAVE'},
      );
      expect(faltan, ['CORREO']);
    });

    test('las de Maestro no faltan nunca: las pone él', () {
      final faltan = LasVariablesDelProyecto.faltan(
        yaml:
            '- takeScreenshot: \${MAESTRO_FILENAME}\n- assertVisible: \${output}\n',
        tiene: const {},
      );
      expect(faltan, isEmpty);
    });

    test('un flow sin variables no echa en falta nada', () {
      expect(
        LasVariablesDelProyecto.faltan(yaml: '- launchApp', tiene: const {}),
        isEmpty,
      );
    });
  });
}
