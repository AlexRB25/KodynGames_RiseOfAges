# iOS: compilar en la nube

Windows no puede compilar apps de iPhone. Lo hace una Mac de GitHub con el flujo
`.github/workflows/ios.yml`. Como el repositorio es público, esas Mac son gratis.

## Compilar

GitHub → pestaña **Actions** → **iOS** → **Run workflow**. Tarda unos 15–25 minutos.
Al terminar, el archivo sale abajo, en **Artifacts**:

- Sin los secretos de Apple: `RiseOfAges-V…-sin-firmar.app.zip`. Solo comprueba que compila;
  **no se puede instalar**.
- Con los secretos: `RiseOfAges-V….ipa`, firmado para la App Store. Si marcas
  "Subir a TestFlight" y tienes la llave de App Store Connect, se sube solo.

También corre si subes una etiqueta `ios-v1.0.18` (`git tag ios-v1.0.18 && git push origin ios-v1.0.18`).

## Lo que necesitas de Apple (una vez)

1. **Apple Developer Program** (99 USD al año): https://developer.apple.com/programs/
2. **Team ID**: developer.apple.com → Account → Membership details (10 letras/números).
3. **App ID**: Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App,
   Bundle ID explícito `com.kodyngames.riseofages`.
4. **Certificado Apple Distribution** (.p12). Sin Mac se puede así:
   - Crear la llave y la solicitud (en Git Bash, que trae openssl):
     ```
     openssl genrsa -out ios_dist.key 2048
     openssl req -new -key ios_dist.key -out ios_dist.csr -subj "/emailAddress=TU_CORREO/CN=Kodyn Games/C=MX"
     ```
   - Certificates → **+** → **Apple Distribution** → subir `ios_dist.csr` → descargar `distribution.cer`.
   - Juntar todo en un .p12 (te pide una contraseña; guárdala):
     ```
     openssl x509 -inform DER -in distribution.cer -out ios_dist.pem
     openssl pkcs12 -export -legacy -inkey ios_dist.key -in ios_dist.pem -out ios_dist.p12
     ```
5. **Perfil de aprovisionamiento**: Profiles → **+** → **App Store Connect** → el App ID de arriba
   → el certificado → nombre, por ejemplo `Rise of Ages AppStore` → descargar `.mobileprovision`.
6. **App en App Store Connect** (para TestFlight): https://appstoreconnect.apple.com → Apps → **+**
   → iOS, nombre "Rise of Ages", Bundle ID `com.kodyngames.riseofages`.
7. (Opcional, para subir solo a TestFlight) **Llave de API**: App Store Connect → Users and Access
   → Integrations → App Store Connect API → **+** (rol App Manager) → descargar `AuthKey_XXXX.p8`
   y anotar Key ID e Issuer ID.

## Secretos en GitHub

Repositorio → Settings → Secrets and variables → Actions → **New repository secret**.
Para pasar un archivo a base64 en PowerShell:
`[Convert]::ToBase64String([IO.File]::ReadAllBytes("ios_dist.p12")) | Set-Clipboard`

| Secreto | Valor |
| --- | --- |
| `APPLE_TEAM_ID` | el Team ID |
| `IOS_CERT_P12_BASE64` | `ios_dist.p12` en base64 |
| `IOS_CERT_PASSWORD` | la contraseña del .p12 |
| `IOS_PROFILE_BASE64` | el `.mobileprovision` en base64 |
| `ASC_KEY_ID` | (opcional) Key ID de la llave de API |
| `ASC_ISSUER_ID` | (opcional) Issuer ID |
| `ASC_KEY_P8` | (opcional) el contenido del `AuthKey_XXXX.p8` tal cual |

Guarda `ios_dist.key`, el `.p12` y su contraseña en un lugar seguro (por ejemplo la Bóveda):
sin ellos hay que hacer un certificado nuevo.

## Notas

- La versión sale de `config/version` de `project.godot` (1.0.18 → build 10018), igual que en Android.
- El icono es `assets/ui/icono_app_1024.png` (sin transparencia, como pide Apple).
- Los pagos con Stripe dentro de la app no los permite Apple para contenido digital (gemas,
  Game Pass): para publicar en la App Store habrá que usar las compras de Apple (StoreKit).
