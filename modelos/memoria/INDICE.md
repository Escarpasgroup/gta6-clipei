# Memória da operação — índice

Leia este índice primeiro e abra só o arquivo da etapa. Caminhos relativos à pasta da operação.
Mantenha entre 30 e 60 linhas.

## Preferências e decisões confirmadas
- `memoria/perfil.md` — perfil de edição do canal (moldura, gancho, legenda, ritmo, volume). Começa com o padrão da skill.
- `memoria/decisoes.md` — decisões editoriais e de operação, com data.
- `memoria/streamers.md` — quem autorizou, @ real, layout e ganho de cada streamer.

## Tendências
- `memoria/tendencias.md` — resumo ativo com data. Vencida sai do resumo.

## Registros (dados/, um gravador por máquina; não sincronizar por nuvem com script gravando)
- `dados/candidatos.jsonl` — fichas por event_id (nota, decisão, motivo, direitos, tempos).
- `dados/publicacoes.jsonl` — estado por event_id|conta|plataforma.
- `dados/metricas.jsonl` — métricas 1 h / 24 h / 72 h.
- `dados/consumo.jsonl` — duração analisada e lacunas por triagem.
- `dados/triagem/*.tsv`, `dados/cache/` — fichas curtas e cursor da triagem.
- `fila/` (+ `postados/log.tsv`, `.feito`) — fila de postagem.

## Configuração
- `config/operacao.env` — papel da máquina, conta, pastas, Buffer, hashtags.
- `config/segredos.env` — chaves do R2. Só no PC publicador. Nunca copiar para memória, logs ou pacote.

## Pendências abertas
(nenhuma)
