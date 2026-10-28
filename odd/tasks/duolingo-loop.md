# Drivy — Bucle Duolingo (conducir mejor, no más)

Rediseño del bucle de juego para premiar hábitos de conducción segura en vez de
kilómetros: racha v2, lecciones, camino de hábitos, XP, ligas públicas por
divisiones, misiones, notificaciones y ventajas Premium de racha.
Rama `feat/duolingo-loop`. Entrega: `ask-on-risk` (previsión > 400 líneas → PRs
encadenados por tarea). Tests: XCTest vía `xcodebuild test` en CI (macos-26).

## Specs

Origen: el usuario aprobó con «a por todo!» la propuesta de 8 puntos (L1–L3).
Lo marcado **(supuesto)** son valores propuestos por el orquestador, pendientes
de aprobación; el resto es el contenido de la propuesta aprobada.
Sustituye a S6 (racha) y S7 (ranking por km) de `odd/tasks/drivy-mvp.md`.

- **S1 Racha v2.** Propuesta aprobada: «El día cuenta si conduces limpio (todos
  los trayectos con score ≥ X) **o** si haces una lección de 1 minuto. Los días
  sin coche no rompen nada.» Reglas por día:
  - Suma +1: día con conducción y Driver Score diario ≥ 75 **(supuesto: X = 75,
    sobre la media ponderada por km que ya calcula `DailyScoreCalculator`)**, o
    día sin conducción con una lección de teoría completada.
  - Neutro (no suma, no rompe): día sin conducir y sin lección.
  - Día con conducción por debajo de X: consume un "hielo"; sin hielos, rompe la
    racha. Una lección ese mismo día no lo rescata **(supuesto: si la rescatara,
    conducir mal saldría gratis)**.
  - Hielos **(supuesto)**: Free 1 por semana ISO, Premium 3 por semana; no se
    acumulan entre semanas; se aplican solos al recalcular. Cálculo puro y
    determinista sobre `daily_scores` + lecciones, sin persistir el estado.
- **S2 Lecciones.** Propuesta aprobada: «Después de cada trayecto, un resumen de
  unos 30 segundos: dónde frenaste fuerte en el mapa y un consejo. Los días sin
  coche, un test de teoría de la DGT o de señales».
  - Resumen post-trayecto: hoja que se abre al terminar un trayecto (antes del
    paywall del primer trayecto). Muestra score, conteo de eventos por tipo, los
    eventos sobre el mapa de la ruta y un consejo según el componente que más
    penalizó. El motor de scoring pasa a devolver la posición de cada evento
    (solo local, no se sube: S12 del MVP).
  - Test de teoría: 5 preguntas de opción múltiple (~1 minuto). Banco de
    preguntas en JSON dentro de la app **(supuesto: 60 preguntas de redacción
    original, no copiadas de exámenes DGT; el usuario las revisa antes de
    publicar)**. Completar el test = lección del día (S1), aunque falles
    preguntas. La generación con IA queda para el coach IA (v1.1).
- **S3 Camino de hábitos.** Propuesta aprobada: «"Frenada suave", "Cero móvil",
  "Velocidad", "Conducción conectada". Cada unidad se supera con retos medidos
  con las métricas que ya calcula el scoring, por ejemplo "5 trayectos sin
  frenadas bruscas".»
  - Unidades en orden **(supuesto)**: Frenada suave (`harsh_brakes = 0`),
    Arranque suave (`harsh_accelerations = 0`), Cero móvil
    (`phone_use_events = 0`), Velocidad (`speeding_events = 0`), Conducción
    conectada (`connected_mode = true`). Cuentan trayectos de ≥ 2 km.
  - 3 niveles por unidad: 3 / 7 / 15 trayectos que cumplen. Cada unidad se
    desbloquea al completar la anterior; el progreso cuenta trayectos desde que
    se desbloqueó **(supuesto)**.
  - Nueva pestaña «Camino» entre Hoy y Ligas, con las unidades y el acceso al
    test de teoría.
- **S4 XP acumulable.** Propuesta aprobada: «XP acumulable … una cifra que solo
  crece». Corrección del orquestador a la propuesta: el XP **no** escala con
  los km (eso devolvería el incentivo de conducir más). Tabla **(supuesto)**:
  trayecto ≥ 2 km con score ≥ 90 → 20 XP, ≥ 75 → 10 XP, resto 0; máximo 3
  trayectos con XP al día; lección 10 XP; misión 15 XP; nivel de unidad 50 XP.
  El servidor calcula el XP a partir de las tablas (fuente de verdad única).
