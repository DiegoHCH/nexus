import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';

void main() {
  group('la ventana de contexto', () {
    // El millón solo lo tiene la variante `[1m]`, y no saberlo cambia el
    // porcentaje por cinco.
    test('el tamaño sale del identificador del modelo', () {
      expect(
        const SessionMeter(model: 'claude-opus-5[1m]').contextWindow,
        1000000,
      );
      expect(const SessionMeter(model: 'claude-opus-5').contextWindow, 200000);
    });

    test('las tres cifras, como en el CLI', () {
      const meter = SessionMeter(
        model: 'claude-opus-5[1m]',
        contextTokens: 63300,
      );

      expect(meter.contextLabel, '63,3k / 1,0M (6 %)');
      expect(meter.contextPercent, 6);
    });

    test('con ventana de 200k, los mismos tokens pesan mucho más', () {
      const meter = SessionMeter(model: 'claude-opus-5', contextTokens: 63300);

      expect(meter.contextLabel, '63,3k / 200,0k (32 %)');
    });

    // Sin turno todavía no hay medida. Un «0 / 1,0M» se leería como una ventana
    // comprobada y vacía, que no es lo mismo que una que nadie ha mirado.
    test('sin tokens no se inventa una lectura', () {
      expect(const SessionMeter(model: 'claude-opus-5').contextLabel, isNull);
      expect(const SessionMeter().contextFraction, 0);
    });

    test('lo que llena el círculo va de 0 a 1 y no se pasa', () {
      expect(
        const SessionMeter(
          model: 'claude-opus-5',
          contextTokens: 100000,
        ).contextFraction,
        0.5,
      );
      // Una sesión reanudada puede traer más tokens que la ventana del modelo
      // que hay puesto ahora: el círculo se queda lleno, no se desborda.
      expect(
        const SessionMeter(
          model: 'claude-opus-5',
          contextTokens: 900000,
        ).contextFraction,
        1.0,
      );
    });
  });
}
