# Drivy — Endurecimiento de seguridad y privacidad

Corrige los hallazgos de la revisión de seguridad del 2026-10-28 (informes
`sec-repo-report.md` y `sec-app-report.md`), salvo el `.p12` compartido con ProofMate.
Rama `fix/security-hardening`. Entrega: un PR. Tests: `supabase/tests` (PGlite) y XCTest en CI.

## Specs

- **S1** Privacidad en App Store: `PrivacyInfo.xcprivacy` declara `UserDefaults` (CA92.1),
  sin tracking ni datos recogidos para tracking.
- **S2** Nombres en ligas: ningún RPC devuelve el uuid de otros usuarios (`is_me` en su
  lugar); el nombre visible inicial es un seudónimo, nunca el nombre real; el usuario ve y
  edita su nombre en Ajustes (1-30 caracteres); los clientes solo pueden actualizar
  `display_name` de su perfil.
- **S3** Invitaciones: códigos de 8 caracteres generados en el servidor (`create_league`),
  máximo 10 intentos fallidos de unión por hora y usuario, y el mismo error para código
  inexistente y liga llena.
- **S4** Ubicación: los textos de permiso describen lo que la app hace (grabación manual,
  también en segundo plano), sin prometer detección automática.
- **S5** Sentry: sin datos personales (filtro antes de enviar, sin breadcrumbs de red, errores
  reportados como código estable y mensaje fijo) y desactivado en builds DEBUG.
- **S6** Cierre de sesión: borra el ancla de freemium del usuario y las rutas en memoria.
- **S7** Base de datos: `anon` sin permisos sobre tablas ni funciones de `public`;
  `authenticated` sin `TRUNCATE`, `REFERENCES` ni `TRIGGER`.
- **S8** CI: `.gitignore` cubre material de firma, `.env`, `*.ipa`, `*.xcarchive` y `*.dSYM`;
  sentry-cli fijado a versión con checksum (sin `curl | bash`); actions fijadas por SHA; el
  log de `altool` se limita a las últimas líneas al fallar.

## Tasks

- **T1** ✅ `8d3e312` (S2, S3, S7) — Migración `security_hardening` + tests. Route: inline (fija el
  contrato de T3). Risk: items 1, 2, 3.
- **T2** ✅ `a662c2e` (S1, S2 Ajustes, S4, S5, S6) — App: privacidad e identidad. Route: delegado, writer
  `app-privacy`.
- **T3** ✅ `c2567c1` (S2 cliente, S3 cliente) — Ligas y share card con `is_me`, `create_league` y nuevos
  errores. Route: delegado, writer `leagues-sec`.
- **T4** ✅ `3414aa9` (S8) — CI y `.gitignore`. Route: delegado, writer `ci-sec`. Risk: item 5.
- **T5** — Verificador independiente de T1 y T4 + CI + aplicar la migración con
  confirmación del usuario.

## Log

- **L1** (2026-10-28) Usuario: «perfecto antes de continuar 1 crea es skill para todo el
  despliegue desde 0 a testflight, incluyendo un paso a paso de las acciones manuales, y 2
  revisa seguridad i filtrado de datos, que no se nos haya colado nada que pueda dar
  problemas».
- **L2** (2026-10-28) Revisión: sin secretos filtrados ni en el árbol ni en el historial; no
  sale ninguna coordenada del dispositivo. Hallazgos listados en S1-S8.
- **L3** (2026-10-28) Usuario: «si, aplica todo menos lo del p12».
- **L4** (2026-10-28) Writers en herdr (`app-privacy`, `leagues-sec`, `ci-sec`). Ajuste del
  parent en CI: si falla la descarga de sentry-cli se avisa y se salta el paso (va antes de la
  subida a TestFlight); si el checksum no coincide, el paso falla sin ejecutar el binario
  (el `continue-on-error` del paso deja seguir la subida y el run muestra el fallo). Checksum y SHAs de actions
  comprobados contra GitHub. Producción tiene 0 ligas, así que el paso a códigos de 8
  caracteres no deja ninguna liga inaccesible.
- **L5** (2026-10-28) Verificador independiente (`verify`, Pi): S2, S3, S7 y S8 correctos con
  42/43 sondas; 1 bloqueador: la migración abortaba si algún perfil tenía un nombre de más de
  30 caracteres. Corrección única: esos nombres pasan a seudónimo antes de la restricción.
  Avisos aplicados: el propietario solo puede cambiar `name` de la liga (no el código), un
  miembro ya dentro no gasta intentos, `create_league` se rinde tras 5 colisiones,
  `service_role` conserva los helpers de día, se elimina el `revoke` de funciones por defecto
  (en un esquema no tiene efecto y global afectaría a MornUp). Avisos asumidos: los miembros
  de una liga privada siguen leyendo `league_members.user_id` (S2 habla de RPC), recuento de
  fallos sin lock, nombres con espacios guardados sin recortar (el cliente recorta). Sondas en
  `supabase/tests/security.test.mjs`, 43/43; tests en serie por memoria (PGlite ~3 GB por
  fichero).
- **L6** (2026-10-28) Usuario: «si, aplica y avisa cuando termine el CI y dejamos ya
  estabilizado en main para seguir añadiendo features». CI de `eac1417` en verde. Migración
  aplicada en thsqgdaadhnnwsadjhrj como `20261028111321 security_hardening`
  (`{"success":true}`); fichero renombrado a esa versión. Verificación de solo lectura: 0
  permisos de `anon` en tablas, RPC con `is_me` y sin uuids, el único perfil con seudónimo,
  restricción de longitud presente, `my_xp` correcto como `authenticated`.
