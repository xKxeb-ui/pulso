# Pulso

App iOS personal que programa notificaciones locales a partir de plantillas con valores aleatorios. Se compila como IPA sin firmar en GitHub Actions; la instalación la hace el usuario con su propio método. Creado: 2026-11-13.

## Alcance

- Plantillas editables (título opcional y mensaje) con variables: `{nombre}`, `{apellido}`, `{monto}`, `{codigo}`. El sufijo `:n` recorta o fija la longitud: `{apellido:3}` da `Flo`, `{codigo:4}` da 4 dígitos. Las variables desconocidas se quedan tal cual.
- Plantilla inicial «Pago recibido»: `{nombre} {apellido:3}* te envió un pago por S/ {monto}. El cód. de seguridad es: {codigo}`.
- Valores compartidos por todas las plantillas: monto al azar entre mínimo y máximo (por defecto 1–10 000, sin decimales, máximo sin tope en la UI), 0–2 decimales, cinco formatos de separadores, código de 3 dígitos y listas editables de nombres y apellidos peruanos.
- Ritmo: fijo cada N segundos, minutos u horas, o aleatorio entre un mínimo y un máximo (cada límite con su unidad).
- Interfaz SwiftUI con Liquid Glass de iOS 26, monocroma (blanco y negro): 4 pestañas (Inicio, Plantillas, Valores, Cola), accesorio inferior con estado y botón, vista previa animada y respuesta háptica.
- Todo local: sin servidor, cuentas ni analítica.

## Restricciones reales de iOS

- iOS conserva como máximo 64 notificaciones pendientes por app. Pulso las programa una a una con el texto ya generado y rellena la cola al abrirse la app y con cada aviso recibido en primer plano. Con app cerrada, la cola cubre 64 × intervalo; con 1 s, sólo un minuto.
- El icono y el nombre de la notificación siempre son los de la app.
- Destino mínimo iOS 26.0, necesario para Liquid Glass.

## Mapa

- `project.yml`: definición XcodeGen; el `.xcodeproj` se genera en CI y no se versiona.
- `Pulso/Model.swift`: modelo puro (intervalos, montos, nombres, plantillas, renderizado con semilla). Sin UIKit, para probarlo con `swiftc`.
- `Pulso/Store.swift`: estado persistido en `UserDefaults` y cola de notificaciones con operaciones en serie.
- `Pulso/Views/`: pantallas y componentes de Liquid Glass.
- `Tests/main.swift`: comprobaciones del modelo; CI las ejecuta antes de compilar.
- `.github/workflows/build-ipa.yml`: prueba, compila sin firma y publica el artefacto `Pulso-ipa`.
- Guía general: `Operations/docs/IOS_COMPILAR_GITHUB.md`.

## Estado y evidencia

- 2026-11-13: código 1.0.0 (build 1) escrito y con commit local. Sin Mac ni Swift en Linux, todavía no se ha compilado.
- Por indicación del usuario no se compila hasta nuevo aviso. Repo previsto: público. `gh` 2.104.0 está instalado en `~/.local/bin` pero sin vincular (`gh auth login --web --scopes workflow`).
- Icono generado con `work/scripts/icon.py` (Pillow), fuera de Git.

## Próximos pasos

1. Crear el repositorio privado en GitHub, hacer push y corregir lo que falle en el primer run.
2. Instalar el IPA y comprobar notificaciones, cola y Liquid Glass en un iPhone real.
3. Añadir plantillas nuevas cuando el usuario las pase.
