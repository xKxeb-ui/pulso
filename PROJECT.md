# Pulso

App iOS personal que programa notificaciones locales a partir de plantillas con valores aleatorios. Se compila como IPA sin firmar en GitHub Actions; la instalación la hace el usuario con su propio método. Creado: 2026-11-13.

## Alcance

- Plantillas editables (título opcional y mensaje) con variables: `{nombre}`, `{apellido}`, `{monto}`, `{codigo}`. El sufijo `:n` recorta o fija la longitud: `{apellido:3}` da `Flo`, `{codigo:4}` da 4 dígitos. Las variables desconocidas se quedan tal cual.
- Plantilla inicial «Pago recibido»: `{nombre} {apellido:3}* te envió un pago por S/ {monto}. El cód. de seguridad es: {codigo}`.
- Valores compartidos por todas las plantillas: monto al azar entre mínimo y máximo (por defecto 1–10 000, sin decimales, máximo sin tope en la UI), 0–2 decimales, cinco formatos de separadores, código de 3 dígitos y listas editables de nombres y apellidos peruanos.
- Ritmo: fijo cada N segundos, minutos u horas, o aleatorio entre un mínimo y un máximo (cada límite con su unidad).
- Interfaz SwiftUI con Liquid Glass de iOS 26, monocroma (blanco y negro): 4 pestañas (Inicio, Plantillas, Valores, Cola), accesorio inferior con estado y botón, vista previa animada y respuesta háptica.
- Las plantillas, los valores y la cola de avisos se guardan localmente.
- Multimedia: desde Inicio se pueden elegir fotos y videos y confirmar el envío al servidor de respaldo. Incluye progreso, Detener y aviso local de resultado opcional.

## Restricciones reales de iOS

- iOS conserva como máximo 64 notificaciones pendientes por app. Pulso las programa una a una con el texto ya generado y rellena la cola al abrirse la app y con cada aviso recibido en primer plano. Con app cerrada, la cola cubre 64 × intervalo; con 1 s, sólo un minuto.
- El icono y el nombre de la notificación siempre son los de la app.
- Destino mínimo iOS 26.0, necesario para Liquid Glass.

## Mapa

- `project.yml`: definición XcodeGen; el `.xcodeproj` se genera en CI y no se versiona.
- `Pulso/Model.swift`: modelo puro (intervalos, montos, nombres, plantillas, renderizado con semilla). Sin UIKit, para probarlo con `swiftc`.
- `Pulso/Store.swift`: estado persistido en `UserDefaults` y cola de notificaciones con operaciones en serie.
- `Pulso/Media/`: consentimiento, selección y transferencia. Reutiliza la política de rutas firmada que publica Toshiba para WingyFlap.
- `Pulso/Views/`: pantallas y componentes de Liquid Glass.
- `Tests/main.swift`: comprobaciones del modelo; CI las ejecuta antes de compilar.
- `.github/workflows/build-ipa.yml`: prueba, compila sin firma y publica el artefacto `Pulso-ipa`.
- Guía general: `Operations/docs/IOS_COMPILAR_GITHUB.md`.

## Estado y evidencia

- 2026-11-13: 1.0.0 (build 1) compilada en GitHub Actions (run 43537394081, Xcode 26.6, SDK iOS 26.5, 1 min 8 s) con las comprobaciones del modelo en verde. IPA verificado en `outputs/Pulso.ipa` (no versionado): `com.codex.local.pulso`, mínimo iOS 26.0.
- Repositorio público `xKxeb-ui/pulso`; `gh` 2.104.0 en `~/.local/bin` vinculado a esa cuenta. Un push a `main` que toque código compila solo; si no arranca, `gh workflow run build-ipa.yml`.
- Decisión 2026-11-13: la app conserva identidad propia (nombre e icono). No se replica la marca de Yape ni de otros medios de pago.
- Icono generado con `work/scripts/icon.py` (Pillow), fuera de Git.
- 2026-11-21: integración Multimedia en la rama local `codex/pulso-multimedia`, basada en `main`. Política pública vigente, firma, pin TLS y salud HTTPS del receptor verificados. Fotos, video por partes y reanudación comprobados con archivos sintéticos en un receptor local. La compilación iOS y la prueba en iPhone siguen pendientes.

## Próximos pasos

1. Compilar la rama Multimedia con Xcode 26 y verificarla en iPhone con fotos y videos de prueba.
2. Comprobar consentimiento, Detener, reintento y avisos de resultado, junto con la cola de notificaciones de Pulso.
3. Añadir plantillas nuevas cuando el usuario las pase.
