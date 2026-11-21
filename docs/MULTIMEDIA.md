# Respaldo de multimedia en Pulso

En Inicio, abre **Multimedia** y pulsa **Activar respaldo**. Pulso verifica la política de Toshiba y muestra la dirección del servidor, el alcance del respaldo y qué ocurre al dejar la pantalla. **Rechazar** deja el respaldo desactivado. **Aceptar e iniciar respaldo** guarda el consentimiento para ese destino y solicita el permiso de Fotos si aún falta.

Con acceso completo, las fotos y los videos disponibles para respaldo se copian automáticamente. Con acceso limitado, se respalda el conjunto autorizado por iOS. Esto incluye el álbum Oculto cuando PhotoKit devuelve sus elementos. El consentimiento de la versión 2 cubre los archivos autorizados en el futuro. Si ya habías activado una versión anterior con un alcance más reducido, Pulso pide aceptar el alcance actualizado y conserva el registro de archivos enviados. La app conserva los originales en Fotos. Los archivos enviados pueden incluir fecha o ubicación.

## Avance y reanudación

Pulso comprueba el permiso de Fotos y reanuda el respaldo al volver a la app, desde cualquier pantalla. También observa los cambios de la fototeca mientras está activa y solicita a iOS tiempo en segundo plano. iOS decide cuándo puede ejecutar esas tareas. Cuando termina el tiempo asignado, Pulso cancela el intento y conserva el avance confirmado.

**Detener y desactivar respaldo** cancela la operación y retira el consentimiento guardado. El registro local de archivos confirmados permite retomar el respaldo si lo autorizas de nuevo para el mismo destino. El receptor puede conservar los archivos y partes que ya recibió. Con **Avisar al comenzar y terminar**, Pulso solicita permiso para mostrar avisos de inicio y resultado.

## Cambio de IP

Pulso consulta la misma política pública firmada que WingyFlap. El procedimiento para publicarla desde Toshiba está en `Projects/wingy-flap/android/docs/RUTAS_FIRMADAS.md` de CodexFS. Un cambio se aplica a las dos apps. Al cambiar de servidor, prepara el receptor HTTPS, autoriza el pin del certificado, revoca la IP anterior y publica el cambio. La clave de firma se queda en Toshiba.

Pulso verifica la firma, revisión y vigencia de la política, además de la identidad TLS del receptor. Comprueba la ruta antes de las peticiones y puede reutilizar la última política válida durante 20 segundos. Una dirección o un pin distintos requieren consentimiento nuevo. El registro de archivos confirmados se guarda por dirección e instalación. Las fotos se envían individualmente y los videos en partes de 4 MiB.
