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
- **main**: `xcodebuild archive` Release firmado para dispositivo iOS
  genérico, `-exportArchive` a un `.ipa` y subida a TestFlight con
  `xcrun altool --upload-app` usando la API key de App Store Connect. Si los
  secrets de App Store Connect no están configurados (forks, estados
  tempranos), el job cae a un build Release **sin firmar** y lo deja anotado en
  el resumen del run.

- [ ] El PR pasa el job `test`
- [ ] No se ha conmutado ni subido `Drivy.xcodeproj` (se genera con XcodeGen)
- [ ] No se ha commiteado ninguna clave (`.p8`), perfil ni certificado

## Pendiente conocido

El pipeline de TestFlight depende de tres secrets del repo
(`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`,
`APP_STORE_CONNECT_API_KEY_BASE64`) y de que la capability Sign in with Apple
(S10) esté activada en el App ID del portal de Apple Developer, no solo en
`project.yml`.
