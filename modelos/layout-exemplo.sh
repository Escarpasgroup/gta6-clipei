# Layout de um streamer: como transformar a live horizontal (1920x1080) no vertical 1080x1920.
# Copie para <operação>/layouts/<apelido>.sh e ajuste o crop da câmera (meça num quadro da live, ver references/3-editar.md).
# Exemplo: câmera no canto superior esquerdo (caixa x28–438, y21–245), câmera inteira em cima sobre o jogo desfocado,
# jogo (recorte central) embaixo. A moldura cobre o canto de cima: deixe o rosto abaixo dela.
SRC=live.mp4
FC_H=700
LAYOUT="split=3[lb][lc][lg];[lb]scale=1244:700,crop=1080:700,boxblur=20,eq=brightness=-0.15[lbg];[lc]crop=410:224:28:21,scale=1080:590:flags=lanczos,unsharp=5:5:0.6[lcam];[lbg][lcam]overlay=0:110[ltop];[lg]crop=956:1080:482:0,scale=1080:1220:flags=lanczos[lgm];[ltop][lgm]vstack"
# Outro formato comum: só o rosto recortado preenchendo o topo (1080x700):
# LAYOUT="split=2[lc][lg];[lc]crop=340:220:50:70,scale=1080:700:flags=lanczos,unsharp=5:5:0.6[ltop];[lg]crop=956:1080:482:0,scale=1080:1220:flags=lanczos[lgm];[ltop][lgm]vstack"
DEC=(-hwaccel cuda)
# Volume: meça um corte sem ganho (qa.sh) e anote aqui. GANHO no plano ≈ 10^((alvo_LUFS - medido)/20).
# GANHO=1
# Créditos: @ real do streamer (confirmado) e se ele autorizou os cortes.
# CANAL=@canal_do_streamer
# AUTORIZADO=sim
