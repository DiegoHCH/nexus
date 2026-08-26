import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/donde_viven_las_corridas.dart';

void main() {
  test('la carpeta de un proyecto es su ruta, y se puede volver', () {
    // El nombre final no vale: dos proyectos pueden llamarse `app` y quedarían
    // mezclados en la misma carpeta, que es perder justo la atribución que esto
    // viene a resolver.
    const proyecto = '/Users/alguien/Workspace/tienda';
    final carpeta = DondeVivenLasCorridas.carpetaDe(proyecto);

    expect(carpeta, 'Users·alguien·Workspace·tienda');
    expect(carpeta, isNot(contains('/')));
    expect(DondeVivenLasCorridas.proyectoDe(carpeta), proyecto);
  });

  test('**Maestro añade su propia estructura a la ruta que se le da**', () {
    // Comprobado contra el binario: con `--debug-output /tmp/x` no escribe en
    // `/tmp/x`, escribe en `/tmp/x/.maestro/tests/<fecha>/<flow>/`. Suponer lo
    // contrario dejaría el índice mirando una carpeta vacía.
    const args = (raiz: '/soporte/pruebas', perfil: 'work', proyecto: '/casa/app');

    expect(
      DondeVivenLasCorridas.paraLanzar(
        raiz: args.raiz,
        perfil: args.perfil,
        proyecto: args.proyecto,
      ),
      '/soporte/pruebas/work/casa·app',
    );
    expect(
      DondeVivenLasCorridas.dondeAterrizan(
        raiz: args.raiz,
        perfil: args.perfil,
        proyecto: args.proyecto,
      ),
      '/soporte/pruebas/work/casa·app/.maestro/tests',
    );
  });
}
