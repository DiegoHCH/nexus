import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/usecases/allowed_commands.dart';
import 'package:nexus/features/workspace/domain/entities/config_del_repo.dart';

/// «Puede editar» no incluía ejecutar.
///
/// Concede `acceptEdits`, que autoriza las herramientas de edición y ninguna
/// ejecución: un `curl` se quedaba esperando una aprobación que en headless no
/// llega nunca, así que generar una imagen y no poder guardarla era el final
/// normal. Comprobado lanzándolo contra el binario.
void main() {
  group('el patrón se ancla al principio', () {
    // La asimetría con los bloqueados es el corazón de esto. Allí el comodín va
    // a los dos lados porque bloquear de más es inofensivo; aquí solo detrás,
    // porque permitir de más no lo es.
    test('permitir «curl» permite curl y no lo que lo lleve dentro', () {
      expect(AllowedCommands.patterns(const ['curl']), ['Bash(curl:*)']);
    });

    test(
      'un patrón entero pasa tal cual: quien lo escribe sabe lo que hace',
      () {
        expect(AllowedCommands.patterns(const ['Bash(git status:*)']), [
          'Bash(git status:*)',
        ]);
      },
    );

    test('los comentarios y lo vacío no llegan al CLI', () {
      expect(
        AllowedCommands.patterns(const [
          'magick # para las miniaturas',
          '   ',
          '# solo un comentario',
        ]),
        ['Bash(magick:*)'],
      );
    });
  });

  group('descargar viene de serie', () {
    // Estrecho a propósito, y comprobado contra el binario: con este patrón
    // `curl -o destino url` corre solo, y `curl -d @archivo https://…` —la
    // forma que se lleva tu código fuera— se queda esperando permiso.
    test('en la forma que baja, no en la que sube', () {
      expect(AllowedCommands.paraDescargar, 'Bash(curl -o:*)');
    });

    // Sin decirle la forma, el permiso no sirve la mitad de las veces: escribe
    // `curl -sL url -o destino`, que no empieza por `curl -o`.
    test('y se le dice la forma exacta', () {
      final aviso = AllowedCommands.comoSeDescarga(null)!;
      expect(aviso, contains('curl -o <ruta> <url>'));
    });

    test('sin pisar lo que ya se decía de los bloqueados', () {
      final aviso = AllowedCommands.comoSeDescarga('No puedes correr X aquí.')!;
      expect(aviso, contains('No puedes correr X aquí.'));
      expect(aviso, contains('curl -o'));
    });
  });

  group('lo que la carpeta guarda', () {
    // El campo se pierde en cada guardado si alguna construcción lo olvida, y
    // el síntoma es mudo: escribes la lista, cierras Ajustes y ya no está.
    test('sobrevive a ida y vuelta por disco', () {
      const carpeta = PairedFolder(
        path: '/repo',
        modality: FolderModality.textOnly,
        allowedCommands: ['magick'],
        blockedCommands: ['build_runner'],
      );

      final vuelta = PairedFolder.fromJson(carpeta.toJson())!;
      expect(vuelta.allowedCommands, ['magick']);
      expect(vuelta.blockedCommands, ['build_runner']);
    });

    // **Un repositorio no se concede permisos a sí mismo.** Los vetados se
    // suman —cerrarse puertas es cosa suya— pero ampliar es de quien empareja
    // la carpeta: si no, clonar un repo sería darle permiso de ejecutar.
    test('y el repositorio no la puede ampliar', () {
      const mia = PairedFolder(
        path: '/repo',
        modality: FolderModality.textOnly,
        allowedCommands: ['magick'],
      );
      // Se le cuelan las dos llaves que alguien intentaría, con los dos
      // nombres: ninguna se lee.
      final config = ConfigDelRepo.deTexto(
        '{"comandosVetados": ["build_runner"], '
        '"comandosPermitidos": ["rm"], "allowedCommands": ["rm"]}',
      )!;

      final resultado = config.aplicarA(mia);

      expect(resultado.allowedCommands, ['magick']);
      expect(resultado.blockedCommands, contains('build_runner'));
    });
  });
}