- **S5 Ligas públicas por divisiones.** Propuesta aprobada: «Ligas públicas por
  divisiones, con ascensos y descensos (Bronce → Diamante) y grupos de unos 30
  jugadores asignados automáticamente. … Las ligas privadas se mantienen como
  extra.»
  - Divisiones: Bronce, Plata, Oro, Platino, Diamante. Grupos de hasta 30 de la
    misma división, formados el lunes 00:00 Europe/Madrid **(supuesto)** con
    quien haya sumado XP la semana anterior o se haya unido nuevo.
  - Ranking semanal por XP de la semana. Suben los 7 primeros y bajan los 5
    últimos **(supuesto)**; en Bronce no se baja y en Diamante no se sube.
    Para subir hay que haber sumado XP esa semana, y en grupos de menos de 12
    nunca baja nadie del top 7 (L10).
  - Participación opt-in con un interruptor en Ajustes y una tarjeta de
    invitación en la pestaña Ligas mientras no se haya decidido (L9)
    **(supuesto: S12 de privacidad del MVP; en el grupo público solo se ve el
    nombre visible)**.
  - Asignación de grupo y ascenso/descenso perezosos: se resuelven en la
    primera llamada del usuario en la semana nueva (L8), sin jobs.
  - Las ligas privadas pasan a ordenar por XP semanal en lugar de score+km.
- **S6 Misiones diarias.** Propuesta aprobada: «"un trayecto sin tocar el
  móvil", "conduce conectado con CarPlay"». 3 misiones al día, elegidas de forma
  determinista por usuario y día de un catálogo **(supuesto: ~10 misiones,
  siempre al menos una que se pueda completar sin conducir, p. ej. la lección)**.
  Ninguna misión pide conducir más km o más trayectos.
- **S7 Notificaciones.** Propuesta aprobada: «nunca durante un trayecto y nunca
  invitando a conducir: algo como "Te queda la lección de hoy"». Solo
  notificaciones locales **(supuesto: sin APNs)**:
  - Recordatorio a las 20:00 **(supuesto)** si el día aún no cuenta para la
    racha: invita a la lección, nunca a conducir.
  - Resultado de la liga pública el lunes por la mañana.
  - Al empezar un trayecto se retiran las notificaciones pendientes del día; se
    reprograman al terminar. Permiso pedido tras la primera lección o el primer
    resumen, nunca al arrancar.
- **S8 Monetización de racha.** Propuesta aprobada: «recuperar la racha o tener
  "hielos" extra como ventaja Premium». Premium = 3 hielos por semana (S1) y
  reparar una racha rota en las 48 h siguientes, una vez cada 30 días
  **(supuesto)**. Sigue el patrón `FreemiumLimits` / `FreemiumAccess` / `*Gate`.
  Sin moneda virtual ni compras consumibles.
- **S9 Superficies existentes.** La share card muestra la racha v2 y la
  división pública (si participa). Los textos siguen en español hardcodeado,
  como el resto de la app.
- **S10 Deuda previa detectada (verificar antes de construir encima).** Posible
  recursión en la policy RLS `league_members_select_league_mates`
  (`0001_drivy_init.sql:280-288`) y desfase de zona horaria entre el lunes
  local del cliente y el `week_start` del servidor en `league_weekly_ranking`.

## Tasks

- **T0** (S10) ✅ DONE — Verificar contra el Supabase real (solo lectura) la
  recursión RLS y la zona horaria. Route: delegado (Pi deepseek, solo
  lectura). Evidencia en L8.
- **T1** (S1, S2, S4, S5, S6, S8) ⏳ — Migración `0002`: `lesson_completions`,
  `quest_completions`, `streak_repairs`, tablas de divisiones/grupos/resultados
  semanales, `league_opt_in` en perfil, función de XP, RPCs de ranking por XP,
  RLS y arreglos de S10 (sin `pg_cron`, L8). Risk: items 1, 2, 3. Commit
  propio `f252810`. Route: inline. RED: 6/6 fallan en la base (S10 con el
  mismo `infinite recursion` que producción); GREEN: 6/6 con 0002.
- **T1b** (S1-S8) ✅ DONE — Capa de datos compartida `ProgressDataLoading` +
  fake. Commit `507e25c`. Route: inline (estado compartido de todos los writers).
- **T2** ✅ DONE (S1, S4, S8) — Racha v2 + hielos + reparación Premium + XP en Hoy.
  Route: delegado, writer A (con T6 y la share card de T9).
