# gta6-clipei

Skill do Claude Code para operar um canal de cortes de lives (GTA 6, GTA RP, GTA V e outros jogos), de ponta a ponta:
grava a live em blocos, faz a triagem, escolhe os momentos com nota, edita no formato vertical do canal, confere
autorização do streamer e duplicidade e posta só o aprovado no TikTok, Reels e Shorts pelo Buffer + Cloudflare R2.

O repositório leva só o processo, os scripts, os modelos e o conhecimento. Não leva vídeos, dados, memória, moldura
nem segredos de nenhum canal: cada pessoa cria a própria operação ao instalar.

## Instalar (Windows)

1. Instale as dependências:

   ```bash
   winget install Git.Git Gyan.FFmpeg yt-dlp.yt-dlp jqlang.jq
   ```

2. Clone dentro da pasta de skills do Claude Code (no Git Bash):

   ```bash
   git clone https://github.com/Escarpasgroup/gta6-clipei.git ~/.claude/skills/gta6-clipei
   ```

3. Crie a sua operação:

   ```bash
   bash ~/.claude/skills/gta6-clipei/instalar.sh "C:/Users/<você>/Documents/MinhaOperacao" publicador meu-pc --baixar-modelo
   ```

4. Edite `config/operacao.env` da operação (CONTA, ARROBA, TEMA, HASHTAGS, CREDITO) e use `/gta6-clipei` no Claude Code.

O passo a passo completo, incluindo dois PCs na mesma operação e a configuração da postagem, está em
[references/6-instalar-e-maquinas.md](references/6-instalar-e-maquinas.md).

## O que fica fora do repositório

- `assets/fonts/*.ttf`: fontes do Windows não são redistribuídas. O `instalar.sh` copia as do seu próprio Windows.
- `operacao.local`: caminho da operação de cada PC, criado pelo `instalar.sh`.
- `config/segredos.env`: chaves do Cloudflare R2. Fica só na pasta da operação do PC publicador e nunca deve ser
  enviado a ninguém.

## Aviso

Só corte lives de quem autorizou. A skill bloqueia a postagem de streamer sem autorização cadastrada em
`memoria/streamers.md`.
