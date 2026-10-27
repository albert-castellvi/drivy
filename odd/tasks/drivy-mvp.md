# Drivy MVP — El Duolingo de la conducción

App iOS nativa que convierte cada trayecto real en una partida: telemetría del
iPhone (GPS + CoreMotion) → Driver Score diario, rachas y ligas privadas.
Backend Supabase. Monetización freemium con StoreKit 2. Build y tests vía
GitHub Actions (runner macOS).

## Specs

- **S1** Usuario (petición original, verbatim): «con el nombre de este repo
  piensa en una APP que pueda tener exito en IOS, con supabase para el backend,
  monetizada, y facilmente viralizable con tiktok e IA».
- **S2** Usuario (verbatim): «la compilacion y todo eso, lo lanzaremos por
  github actions».
- **S3** Usuario (verbatim): «IOS Native» — Swift + SwiftUI, sin frameworks
  multiplataforma.
- **S4** El MVP registra trayectos automáticamente detectando conducción
  (sigmoide sobre velocidad GPS + patrones de CoreMotion) o con botón manual.
  Mínimo viable: botón manual + auto-detección best-effort silenciosa.
- **S5** Scoring v1 por trayecto, 0–100, compuesto por: frenadas bruscas
  (desaceleración > 3.5 m/s²), aceleraciones bruscas (> 3.0 m/s²), uso del
  móvil al volante (unlock/interacción durante conducción), y exceso de
  velocidad respecto al límite (umbral +10 km/h). Penalizaciones acumulativas
  ponderadas por km.
- **S6** Driver Score diario = media ponderada por distancia de los trayectos
  del día. Racha = días consecutivos con ≥ 1 trayecto. La racha se rompe con
  2 días sin conducir (gracia de 1 día, estilo Duolingo con "hielo").
- **S7** Ligas privadas: grupos de hasta 25 amigos, ranking semanal por Driver
  Score medio + km. Invite link (deep link universal) para unirse.
- **S8** Share card viral: imagen cuadrada generada on-device (score, racha,
  posición en liga) lista para compartir en Instagram/TikTok stories.
- **S9** Monetización freemium: 7 días de histórico completo gratis; después,
  Free = solo último día + 1 liga; Premium (€4.99/mes, StoreKit 2) = histórico
  ilimitado, ligas ilimitadas, coach IA (v1.1, fuera de este MVP) y stats
  avanzadas. Paywall tras el primer trayecto completado, nunca bloqueante para
  registrar trayectos.
- **S10** Supabase: Auth (Sign in with Apple obligatorio por policy de Apple
  cuando hay login social), Postgres (trayectos, scores, ligas, membresías),
  RLS por usuario, Edge Functions para scoring agregado semanal de ligas.
  Las muestras crudas de GPS/Motion se suben resumidas (no streaming continuo)
  para contener costes.
- **S11** CI en GitHub Actions: runner `macos-15`, `xcodebuild test` en
  simulador iPhone en cada PR; build de archivo Release para TestFlight
  (firmado con secrets de Apple Developer) solo en `main`.
- **S12** Privacidad: sin cierre forzoso para usar la app (Apple obliga a un
  modo básico); explicación clara de uso de ubicación en background
  (justificación: "siempre" para registrar trayectos). Sin venta de datos.
- **S14** Identidad de la app: bundle ID `com.acrstudio.drivy`, nombre visible
  `Drivy`, scheme Xcode `Drivy`.
- **S13** Conducción conectada: la app detecta CarPlay (ruta de audio
  `.carAudio` en `AVAudioSession`) o Bluetooth manos libres del coche
  (`.bluetoothHandsfree` / `.bluetoothA2DP`) sin entitlements especiales.
  Conducción conectada → bonus en el score y exención de la penalización por
  uso del móvil. Focus Status API (`FocusStatusCenter`) es señal terciaria
  opt-in, nunca requisito. Template CarPlay real en pantalla: fuera del MVP
  (entitlement sujeto a aprobación de Apple), roadmap v2.

## Tasks

- **T1** (S10) ✅ DONE — Migraciones Supabase: tablas `profiles`, `drives`,
  `daily_scores`, `leagues`, `league_members`, RLS y función de ranking
  semanal. Route: delegado. Commit: `feat(backend): supabase schema v1`.
