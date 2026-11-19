# 3. Editar o corte (perfil do canal + renderizador)

Leia antes `<operação>/memoria/perfil.md` (o gosto deste canal) e, para ideias, `conhecimento.md`.

## Moldura do canal (criar uma nova por canal)
```
bash SK/scripts/criar_moldura.sh <operação>/marca/moldura.png @seu.canal FF2E63 111827 <um_corte.mp4> 3 previa.jpg
```
Cantoneiras na cor de destaque + selo escuro com o @ no alto à esquerda. Escolha 1 cor de destaque forte (identidade)
e 1 escura para o selo. Olhe a prévia: o selo não pode cobrir olhos nem gancho; nada na faixa de baixo (legenda das
redes). Arte própria também serve: PNG 1080x1920 transparente no mesmo caminho. O render aplica sozinho.
Mudou o desenho → mostre a prévia ao dono do canal antes de usar.

## Pasta de cada corte
`<TRAB>/vedit-<apelido>/cN/` com `plano.sh` (`source ../bNNN/comum.sh`), `legendas.ass` e `falas.txt`.
Modelos: `SK/modelos/plano-exemplo.sh`, `legendas-exemplo.ass`, `falas-exemplo.txt`.
- `SEGS` = trechos em tempo da ORIGEM (o bloco) com efeito: `none`, `motion X Y Z0 Z1`, `face X Y Z [Z0]`, `crash`,
  `game Z X Y`, `freeze`, `freezeface`, `trava`, `travazoom`, `lento F`, `rapido F`, `fim`, `pb`, `boom`, `wasted`
  (lista completa no topo de `render.sh`). Legendas e `VOZ`/`SFX` em tempo da SAÍDA.
- Mapa origem → saída: `bash SK/scripts/render.sh <corte>/plano.sh --mapa`.
- Rosto (X,Y para zoom): `bash SK/scripts/detalhe.sh rosto <pasta> <FC_H> <t1> <t2> …` (meça cada trecho).

## Legendas
- Gancho (`Hook`) 0–3,5 s em y = FC_H; asterisco (`Cap`) em y≈1500 (jogo) ou ≈630 (câmera).
- Fala palavra por palavra: escreva `falas.txt` (`inicio fim TEXTO` em tempo de saída; durante o gancho use
  `inicio fim y=<FC_H+165> TEXTO`), renderize uma vez (gera `voz.wav`), depois
  `bash SK/scripts/palavras_alinhadas.sh falas.txt voz.wav <FC_H+95> >> legendas.ass` e renderize de novo.
- Fala confirmada só com `bash SK/scripts/detalhe.sh fala <pasta> <inicio> <dur>`. Live gringa: traduza com
  naturalidade para o idioma do canal, sem inventar.
- Edite o `.ass` com a ferramenta Edit (sed estraga `\f`, `\t`, `\N`).

## Pauta editorial (obrigatória, ANTES do render)
Cortar e legendar a live de outra pessoa é material reutilizado: as redes tiram da recomendação. Cada corte precisa
de contribuição editorial real. Antes de renderizar, preencha e grave:
```
bash SK/scripts/registro.sh editorial <event_id> '<json>'    # modelo: SK/modelos/editorial-exemplo.json
```
1. `contexto`: o que estava acontecendo (o que veio antes, quem é quem). Assista o antes, não só a transcrição.
2. `historia`: existe começo, virada e fim? Se não existe, diga `false` (e repense o corte).
3. `abertura`: abertura contextualizada (cartela/gancho dos 2 primeiros segundos) que situa quem não viu a live.
4. `contribuicoes`: só onde acrescenta de verdade, cada uma com `texto` e `base` (onde, no material, isso se apoia):
   `contexto` (cartela do que veio antes), `analise` (o que ele fez/errou, mostrado na tela), `explicacao` (mecânica
   ou regra que o próprio material mostra), `comentario`, `humor` (asterisco de reação), `narracao` (voz/texto
   narrando). **Não contam:** legenda, zoom, transição, velocidade, borda, moldura, marca-d'água.
