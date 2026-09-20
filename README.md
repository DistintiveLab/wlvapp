# WLVD — app

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

Wrapper para Android/iOS do painel **WLVD** (*World Labour Values Database*),
uma aplicação R Shiny disponível em <https://worldlabourvalues.org>.

O app é um `WebView` em Flutter que carrega o painel publicado. A lógica de
negócio fica no painel web; o app adiciona recursos nativos de casca
(veja [Recursos nativos](#recursos-nativos)).

## Tecnologia

- Flutter 3.3.10 estável (Dart 2.18.6) — versão pinada para builds
  reproduzíveis no F-Droid
- `webview_flutter` para o WebView
- `url_launcher` para abrir links externos no navegador do sistema
- `path_provider` + `share_plus` + `open_file` para o gerenciador de downloads

## Recursos nativos

- **Tela de erro offline** com botão "Tentar novamente".
- **Links externos** (fora de `worldlabourvalues.org`) abrem no navegador.
- **Pull-to-refresh**: arraste a página para baixo no topo para recarregar
  (detectado via JS injetado e executado no WebView).
- **Compartilhar página** (FAB → menu) via share sheet do sistema.
- **Downloads locais**: os botões de download do painel Shiny (aba Download,
  Indicadores, País, Comércio) são interceptados via JS; o arquivo XLSX/CSV é
  baixado no contexto da página (com sessão do Shiny) e salvo em
  `Android/data/org.worldlabourvalues.wlv_panel/files/downloads`. A página
  "Meus downloads" lista os arquivos com abrir/compartilhar/excluir — acesso
  rápido offline à aba de dados.
- **Idioma/aba lembrados** via `localStorage` do painel (persistido no WebView).

## O painel

- URL canônica: `https://worldlabourvalues.org` (responde 200 direto).
- `https://panel.worldlabourvalues.org` responde **302** e redireciona para a
  URL canônica (`.../?tab=map&wlv_entry=panel`).
- O código-fonte do painel está em
  <https://gitlab.com/rodrigoesborges/labourvaluesdatapanel>.

## Executar e compilar

```bash
flutter pub get
flutter run                 # dispositivo/emulador Android
flutter build apk --release # gera o APK em build/app/outputs/flutter-apk/
flutter test                # testes unitários
flutter analyze             # análise estática
```

## Ícone

O ícone do launcher é gerado a partir do favicon do painel
(`www/favicon.ico` no repositório GitLab), convertido com `ImageMagick` para um
master PNG de 1024x1024 (fundo `#FDD695`, opaco) e então redimensionado para os
tamanhos de Android e iOS. Os PNGs fonte ficam em `icon-src/`.

## Licença

Código do wrapper licenciado sob [GPL-3.0](LICENSE). O conteúdo e o serviço do
painel continuam regidos pelos termos do projeto WLVD.

## Publicação (F-Droid)

- Metadados de loja (descrições, changelog, ícone) ficam em
  `fastlane/metadata/android/{en-US,pt-BR}/` (formato fastlane/Triple-T,
  lido pelo F-Droid).
- Cada release precisa de tag git `v<versionName>` (ex.: `v1.0.0` para
  `versionCode 1`), com changelog em `fastlane/.../changelogs/<versionCode>.txt`.
- Screenshots em `fastlane/metadata/android/{en-US,pt-BR}/images/phoneScreenshots/`.
- A receita de build para o F-Droid (pinando o Flutter 3.3.10 via srclib) fica em
  `fdroid/metadata/org.worldlabourvalues.wlv_panel.yml`; para submeter, copie-a
  para `metadata/` num fork do fdroiddata e abra um MR.
