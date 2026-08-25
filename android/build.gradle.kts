allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// **Se le sube el `compileSdk` a los plugins que se quedaron atrás.**
//
// `flutter_pcm_sound` —el altavoz del teléfono— se fija en `compileSdkVersion 33`, y una
// dependencia suya (`androidx.fragment:fragment:1.7.1`) exige compilar contra 34 o más.
// El proyecto ya va por el 37; el que se queda corto es el plugin, así que el arreglo no
// puede estar en `app/`.
//
// Se hace en `afterEvaluate` porque el bloque `android` de cada plugin no existe hasta
// que su script se evalúa, y con `withGroovyBuilder` para no tener que meter los tipos
// de AGP en el classpath de este archivo. Y **antes** del `evaluationDependsOn` de
// abajo, que evalúa `:app` en el acto: después de eso, registrar un `afterEvaluate`
// sobre un proyecto ya evaluado es un error de Gradle, no un no-op.
//
// **Es un parche sobre código de otro y conviene saberlo**: solo sube a los que están
// por debajo, nunca baja a nadie, y desaparece el día que el plugin se actualice.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        android.withGroovyBuilder {
            val actual = getProperty("compileSdkVersion")?.toString() ?: ""
            val numero = actual.removePrefix("android-").toIntOrNull() ?: 0
            if (numero < 35) "compileSdkVersion"(35)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
