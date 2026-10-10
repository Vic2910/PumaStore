# Web independiente del gerente general

Se conservan `web-preview/index.html` y `PUMA-Vista-Previa.html` como preview móvil con marco. La nueva aplicación web se abre por separado en **`gerente.html`** y ocupa la pantalla del navegador, sin marco de teléfono.

## Abrir localmente

Desde la raíz del proyecto:

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory web-preview
```

- **Aplicación web del gerente general:** http://127.0.0.1:8765/gerente.html
- **Preview móvil conservada:** http://127.0.0.1:8765/index.html

Usa el correo y contraseña de una cuenta activa con perfil `general` en Supabase. Se mantienen las migraciones y el alta de cuentas indicadas en `PUESTA_EN_MARCHA.md`. Las cuentas de sucursal se rechazan en esta nueva página con un mensaje; sus permisos siguen controlados por Supabase RLS.

La navegación lateral incluye dashboard, sucursales, gerentes, rendimiento, llenados, personal, turnos, inventario comercial, punto de venta, servicios y cuenta. En teléfono pasa a un menú desplegable, sin simulación de dispositivo. El contenido utiliza tarjetas y campos más amplios; en escritorio el dashboard y las sucursales aprovechan varias columnas. Los formularios se conservan en diálogos adaptables y las operaciones esperan confirmación del servidor.

El sidebar organiza las opciones en un acordeón: **Panorama general** (Resumen y Rendimiento), **Administración** (Sucursales, Gerentes, Personal y Turnos), **Operación y ventas** (Llenados, Inventario comercial, Punto de venta y Servicios) y **Cuenta y conexión**. Se abre un grupo a la vez; al navegar se abre el grupo de la pantalla activa. La selección se conserva durante las actualizaciones de datos. Usa `details/summary` nativo para teclado y lectores de pantalla. Este ajuste modifica únicamente `gerente.js`, `gerente.css` y el paquete generado, sin cambios en la preview ni en Supabase.

## Archivos nuevos y reutilización

- `web-preview/gerente.html`: entrada independiente y estructura de encabezado, navegación y contenido.
- `web-preview/gerente.css`: estilos exclusivos, escritorio/tablet/teléfono; no se carga en la preview.
- `web-preview/gerente.js`: navegación de todos los módulos, menú móvil, identidad real y restricción de acceso a gerente general. Se carga después de la aplicación existente y reutiliza sus pantallas.
- `web-preview/build-general.py` y `PUMA-Gerente-General.html`: empaquetado autónomo opcional. Regenerar con `python web-preview/build-general.py`. Necesita Internet y Auth para acceder a datos reales.
- `scripts/test_web.py` y `web-preview/ui.test.js`: incluyen pruebas de navegación del portal, rol, menú y conservación de navegación de la preview.

Ambas entradas usan la misma lógica y cliente Supabase; no duplican la base ni requieren una migración. La sesión se guarda en memoria, por lo que una pestaña nueva o una recarga requieren iniciar sesión de nuevo. Este cambio no publica el portal en Internet; el servidor indicado permite usarlo en el PC local. Para acceder desde otro teléfono o PC hace falta servirlo en una dirección accesible, idealmente un alojamiento HTTPS.

## Validación

41 pruebas JavaScript aprobadas, incluidas las de guardado y Auth simulados. Las pruebas de render usan DOM simulado. El navegador automatizado falla al iniciar en este entorno; no se ha verificado la apariencia con capturas reales de escritorio y teléfono ni una sesión real de gerente general. La preview se conserva y sus archivos de entrada no se modifican para crear el portal.
