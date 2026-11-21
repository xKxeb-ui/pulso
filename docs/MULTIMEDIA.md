# Respaldo de multimedia en Pulso

En el primer inicio, crea el perfil con tu nombre y responde al permiso de Fotos. Desde Inicio, toca la onda de Pulso en la esquina superior derecha y pulsa **Activar respaldo**. La app verifica la política de Toshiba y muestra el destino, el nombre que identificará el respaldo en el servidor y las fotos y videos que podrá copiar. **Rechazar** deja el respaldo desactivado. **Aceptar e iniciar respaldo** guarda el consentimiento para ese destino y perfil.

Con acceso completo se respaldan fotos y videos de la fototeca. Con acceso limitado se respalda el conjunto autorizado por iOS. Esto incluye el álbum Oculto cuando PhotoKit devuelve sus elementos. El alcance de fuentes sigue siendo la fototeca personal. El consentimiento cubre los archivos que iOS autorice más adelante. Si ya habías activado una versión anterior, Pulso pide confirmar una vez el envío del nombre y conserva el registro de archivos ya enviados. Los originales se conservan en Fotos. Los archivos enviados pueden incluir fecha o ubicación.

## Avance y reanudación

Pulso comprueba el permiso de Fotos y reanuda el respaldo al volver a la app. En primer plano, observa los cambios de la fototeca y comprueba aproximadamente cada segundo si cambia la cantidad de elementos de Oculto devueltos por PhotoKit. Un cambio programa otro pase de los pendientes. Pulso solicita a iOS tiempo en segundo plano. iOS decide cuándo concede ese tiempo y Pulso conserva las cargas confirmadas si el intento se interrumpe.

**Detener y desactivar respaldo** cancela la operación y retira el consentimiento guardado. El registro local de archivos confirmados permite retomar el respaldo si lo autorizas de nuevo para el mismo destino. El receptor puede conservar los archivos y partes que ya recibió. Con **Avisar al comenzar y terminar**, Pulso solicita permiso para mostrar avisos de inicio y resultado.

## Cambio de IP

Pulso consulta la misma política pública firmada que WingyFlap. El procedimiento para publicarla desde Toshiba está en `Projects/wingy-flap/android/docs/RUTAS_FIRMADAS.md` de CodexFS. Un cambio se aplica a las dos apps. Al cambiar de servidor, prepara el receptor HTTPS, autoriza el pin del certificado, revoca la IP anterior y publica el cambio. La clave de firma se queda en Toshiba.

Pulso verifica la firma, revisión y vigencia de la política, además de la identidad TLS del receptor. Comprueba la ruta antes de las peticiones y puede reutilizar la última política válida durante 20 segundos. Una dirección o un pin distintos requieren consentimiento nuevo. El registro de archivos confirmados se guarda por dirección e instalación. El respaldo procesa hasta cinco archivos en paralelo y mantiene los videos en partes reanudables de 4 MiB.
