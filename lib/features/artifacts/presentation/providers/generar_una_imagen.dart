import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/artifacts/data/datasources/gemini_image_data_source.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/artifacts/domain/usecases/lo_que_se_pide_dibujar.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';

/// Lo que salió de pedir una imagen: dónde quedó y con qué id se le puede pedir
/// un cambio, o por qué no salió.
typedef LoQueSalio = ({String? ruta, String? id, String? problema});

/// Lo que hay que saber para pedir una: qué se quiere, de qué cuenta sale el
/// gasto, si se sigue de una anterior y qué imágenes se dan de referencia.
typedef ElEncargo = ({
  String descripcion,
  String? perfil,
  String? seguirDe,
  List<String> referencias,
});

/// Genera una imagen y la deja en la carpeta de documentos.
///
/// Ahí y no en un temporal porque **es el sitio donde ya viven las cosas que
/// produce Nexus**: el visor las abre, el chat las enseña en miniatura y la
/// lista de documentos las encuentra. Una imagen en `/tmp` sería una que
/// desaparece sin avisar.
final generarUnaImagenProvider = Provider<Future<LoQueSalio> Function(ElEncargo)>(
  (ref) {
    return (encargo) async {
      // La de **esta** cuenta. Sin llave aquí no se cae hacia otra: el gasto de
      // las imágenes sale de un bolsillo concreto, y tomar prestada la de otra
      // cuenta porque «alguna hay» es justo lo que esto viene a evitar.
      final llave = await ref
          .read(geminiImageKeyStoreProvider)
          .read(encargo.perfil);
      if (llave == null || llave.isEmpty) {
        return (ruta: null, id: null, problema: 'sin-llave');
      }
      final carpeta = ref.read(artifactsFolderProvider);
      if (carpeta == null || carpeta.isEmpty) {
        return (ruta: null, id: null, problema: 'sin-carpeta');
      }

      final hecha = await const GeminiImageDataSource().generar(
        llave: llave,
        modelo: ref.read(modeloDeImagenProvider).id,
        descripcion: encargo.descripcion,
        seguirDe: encargo.seguirDe,
        referencias: await _leerLasReferencias(encargo.referencias),
      );
      if (!hecha.salio) {
        return (ruta: null, id: null, problema: hecha.problema);
      }

      final nombre = LoQueSePideDibujar.nombrePara(
        encargo.descripcion,
        DateTime.now(),
      );
      final destino = File('$carpeta/$nombre');
      try {
        await destino.parent.create(recursive: true);
        await destino.writeAsBytes(hecha.bytes!);
      } on FileSystemException catch (e) {
        // La imagen existió y se perdió al guardarla, que es lo peor que puede
        // pasar aquí: se pagó y no quedó nada. Se dice con el motivo.
        return (
          ruta: null,
          id: null,
          problema: 'no se pudo guardar: ${e.message}',
        );
      }

      // Para que la lista de documentos la vea sin reabrir nada.
      ref.invalidate(artifactsProvider);
      return (ruta: destino.path, id: hecha.id, problema: null);
    };
  },
);

/// Lo que se adjuntó, leído del disco.
///
/// **Lo que no sea una imagen se ignora en silencio**, y es lo correcto: se
/// puede adjuntar un `.md` a la conversación por otro motivo, y negarse a
/// dibujar por eso sería castigar un gesto legítimo. Lo que no se puede leer,
/// igual: una referencia menos es peor que no generar nada.
Future<List<ImagenDeReferencia>> _leerLasReferencias(List<String> rutas) async {
  final leidas = <ImagenDeReferencia>[];
  for (final ruta in rutas) {
    if (!Artifact.isImage(ruta)) continue;
    try {
      final bytes = await File(ruta).readAsBytes();
      leidas.add(ImagenDeReferencia(bytes, _mimeDe(ruta)));
    } on FileSystemException {
      continue;
    }
  }
  return leidas;
}

String _mimeDe(String ruta) {
  final punto = ruta.lastIndexOf('.');
  final extension = punto == -1 ? '' : ruta.substring(punto).toLowerCase();
  return switch (extension) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.webp' => 'image/webp',
    '.gif' => 'image/gif',
    _ => 'image/png',
  };
}
