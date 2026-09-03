import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/entities/linea_de_registro.dart';
import 'package:nexus/features/emulators/domain/usecases/los_registros_del_dispositivo.dart';

/// Los registros del sistema del dispositivo: de dónde salen y cómo se leen.
///
/// 🔴 **Esto no es lo que ya se ve.** `flutter run` reenvía lo que la app
/// imprime, y eso Nexus ya lo enseña. Lo que falta —y es la mitad de la
/// respuesta a «por qué se cayó»— es lo que dice el **sistema**: un crash
/// nativo, un ANR, el `Fatal signal 11`. Eso no pasa por el daemon de Flutter.
void main() {
  group('con qué se piden', () {
    test('en Android, con el formato que trae el pid', () {
      final args = LosRegistrosDelDispositivo.argumentos(
        plataforma: PlataformaEmulador.android,
        deviceId: 'emulator-5554',
      );

      expect(args, containsAllInOrder(['-s', 'emulator-5554', 'logcat']));
      expect(
        args,
        containsAllInOrder(['-v', 'threadtime']),
        reason:
            'es el único formato de logcat que trae pid, y sin pid no se puede '
            'separar lo de la app de lo de todo lo demás',
      );
    });

    // El registro de Android guarda un rato largo: abrirlo con quinientas
    // líneas de antes hace que la primera de la app se pierda de vista.
    test('y tirando lo que ya había en el búfer', () {
      expect(
        LosRegistrosDelDispositivo.argumentos(
          plataforma: PlataformaEmulador.android,
          deviceId: 'x',
        ),
        containsAllInOrder(['-T', '1']),
      );
      expect(
        LosRegistrosDelDispositivo.argumentos(
          plataforma: PlataformaEmulador.android,
          deviceId: 'x',
          desdeAhora: false,
        ),
        isNot(contains('-T')),
      );
    });

    // Sin `-u` se engancha al primer aparato que encuentre, que es el fallo que
    // nadie mira porque las líneas salen igual.
    test('en iOS, contra el aparato que se dice', () {
      expect(
        LosRegistrosDelDispositivo.argumentos(
          plataforma: PlataformaEmulador.ios,
          deviceId: '00008030-000C390C1AC0C02E',
        ),
        ['-u', '00008030-000C390C1AC0C02E'],
      );
    });

    // `adb` lo tiene cualquiera que compile Android; `idevicesyslog` viene de
    // libimobiledevice y es opcional. Quien pinte el botón necesita saberlo.
    test('cada plataforma con su binario, que no es el mismo', () {
      expect(
        LosRegistrosDelDispositivo.binarioPara(PlataformaEmulador.android),
        'adb',
      );
      expect(
        LosRegistrosDelDispositivo.binarioPara(PlataformaEmulador.ios),
        'idevicesyslog',
      );
    });
  });

  group('leer una línea de Android', () {
    test('la parte entera: pid, nivel, etiqueta y texto', () {
      final l = LosRegistrosDelDispositivo.leer(
        '09-03 10:00:00.123  1234  1256 E AndroidRuntime: FATAL EXCEPTION: main',
      )!;

      expect(l.pid, 1234);
      expect(l.nivel, NivelDeRegistro.error);
      expect(l.etiqueta, 'AndroidRuntime');
      expect(l.texto, 'FATAL EXCEPTION: main');
    });

    test('las seis letras de nivel', () {
      const letras = {
        'V': NivelDeRegistro.verboso,
        'D': NivelDeRegistro.depuracion,
        'I': NivelDeRegistro.info,
        'W': NivelDeRegistro.aviso,
        'E': NivelDeRegistro.error,
        'F': NivelDeRegistro.fatal,
      };

      letras.forEach((letra, nivel) {
        expect(
          LosRegistrosDelDispositivo.leer(
            '09-03 10:00:00.123  1  2 $letra Tag: x',
          )?.nivel,
          nivel,
          reason: letra,
        );
      });
    });

    // El que se vino a ver.
    test('un crash nativo se lee como fatal', () {
      final l = LosRegistrosDelDispositivo.leer(
        '09-03 10:00:00.123  9876  9876 F libc: Fatal signal 11 (SIGSEGV)',
      )!;

      expect(l.nivel, NivelDeRegistro.fatal);
      expect(l.texto, contains('SIGSEGV'));
    });

    test('un texto con dos puntos dentro no se parte por el primero', () {
      expect(
        LosRegistrosDelDispositivo.leer(
          '09-03 10:00:00.123  1  2 I Tag: a las 10:00: pasó algo',
        )?.texto,
        'a las 10:00: pasó algo',
      );
    });
  });

  group('leer una línea de iOS', () {
    test('la parte entera', () {
      final l = LosRegistrosDelDispositivo.leer(
        'Sep  3 10:00:00 iPhone Runner(Flutter)[1234] <Error>: algo se rompió',
      )!;

      expect(l.pid, 1234);
      expect(l.nivel, NivelDeRegistro.error);
      expect(l.etiqueta, 'Runner(Flutter)');
      expect(l.texto, 'algo se rompió');
    });

    // 🔴 `Notice` es lo **normal** en iOS, no un aviso. Traducirlo a «aviso» por
    // el nombre llenaría el filtro de ruido justo al subirlo a «solo avisos».
    test('Notice es normal, no un aviso', () {
      expect(
        LosRegistrosDelDispositivo.leer(
          'Sep  3 10:00:00 iPhone Runner[1] <Notice>: x',
        )?.nivel,
        NivelDeRegistro.info,
      );
      expect(
        LosRegistrosDelDispositivo.leer(
          'Sep  3 10:00:00 iPhone Runner[1] <Warning>: x',
        )?.nivel,
        NivelDeRegistro.aviso,
      );
    });
  });

  // Los dos formatos intercalan líneas que no son entradas, y negarse por ellas
  // dejaría la ventana vacía justo cuando algo se está cayendo.
  test('lo que no es una entrada se descarta sin romper nada', () {
    for (final linea in [
      '--------- beginning of crash',
      '',
      '        at com.ejemplo.App.main(App.java:12)',
      'cualquier cosa',
    ]) {
      expect(LosRegistrosDelDispositivo.leer(linea), isNull, reason: linea);
    }
  });

  group('qué se queda en pantalla', () {
    LineaDeRegistro linea({
      NivelDeRegistro nivel = NivelDeRegistro.info,
      String etiqueta = 'Tag',
      String texto = 'algo',
      int? pid = 100,
    }) => LineaDeRegistro(
      nivel: nivel,
      etiqueta: etiqueta,
      texto: texto,
      pid: pid,
    );

    test('el nivel es un suelo, no una igualdad', () {
      expect(
        LosRegistrosDelDispositivo.pasa(
          linea(nivel: NivelDeRegistro.fatal),
          minimo: NivelDeRegistro.aviso,
        ),
        isTrue,
      );
      expect(
        LosRegistrosDelDispositivo.pasa(
          linea(nivel: NivelDeRegistro.depuracion),
          minimo: NivelDeRegistro.aviso,
        ),
        isFalse,
      );
    });

    test('filtrando por proceso, lo de otro no entra', () {
      expect(
        LosRegistrosDelDispositivo.pasa(linea(pid: 999), delProceso: 100),
        isFalse,
      );
      expect(
        LosRegistrosDelDispositivo.pasa(linea(pid: 100), delProceso: 100),
        isTrue,
      );
    });

    // 🔴 La regla que no se ve: esconder las líneas sin pid mientras se filtra
    // por proceso es esconder justo el encabezado del volcado.
    test('una línea sin pid se queda aunque se filtre por proceso', () {
      expect(
        LosRegistrosDelDispositivo.pasa(linea(pid: null), delProceso: 100),
        isTrue,
      );
    });

    test('el texto busca también en la etiqueta', () {
      expect(
        LosRegistrosDelDispositivo.pasa(
          linea(etiqueta: 'AndroidRuntime'),
          conteniendo: 'runtime',
        ),
        isTrue,
      );
      expect(
        LosRegistrosDelDispositivo.pasa(linea(), conteniendo: 'nada de eso'),
        isFalse,
      );
    });

    test('un filtro en blanco no filtra', () {
      expect(
        LosRegistrosDelDispositivo.pasa(linea(), conteniendo: '  '),
        isTrue,
      );
    });
  });
}
