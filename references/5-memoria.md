# 5. Memória, métricas e aprendizado

## Onde fica (pasta da operação)
- `memoria/INDICE.md` (30–60 linhas): ponto de partida; abra só o arquivo que o índice indicar.
- `memoria/perfil.md` — gosto do canal (edição). `memoria/decisoes.md` — decisões com data.
  `memoria/streamers.md` — autorização, @, layout, ganho. `memoria/tendencias.md` — resumo ativo com data.
- `dados/*.jsonl` (um gravador por máquina): `candidatos`, `publicacoes`, `metricas`, `consumo`, `autorizacoes`
  (cadastro dos streamers), `controle` (aprovado/revisão/bloqueado por rede, com motivos), `historico` (impressões
  de duplicidade de tudo que foi para a fila); `dados/triagem/*.tsv`. `memoria/autorizacoes/` = prints/links de evidência.
  Consulta com `jq`. `fila/postados/log.tsv` e `.feito` são lidos por `registro.sh importar`.
- Conhecimento geral (vale para todo canal): `SK/references/conhecimento.md` e `padroes-referencias.md`.

## Feedback do dono do canal
- Preferência geral ("não gostei do amarelo", "zoom tem que ser no rosto") → regra em `perfil.md` (✅/❌, com data)
  e conte em uma linha o que anotou. Específico de um vídeo → só corrija.
- Correção explícita vale na hora. Na dúvida, registre como 🧪.

## Métricas por corte e rede
`bash SK/scripts/registro.sh metrica <event_id> <plataforma> <1h|24h|72h> '{"views":1234,"pct_visto":0.61}'`
Campos: views, tempo_medio_s, pct_visto, retencao_inicial, compartilhamentos, salvamentos, seguidores (ausente = null).
Horário, tema, gancho, duração, nota prevista, criador e edição já estão na ficha (junte por `event_id`).

## Auditoria e restrições
- `registro.sh auditoria [event_id]` → por corte: streamer, link e horário da live, autorização, trecho, contribuições
  editoriais, duplicidade, riscos, redes aprovadas, estado de publicação e justificativa (`dados/auditoria.tsv`).
  Cortes antigos sem ficha aparecem como "legado (sem ficha)".
- Rede avisou/limitou um post (conteúdo não original, duplicado, direitos, alcance cortado) → `registro.sh estado
  <event_id> <rede> restrito` e anote o aviso em `decisoes.md`.
- `registro.sh relatorio` → estados por rede, motivos mais comuns de revisão/bloqueio, e por formato (categoria/tema
  · nível editorial) e por streamer: aprovados, bloqueios, restritos e views médias. Use para cortar o que é limitado.

## Aprender sem se enganar
- Um post = uma hipótese. Compare por plataforma, duração, idade do post e mediana do perfil.
- Só mude peso ou limiar da nota com 10–20 publicações comparáveis e o padrão repetido em mais de uma janela.
  Registre em `decisoes.md`: amostra, evidência, efeito esperado, condição de reversão.
- Acompanhe falsos positivos (nota alta, desempenho baixo), descartes recuperados e previsão × resultado.
- Aprendizado que vale para qualquer canal → proponha acrescentar em `SK/references/conhecimento.md` (com dado).
- Tendência vencida sai do resumo ativo. Destinos e regras de publicação só mudam por configuração explícita.
