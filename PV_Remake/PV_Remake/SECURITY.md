# Seguridad de PVFinder

## Modelo de protección

- El repositorio **permanece privado**. `server.py`, SQLite y las variables de entorno **no se sirven** por la página web.
- `/delta.lua` es **público por diseño** para permitir el `loadstring`. Cualquier código ejecutado en el cliente (Lua, HTML, CSS o JavaScript) puede recuperarse o copiarse. Nunca insertar claves, contraseñas o secretos en esos archivos.
- Los datos privados se protegen con autorización **en el servidor**, no ocultando botones ni ofuscando Lua.
- Un token de **jugador** permite consultar el feed; no administrar enlaces ni registrar detecciones.
- La credencial de **recolector** autoriza solo el envío de datos. Su dueño puede enviar datos falsos: las detecciones del cliente no se verifican independientemente.
- La contraseña de **administrador** se configura en las variables secretas de Render. Las sesiones y credenciales se almacenan como hashes en SQLite.

## Controles agregados

- CSP restrictiva para HTML, política anti-iframe, encabezados de privacidad y permisos mínimos.
- Cookies de sesión `Secure` cuando el servicio usa HTTPS.
- Límites adicionales de solicitudes para el Live Feed y el canje de enlaces de usuario.
- Lista de campos expuestos por `/api/feed` reducida: los visitantes no reciben identificadores internos del recolector.
- Los tokens de jugador pueden revocarse; la página no permite descargar la base de datos ni el código de backend.

## Acciones del propietario

1. Activar **2FA** para GitHub y Render.
2. Evitar publicar capturas de tokens, contraseñas, credenciales, encabezados `Authorization` o variables de entorno.
3. Revocar accesos y recolectores que ya no se usen desde el panel privado.
4. Rotar inmediatamente las credenciales comprometidas.
5. Usar una contraseña larga, única y no compartida para el administrador.
6. Para protección avanzada frente a ataques de volumen: usar dominio propio + WAF/proxy administrado, si se justifica.

## Advertencias

No existe código del cliente «imposible de desofuscar», ni una página pública inmune a ataques. Las pruebas de seguridad deben realizarse de forma autorizada y periódica. No compartir ni usar una clave de recolector para iniciar sesión en Delta.
