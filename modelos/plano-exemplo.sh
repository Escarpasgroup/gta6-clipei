# Plano de um corte (render.sh <pasta>/plano.sh). Exemplo real aprovado: tentativa de roubar viatura → polícia derruba.
# Tempos de SEGS = da ORIGEM (o bloco). Tempos de legendas/VOZ/SFX = da SAÍDA. Veja o mapa: render.sh plano.sh --mapa
# source do layout do bloco (preparar_live.sh grava comum.sh com SRC já apontando para o bloco):
source ../b007/comum.sh
OUT=final.mp4
GANHO=2.6
# "inicio fim efeito [params]" — efeitos mais usados:
#   none                      sem efeito
#   motion X Y Z0 Z1          zoom contínuo suave no rosto (X,Y = nariz em px do quadro de saída), de Z0 até Z1
#   face X Y Z [Z0]           aproxima suave no rosto até Z
#   crash                     clarão + tremida (impacto)
#   game Z X Y [Z0]           zoom suave no jogo · freeze / trava / lento F / rapido F / fim  (ver render.sh)
SEGS=(
  "137.0 141.0 motion 156 270 1 1.06"
  "141.0 142.4 crash"
  "142.4 152.5 face 156 270 1.2 1.08"
  "155.0 162.5 motion 156 270 1.08 1"
  "162.5 167.0 none"
  "181.5 187.0 face 156 270 1.15 1.05"
)
