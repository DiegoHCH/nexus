import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/presentation/providers/repo_de_pruebas_providers.dart';
import 'package:nexus/features/e2e/presentation/widgets/cuentas_de_un_proyecto.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Las cuentas con las que corren las pruebas, por proyecto.
///
/// **Sección propia y no un trozo de Pruebas.** Aquella responde «¿qué pruebas
/// tengo y dónde viven?»; ésta, «¿con qué credenciales corren?». Son dos preguntas
/// distintas y la segunda trae un formulario con contraseñas dentro, que no es algo
/// que uno quiera encontrarse de paso.
///
/// 🔴 **Un proyecto sin cuentas no se lista.** Enseñar los seis emparejados con
/// «ninguna» al lado convierte la sección en un inventario de vacíos: lo que se
/// viene a ver es lo que hay configurado. Los que no tienen se alcanzan por el
/// desplegable de abajo, que es donde la ausencia sí es la respuesta.
class CuentasSection extends ConsumerWidget {
  const CuentasSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final carpetas = ref.watch(workspaceControllerProvider).folders;

    final conCuentas = [
      for (final carpeta in carpetas)
        if (ref.watch(cuentasDePruebaProvider(carpeta.workingDirectory)).isNotEmpty)
          carpeta,
    ];

    return ListView(
      children: [
        Text(
          strings.e2eAccountsWhere,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s4),

        if (conCuentas.isEmpty)
          Text(
            strings.e2eAccountsNoneAnywhere,
            style: NexusTypography.body.copyWith(color: colors.mute),
          ),

        for (final carpeta in conCuentas)
          Padding(
            padding: const EdgeInsets.only(bottom: NexusSpacing.s5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  carpeta.nombreDelRepo,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                Text(
                  carpeta.workingDirectory,
                  style: NexusTypography.mono.copyWith(color: colors.rule2),
                ),
                const SizedBox(height: NexusSpacing.s2),
                CuentasDeUnProyecto(proyecto: carpeta.workingDirectory),
              ],
            ),
          ),

        // La puerta para los que todavía no tienen ninguna. Va al final porque es
        // la acción rara: lo normal es venir a mirar o corregir una que ya está.
        if (carpetas.isNotEmpty) ...[
          const Divider(),
          Text(
            strings.e2eAccountsAddTo,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s2),
          for (final carpeta in carpetas)
            if (!conCuentas.contains(carpeta))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      editarCuenta(context, carpeta.workingDirectory, null),
                  child: Text(carpeta.nombreDelRepo),
                ),
              ),
        ],
      ],
    );
  }
}
