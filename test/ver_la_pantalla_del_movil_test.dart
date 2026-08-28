import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/domain/usecases/el_espejo_del_movil.dart';

/// Con qué se llama a scrcpy.
///
/// **Los flags están comprobados contra scrcpy 3.3.3** en esta máquina, no supuestos.
/// Y se lanza scrcpy en vez de hacerlo nosotros porque se midió la alternativa: una
/// captura por `adb exec-out screencap` tarda ~690 ms, o sea 1,4 por segundo.
void main() {
  List<String> args({bool conControl = true, bool encima = false}) =>
      ElEspejoDelMovil.argumentos(
        deviceId: '36c56d94',
        titulo: 'POCO F6',
        conControl: conControl,
        encima: encima,
      );

  test('lleva el dispositivo y el nombre legible como título', () {
    // Un número de serie no dice cuál de los dos móviles es.
    expect(args(), containsAllInOrder(['--serial', '36c56d94']));
    expect(args(), containsAllInOrder(['--window-title', 'POCO F6']));
  });

  test('sin audio y con el tamaño acotado', () {
    expect(args(), contains('--no-audio'));
    expect(args(), containsAllInOrder(['--max-size', '1024']));
  });

  test('mantiene la pantalla despierta', () {
    // Que si no se apaga a mitad de lo que estabas mirando.
    expect(args(), contains('--stay-awake'));
  });

  group('el control', () {
    test('con control, no se pasa --no-control', () {
      expect(args(), isNot(contains('--no-control')));
    });

    test('**sin control cuando corre una prueba**', () {
      // No es una precaución menor: Maestro inyecta eventos en el mismo
      // dispositivo. Si se toca la pantalla a la vez, los dos pelean por él y el
      // fallo que salga se lo habrán inventado entre los dos.
      expect(args(conControl: false), contains('--no-control'));
    });
  });

  group('encima de todo', () {
    test('solo cuando se pide', () {
      expect(args(), isNot(contains('--always-on-top')));
    });

    test('con una corrida viva, sí: se mira sin perder Nexus de vista', () {
      expect(args(encima: true), contains('--always-on-top'));
    });
  });
}
