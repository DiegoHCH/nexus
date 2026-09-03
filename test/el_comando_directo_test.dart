import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/domain/usecases/el_comando_directo.dart';

/// Lo que decide si un `!` acaba en git o en Claude.
///
/// Se prueba entero porque las dos formas de equivocarse cuestan: reconocer de
/// más manda a git una frase que era un encargo, y reconocer de menos deja el
/// comando escrito sin que pase nada.
void main() {
  group('qué es un comando directo', () {
    test('lo que lleva ! delante', () {
      final directo = ElComandoDirecto.deLaFrase('!git status');

      expect(directo?.comando, 'git');
      expect(directo?.argumentos, ['status']);
    });

    test('y lo que no, no lo es', () {
      expect(ElComandoDirecto.deLaFrase('git status'), isNull);
      expect(ElComandoDirecto.deLaFrase('arregla el !git de ayer'), isNull);
      expect(ElComandoDirecto.deLaFrase(''), isNull);
    });

    // Un `!` suelto es alguien que empezó a escribir. Ni se corre ni se manda a
    // Claude: no hay nada que hacer con él.
    test('un ! solo no es nada', () {
      expect(ElComandoDirecto.deLaFrase('!'), isNull);
      expect(ElComandoDirecto.deLaFrase('!   '), isNull);
    });

    test('los espacios de alrededor no cuentan', () {
      expect(ElComandoDirecto.deLaFrase('  !git  status  ')?.argumentos, [
        'status',
      ]);
    });

    // 🔴 Lo que no es git **también se reconoce**, y a propósito: quien lo
    // recibe tiene que poder decir qué se intentó. Devolver `null` aquí lo
    // mandaría a Claude como si fuera un encargo, y «!make test» no es un
    // encargo — es un comando que esta versión no corre.
    test('lo que no es git se reconoce igual, para poder decirlo', () {
      final directo = ElComandoDirecto.deLaFrase('!make test');

      expect(directo?.comando, 'make');
      expect(directo?.comando, isNot(ElComandoDirecto.soloEste));
    });
  });

  group('las comillas, que son lo que permite commitear', () {
    test('un mensaje con espacios llega de una pieza', () {
      final directo = ElComandoDirecto.deLaFrase('!git commit -m "fix: algo"');

      expect(directo?.argumentos, ['commit', '-m', 'fix: algo']);
    });

    test('las simples valen igual', () {
      expect(
        ElComandoDirecto.deLaFrase("!git commit -m 'y esto'")?.argumentos,
        ['commit', '-m', 'y esto'],
      );
    });

    // Una comilla de un tipo dentro del otro es texto, no una comilla: sin esto,
    // un mensaje con un apóstrofo —«no funcionó»— partiría la pieza a la mitad.
    test('una comilla dentro de la otra es texto', () {
      expect(
        ElComandoDirecto.deLaFrase(
          '!git commit -m "no funcionó\'"',
        )?.argumentos,
        ['commit', '-m', "no funcionó'"],
      );
    });

    // Alguien a medio escribir. Devolver lo que hay se parece más a lo que
    // quería que negarse.
    test('una comilla sin cerrar se cierra al final', () {
      expect(
        ElComandoDirecto.deLaFrase('!git commit -m "a medio')?.argumentos,
        ['commit', '-m', 'a medio'],
      );
    });

    // 🔴 Una pieza vacía **es una pieza**: `-m ""` es un mensaje vacío, no la
    // ausencia de un argumento, y git tiene que recibir los dos para poder
    // quejarse de lo que le llega.
    test('un argumento vacío sigue siendo un argumento', () {
      expect(ElComandoDirecto.deLaFrase('!git commit -m ""')?.argumentos, [
        'commit',
        '-m',
        '',
      ]);
    });
  });

  group('cómo se enseña la salida', () {
    test('va en un bloque de código, que es lo que la alinea', () {
      expect(
        ElComandoDirecto.enBloque('a1b2c3 primero\nd4e5f6 segundo'),
        '```\na1b2c3 primero\nd4e5f6 segundo\n```',
      );
    });

    // Una o dos comillas sueltas **no** obligan a crecer, y conviene fijarlo:
    // para cerrar un bloque hacen falta comillas al principio de una línea, así
    // que una a media línea no cierra nada. Crecer aquí sería cercado de sobra.
    test('una comilla suelta no obliga a crecer', () {
      expect(
        ElComandoDirecto.enBloque(
          'a1b2c3 refactor: quitar `json_serializable`',
        ),
        startsWith('```\n'),
      );
    });

    // 🔴 Tres sí: ahí el bloque se cerraría a media salida y el resto se
    // pintaría como prosa suelta. En un repo donde se habla de código, un
    // mensaje de commit con un bloque dentro pasa.
    test('el cercado crece cuando la salida trae uno igual de largo', () {
      final puesto = ElComandoDirecto.enBloque(
        'a1b2c3 docs: explicar el ``` de los bloques',
      );

      expect(puesto, startsWith('````\n'));
      expect(puesto, endsWith('\n````'));
    });

    test('y crece lo que haga falta, no un escalón fijo', () {
      expect(
        ElComandoDirecto.enBloque('esto lleva ````cuatro```` dentro'),
        startsWith('`````\n'),
      );
    });

    // Sin esto, una salida sin salto final deja el cierre pegado a la última
    // línea y deja de ser un cercado.
    test('el cierre siempre va en su propia línea', () {
      for (final salida in ['una línea', 'con salto al final\n', 'dos\n\n']) {
        expect(ElComandoDirecto.enBloque(salida), endsWith('\n```'));
      }
    });
  });

  group('en piezas', () {
    test('los espacios de sobra no hacen argumentos vacíos', () {
      expect(ElComandoDirecto.enPiezas('  a   b  '), ['a', 'b']);
    });

    test('una línea vacía no da piezas', () {
      expect(ElComandoDirecto.enPiezas('   '), isEmpty);
    });

    // Los saltos de línea separan igual que los espacios: se pega un comando de
    // otro sitio y llega con el salto dentro.
    test('un salto de línea separa como un espacio', () {
      expect(ElComandoDirecto.enPiezas('log\n--oneline'), ['log', '--oneline']);
    });
  });

  // El parte de una corrida, que vivía dentro del controlador.
  group('cómo se cuenta lo que hizo', () {
    String parte({int codigo = 0, String salida = '', bool tardo = false}) =>
        ElComandoDirecto.comoSeCuenta(
          (codigo: codigo, salida: salida, tardoDemasiado: tardo),
          cabecera: 'en nexus · develop',
          tardoDemasiado: 'tardó demasiado, lánzalo en la terminal',
          fallo: (c) => 'git terminó con $c',
          sinNadaQueDecir: 'sin nada que decir',
        );

    // Costó un incidente: la primera vez que esto se usó contestó sobre un repo
    // que no era, y lo único que lo delató fue el nombre de una rama.
    test('la cabecera va siempre, y va primero', () {
      for (final p in [
        parte(),
        parte(salida: 'algo'),
        parte(codigo: 1),
        parte(tardo: true),
      ]) {
        expect(p, startsWith('**en nexus · develop**'), reason: p);
      }
    });

    test('la salida de git va en bloque, para que se lea alineada', () {
      final p = parte(salida: 'a1b2c3 primero\nd4e5f6 segundo');

      expect(p, contains('```\na1b2c3 primero\nd4e5f6 segundo\n```'));
    });

    test('un cero sin salida no es un fallo: es que no había nada', () {
      final p = parte();

      expect(p, contains('sin nada que decir'));
      expect(p, isNot(contains('git terminó')));
    });

    // 🔴 Un código distinto de cero con la salida en blanco es un fallo mudo, y
    // eso se lee como que la app no hizo nada.
    test('un fallo sin salida se dice igual, y no como «nada que decir»', () {
      final p = parte(codigo: 128);

      expect(p, contains('git terminó con 128'));
      expect(p, isNot(contains('sin nada que decir')));
    });

    test('un fallo con salida dice las dos cosas', () {
      final p = parte(codigo: 1, salida: 'fatal: not a git repository');

      expect(p, contains('git terminó con 1'));
      expect(p, contains('fatal: not a git repository'));
    });

    // Un plantón se arregla de otra manera que un código 1 —lanzarlo en la
    // terminal— así que no se cuenta como un fallo más.
    test('un plantón lo dice y se calla lo demás', () {
      final p = parte(tardo: true, codigo: -1, salida: 'a medias');

      expect(p, contains('tardó demasiado'));
      expect(p, isNot(contains('git terminó')));
      expect(p, isNot(contains('a medias')));
    });

    test('una salida de solo espacios cuenta como vacía', () {
      expect(parte(salida: '   \n  '), contains('sin nada que decir'));
    });
  });
}
