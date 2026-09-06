import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/franja_del_dia.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/domain/usecases/la_puerta_que_saluda.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

// La puerta: sin conversaciones abiertas, se saluda y se pregunta dónde.
//
// 🔴 **Nace de quitar un caso, no de arreglarlo.** La pantalla de arranque
// enseñaba la caja de texto con los chips de la conversación que acabaste de
// cerrar —carpeta, repo, rama y cuenta—, y escribir mandaba el encargo ahí sin
// decírtelo. La salida no era arreglar los chips: era que esa pantalla no tenga
// caja. Se saluda, se pregunta, y la interfaz aparece cuando hay dónde trabajar.

const _nexus = PairedFolder(
  path: '/Users/alguien/personal/nexus',
  modality: FolderModality.voice,
);
const _tienda = PairedFolder(
  path: '/Users/alguien/trabajo/front-mobile-b2c',
  modality: FolderModality.textOnly,
);

void main() {
  group('la hora se saluda como la saluda una persona', () {
    test('la mañana empieza a las seis', () {
      expect(
        LaPuertaQueSaluda.franjaDe(DateTime(2026, 9, 5, 5, 59)),
        FranjaDelDia.noche,
        reason: 'a las seis menos uno no se está empezando el día',
      );
      expect(
        LaPuertaQueSaluda.franjaDe(DateTime(2026, 9, 5, 6)),
        FranjaDelDia.manana,
      );
    });

    test('y acaba a las doce, no cuando lo diga el reloj', () {
      expect(
        LaPuertaQueSaluda.franjaDe(DateTime(2026, 9, 5, 11, 59)),
        FranjaDelDia.manana,
      );
      expect(
        LaPuertaQueSaluda.franjaDe(DateTime(2026, 9, 5, 12)),
        FranjaDelDia.tarde,
      );
    });

    test('la noche entra a las ocho', () {
      expect(
        LaPuertaQueSaluda.franjaDe(DateTime(2026, 9, 5, 19, 59)),
        FranjaDelDia.tarde,
      );
      expect(
        LaPuertaQueSaluda.franjaDe(DateTime(2026, 9, 5, 20)),
        FranjaDelDia.noche,
      );
    });
  });

  group('el saludo, en los dos idiomas', () {
    const es = NexusStringsEs();
    const en = NexusStringsEn();

    test('lleva tu nombre y la pregunta', () {
      final dicho = es.saludoDeLaPuerta(FranjaDelDia.manana, 'Argonauta');

      expect(dicho, startsWith('Buenos días, Argonauta'));
      expect(dicho, contains('¿En dónde vamos a trabajar hoy?'));
    });

    // Sin nombre elegido no se saluda a nadie a medias: se saluda y ya.
    test('sin nombre, no queda una coma huérfana', () {
      final dicho = es.saludoDeLaPuerta(FranjaDelDia.tarde, null);

      expect(dicho, 'Buenas tardes. ¿En dónde vamos a trabajar hoy?');
      expect(es.saludoDeLaPuerta(FranjaDelDia.tarde, ''), dicho);
    });

    test('y en inglés dice lo mismo, no lo mismo traducido a medias', () {
      expect(
        en.saludoDeLaPuerta(FranjaDelDia.noche, 'Argonauta'),
        'Good evening, Argonauta. Where are we working today?',
      );
    });
  });

  group('lo que contestas en la puerta', () {
    test('nombrar una carpeta abre ahí', () {
      final dicho = LaPuertaQueSaluda.interpreta('trabajemos en nexus', const [
        _nexus,
        _tienda,
      ]);

      expect(dicho, isA<SeTrabajaAqui>());
      expect((dicho as SeTrabajaAqui).carpeta, _nexus);
      expect(dicho.tarea, isEmpty, reason: 'solo dijo dónde, no qué');
    });

    // Si además dices qué, la conversación no nace muda: nace con trabajo.
    test('y si dices además qué hacer, eso viaja con ella', () {
      final dicho = LaPuertaQueSaluda.interpreta(
        'en nexus, mira el último PR',
        const [_nexus],
      );

      expect((dicho as SeTrabajaAqui).tarea, contains('el último PR'));
    });

    // 🔴 Decidido a la vista: viaja el **nombre**, no el contenido. Y una puerta
    // que esconde la mitad de las carpetas es media puerta.
    test('las de solo texto también se pueden nombrar', () {
      final dicho = LaPuertaQueSaluda.interpreta(
        'vamos a trabajar en front-mobile-b2c',
        const [_nexus, _tienda],
      );

      expect((dicho as SeTrabajaAqui).carpeta, _tienda);
    });

    test('nombrar dos no elige ninguna', () {
      final dicho = LaPuertaQueSaluda.interpreta(
        'nexus y front-mobile-b2c',
        const [_nexus, _tienda],
      );

      expect(dicho, isA<SeNombraronDos>());
      expect((dicho as SeNombraronDos).carpetas, hasLength(2));
    });

    test('y lo que no nombra ninguna se dice, no se adivina', () {
      expect(
        LaPuertaQueSaluda.interpreta('buenos días', const [_nexus, _tienda]),
        isA<NoSeEntendioDonde>(),
      );
    });
  });
}
