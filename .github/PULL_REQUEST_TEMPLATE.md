<!--
  Drivy PR template. Keep the CI section in sync with .github/workflows/ci.yml.
-->

## Qué cambia

<!-- Una o dos frases. -->

## Specs cubiertas

<!-- Referencia las S# de odd/tasks/drivy-mvp.md que este PR satisface. -->

- S

## Pruebas

- [ ] Tests nuevos o actualizados para cada regla tocada
- [ ] Tests existentes que comparten código tocado siguen pasando

Comandos ejecutados localmente (si aplica):

```text

```

## Checklist CI (S11)

El workflow `.github/workflows/ci.yml` corre en macOS:

- **PR**: `xcodegen generate` + `xcodebuild test` en simulador
  `iPhone 16` (scheme `Drivy`). Es lo que valida el PR.
- **main**: build Release **sin firmar** para dispositivo iOS genérico, para
  detectar fallos que solo aparecen con optimizaciones / arquitectura arm64.

- [ ] El PR pasa el job `test`
- [ ] No se ha conmutado ni subido `Drivy.xcodeproj` (se genera con XcodeGen)

## Pendiente conocido

El archive firmado para TestFlight **no** está automatizado todavía: requiere
secrets de Apple Developer (`APPLE_TEAM_ID`, certificado de distribución,
provisioning profile y API key de App Store Connect) que aún no existen en el
repo. Está documentado como TODO en la cabecera de
`.github/workflows/ci.yml`.
