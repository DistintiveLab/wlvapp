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
```bash
export JAVA_HOME=/media/usb1/Development/android-studio/jre
export ANDROID_HOME=/home/rodrigo/Android/Sdk
export ANDROID_SDK_ROOT=/home/rodrigo/Android/Sdk
export PATH="$JAVA_HOME/bin:$PATH"

flutter pub get
flutter run                          # executa no dispositivo/emulador
flutter build apk --release          # APK em build/app/outputs/flutter-apk/
flutter build apk --debug
flutter test                         # testes em test/widget_test.dart e test/downloads_test.dart
flutter analyze
```

## Ambiente (gotchas importantes)

- **Flutter 3.3.10 estável** (Dart 2.18.6, dez/2022), pinado em
  `/media/usb1/Development/gits/flutter-3.3.10/bin/flutter` para builds
  reproduzíveis no F-Droid (o checkout antigo do canal `master` continua em
  `/media/usb1/Development/gits/flutter`, mas não é mais usado).
  API antiga do `webview_flutter` (`WebView(initialUrl:..., javascriptMode:...)`,
  `WillPopScope`), não as APIs atuais (`WebViewController` novo, `PopScope`).
- **Android SDK**: o SDK completo está em `/home/rodrigo/Android/Sdk`.
  A variável global `ANDROID_SDK_ROOT` aponta para um caminho inexistente
  (`/media/usb1/Development/android-sdk-linux/`); `ANDROID_HOME` está vazia.
  Para compilar, `android/local.properties` deve apontar `sdk.dir` para
  `/home/rodrigo/Android/Sdk` (já configurado). Em caso de dúvida, prefixe:
  ```bash
  ANDROID_HOME=/home/rodrigo/Android/Sdk ANDROID_SDK_ROOT=/home/rodrigo/Android/Sdk flutter build apk --release
  ```
- **Plataformas instaladas**: `android-32`, `android-33`, `android-35`, `android-36`
  e `android-36-2`. Não há `android-31` (padrão do Flutter 3.1). Por isso
  `android/app/build.gradle` fixa `compileSdkVersion 33`, `targetSdkVersion 33`
  e `minSdkVersion 21` (em vez de `flutter.compileSdkVersion`, que é 31).
  `compileSdkVersion 33` é exigido pelo `url_launcher_android`. Evite
  `android-35`: o `android.jar` dele estava corrompido para este toolchain
  (AAPT2 falha com "RES_TABLE_TYPE_TYPE entry offsets overlap").
- **NDK não está instalado** e o projeto não usa código nativo; a linha
  `ndkVersion flutter.ndkVersion` foi removida de `build.gradle` de propósito.
  Não a readicione sem instalar o NDK.
- O build usa Gradle 7.4 e AGP 7.1.2 (definidos no scaffold do Flutter 3.1);
  não atualize sem verificar compatibilidade com o Flutter antigo.
- **Java**: use Java 11 (o JRE empacotado do Android Studio em
  `/media/usb1/Development/android-studio/jre`). O Java do sistema é 21, novo
  demais para o Gradle 7.4; o Java 17 do sistema é só JRE (sem `javac`).
  Prefixe o build com `JAVA_HOME=/media/usb1/Development/android-studio/jre`.
- **Kotlin**: `ext.kotlin_version = '1.7.20'` em `android/build.gradle`. Versões
  mais antigas (ex.: 1.6.10) falham ao ler metadados Kotlin 1.7+ das
  dependências.
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
  - `PanelWebView` (StatefulWidget) — `WebView` com:
    - `javascriptMode: JavascriptMode.unrestricted` (necessário ao Shiny).
    - `gestureNavigationEnabled: true`.
    - `navigationDelegate`: URLs do domínio navegam internamente; URLs externas
      abrem via `url_launcher`.
    - `WillPopScope`: botão voltar navega no histórico do WebView antes de
      fechar o app.
    - Indicador de progresso no topo enquanto carrega.
    - Tela de erro com "Tentar novamente" quando uma falha de rede acontece
      antes da primeira página terminar de carregar (`_isNetworkError`).
  - `_ErrorView` — tela de erro/retry.

## Dependências (pinned pelo resolver)

- `webview_flutter: ^3.0.4` (resolvido para 3.0.4, plugin Android 2.10.4).
  DOM storage já é habilitado por padrão pelo plugin Android, então
  `localStorage`/cookies do painel (idioma, aba) persistem.
- `url_launcher: ^6.1.6` (resolvido para 6.1.10).

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
