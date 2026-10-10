# PUMA web

Hay dos entradas independientes: **`gerente.html`** es la aplicación web del gerente general adaptable a PC y teléfono, sin marco; **`index.html`** conserva la preview móvil. Tras iniciar el servidor indicado abajo, abre `http://127.0.0.1:8765/gerente.html` para la web general. Consulta [WEB_GERENTE_GENERAL.md](../WEB_GERENTE_GENERAL.md) para archivos y límites de verificación.

La aplicación normal se conecta a Supabase con **correo/contraseña de Auth**. Ya no usa `gerente.general / 1234` ni requiere publicar manualmente. Las operaciones se confirman en la base antes de mostrar éxito; si fallan, el formulario conserva sus datos.

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory web-preview
```

Abre `http://127.0.0.1:8765`. Antes de iniciar sesión sigue [PUESTA_EN_MARCHA.md](../PUESTA_EN_MARCHA.md): migración 002 final, cuenta Auth y perfil general. URL y clave pública ya están precargadas.

En **Más → Turnos y horarios** encontrarás programación con filtros, estados y contadores. Asigna un empleado activo y un horario mañana/tarde/noche/personalizado. Noche termina al día siguiente. Desde el detalle puedes editar o cancelar un turno Programado; la cancelación necesita confirmación y no borra historial. Entrada/salida cambian el estado a En curso/Completado. Los solapamientos y las fechas finales inválidas se rechazan.

Los módulos de combustible, cortes, personal, productos, ventas y servicios también guardan automáticamente en Supabase. Los datos se actualizan cada 30 segundos cuando no hay un formulario de turno/corte abierto. Las cuentas de gerentes se crean en Auth desde el módulo de Gerentes; si Supabase exige confirmar el correo, deben hacerlo antes de entrar.

`PUMA-Vista-Previa.html` empaqueta la misma aplicación y necesita Internet para datos reales. No es un modo offline de operación. `python web-preview/build-preview.py` lo regenera; `python scripts/test_web.py` ejecuta 44 pruebas desde la raíz. Las pruebas de render usan DOM simulado y no certifican apariencia real. La demostración local solo está disponible en el modo explícito de pruebas `?test=identificador`, con almacenamiento separado y sin datos remotos.