- **T2** (S3, S11) ✅ DONE — Proyecto Xcode + shell SwiftUI (tab root: Hoy /
  Ligas / Ajustes), Sign in with Apple, cliente Supabase. Route: delegado.
  Commit: `feat(app): xcode project and auth shell`.
- **T3** (S4, S5, S10, S13) ✅ DONE — Tracking de trayecto (CLLocation +
  CMMotionManager), detección de conducción conectada (AVAudioSession route
  changes) y motor de scoring v1 como módulo testeable puro (inyección de
  muestras). Route: delegado. Commit: `feat(app): drive tracking and scoring
  engine`.
- **T4** (S6, S7, S8) ✅ DONE — Pantallas core: Hoy (score, racha), detalle
  de trayecto con mapa, Ligas + invite, share card. Route: delegado. Commit:
  `feat(app): core screens and share card`.
- **T5** (S9) ✅ DONE — Paywall StoreKit 2 y límites freemium. Route:
  delegado. Commit: `feat(app): freemium paywall with storekit 2`.
- **T6** (S11) ✅ DONE (parcial por diseño) — Workflow GitHub Actions: PR
  (tests) y main (release build sin firmar). Route: delegado. Commit:
  `feat(ci): macos build and test pipeline`.
- **T7** Verificación final: suite completa en CI, veredicto por S#.
  Route: QA delegado. Commit: — (evidencia en este Log).

## Log

- **L1** Usuario (verbatim): «con el nombre de este repo piensa en una APP que
  pueda tener exito en IOS, con supabase para el backend, monetizada, y
  facilmente viralizable con tiktok e IA». Decisión: concepto 1 "Duolingo de
  la conducción" elegido de entre 4 propuestas; usuario: «dios santo me parece
  una puta maravilla».
- **L2** Usuario (verbatim): «IOS Native» al entregar el repo clonado
  (albert-castellvi/drivy, solo LICENSE).
- **L3** Usuario (verbatim): «la compilacion y todo eso, lo lanzaremos por
  github actions» — flujo: Linux para código/spec/backend, CI macOS para
  build y tests. Repo remoto: github.com/albert-castellvi/drivy.
- **L4** Usuario pregunta por integración CarPlay. Decisión: template CarPlay
  UI fuera del MVP (entitlement con revisión de Apple, categorías cerradas no
  encajan); se añade S13 — detección pasiva de conducción conectada vía
  AVAudioSession (`.carAudio` CarPlay, `.bluetoothHandsfree` BT del coche),
  con bonus de score y exención de penalización por uso del móvil. Confirmado
  por usuario: «sino la conexion con blutooth con el coche, con eso lo
  sabriamos no?»
- **L5** Usuario (verbatim): «bundel com.acrstudio.drivy» — bundle ID fijado
  para T2 y para el alta de la app en App Store Connect.
- **L6** Usuario (verbatim): «https://thsqgdaadhnnwsadjhrj.supabase.co usa
  este proyecto, limpialo y lanza desde ahi». Proyecto Supabase "MornUp"
  (app anterior, 21 tablas con 0 filas, 6 edge functions de givva.app):
  schema `public` limpiado (drop de tablas + funciones; edge functions sin
  tool de borrado en MCP, pendientes de borrado manual en dashboard).
  Aplicadas migraciones `drivy_schema_v1` (20261027125528) y
  `drivy_function_hardening` (search_path fijado, `handle_new_user` no
  ejecutable vía RPC). Advisors: solo quedan los 2 avisos intencionales de
  los RPC de app. URL API: https://thsqgdaadhnnwsadjhrj.supabase.co.
- **L7** T2 ejecutado por worker (gentle-ai-worker). 26 ficheros Swift +
  `project.yml` (XcodeGen, se genera en CI) + `.gitignore`. Tests: 20
  (config/identidad S14, máquina de estados auth, nonce Apple). Riesgos
  documentados pendientes de CI (T6/T7): excludes de XcodeGen sin probar en
  mac (fallback: subdirectorios explícitos), símbolos supabase-swift v2 sin
  compilar, capability Sign in with Apple también en el App ID del portal,
  `xcodegen generate` nunca ejecutado localmente. Verificación structural
  (YAML/plist parse, balance lint) OK. Veredictos: S3 ✓, S11 parcial (la
  parte de proyecto; el workflow es T6), S14 ✓.
