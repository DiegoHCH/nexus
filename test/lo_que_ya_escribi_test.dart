import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/lo_que_ya_escribi.dart';

/// El historial de la caja, como el de una terminal.
///
/// Se prueba entero porque las tres formas de decepcionar están muy juntas:
/// perder lo que llevabas escrito, dar la vuelta al llegar al final, y comerse
/// la flecha cuando lo que querías era mover el cursor.
void main() {
  LoQueYaEscribi conTres() =>
      LoQueYaEscribi.de(['primero', 'segundo', 'tercero']);

  group('el orden es del más reciente al más viejo', () {
    test('la primera flecha trae lo último que enviaste', () {
      expect(conTres().haciaAtras('').texto, 'tercero');
    });

    test('y las siguientes van hacia atrás en el tiempo', () {
      final uno = conTres().haciaAtras('');
      final dos = uno.haciaAtras('');
      final tres = dos.haciaAtras('');

      expect(
        [uno.texto, dos.texto, tres.texto],
        ['tercero', 'segundo', 'primero'],
      );
    });
  });

  group('lo que llevabas escrito', () {
    // 🔴 El error que más molesta: escribes media frase, subes por curiosidad y
    // al bajar tu media frase tiene que seguir ahí. Sin esto, una flecha te
    // borra el trabajo y aprendes a no usar la flecha.
    test('se guarda al subir y vuelve al bajar', () {
      final subido = conTres().haciaAtras('lo que iba escribiendo');

      expect(subido.texto, 'tercero');
      expect(subido.haciaAdelante().texto, 'lo que iba escribiendo');
      expect(subido.haciaAdelante().recorriendo, isFalse);
    });

    test('y se guarda una sola vez, no en cada paso', () {
      final dosArriba = conTres()
          .haciaAtras('el borrador')
          // Lo que hay en la caja en el segundo paso ya es del historial: si se
          // guardara otra vez, el borrador se perdería en el primer paso.
          .haciaAtras('tercero');

      expect(dosArriba.texto, 'segundo');
      expect(dosArriba.haciaAdelante().haciaAdelante().texto, 'el borrador');
    });
  });

  group('los topes', () {
    // Envolver haría que la flecha de más devuelva lo que acabas de escribir, y
    // eso se lee como un fallo, no como una vuelta.
    test('al final del historial se queda quieto', () {
      var donde = conTres();
      for (var i = 0; i < 10; i++) {
        donde = donde.haciaAtras('');
      }

      expect(donde.texto, 'primero');
      expect(donde.posicion, 2);
    });

    test('sin historial no pasa nada, y no se pierde el borrador', () {
      final vacio = LoQueYaEscribi.de(const []);
      final tras = vacio.haciaAtras('lo mío');

      expect(tras.recorriendo, isFalse);
      expect(tras.texto, '');
    });

    test('bajar sin haber subido no hace nada', () {
      expect(conTres().haciaAdelante().recorriendo, isFalse);
    });
  });

  group('qué entra en el historial', () {
    test('los vacíos no', () {
      expect(LoQueYaEscribi.de(['a', '', '   ', 'b']).entradas, ['b', 'a']);
    });

    // Seguidos y no todos: tres `!git status` en la mañana no deberían costar
    // tres flechas, pero dos veces lo mismo con diez cosas en medio son dos
    // momentos distintos. Es `ignoredups`, no `ignoreboth`.
    test('los repetidos seguidos se colapsan, los separados no', () {
      expect(LoQueYaEscribi.de(['a', 'a', 'a']).entradas, ['a']);
      expect(LoQueYaEscribi.de(['a', 'b', 'a']).entradas, ['a', 'b', 'a']);
    });

    test('y se recortan los espacios de alrededor', () {
      expect(LoQueYaEscribi.de(['  hola  ']).entradas, ['hola']);
    });
  });

  group('cuándo la flecha es del historial y cuándo del cursor', () {
    // 🔴 La caja llega a seis líneas. Secuestrar la flecha siempre rompería
    // escribir un mensaje de varias líneas, que es justo cuando más importa el
    // mensaje.
    test('arriba navega desde la primera línea', () {
      expect(LoQueYaEscribi.navegaHaciaAtras('una sola línea', 5), isTrue);
      expect(LoQueYaEscribi.navegaHaciaAtras('', 0), isTrue);
    });

    test('y no navega si hay algo escrito por encima del cursor', () {
      // El cursor en la segunda línea: arriba tiene que subir dentro del texto.
      expect(LoQueYaEscribi.navegaHaciaAtras('una\ndos', 5), isFalse);
    });

    test('abajo vuelve desde la última línea', () {
      expect(LoQueYaEscribi.navegaHaciaAdelante('una\ndos', 5), isTrue);
      expect(LoQueYaEscribi.navegaHaciaAdelante('una\ndos', 1), isFalse);
    });

    test('un cursor fuera de rango no revienta', () {
      expect(LoQueYaEscribi.navegaHaciaAtras('corto', 999), isTrue);
      expect(LoQueYaEscribi.navegaHaciaAdelante('corto', 999), isTrue);
    });
  });

  test('al enviar se suelta el recorrido y el borrador', () {
    final suelto = conTres().haciaAtras('algo').suelta();

    expect(suelto.recorriendo, isFalse);
    expect(suelto.texto, '');
    expect(suelto.entradas, isNotEmpty);
  });
}
