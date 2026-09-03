import 'package:nexus/features/assistant/domain/repositories/el_despacho_de_carpeta.dart';

/// Un despacho que no enruta: todo se atiende donde se pidió.
///
/// Es lo que necesitan las pruebas que **no van del enrutado** — la mayoría—:
/// sin esto tendrían que montar el workspace y las conversaciones para llegar a
/// lo que afirman, que las convertiría en pruebas de otra cosa. Las del enrutado
/// tienen las suyas en `enrutar_a_la_carpeta_que_dices_test.dart`.
class SinEnrutar implements ElDespachoDeCarpeta {
  const SinEnrutar();

  @override
  Future<LoQueQuedaPorHacer> despachar(
    String frase, {
    required String? carpetaDeAqui,
    required String loQueSeVe,
    required bool allowWrites,
    required List<String> attachments,
    bool elFocoSigue = true,
  }) async => AtiendeloTu(frase);
}
