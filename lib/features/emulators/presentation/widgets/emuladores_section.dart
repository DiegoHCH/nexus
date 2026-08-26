import 'package:flutter/material.dart';
import 'package:nexus/features/emulators/presentation/widgets/dispositivos_panel.dart';

/// Los emuladores de la máquina, en Ajustes.
///
/// **Sección y no un sheet sobre el orbe**, y la diferencia no es estética: el
/// visor de documentos interrumpe porque trae algo que acabas de pedir, y esto se
/// consulta *antes* de trabajar. Configuración, no noticia.
///
/// Lo que se ve lo pinta [DispositivosPanel], que es el mismo widget que usa el
/// menú del compositor. Aquí solo se decide que va entero y no compacto.
class EmuladoresSection extends StatelessWidget {
  const EmuladoresSection({super.key});

  @override
  Widget build(BuildContext context) => const DispositivosPanel();
}
