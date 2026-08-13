import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/repositories/stays_awake_impl.dart';

/// Lo que se prueba aquí es el **recuento**, que es donde está la decisión: si
/// se le dijera al sistema «ya puedes dormirte» en cuanto termina el primer
/// encargo, con tres conversaciones en marcha el Mac se dormiría encima de las
/// otras dos. Y pasaría solo a veces —cuando la corta acabe antes—, que es la
/// peor forma de que pase.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> llamadas;

  setUp(() {
    llamadas = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.katanalabs.nexus/power'),
          (call) async {
            llamadas.add(call.method);
            return call.method == 'keepAwake' ? true : null;
          },
        );
  });

  test('un encargo: se pide una vez y se suelta una vez', () async {
    final awake = StaysAwakeImpl();

    final soltar = await awake.hold('uno');
    expect(llamadas, ['keepAwake']);

    soltar();
    await Future<void>.delayed(Duration.zero);
    expect(llamadas, ['keepAwake', 'allowSleep']);
  });

  test('dos a la vez: al sistema se le habla una sola vez', () async {
    final awake = StaysAwakeImpl();

    final primero = await awake.hold('uno');
    final segundo = await awake.hold('dos');
    expect(llamadas, ['keepAwake']);

    // El primero termina y el segundo sigue trabajando: aquí es donde el Mac
    // no puede dormirse.
    primero();
    await Future<void>.delayed(Duration.zero);
    expect(llamadas, ['keepAwake']);

    segundo();
    await Future<void>.delayed(Duration.zero);
    expect(llamadas, ['keepAwake', 'allowSleep']);
  });

  // Soltar dos veces el mismo pasaría con un `finally` que se ejecuta tras una
  // cancelación ya propagada; sin esta guarda, la cuenta se iría por debajo de
  // cero y el siguiente encargo no volvería a pedirlo.
  test('soltar dos veces el mismo no descuadra la cuenta', () async {
    final awake = StaysAwakeImpl();

    final soltar = await awake.hold('uno');
    soltar();
    soltar();
    await Future<void>.delayed(Duration.zero);

    final otro = await awake.hold('dos');
    expect(llamadas, ['keepAwake', 'allowSleep', 'keepAwake']);

    otro();
  });
}
