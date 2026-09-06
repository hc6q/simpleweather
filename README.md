# Weather App

[![iOS Build](https://github.com/hc6q/simpleweather/actions/workflows/ios-build.yml/badge.svg)](https://github.com/hc6q/simpleweather/actions/workflows/ios-build.yml)

App iOS minimalista em preto OLED, com localização automática, previsão atual, próximas horas, quatro dias e widgets pequeno e médio. Interface em português do Brasil e inglês. Swift, SwiftUI, WeatherKit, CoreLocation, WidgetKit e async/await; iOS 17+. Sem dependências externas no app.

## Validação

O [GitHub Actions](https://github.com/hc6q/simpleweather/actions/workflows/ios-build.yml) compila o app e os widgets em Debug e Release e executa 24 testes offline. O status acima acompanha a branch `main`; cada execução mantém os logs, os resultados dos testes e as imagens das interfaces.

## Diagnóstico temporário no iPhone

Esta versão inclui **••• → Diagnóstico**, também acessível quando a previsão não carrega. A tela normal mantém a mensagem amigável; o relatório registra separadamente autorização, CLLocation e coordenadas, reverse geocoding, início/resultado de cada consulta WeatherKit e eventuais erros do pipeline do app.

1. Instale o IPA sem assinatura após assiná-lo no Feather.
2. Abra **••• → Diagnóstico** para ver a última tentativa automática.
3. Toque em **Executar teste isolado**. Ele obtém uma nova CLLocation, registra o reverse geocoding e chama apenas `.current`. Se `.current` funcionar, testa `.hourly` e `.daily` em chamadas separadas. Uma falha em `.hourly` não impede o teste de `.daily`.
4. Aguarde o resultado e toque em **Copiar diagnóstico**. O texto inclui Bundle Identifier, Domain, Code, localizedDescription, userInfo e a cadeia NSUnderlyingErrorKey de cada erro.

O teste isolado não usa o timeout agregado do app e não converte erros nativos do WeatherKit. Timeouts locais de localização/geocoding têm domínios `SimpleWeather.CoreLocation` / `SimpleWeather.Geocoding`, distintos dos erros devolvidos pela Apple. Se CoreLocation falhar, WeatherKit fica como `NOT RUN`. Se somente geocoding falhar, a previsão continua usando coordenadas válidas e o nome genérico de localização.

O relatório isolado permanece em memória durante a sessão, separado das atualizações automáticas. Ele contém coordenadas: revise antes de compartilhar. Credenciais reconhecidas em userInfo/descrições são ocultadas; dados binários e objetos opacos não são despejados. Logger registra etapas e erros, trata descrições/userInfo/coordenadas como privados e percorre erros internos com proteção contra ciclos. Não há envio de diagnóstico nem fornecedor meteorológico alternativo.

Os testes offline verificam preservação/redação de erros, sequência das consultas e separação das falhas. **Eles não identificam a causa no iPhone: a investigação permanece aberta até recebermos o Domain + Code reais do aparelho.**

## Build automático

O workflow **iOS Build** (`.github/workflows/ios-build.yml`) roda em push, pull request e execução manual. Usa macOS 15 e Xcode 16.4, versões presentes na [imagem oficial do runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).

1. Exibe versão do Xcode e schemes; valida a estrutura do projeto.
2. Compila o app e a extensão incorporada em Debug para iOS Simulator, sem assinatura.
3. Seleciona dinamicamente um iPhone disponível e executa testes offline.
4. Compila Release, sem os fixtures de desenvolvimento.
5. Publica `WeatherApp-Simulator`, `WeatherApp-VisualReview` e `WeatherApp-Diagnostics`.

Veja **GitHub → Actions → iOS Build → execução do commit**. O artefato de Simulator contém um `.app`; **não é um IPA instalável no iPhone**. Não são necessários secrets para esse workflow.

## Build local

Abra `WeatherApp.xcodeproj` no Xcode 16.4 ou posterior e selecione o scheme compartilhado **WeatherApp**. O projeto já está versionado e não exige XcodeGen, CocoaPods ou geração inicial.

```bash
xcodebuild -project WeatherApp.xcodeproj -scheme WeatherApp \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO clean build
```

Para testar, selecione um iPhone Simulator no Xcode e use **Product → Test**. Os testes não consultam a rede, WeatherKit ou GPS. O processo de testes não inicia a busca de localização do app.

Ao adicionar/remover arquivos Swift, execute `python3 scripts/generate_project.py`. O gerador usa só a biblioteca padrão do Python. Depois execute `python3 scripts/validate_project.py`; essa validação estrutural não substitui a compilação.

## WeatherKit e iPhone físico

O app usa `WeatherService.shared`; dados de demonstração existem apenas em previews e testes. A execução real requer assinatura e configuração da conta [Apple Developer com WeatherKit](https://developer.apple.com/help/account/services/weatherkit/).

1. Em `Config/Project.xcconfig`, defina seu `DEVELOPMENT_TEAM`. Se necessário, troque `APP_BUNDLE_IDENTIFIER` por um identificador exclusivo. O padrão inicial é `com.hc6q.weatherapp`.
2. No Apple Developer Portal, registre o App ID principal e `com.hc6q.weatherapp.widgets` (ou os identificadores derivados da sua alteração).
3. Habilite **WeatherKit** nas capabilities e nos App Services dos dois App IDs, pois a extensão também pode consultar a Apple.
4. Registre o App Group `group.com.hc6q.weatherapp` (ou o identificador derivado) e associe os dois App IDs ao mesmo grupo.
5. No Xcode, confira **Signing & Capabilities → WeatherKit / App Groups** nos dois targets e atualize os provisioning profiles.
6. Instale no iPhone, abra o app e permita localização **Durante o Uso**. Depois adicione os widgets pela tela de início.

O CI sem assinatura valida código e integração dos targets, mas não comprova a autorização de uma conta Apple para receber previsões. O usuário vê mensagens amigáveis quando a autorização do serviço ou a rede falha. O rodapé mostra a atribuição e as [fontes exigidas pela Apple](https://developer.apple.com/weatherkit/#apple-weather-and-third-party-attribution).

## Localização, cache e widgets

- CoreLocation usa `requestLocation()`, com precisão de aproximadamente um quilômetro. Não há GPS contínuo, permissão permanente nem modo de localização em segundo plano.
- A cidade vem de geocodificação reversa. Falhas preservam o nome apenas quando as coordenadas ainda estão próximas; em uma região nova, o fallback é “Localização atual”.
- O app reutiliza localização recente por até cinco minutos e atualiza a previsão quando há mudança de região, dados antigos ou pedido manual.
- Snapshot `Codable` em App Group, escrita atômica e proteção de arquivo após o primeiro desbloqueio. Celsius/Fahrenheit, última localização e atribuição usam preferências compartilhadas.
- O widget lê o cache e pode consultar WeatherKit com as últimas coordenadas autorizadas por até 12 horas, sem ligar o GPS. Depois disso, é preciso abrir o app para obter localização recente. Ele não acompanha deslocamentos com o app fechado.
- O provider solicita nova timeline em cerca de 30 minutos; **o iOS decide quando executar**. Não existe garantia de atualização no minuto solicitado.
- O app e a extensão têm arquivos de cache separados para evitar sobrescritas entre processos. Uma falha posterior preserva o último resultado válido do widget para aquela região.
- Se a previsão estiver antiga, o widget usa a linha da condição para exibir o horário da última atualização. Assim a temperatura antiga não aparece como leitura atual. Dados ausentes exibem traços e orientação para abrir o app.
- Os widgets não exibem cidade. Ao tocar, abrem o app, onde também estão a atribuição e as fontes. Cores em modos de widgets tingidos são controladas pelo iOS.

## Interface e revisão visual

As três interfaces são SwiftUI real: preto `#000000`, cards `#060606`, bordas discretas, fonte do sistema e ícones SF Symbols com acabamento em cinza, amarelo e ciano. O desenho dos símbolos nativos pode diferir dos ícones tridimensionais das referências.

Há previews de nublado, chuva, sol, noite e dos dois widgets. `VisualReviewTests` usa uma janela com `UIHostingController` no Simulator para capturar a tela nas larguras 375, 390 e 430 pt, os widgets 170×170 / 364×170 e uma variante com Dynamic Type de acessibilidade. O teste também rejeita capturas vazias. As imagens são exportadas no artefato `WeatherApp-VisualReview`. São capturas das interfaces com fixtures de teste, não capturas dos widgets instalados na tela de início do iOS.

No iPhone, confira também VoiceOver, Reduzir Movimento, localização negada, modo avião com/sem cache e a troca de unidade refletida nos widgets. O App Icon está em `Assets.xcassets`, com o desenho vetorial editável em `Config/AppIcon.svg`.

## IPA sem assinatura para iPhone

O workflow manual [iOS Unsigned IPA](https://github.com/hc6q/simpleweather/actions/workflows/ios-unsigned-ipa.yml) usa o projeto e o scheme atuais. Compila em **Release**, com `-sdk iphoneos`, destino `generic/platform=iOS` e arquitetura `arm64`. A assinatura é desativada com `CODE_SIGNING_ALLOWED=NO` e `CODE_SIGNING_REQUIRED=NO`; Automatic Signing não é usado nessa execução.

1. Abra **Actions → iOS Unsigned IPA → Run workflow**, na branch `main`.
2. Quando terminar, baixe o artifact **SimpleWeather-Unsigned-iPhone**.
3. Extraia **SimpleWeather-Unsigned.ipa** do ZIP do artifact e importe no **Feather**, onde a assinatura será feita posteriormente.

O IPA contém `Payload/SimpleWeather.app` e a extensão `PlugIns/WeatherWidgets.appex`. O workflow abre o IPA final e verifica o SDK `iphoneos`, a plataforma Mach-O `IOS`, a arquitetura `arm64` do app e do widget, as permissões dos executáveis e a ausência de assinatura. Os logs e o resumo da execução registram essas verificações e o SHA-256 do IPA.

Apenas o nome da pasta externa do app muda no pacote; identificadores, executáveis, interface, frameworks e arquivos de entitlements do projeto são preservados. O GitHub apenas compila e empacota: não utiliza certificado, senha, provisioning profile, conta Apple ou secrets de assinatura. Esse workflow não faz upload para TestFlight nem assina o aplicativo.

## Organização

- `WeatherApp/`: entrada SwiftUI, localização, geocodificação, estado da tela e views.
- `Shared/`: modelos, formatação, WeatherKit, cache, componentes e String Catalog.
- `WeatherWidgets/`: bundle WidgetKit, widgets e timeline provider.
- `WeatherAppTests/`: conversão, datas/fusos, seleção das previsões, persistência e renderização.
- `WeatherApp.xcodeproj/`: targets app/extensão/testes e scheme compartilhado.
- `Config/`: identificadores, versão, assinatura e origem vetorial do ícone.
