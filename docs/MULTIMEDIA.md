# Multimedia en Pulso

En Inicio, abre **Multimedia** y selecciona las fotos y los videos en el selector de iOS. Pulso verifica la política de Toshiba y muestra la dirección del servidor antes de enviar. Cada envío requiere **Confirmar y enviar**. Los archivos pueden incluir metadatos como la fecha o la ubicación.

Mantén abierta la pantalla Multimedia durante la transferencia. **Detener** cancela la actividad en curso. El contador muestra los archivos que el receptor confirmó. Mientras conserves la selección, **Revisar y continuar** reintenta los pendientes y consulta qué partes de un video ya recibió el servidor. Un envío detenido puede haber dejado archivos o partes en el servidor.

**Avisar al terminar** solicita el permiso de avisos de iOS y publica el resultado de la transferencia. La programación de las notificaciones por plantilla vive en `Store.swift`.

## Cambio de IP

Pulso consulta la misma política pública firmada que WingyFlap. El procedimiento para editar las rutas y publicarlas desde Toshiba está en `Projects/wingy-flap/android/docs/RUTAS_FIRMADAS.md` de CodexFS. La operación afecta a las dos apps. Al cambiar de servidor, prepara el receptor HTTPS, autoriza el pin del certificado, revoca la IP anterior y publica el cambio. La clave de firma se queda en Toshiba.

Pulso verifica la firma, la revisión y la vigencia de la política. También verifica la identidad TLS de cada conexión con la IP y el pin autorizados. Antes de confirmar, muestra el primer destino habilitado. Consulta la política antes de cada archivo y puede reutilizarla hasta 20 segundos entre peticiones de un video. Si el destino confirmado deja de estar autorizado, interrumpe el envío y pide una confirmación nueva.

El receptor usa un identificador aleatorio de la instalación de Pulso para agrupar los archivos. Las fotos viajan individualmente y los videos se cargan en partes de 4 MiB.
