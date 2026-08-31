import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/artifacts/data/datasources/gemini_image_data_source.dart';
import 'package:nexus/features/artifacts/domain/usecases/lo_que_se_pide_dibujar.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';

/// Lo que salió de pedir una imagen: dónde quedó, o por qué no salió.
typedef LoQueSalio = ({String? ruta, String? problema});

/// Genera una imagen y la deja en la carpeta de documentos.
///
/// Ahí y no en un temporal porque **es el sitio donde ya viven las cosas que
/// produce Nexus**: el visor las abre, el chat las enseña en miniatura y la
/// lista de documentos las encuentra. Una imagen en `/tmp` sería una que
/// desaparece sin avisar.
final generarUnaImagenProvider = Provider<Future<LoQueSalio> Function(String)>((
  ref,
) {
  return (descripcion) async {
    final llave = await ref.read(geminiImageKeyStoreProvider).read();
    if (llave == null || llave.isEmpty) {
      return (ruta: null, problema: 'sin-llave');
    }
    final carpeta = ref.read(artifactsFolderProvider);
    if (carpeta == null || carpeta.isEmpty) {
      return (ruta: null, problema: 'sin-carpeta');
    }

    final hecha = await const GeminiImageDataSource().generar(
      llave: llave,
      descripcion: descripcion,
    );
    if (!hecha.salio) return (ruta: null, problema: hecha.problema);

    final nombre = LoQueSePideDibujar.nombrePara(descripcion, DateTime.now());
    final destino = File('$carpeta/$nombre');
    try {
      await destino.parent.create(recursive: true);
      await destino.writeAsBytes(hecha.bytes!);
    } on FileSystemException catch (e) {
      // La imagen existió y se perdió al guardarla, que es lo peor que
      // puede pasar aquí: se pagó y no quedó nada. Se dice con el motivo.
      return (ruta: null, problema: 'no se pudo guardar: ${e.message}');
    }

    // Para que la lista de documentos la vea sin reabrir nada.
    ref.invalidate(artifactsProvider);
    return (ruta: destino.path, problema: null);
  };
});