- **T3** (S2) ✅ DONE — Test de teoría + banco de
  preguntas. Route: delegado, writer B1 (B falló por límite de salida, L11).
- **T4** ✅ DONE (S2) — Resumen post-trayecto con eventos en el mapa. Route:
  delegado, writer C.
- **T5** (S3) ✅ DONE — Pestaña Camino y unidades.
  Route: delegado, writer B2.
- **T6** ✅ DONE (S6) — Misiones diarias. Route: delegado, writer A.
- **T7** ✅ DONE (S5) — Ligas públicas en iOS + ranking privado por XP. Route:
  delegado, writer D.
- **T8** ✅ DONE (S7) — Notificaciones locales. Route: inline (parent, al integrar:
  toca DriveRecorder, la app y los puntos de enganche de B y C).
- **T9** (S9) ✅ DONE — Share card (writer A) y documentación (parent: este documento).
- **T10** ✅ DONE — Verificador independiente de T1 (L10) + QA del Swift (L13) y
  recomprobación de B1-B5 (L14).

## Log

- **L1** (2026-10-27) Usuario: «revisa las funcionalidades ahora, piensa en un
  duolingo para conducir».
- **L2** (2026-10-27) Orquestador: revisión. La racha (≥ 1 trayecto al día) y el
  ranking por `total_km` premian conducir más, no mejor; las ligas solo privadas
  tienen problema de arranque; no hay notificaciones. Propuesta de 8 puntos.
- **L3** (2026-10-27) Usuario: «a por todo!».
- **L4** (2026-10-27) Mapa de solo lectura: el motor solo devuelve conteos (sin
  posición de eventos); no hay Edge Functions ni cron (el ranking se calcula en
  vivo por RPC); `DriveRecorder` es un `@StateObject` de `TodayView` (hay que
  subirlo a la app para silenciar notificaciones); no hay notificaciones, ni
  localización, ni tests de SQL. Previsión: ~3.000–4.000 líneas → 10 tareas.
  Siguiente paso: aprobación del spec por el usuario (regla de ~/CLAUDE.md).
- **L5** (2026-10-27) Usuario: «si dale». Spec aprobado con los supuestos tal
  cual. Arranca T0.
- **L6** (2026-10-27) Lectura de `0001_drivy_init.sql`: además de S10,
  `league_weekly_ranking` es `security definer` y no comprueba que quien llama
  sea miembro de `p_league_id` (cualquier usuario autenticado que conozca el
  uuid lee el ranking). Se corrige en T1. El proyecto Supabase es compartido
  («MornUp»): T1 no debe tocar objetos ajenos a Drivy.
- **L7** (2026-10-27) Usuario: «perfecto cuando termines merge i push i para
  testflight». Al cerrar la feature: merge a `main`, push y build firmada a
  TestFlight.
- **L8** (2026-10-27) T0 (Supabase thsqgdaadhnnwsadjhrj, solo lectura):
  `show timezone` → `UTC`; `pg_cron` 1.6.4 disponible, no instalado; en
  `public` solo están las 5 tablas de Drivy; datos: 1 trayecto, 1 usuario,
  0 ligas. Como `authenticated`, tanto `select count(*) from league_members`
  como `from leagues` fallan con `ERROR: 42P17: infinite recursion detected in
  policy for relation "league_members"`: las ligas privadas no funcionan hoy.
  Decisión de diseño de T1: sin `pg_cron`. Las ligas públicas se asignan y
  liquidan de forma perezosa en la primera llamada de la semana (como
  Duolingo), con un lock por división y semana. Sustituye a «Cierre semanal
  con un job de `pg_cron`» de S5 (detalle técnico, mismo comportamiento).
- **L9** (2026-10-27) Rutas: writer trigger (a) — cuatro unidades
  independientes con superficies disjuntas, cada una de varios ficheros y
  más de 100 líneas, lanzadas a la vez en Pi (deepseek, effort medio, regla
  de ~/CLAUDE.md). No hay toolchain Swift en esta máquina (Linux): CI en
  macos-26 es el compilador. El parent posee git, `TodayView` lo integra el
  writer A con los contratos fijados de B (`LessonQuizView`) y C
  (`DriveDebriefView`), y T8 lo hace el parent. Decisión de UX: la invitación
  a ligas públicas es una tarjeta en la pestaña Ligas, no otra hoja tras el
  primer trayecto (ya hay resumen + paywall); S5 se reescribe en ese punto.
