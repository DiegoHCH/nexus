import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/diagnostico/registro_de_la_app.dart';

/// El registro de la app, uno solo.
///
/// Lo sobreescribe `main` con el mismo que engancha al arrancar: si Ajustes
/// construyera el suyo, enseñaría una ruta correcta de un archivo en el que no
/// escribe nadie — que es peor que no enseñar ninguna.
final registroDeLaAppProvider = Provider<RegistroDeLaApp>(
  (ref) => RegistroDeLaApp(),
);

/// Dónde vive el registro. Asíncrono porque resolver la carpeta de soporte lo
/// es, y `null` mientras no se sepa — que es distinto de «no hay registro».
final rutaDelRegistroProvider = FutureProvider<String?>(
  (ref) => ref.watch(registroDeLaAppProvider).ruta,
);
