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
- **main**: antes de archivar, un paso provisiona el material de firma vía
  **API REST de App Store Connect** (`.github/scripts/provision-signing.sh`):
  asegura el App ID `com.acrstudio.drivy` y su capability de Sign in with
  Apple, crea el certificado **Apple Distribution** con un CSR nuevo y lo
  importa en un keychain temporal del runner, y crea e instala el perfil
  **App Store**. Después `xcodebuild archive` Release para dispositivo iOS
  genérico con firma **manual** (`CODE_SIGN_IDENTITY="Apple Distribution"`,
  `PROVISIONING_PROFILE_SPECIFIER="Drivy App Store CI"`), `-exportArchive`
  con `signingStyle manual` a un `.ipa` y subida a TestFlight con
  `xcrun altool --upload-app`. Si los secrets de App Store Connect no están
  configurados (forks, estados tempranos), el job cae a un build Release
  **sin firmar** y lo deja anotado en el resumen del run.

- [ ] El PR pasa el job `test`
- [ ] No se ha conmutado ni subido `Drivy.xcodeproj` (se genera con XcodeGen)
- [ ] No se ha commiteado ninguna clave (`.p8`), perfil ni certificado

## Pendiente conocido

El pipeline de TestFlight depende de tres secrets del repo
(`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`,
`APP_STORE_CONNECT_API_KEY_BASE64`). Ni el `p12` ni el `.mobileprovision` se
commitean: los crea el job en cada ejecución, así que la clave privada del
certificado de distribución muere con el runner. Consecuencia: si el equipo ya
tiene un certificado de distribución que no fue creado por esta ejecución, el
paso de provisionamiento **falla a propósito** (no revoca nada) y el arreglo es
decisión humana — revocar el certificado viejo en el portal de Apple Developer
para que el job cree uno nuevo, o guardar el `.p12` como secret y añadir una
ruta de reutilización. La capability de Sign in with Apple (S10) ya la activa
el propio job, así que no hace falta tocar el portal a mano para eso.

Los crashes Release solo se simbolizan en Sentry si existe el secret
`SENTRY_AUTH_TOKEN` (token de organización de `acr-studio`). Sin él, el paso
`Upload dSYMs to Sentry` avisa y se salta sin romper el job.