- **L10** (2026-10-27) Verificador independiente de T1 (Pi deepseek, scratch
  `/tmp/drivy-probe.agD8PN`): 22/22 en verde, sin bloqueadores. Avisos
  aplicados en `0002` antes de desplegar: A2 (fallo previo: cualquiera podía
  insertarse en una liga privada sin código; ahora solo el dueño se añade a sí
  mismo y el resto pasa por `join_league_by_code`), A4 (`p_week_start` se
  redondea a su lunes en el ranking y en `my_xp`), A6 (días de lección y misión
  limitados a hoy y ayer en Madrid; reparaciones a 3 días). Las sondas se
  guardan como `supabase/tests/adversarial.test.mjs`. Decisión A3 escrita en
  S5. Pendientes asumidos: A1 (aplicar la migración antes de publicar la
  build), A5 (tope de 30 probado solo en una sesión), A7 (el ledger se calcula
  en cada lectura).
- **L11** (2026-10-27) Writers A, C y D terminaron; B agotó su límite de
  salida sin escribir nada y se relanzó partido en B1 (lecciones, banco escrito
  en tandas de 10) y B2 (Camino). Commits por unidad: `c7ebd60` (T8),
  `3c5f1b6` (T4), `40f584b` (T7), `c7029bf` (T2, T6 y share card de T9).
  Revisión del banco por el parent: corregidas `roundabout_exit_signal` (se
  señaliza después de pasar la salida anterior, no antes) y
  `lights_day_interurban` (la luz de cruce de día no es obligatoria para
  turismos; sustituida por `lights_in_tunnel`). Pendiente de revisión humana:
  todo el banco, en especial `alcohol_rate_*`, por la reforma en trámite de
  las tasas de alcohol. Entrega: un único PR con un commit por unidad (el
  usuario pidió merge al terminar, L7).
- **L12** (2026-10-28) Usuario: «si» (aplicar `0002`). Aplicada en
  thsqgdaadhnnwsadjhrj como migración `20261028084225 0002_duolingo_loop`
  (`{"success":true}`), sha256 del fichero igual al del commit. Verificación de
  solo lectura: 12 tablas, políticas nuevas presentes, lectura como
  `authenticated` de `league_members`/`leagues`/`profiles` y `my_xp` sin error
  (la recursión ha desaparecido). Avisos del linter esperados (RPC security
  definer por diseño; grupos públicos sin políticas a propósito). Desfase
  detectado: en remoto existe `20261027125628 drivy_function_hardening`, que
  no está en `supabase/migrations/`. Primer CI del PR: la app compiló; un
  único error en un test (orden de argumentos), corregido.
- **L13** (2026-10-28) CI en verde en `98d9c18` (573 tests). Usuario: «usa el
  multiplexer de herdr con los agentes de pi»; los agentes de Pi pasan a lanzarse
  en panes de herdr. QA (agente `qa`, Pi + 5 jueces glm5.3-flash, informe
  `qa-report.md`): S2, S4, S6, S8 y S9 cumplen y el principio de seguridad se
  mantiene. 5 bloqueadores: B1 (claves de día y semana con la zona horaria del
  dispositivo frente a Madrid en el servidor; en Canarias, de 23:00 a 00:00,
  se rechazan lecciones y se pierden misiones), B2 (la notificación de liga no
  se silencia durante un trayecto), B3 (el orden resumen → paywall no tiene
  test), B4 (Camino no se recarga y no registra niveles), B5 (el texto de la
  lección promete sumar el día cuando ese día ya hubo conducción sucia).
  Corrección: agentes `fix-tz` (B1, B2) y `fix-ui` (B3-B5) en paralelo con
  superficies disjuntas.
- **L14** (2026-10-28) Correcciones de QA: `b17a7b4` (B1, B2) y `2b51e27` (B3-B5;
  el parent corrigió además el texto de la lección en Camino). Recomprobación
  limitada a B1-B5 (agente `recheck`): las 5 FIXED. CI del PR `40663169594` en
  verde. Merge del PR #9 en `main` (`c8ec2a7`, rama borrada). Build firmada
  `40664160379`: 598 tests, 0 fallos; build 31 subida a TestFlight (Delivery UUID
  `559323d6-e849-42f8-b094-74d63c560829`). Pendiente humano: revisar las 60
  preguntas (sobre todo `alcohol_rate_*`) y probar la build 31 en el dispositivo.
  Avisos asumidos: A5 (tope de 30 sin probar con concurrencia real), A7 (ledger
  sin materializar) y el desfase de la migración remota `drivy_function_hardening`.
