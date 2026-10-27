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
  - Participación opt-in con un interruptor en Ajustes y una invitación única
    tras el primer trayecto **(supuesto: S12 de privacidad del MVP; en el grupo
    público solo se ve el nombre visible)**.
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
  job `pg_cron`, RLS y arreglos de S10. Risk: items 1, 2, 3. Commit propio.
  Route: inline.
- **T2** (S1, S4, S8) ⏳ — Racha v2 + hielos + reparación Premium + XP en Hoy.
  Route: pendiente.
- **T3** (S2) ⏳ — Test de teoría + banco de preguntas. Route: pendiente.
- **T4** (S2) ⏳ — Resumen post-trayecto con eventos en el mapa. Route:
  pendiente.
- **T5** (S3) ⏳ — Pestaña Camino y unidades. Route: pendiente.
- **T6** (S6) ⏳ — Misiones diarias. Route: pendiente.
- **T7** (S5) ⏳ — Ligas públicas en iOS + ranking privado por XP. Route:
  pendiente.
- **T8** (S7) ⏳ — Notificaciones locales. Route: pendiente.
- **T9** (S9) ⏳ — Share card y documentación. Route: pendiente.
- **T10** — Verificador independiente (items 1, 2 y 3 de alto riesgo).

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
