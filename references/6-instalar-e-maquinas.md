# 6. Instalar, passar para outra pessoa e usar em dois PCs

## O que é o pacote
A pasta `gta6-clipei/` (esta skill) é o pacote inteiro: processo, scripts, modelos e conhecimento. Não leva vídeos,
dados, memória, moldura nem segredos de nenhum canal. Cada pessoa cria a própria operação ao instalar.
Para gerar o .zip para distribuir: `bash SK/empacotar.sh <destino.zip>` (tira `operacao.local` e as fontes).

## Instalar num PC novo (Windows)
1. Instale: Git for Windows, ffmpeg (build full do gyan.dev, com filtro whisper), yt-dlp e jq:
   `winget install Git.Git Gyan.FFmpeg yt-dlp.yt-dlp jqlang.jq`. Claude Code (app do Claude, aba Code).
2. Descompacte a pasta em `%USERPROFILE%\.claude\skills\gta6-clipei\` (fica disponível em qualquer projeto).
3. No Git Bash:
   `bash ~/.claude/skills/gta6-clipei/instalar.sh "C:/Users/<você>/Documents/MinhaOperacao" publicador meu-pc --baixar-modelo`
   (troque `publicador` por `analise` no segundo PC). Cria config, memória, fila, layouts e uma moldura inicial;
   copia as fontes do Windows; baixa o modelo do Whisper (466 MB, licença MIT); roda a simulação.
4. Edite `config/operacao.env` (CONTA, ARROBA, TEMA, HASHTAGS, CREDITO). Crie a moldura do canal (`3-editar.md`).
5. Publicador: "/gta6-clipei configurar postagem" (`4-postagem.md`).
6. Teste: `bash SK/scripts/simular.sh` → `0 falha(s)`.

Versões em que foi testado (2026-11-19): Git 2.55 (bash 5.3, gawk 5.4.1, curl 8.21), ffmpeg 9.0.2 (com whisper e
chromaprint), yt-dlp 2026.10.26, jq 1.8.2. Python e SQLite não são usados. GPU NVIDIA opcional.

## Dois PCs na mesma operação
- **Um único publicador por conta**: só ele tem a tarefa agendada, `segredos.env` e `PAPEL=publicador`.
  Instalar como `analise` numa pasta com config copiada do publicador rebaixa o papel sozinho.
- O de análise grava, tria, faz a ficha e a pauta editorial (`registro.sh editorial`) e renderiza. Entrega `.mp4` +
  `.txt` (+ `.capa`) na `fila/` do publicador por cópia e manda as fichas: `registro.sh exportar > fichas.jsonl` →
  no publicador `registro.sh juntar fichas.jsonl` (a pauta editorial vai junto, é linha da ficha).
- **Conferência só no publicador**: o cadastro de autorizações e o histórico de duplicidade moram lá. Lá roda
  `registro.sh avaliar <event_id> <fila/arquivo.mp4>` → revisão, se houver → `entregar`.
- Render no PC que também roda FiveM: `FIVEM_MODO` (`pausar|leve|ignorar`) e `RENDER_THREADS` na config de cada PC.
- Voz fora da boca de um streamer: `AV_MS` vai no layout dele (`layouts/*.sh`): copie os layouts entre os PCs.
- Cada PC grava só o próprio `dados/`. Não sincronize `dados/` por OneDrive/Drive com script gravando.
- `memoria/` pode ir junto (texto), mas edite num PC só por vez.

## Trocar o publicador sem perder histórico
1. Antigo: desligue a tarefa agendada; rode `registro.sh importar`; copie `dados/`, `memoria/`, `fila/` (com
   `postados/` e `.feito`) e `config/operacao.env`.
2. Antigo vira `PAPEL=analise`. Novo: `instalar.sh <pasta copiada> publicador`, coloque `segredos.env`, crie a tarefa.
3. Novo: `simular.sh` e `registro.sh resumo` (mesmos números do antigo). Nunca deixe duas tarefas ligadas.

## Passar para outra pessoa
Mande só o .zip do `empacotar.sh`. Ela instala, cria a própria moldura, conecta o próprio Buffer e R2 e pede
autorização aos próprios streamers. Nada da sua conta vai junto. Fontes não vão no pacote (são do Windows de cada um).
