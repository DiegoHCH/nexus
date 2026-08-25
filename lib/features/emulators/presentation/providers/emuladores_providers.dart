import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';

final emuladoresDataSourceProvider = Provider<EmuladoresDataSource>(
  (ref) => const EmuladoresDataSource(),
);

/// Lo que hay en la máquina ahora mismo.
///
/// **Se relee y no se guarda**, por el mismo motivo que la lista de documentos:
/// el usuario puede cerrar un emulador desde su propia ventana, y una copia
/// cacheada estaría mintiendo justo cuando importa —al mirar si arrancar o
/// cerrar—. Cuesta un `flutter emulators` y un par de `adb`, así que se paga.
final emuladoresProvider =
    FutureProvider<({List<Emulador> emuladores, String? error})>(
      (ref) => ref.watch(emuladoresDataSourceProvider).listar(),
    );
