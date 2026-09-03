import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';

/// El README dice cuántas conversaciones caben. Que sea verdad.
///
/// 🔴 **El propio README presume de tener esta red y no la tenía para el
/// número.** Dice: «hay pruebas que fallan si desaparece **o si vuelve a ceder
/// algo que Nexus sí hace**: esa lista se encogió tres veces en dos días por
/// vender de menos». Y ahí estaba, vendiendo de menos: `Conversations.max`
/// subió de tres a seis cuando el uso corrigió el argumento —«no se siguen
/// todas a la vez: se dejan corriendo y se vuelve a ellas»— y el README se
/// quedó en tres, en dos sitios.
///
/// Que nadie lo notara es lo esperable: un número en prosa no lo comprueba
/// nada. Es el mismo motivo por el que `contrato_y_documento_test` compara el
/// código con `docs/PROTOCOL.md`.
void main() {
  const enLetra = {
    1: 'una',
    2: 'dos',
    3: 'tres',
    4: 'cuatro',
    5: 'cinco',
    6: 'seis',
    7: 'siete',
    8: 'ocho',
  };

  test('el número del README es el del código', () {
    final readme = File('README.md').readAsStringSync();
    final cabe = enLetra[Conversations.max];

    expect(
      cabe,
      isNotNull,
      reason:
          'subió el tope y no hay palabra para él: añádela arriba en vez de '
          'dar por buena una prueba que ya no comprueba nada',
    );

    final dice = RegExp(
      r'[Hh]asta (\w+) conversaciones',
    ).allMatches(readme).map((m) => m.group(1)!.toLowerCase()).toSet();

    expect(dice, isNotEmpty, reason: 'el README dejó de decir cuántas caben');
    expect(
      dice,
      {cabe},
      reason:
          'el README dice «${dice.join(', ')}» y caben $cabe '
          '(Conversations.max = ${Conversations.max})',
    );
  });
}
