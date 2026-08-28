import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/entities/pasada_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/el_numero_de_las_pruebas.dart';

/// El número que se lleva a la reunión.
///
/// La mitad de estas pruebas comprueban lo que el número **no** dice. El
/// encargo pedía «lo corre cualquiera a diario» y de esa frase solo se puede
/// medir la mitad desde una máquina; el resto de este archivo existe para que
/// nadie complete la otra mitad más adelante sin darse cuenta.

final ahora = DateTime(2026, 8, 28, 12);

PasadaDePrueba pasada({
  required int haceDias,
  ComoAcabo comoAcabo = ComoAcabo.bien,
  String? proyecto = '/repos/app',
  int horas = 0,
}) => PasadaDePrueba(
  carpeta: '/test/$haceDias-$horas-$proyecto',
  flow: 'login',
  cuando: ahora.subtract(Duration(days: haceDias, hours: horas)),
  comoAcabo: comoAcabo,
  proyecto: proyecto,
);

void main() {
  test('sin pasadas no hay número, y no revienta', () {
    final numero = ElNumeroDeLasPruebas.de(const [], ahora: ahora);

    expect(numero.ultimos30, 0);
    expect(numero.dias, 0);
    expect(numero.desde, isNull);
    // `null` y no `0`: no hay con qué comparar, que no es lo mismo que «no
    // creció». Un cero ahí se pintaría como una caída.
    expect(numero.veces, isNull);
  });

  test('cuenta la ventana de 30 días y la anterior por separado', () {
    final numero = ElNumeroDeLasPruebas.de([
      pasada(haceDias: 1),
      pasada(haceDias: 29),
      pasada(haceDias: 31),
      pasada(haceDias: 59),
      // Fuera de las dos ventanas: no cuenta en ninguna, pero sí fija el
      // «desde», porque «47 pasadas» no dice nada sin saber desde cuándo.
      pasada(haceDias: 400),
    ], ahora: ahora);

    expect(numero.ultimos30, 2);
    expect(numero.previos30, 2);
    expect(numero.veces, 1.0);
    expect(numero.desde, ahora.subtract(const Duration(days: 400)));
  });

  test('los días son distintos, no las pasadas', () {
    // Cuarenta pasadas en una tarde son alguien peleándose con un flow, no una
    // costumbre. Sin este dato el número miente por el lado bueno.
    final numero = ElNumeroDeLasPruebas.de([
      for (var i = 0; i < 8; i++) pasada(haceDias: 2, horas: i),
      pasada(haceDias: 5),
    ], ahora: ahora);

    expect(numero.ultimos30, 9);
    expect(numero.dias, 2);
  });

  test('lo que no acabó no cuenta como resultado', () {
    final numero = ElNumeroDeLasPruebas.de([
      pasada(haceDias: 1),
      pasada(haceDias: 1, comoAcabo: ComoAcabo.mal),
      pasada(haceDias: 1, comoAcabo: ComoAcabo.enMarcha),
      pasada(haceDias: 1, comoAcabo: ComoAcabo.vayaUstedASaber),
    ], ahora: ahora);

    expect(numero.ultimos30, 4, reason: 'las cuatro se corrieron');
    // Pero solo dos son un resultado. Contar la que sigue en marcha o la que no
    // dejó rastro como fallo inflaría justo el número que nadie quiere inflado.
    expect(numero.bien, 1);
    expect(numero.mal, 1);
  });

  test('un mes sin pasadas anteriores no se divide entre cero', () {
    final numero = ElNumeroDeLasPruebas.de([
      pasada(haceDias: 1),
      pasada(haceDias: 2),
    ], ahora: ahora);

    expect(numero.previos30, 0);
    expect(numero.veces, isNull);
  });

  test('crecer se puede decir con un número', () {
    final numero = ElNumeroDeLasPruebas.de([
      for (var i = 0; i < 47; i++) pasada(haceDias: 1 + i % 22, horas: i),
      for (var i = 0; i < 3; i++) pasada(haceDias: 35 + i),
    ], ahora: ahora);

    expect(numero.ultimos30, 47);
    expect(numero.previos30, 3);
    expect(numero.veces!.toStringAsFixed(1), '15.7');
  });

  test('los proyectos se cuentan una vez, y los sin atribuir no cuentan', () {
    final numero = ElNumeroDeLasPruebas.de([
      pasada(haceDias: 1, proyecto: '/repos/app'),
      pasada(haceDias: 2, proyecto: '/repos/app'),
      pasada(haceDias: 3, proyecto: '/repos/otra'),
      // Sin atribuir: se enseña en la lista, pero no puede sumar un proyecto
      // que nadie sabe cuál es.
      pasada(haceDias: 4, proyecto: null),
    ], ahora: ahora);

    expect(numero.proyectos, 2);
  });

  // El de forma. La tentación de la siguiente vuelta es contar personas —el
  // encargo pedía «lo corre cualquiera»— y aquí no hay de dónde: el único campo
  // que se le parece es `perfil`, que es una cuenta de Claude de **esta**
  // máquina. Contar perfiles distintos y llamarlo «gente» daría dos para quien
  // tenga la cuenta del trabajo y la personal, y cero para un equipo entero
  // trabajando en sus propios Macs.
  test(
    'el número no mira el perfil, que es lo que se parece a una persona',
    () {
      final fuente =
          File('lib/features/e2e/domain/usecases/el_numero_de_las_pruebas.dart')
              .readAsLinesSync()
              .where((l) => !l.trimLeft().startsWith('///'))
              .join('\n');

      expect(
        fuente,
        isNot(contains('.perfil')),
        reason:
            'contar perfiles sería contar cuentas de una máquina y llamarlo '
            'equipo: dos para quien tiene trabajo y personal, cero para un '
            'equipo entero en sus propios Macs',
      );
    },
  );
}