5. `fala_preservada: true` = as falas e o sentido do streamer ficaram como ele disse. `inventado: false` = nenhuma
   reação, fato ou declaração inventada. Qualquer um falso → bloqueado.

Nível calculado: `editorial` (≥2 contribuições válidas, ≥1 informativa — contexto/análise/explicação/narração — e
abertura) · `leve` (1) · `reutilizado` (0). Só `editorial` pode ser aprovado sem revisão humana. Na dúvida sobre um
fato do jogo, não afirme: descreva o que se vê.

## Voz atrasada em relação à boca (live do streamer)
Nossa gravação e o render não criam atraso (áudio e vídeo medidos dentro de ±22 ms). Se a voz da LIVE vem fora da
boca (OBS do streamer), meça uma vez por streamer: `bash SK/scripts/detalhe.sh sinc <bloco> <t_falando_de_frente>`
→ escolha, com fone, a versão em que a boca bate e grave `AV_MS=<valor>` no layout dele (o render desloca o áudio;
positivo = voz atrasada). Anote em `memoria/streamers.md`. Confira de novo se ele mudar a câmera ou o mic.

## Regras fixas de retenção, engajamento e capa (aulas adotadas pelo dono, ver `aula-*.md`)
- As 3 armas juntas, uma reforçando a outra: som (voz do streamer audível), imagem (corte de tempo morto, zoom,
  movimento) e texto na tela (gancho, fala, asterisco). Faltou uma → o corte não está pronto.
- Gancho com a palavra que alguém pesquisaria ("BRIGA DE BAR NO GTA 6", "CARRO CLÁSSICO NO GTA 6").
- Pergunta fácil escrita no fim, em todo corte: sim/não ou "qual dos dois" ("VOCÊ ENTRAVA NESSA BRIGA?").
  Estilo `Hook`, `\pos(540,620)`, nos últimos ~2,5 s, sem alongar o corte. Pergunta difícil ninguém responde.
  Varie o texto: nunca a mesma pergunta duas vezes no lote.
- Capa: escolha o quadro com o rosto reagindo OLHANDO PARA A CÂMERA + o clímax do jogo no mesmo quadro. Olhe esse
  quadro em 180 px de largura: rosto, gesto e objeto do jogo reconhecíveis. Grave o tempo em ms em
  `FILA/N_apelido.capa` na entrega. Nunca capa gerada por IA.

## Renderizar e revisar
```
bash SK/scripts/render.sh <corte>/plano.sh          # ~40 s por 45 s de vídeo com GPU
bash SK/scripts/detalhe.sh saida <corte> final.mp4 <t1> <t2> …   # 1 folha de revisão
bash SK/scripts/qa.sh <corte>/final.mp4 <t> quadro.jpg          # 1080x1920, 15–45 s, -12,5 a -11 LUFS, áreas das redes
```
Confira: zoom no rosto, legenda sem cobrir rosto/legenda do jogo, texto certo, início com ação, fim ≤2 s após o
desfecho, sincronia, nada importante nas áreas coloridas do `qa.sh` (interface das redes, medidas aproximadas).

## Armadilhas técnicas (Windows + Git Bash)
- Pasta de trabalho de caminho CURTO (`%LOCALAPPDATA%\Temp\vedit-x`): o Whisper quebra com caminho longo.
- O bash da ferramenta pode falhar com `fnm`: chame `"C:/Program Files/Git/bin/bash.exe"` e use caminhos absolutos
  (o `cd` não persiste e pode quebrar a cadeia `&&`).
- NVENC pode falhar com driver antigo: o render usa libx264; `-hwaccel cuda` só para decodificar.
- `drawtext` precisa de `fontfile=`; `subtitles` precisa de `fontsdir=fonts` (pasta pequena; a skill copia).
- Whisper transcreve a voz do jogo e inventa "[MÚSICA]"; janelas curtas (`detalhe.sh fala`) acertam mais que o SRT longo,
  e o SRT longo escorrega o tempo.
- Duas faixas de áudio iguais (OBS): `-map 0:a:0`. Sem GPU NVIDIA tudo roda na CPU (3–6 min por corte num notebook).
