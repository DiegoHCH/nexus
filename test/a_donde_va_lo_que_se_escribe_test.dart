import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/a_donde_va_lo_que_se_escribe.dart';

/// El orden en que se reconocen los atajos del compositor.
///
/// 🔴 **Vivía dentro de un `submit` de 217 líneas y no lo cubría nada.** No es
/// plumbing: es una precedencia, y equivocarla **secuestra trabajo de verdad**.
/// `LoQueSePreguntaDeLaAgenda` ya lo dice de su lado —«buscar "reunión" dentro
/// del texto convertiría "arregla el bug de la pantalla de reuniones" en una
/// consulta de agenda»— y esto es lo mismo un nivel más arriba.
void main() {
  ADondeVa donde(
    String frase, {
    bool esElParte = false,
    bool hayAdjuntos = false,
  }) => ADondeVaLoQueSeEscribe.de(
    frase,
    esElParte: esElParte,
    hayAdjuntos: hayAdjuntos,
  );

  test('lo normal va a Claude', () {
    expect(donde('arregla el crash del perfil'), isA<AClaude>());
    expect(donde(''), isA<AClaude>());
  });

  group('los atajos, cada uno al suyo', () {
    test('git', () {
      final va = donde('!git status') as AlGit;

      expect(va.comando.comando, 'git');
    });

    test('dibujar', () {
      expect((donde('/imagen un zorro') as ADibujar).descripcion, 'un zorro');
    });

    test('editar la anterior', () {
      expect(
        (donde('/edita ponle fondo azul') as AEditarLaImagen).cambio,
        'ponle fondo azul',
      );
    });

    test('la agenda', () {
      expect(donde('qué reuniones tengo hoy'), isA<ALaAgenda>());
    });

    test('el parte', () {
      expect(donde('dame el daily'), isA<AlParte>());
    });
  });

  // 🔴 La asimetría que no se ve y se rompe sola.
  group('los adjuntos no valen igual para todos', () {
    test('dibujar y editar los admiten: son las referencias', () {
      expect(donde('/imagen un zorro', hayAdjuntos: true), isA<ADibujar>());
      expect(
        donde('/edita fondo azul', hayAdjuntos: true),
        isA<AEditarLaImagen>(),
        reason:
            'lo que se suelta en la caja es material, no un motivo para no '
            'reconocer el atajo',
      );
    });

    test('la agenda y el parte no', () {
      expect(
        donde('mi agenda', hayAdjuntos: true),
        isA<AClaude>(),
        reason: 'quien suelta archivos y escribe «mi agenda» pide otra cosa',
      );
      expect(donde('dame el daily', hayAdjuntos: true), isA<AClaude>());
    });

    test('y git tampoco se estorba con ellos', () {
      expect(donde('!git status', hayAdjuntos: true), isA<AlGit>());
    });
  });

  // Un parte que mencione `/imagen` acabaría dibujando.
  test('redactando el parte no se reconoce ningún atajo', () {
    for (final frase in [
      '!git log',
      '/imagen un gráfico',
      '/edita ponlo en azul',
      'mi agenda',
      'dame el daily',
    ]) {
      expect(donde(frase, esElParte: true), isA<AClaude>(), reason: frase);
    }
  });

  group('el orden entre atajos', () {
    // `!` no empieza ninguna frase que alguien escriba en serio, que es lo que
    // permite mirarlo primero sin pensarlo.
    test('git gana a lo que venga detrás', () {
      expect(donde('!git log --oneline /imagen'), isA<AlGit>());
    });

    test('dibujar gana a editar', () {
      expect(donde('/imagen un zorro'), isA<ADibujar>());
    });

    // Lo importante del orden es lo que **no** debe pasar: una frase de trabajo
    // que suene a atajo sigue siendo trabajo.
    test('una frase de trabajo que nombra un atajo no lo dispara', () {
      for (final frase in [
        'arregla el bug de la pantalla de reuniones',
        'revisa el generador de imagen del perfil',
        'documenta cómo se pide la agenda',
      ]) {
        expect(donde(frase), isA<AClaude>(), reason: frase);
      }
    });
  });

  test('los espacios de más no cambian a dónde va', () {
    expect(donde('   /imagen un zorro  '), isA<ADibujar>());
    expect(donde('  dame el daily '), isA<AlParte>());
  });
}