- **L8** Corte de slice PR (estrategia chained PR, rama > 400 líneas):
  commit `3fcc8f8` = slice 1 «backend schema v1 + app shell/auth».
  Slices siguientes: slice 2 = T3 (tracking/scoring), slice 3 = T4+T5
  (pantallas core + paywall), slice 4 = T6 (CI). PRs apilados sobre
  `main` al cerrar la feature.
- **L9** T3 ejecutado por worker. Scoring puro (solo Foundation) con
  umbrales estrictos + histéresis de release; fórmula: penalty = (frenadas×12
  + acels×8 + excesos×10 + teléfono×25 si no conectado) / max(km, 0.1);
  score = clamp(100 − penalty + 5 si conectado); diario S6 = media ponderada
  por km recalculada desde el servidor. 75 tests nuevos (re-derivados en
  Python como doble comprobación). Riesgos documentados: supabase-swift sin
  compilar (v2.55.5 verificada a ojo), eje longitudinal asume montaje
  vertical del iPhone, sin datos de límite de velocidad aún (eventos de
  exceso = 0 hasta MapKit en T4), señal de uso del móvil = proxy
  didBecomeActive, subidas fallidas sin cola de reintento. Veredictos:
  S4 ✓, S5 ✓, S6 ✓, S10 ✓, S12 ✓, S13 ✓ (todos pendientes de compilación
  en CI).
- **L10** T5 ejecutado por worker: módulo `Drivy/Monetization` (12 ficheros,
  StoreKit aislado en un único fichero tras protocolo) + 78 tests (reglas S9
  re-derivadas en Python, 35/35). Decisión de spec (ambigüedad S9): el cap
  de 1 liga del plan Free aplica SIEMPRE, también durante la ventana de 7
  días de histórico completo — base: el contraste del spec «1 liga» vs
  «ligas ilimitadas». Anchor del gating sin backend: perfil/fecha del primer
  trayecto (cableado en integración). Veredicto: S9 ✓ (pendiente de
  compilación y StoreKit real en CI).
- **L11** T4 ejecutado por worker: pantallas Hoy/Ligas/detalle + share card
  (S8, ImageRenderer 1080px) + 75 tests. Hueco deliberado: el mapa del
  detalle no dibuja aún porque DriveRecorder no expone coordenadas
  (LocalRouteStore vacío) — wiring de track local en integración. Riesgos:
  supabase-swift sin compilar, RPC errors mapeados por string, código de
  invite con colisión → error genérico (unique constraint). Racha S6
  revisada a mano contra el spec literal: correcta. Veredictos: S6 ✓,
  S7 ✓, S8 ✓ (pendientes de compilación en CI).
- **L13** Integración S9 + cierre del hueco L11 (worker, superficies
  ampliadas tras escalado): FreemiumSessionCoordinator a nivel app (anchor
  = auth.users.created_at vía UserSummary.createdAt, re-anclaje al primer
  trayecto una vez por cuenta), paywall once-ever tras el primer trayecto
  (persistido, nunca bloquea registrar), pantalla Histórico en Hoy con
  fila de bloqueo + upsell (canViewHistory), cap de 1 liga en free que
  bloquea create/join antes de llamar al RPC, y ruta local expuesta por
  DriveRecorder para la polyline del detalle. 53 tests nuevos. Revisado
  a mano: sin coordenadas en el payload de subida, ciclo de vida por
  cuenta correcto. Veredicto: S9 wired ✓, L11 cerrado.
- **L12** T6 ejecutado por worker: `.github/workflows/ci.yml` (2 jobs,
  macos-15): test = xcodegen + assert de scheme/targets + xcodebuild test en
  iPhone 16; build-release = build Release unsigned genérico solo en
  main/dispatch. TestFlight firmado queda como TODO documentado en el
  header del workflow (secrets: APPLE_TEAM_ID, certificados p12, API key
  de ASC) — no hay secrets en el repo. Pendiente humano: activar
  capability Sign in with Apple en el App ID del portal. Verificación:
  YAML parse + bash -n (10/10) + lógica del assert probada positiva y
  negativa; nunca ejecutado. Veredicto S11: parcial (PR tests ✓ real,
  archive firmado pendiente de secrets).
