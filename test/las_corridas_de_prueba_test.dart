import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/lector_de_corridas.dart';

/// Leer lo que dejó una corrida de Maestro.
///
/// El `commands.json` de aquí tiene la forma del de verdad, comprobada contra las
/// corridas de esta máquina: una lista de objetos con `command` y `metadata`, el
/// entorno dentro del primer comando, y dos pasos de andamiaje al principio que
/// no son de la prueba.
String _commands({
  String estadoDelUltimo = 'COMPLETED',
  String dispositivo = 'emulator-5554',
  int pasosDePrueba = 3,
}) {
  final pasos = <String>[
    '{"command":{"defineVariablesCommand":{"env":'
        '{"MAESTRO_FILENAME":"login","MAESTRO_DEVICE_UDID":"$dispositivo"}}},'
        '"metadata":{"status":"COMPLETED","sequenceNumber":0}}',
    '{"command":{"applyConfigurationCommand":{}},'
        '"metadata":{"status":"COMPLETED","sequenceNumber":1}}',
  ];
  for (var i = 0; i < pasosDePrueba; i++) {
    final ultimo = i == pasosDePrueba - 1;
    pasos.add(
      '{"command":{"tapOnElementCommand":{}},'
      '"metadata":{"status":"${ultimo ? estadoDelUltimo : 'COMPLETED'}"}}',
    );
  }
  return '[${pasos.join(',')}]';
}

void main() {
  group('el estado de una corrida', () {
    test('todo completado es que fue bien', () {
      final r = LectorDeCorridas.leer(_commands());
      expect(r.como, ComoAcabo.bien);
      expect(r.bien, 3);
    });

    test('un paso fallado la tumba entera', () {
      final r = LectorDeCorridas.leer(
        _commands(estadoDelUltimo: 'FAILED'),
      );
      expect(r.como, ComoAcabo.mal);
      // Y se sabe cuántos llegaron: «2 de 3» dice dónde se rompió.
      expect(r.bien, 2);
      expect(r.pasos, 3);
    });

    test('un paso corriendo es una corrida en marcha', () {
      expect(
        LectorDeCorridas.leer(_commands(estadoDelUltimo: 'RUNNING')).como,
        ComoAcabo.enMarcha,
      );
    });

    test('**el andamiaje de Maestro no cuenta como pasos**', () {
      // Los dos primeros comandos son definir variables y aplicar configuración.
      // Contarlos haría que «5 pasos» no coincidiera con las tres líneas que
      // alguien escribió en su `.yaml`, y eso hace desconfiar del número.
      expect(LectorDeCorridas.leer(_commands(pasosDePrueba: 3)).pasos, 3);
    });

    test('el dispositivo sale del entorno del primer comando', () {
      // No está en la raíz del JSON: viaja dentro del `defineVariablesCommand`.
      expect(
        LectorDeCorridas.leer(_commands(dispositivo: 'emulator-5556')).dispositivo,
        'emulator-5556',
      );
    });

    test('sin commands.json legible no se inventa un estado', () {
      // Pasa de verdad: el proceso murió antes de escribirlo. Decir «fue bien»
      // ahí sería mentir, y decir «falló» también.
      for (final basura in ['', 'no es json', '{}', '[]']) {
        expect(
          LectorDeCorridas.leer(basura).como,
          ComoAcabo.vayaUstedASaber,
          reason: 'con «$basura»',
        );
      }
    });
  });

  group('cuándo corrió', () {
    test('sale del nombre de la carpeta, no de su fecha en disco', () {
      // Copiar o mover la carpeta cambiaría la fecha del archivo; el nombre lo
      // puso Maestro y no se mueve.
      expect(
        LectorDeCorridas.cuandoDe('2026-08-25_163001'),
        DateTime(2026, 8, 25, 16, 30, 1),
      );
    });

    test('una carpeta que no sigue el patrón no da fecha inventada', () {
      expect(LectorDeCorridas.cuandoDe('otra-cosa'), isNull);
      expect(LectorDeCorridas.cuandoDe('2026-08-25'), isNull);
    });
  });

  group('atribuir una corrida que no lanzó Nexus', () {
    const pruebas = {
      '/casa/tienda': ['login', 'checkout'],
      '/casa/banco': ['login', 'transferir'],
      '/casa/blog': ['publicar'],
    };

    test('un nombre único se atribuye', () {
      final r = LectorDeCorridas.atribuyePorNombre('checkout', pruebas);
      expect(r.proyecto, '/casa/tienda');
    });

    test('**un nombre repetido no se adivina**', () {
      // `login.yaml` es el nombre más probable del mundo y está en dos proyectos.
      // Elegir uno sería atribuir mal la mitad de las veces, y sin decirlo.
      final r = LectorDeCorridas.atribuyePorNombre('login', pruebas);
      expect(r.proyecto, isNull);
      // Pero los candidatos se enseñan: fallar del lado visible, no del cómodo.
      expect(r.candidatos, containsAll(['/casa/tienda', '/casa/banco']));
    });

    test('un nombre que no está en ninguno queda sin proyecto', () {
      final r = LectorDeCorridas.atribuyePorNombre('vete_a_saber', pruebas);
      expect(r.proyecto, isNull);
      expect(r.candidatos, isEmpty);
    });
  });
}
