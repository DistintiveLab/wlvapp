# AGENTS.md

Guia para agentes trabalharem neste repositório.

## Visão geral

App Flutter que é um wrapper (`WebView`) do painel WLVD (R Shiny) publicado em
`https://worldlabourvalues.org`. O comportamento do painel fica no web; o app
carrega a URL, mantém a navegação interna, abre links externos no navegador do
sistema e adiciona recursos nativos de casca (pull-to-refresh, compartilhar,
gerenciador de downloads locais dos XLSX/CSV do painel).

- Alvo principal: **Android**. iOS também está configurado, mas não é compilado
  neste ambiente (Linux). O alvo `web/` foi removido porque `webview_flutter`
  não suporta web.
- Código Dart: `lib/main.dart` (WebView + menu), `lib/bridge_js.dart`
  (JS injetado: pull-to-refresh e interceptação de `a.shiny-download-link`
  do Shiny, arquivos enviados em chunks base64 via JavascriptChannel
  `WLVDNative`), `lib/downloads.dart` (armazenamento + UI "Meus downloads").

## Comandos

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/home/rodrigo/Android/Sdk
export ANDROID_SDK_ROOT=/home/rodrigo/Android/Sdk
export PATH="/media/usb1/Development/gits/flutter-3.47.5/bin:$PATH"

flutter pub get
flutter run                          # executa no dispositivo/emulador
flutter build apk --release          # APK em build/app/outputs/flutter-apk/
flutter build apk --debug
flutter test                         # testes em test/widget_test.dart e test/downloads_test.dart
flutter analyze
```

## Ambiente (gotchas importantes)

- **Flutter 3.47.5 estável** (set/2026), clonado em
  `/media/usb1/Development/gits/flutter-3.47.5` (padrão srclib do F-Droid:
  `git clone --depth 1 --branch 3.47.5`). O checkout antigo do 3.3.10 continua
  em `/media/usb1/Development/gits/flutter-3.3.10`, usado só para a linha
  1.0.2/3. Desde a 1.0.3 o app usa a API atual do `webview_flutter`
  (`WebViewController` + `WebViewWidget`, `PopScope`, `SharePlus.instance`).
- **Android SDK**: o SDK completo está em `/home/rodrigo/Android/Sdk`.
  A variável global `ANDROID_SDK_ROOT` aponta para um caminho inexistente
  (`/media/usb1/Development/android-sdk-linux/`); `ANDROID_HOME` está vazia.
  Para compilar, `android/local.properties` deve apontar `sdk.dir` para
  `/home/rodrigo/Android/Sdk` (já configurado). Em caso de dúvida, prefixe:
  ```bash
  ANDROID_HOME=/home/rodrigo/Android/Sdk ANDROID_SDK_ROOT=/home/rodrigo/Android/Sdk flutter build apk --release
  ```
- **Plataformas instaladas**: `android-32`, `android-33`, `android-35`,
  `android-36` e `android-36-2`. O app usa os defaults do Flutter
  (`compileSdk`/`targetSdk` 36, `minSdk` 24 — mínimo do Flutter 3.47; a
  1.0.2 ainda suportava minSdk 21 com compile/target 33).
- **NDK não está instalado** e o projeto não usa código nativo; não readdicione
  `ndkVersion` em `android/app/build.gradle.kts` sem instalar o NDK.
- O build usa **Gradle 9.3.1, AGP 9.1.0 e Kotlin 2.4.0** (scaffold do
  Flutter 3.47, arquivos `.kts`). Não mexa em `android.newDsl`/
  `android.builtInKotlin` no `gradle.properties` sem testar o build.
- **Java**: use o JDK 21 do sistema (`/usr/lib/jvm/java-21-openjdk-amd64`,
  com `javac`); Gradle 9 exige JDK 17+. O Java 11 do Android Studio não serve
  mais para builds, só para `keytool`.
- **Debug keystore**: o `~/.android/debug.keystore` foi regerado com o keytool do
  Java 11 (alias `AndroidDebugKey`, senha `android`). O keystore antigo usava MAC
  `HmacPBESHA256`, que o Java 11 não consegue ler ("Integrity check failed").
  Se precisar regenerar, use:
  ```bash
  /media/usb1/Development/android-studio/jre/bin/keytool -genkeypair -v \
    -keystore ~/.android/debug.keystore -storepass android \
    -alias AndroidDebugKey -keypass android \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US"
  ```

## Arquitetura

- `lib/main.dart`:
  - `kHomeUrl` = `https://worldlabourvalues.org` (URL canônica).
  - `isWlvdUrl(String)` — função pura que decide se uma URL é do painel
    (domínio ou subdomínio de `worldlabourvalues.org`). É testada em
    `test/widget_test.dart`.
  - `WlvdApp` — `MaterialApp`.
  - `PanelWebView` (StatefulWidget) — `WebViewWidget` com `WebViewController`
    criado no `initState`:
    - `setJavaScriptMode(JavaScriptMode.unrestricted)` (necessário ao Shiny).
    - `addJavaScriptChannel('WLVDNative', ...)` recebe os chunks base64.
    - `NavigationDelegate`: URLs do domínio navegam internamente; URLs externas
      abrem via `url_launcher`; `onPageFinished` injeta `kBridgeJs`.
    - `PopScope`: botão voltar navega no histórico do WebView antes de
      fechar o app.
    - Indicador de progresso no topo enquanto carrega.
    - Tela de erro com "Tentar novamente" e "Meus downloads" quando uma falha
      de rede acontece antes da primeira página terminar de carregar
      (`_isNetworkError`).
  - `_ErrorView` — tela de erro/retry + acesso a downloads salvos offline.

## Dependências (pinned pelo resolver)

- `webview_flutter: ^4.13.0` (resolvido para 4.14.1).
  DOM storage é habilitado por padrão pelo plugin Android, então
  `localStorage`/cookies do painel (idioma, aba) persistem.
- `url_launcher: ^6.1.6` (resolvido para 6.3.2), `share_plus` 13.3
  (`SharePlus.instance.share`), `open_file` 4.0, `path_provider` 2.1.6.

## Ícones

- Gerados a partir de `icon-src/favicon.ico` (favicon do painel, baixado de
  `www/favicon.ico` no repo GitLab do painel).
- O `favicon.ico` é um contêiner ICO com um único PNG 751x750 embutido
  (RGBA, arte circular com cantos transparentes).
- Convertido para `icon-src/favicon-app-1024.png` (1024x1024, opaco, fundo
  `#FDD695` — pêssego do próprio favicon, borda superior do emblema —, arte
  centralizada em ~72% do canvas), que é o master de onde todos os tamanhos
  são redimensionados.
- Android: `android/app/src/main/res/mipmap-*/ic_launcher.png` (48, 72, 96,
  144 e 192 px).
- iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (PNGs opacos, sem canal
  alpha — requisito do iOS).
- Para regenerar, usar `convert` (ImageMagick) com `-resize`, `-extent`
  (fundo `#FDD695`), `-alpha off` e saída `PNG24:` para garantir ausência
  de alpha.

## Convenções

- Textos de UI em português (com acentos, UTF-8).
- O app não replica lógica do painel; mudanças de comportamento pertencem ao
  repo do painel (GitLab), não aqui.
- Código do wrapper é propositalmente mínimo; não adicione features de negócio.
- Licença do projeto: **GPL-3.0** (`LICENSE` na raiz).
- Metadados de loja em `fastlane/metadata/android/{en-US,pt-BR}/`; a cada
  release, atualizar `changelogs/<versionCode>.txt` e criar tag `v<versionName>`.
