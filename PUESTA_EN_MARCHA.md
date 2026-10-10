# Activar PUMA con Supabase

La web independiente del gerente general está en **http://127.0.0.1:8765/gerente.html** cuando ejecutes el servidor del paso 4. La raíz `/index.html` conserva la preview móvil con marco. Consulta [WEB_GERENTE_GENERAL.md](WEB_GERENTE_GENERAL.md).

El proyecto ya tiene tablas y RLS. Auth responde correctamente y la nueva función de guardado está publicada. La consulta sin sesión a `station_documents` devuelve acceso denegado: **es correcto**, no se debe conceder lectura pública para resolverlo.

## Pasos que faltan en el panel

1. Ejecuta la **versión final** de [002_automatic_operations.sql](supabase/migrations/002_automatic_operations.sql) en SQL Editor. Se puede ejecutar nuevamente: usa `create or replace` y vuelve a establecer permisos. Incluye las últimas validaciones de turnos y revoca permisos anónimos que Supabase puede conceder por defecto.
2. Ve a **Authentication → Users → Add user → Create new user**. Introduce tu correo real y una contraseña. Activa **Auto Confirm User** para la cuenta inicial.
3. Abre [bootstrap_general.sql](supabase/bootstrap_general.sql). Cambia `REEMPLAZAR_CON_TU_CORREO` por ese mismo correo y ejecuta el archivo. Esto vincula la cuenta de Auth al perfil **Gerente general**; crear solamente la cuenta no asigna el rol.
4. Desde la raíz del proyecto, ejecuta:

   ```powershell
   python -m http.server 8765 --bind 127.0.0.1 --directory web-preview
   ```

   Abre `http://127.0.0.1:8765`. Inicia sesión con el correo y contraseña recién creados. URL y clave pública del proyecto ya están precargadas. No uses `gerente.general / 1234`: la aplicación normal ahora exige Auth real.
5. Crea una sucursal. **Guardar** la registra en Supabase automáticamente, sin pulsar Publicar. Los tanques nuevos están vacíos y tienen capacidad 10,000 galones.
6. Desde **Gerentes**, crea una cuenta de gerente de sucursal con correo y contraseña y asígnala. El registro por correo debe estar habilitado en Supabase Auth; si la confirmación de correo está habilitada, el gerente debe confirmarlo antes de iniciar sesión. La sesión del general no se sustituye por la nueva cuenta.
7. En Xcode abre el mismo proyecto, ejecuta la app y usa el mismo correo/contraseña. Las sucursales, tanques, cortes, personal, turnos, productos, ventas y servicios deben aparecer desde la misma base.

No compartas contraseñas ni claves administrativas en el chat. La clave `anon` es pública, pero el acceso a datos requiere sesión y perfil activo.

## Prueba del recorrido real

- Registra un empleado en web y comprueba que aparece en móvil después de actualizar o esperar hasta 30 segundos.
- En Turnos, selecciona el empleado, la fecha y **Noche**. Se calcula 22:00–06:00 del día siguiente. Guarda, abre detalle, edita observaciones y cancela con confirmación. El registro permanece Cancelado y el horario queda libre.
- Crea un producto con precio $10 y stock 5, vende 2 con pago $25: stock 3, total $20 y cambio $5. Confirma el mismo historial en el otro cliente.
- Registra un llenado; comprueba inventario e historial en ambas plataformas.
- Corta la conexión al guardar: no debe mostrarse éxito; el formulario conserva sus datos y permite reintentar.

## Si el acceso falla

| Mensaje | Qué revisar |
| --- | --- |
| Credenciales inválidas | Usar correo real de Auth, contraseña correcta y cuenta confirmada. |
| Perfil inactivo o no provisionado | Ejecutar el bootstrap con el correo correcto o revisar `profiles.active`. |
| Falta actualizar las funciones / PGRST202 | Ejecutar la versión final de la migración 002. |
| Conflicto de versión | Otro cliente modificó los datos. Se descarga el estado actual; revisa el formulario antes de reintentar. |
| Acceso denegado a la sucursal | Revisar rol, perfil activo y `profiles.station_id`; no abrir la tabla a `anon`. |

Las comprobaciones reales hechas hasta ahora verifican conectividad y existencia de tablas/funciones, **no una sesión de usuario ni una venta real**. Para completar esa comprobación hace falta crear la cuenta y ejecutar el recorrido anterior.

Opcional: [supabase/tests/automatic_operations.sql](supabase/tests/automatic_operations.sql) comprueba en SQL Editor permisos, revisiones, conflictos y baja de gerente dentro de una transacción que termina en `ROLLBACK`. No lo he ejecutado en tu servidor; no deja las cuentas ni los datos temporales de prueba.

Para la validación de fechas pasadas y eliminar perfiles de gerentes, ejecuta también `supabase/migrations/003_shift_history_manager_delete.sql` después de 002. Consulta [TURNOS_Y_ELIMINACION.md](TURNOS_Y_ELIMINACION.md).
