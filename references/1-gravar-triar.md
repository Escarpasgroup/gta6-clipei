# 1. Gravar a live e triar com orçamento

`SK` = pasta da skill. Use o bash do Git: `"C:/Program Files/Git/bin/bash.exe"`.

## Gravar (em segundo plano)
```
bash SK/scripts/gravar_live.sh <url_da_live> <TRAB>/vedit-<apelido> 21600 0 1200
```
Grava até 6 h em blocos de 20 min (`parte_000.mp4`, …); `0` = desde o começo da janela que o YouTube guarda.
Sem o último argumento grava um `live.mp4` único (só abre no fim). Live caiu e voltou → rode de novo noutra pasta.
A skill **não** vigia live com a sessão fechada: o processo é da sessão que o iniciou.

## Várias sessões ao mesmo tempo: nunca o mesmo streamer
- Antes de escolher ou trocar de live: `bash SK/scripts/lives_reserva.sh listar` mostra quem já está sendo gravado
  (`streamer dono segundos situacao`). Escolha só streamer fora da lista (ou com reserva `expirada`).
- `gravar_live.sh` reserva o canal sozinho ao começar, renova a cada 2 min e libera ao terminar. Se outra sessão já
  grava o canal, sai com `STREAMER JA EM GRAVACAO` (código 3): escolha outra live, não insista.
- Canal não identificado pela URL → passe a chave: `GTA6_STREAMER=@canal bash SK/scripts/gravar_live.sh ...`.
- Reserva sem renovação há mais de 10 min (`RESERVA_EXPIRA_S`) expira e pode ser assumida.
- A sessão supervisora só coordena (lista reservas, vê sessões travadas, manda a próxima live livre); quem grava e
  edita são as sessões de corte.

## Preparar cada bloco que fecha (proxy vertical + Whisper uma vez + candidatos)
```
bash SK/scripts/blocos_live.sh <TRAB>/vedit-<apelido> <operação>/layouts/<apelido>.sh
```
Fica vigiando (rode em segundo plano) e imprime `PRONTO …/bNNN`. Só um vigia por gravação.
Vídeo já gravado: ponha como `<pasta>/live.mp4` e rode `bash SK/scripts/preparar_live.sh <pasta> <layout.sh>`.

## Layout de streamer novo
1. Tire um quadro da live: `ffmpeg -ss 600 -i parte_000.mp4 -frames:v 1 q.jpg` e ache a caixa da câmera (x, y, largura,
   altura) e a área do jogo sem a câmera.
2. Copie `SK/modelos/layout-exemplo.sh` para `<operação>/layouts/<apelido>.sh` e troque os números do `crop`.
3. Prepare um bloco, olhe `detalhe.sh quadros` e confira: rosto inteiro, abaixo do selo da moldura, sem bordas.
4. Meça o volume de um corte sem ganho (`qa.sh`) e anote o `GANHO` no layout. Registre o streamer em
   `memoria/streamers.md` (@ real e autorização).

## Primeira passada (só texto)
`bash SK/scripts/triagem.sh <TRAB>/vedit-<apelido>` → uma ficha curta por janela
(`origem bloco tipo ini_s fim_s ini_origem_s borda sinal sinais texto`).
- **Cache/cursor**: chave = origem (pasta + horário de início) + bloco + `TRIAGEM_VERSAO`. Rodar de novo com a live
  aberta só trata blocos novos. Mudou a triagem → suba a versão na config.
- **Sobreposição**: `borda=1` = janela a menos de 15 s do limite do bloco → abra também o bloco vizinho.
- **Orçamento**: até `FORTES_POR_HORA` (6) janelas fortes por hora nova + amostra de ~15% (mín. 1) de sinal fraco
  (silêncio ≥4 s seguido de pico): detalhe visual, fala baixa, NPC, piada sem fala.
- **Sinais são pistas**: grito sem história, fala dublada do jogo e música dão falso positivo.
- **Lacunas** em `dados/consumo.jsonl`. Não capturados hoje: chat, OCR, marcações, áudio do jogo separado, cortes de cena.
- `--preparar <layout>` roda `blocos_live.sh` uma vez antes; não use se já há um vigia nessa gravação.

## Abrir só candidatos
1. `bash SK/scripts/detalhe.sh quadros <bloco> <ini-15> <dur+30> 2` (±15 s). Câmera: `... 2 facecam`.
2. Sem desfecho → expanda +30 s uma vez. Ainda sem → ficha com `desfecho: ""` (vira `aguardando_desfecho`) e confira
   o próximo bloco quando fechar.
3. Nunca escolha só por transcrição ou um quadro: confirme a sequência nos quadros e a fala com `detalhe.sh fala`.
4. Conteúdo pesado (quadros, áudio, transcrição inteira) fica em disco; leia trechos.
Registro de consumo: sem contagem de tokens, `consumo.jsonl` guarda duração analisada, blocos e etapas caras.
