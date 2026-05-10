# Nacidos de la Bruma - juego online

Juego web inspirado en las reglas de `MistbornRulebook_V1.pdf`, preparado para 1-4 personas en sala online.

## Arrancar

```powershell
powershell -ExecutionPolicy Bypass -File .\server.ps1 -Port 8787
```

Abre `http://localhost:8787/`.

Para jugar con otras personas en la misma red, comparte la URL LAN que imprime el servidor. Para jugar fuera de tu red local, usa un tunel tipo Tailscale, ZeroTier, Cloudflare Tunnel o ngrok apuntando al puerto 8787.

## Reglas implementadas

- 1-4 jugadores por sala.
- Modo competitivo o modo Lord Legislador para solitario/cooperativo.
- Mazo inicial con 6 Funding y 4 entrenamientos.
- Mercado de 6 cartas, compras con monedas y reemplazo inmediato.
- Mano, mazo, descarte, cartas en juego, aliados persistentes y pila eliminada.
- Pista de entrenamiento con aumento de metales quemables, habilidades y Atium.
- Quemar metales, flarear fichas, refrescar metales y usar cartas de accion como metales.
- Misiones: 3 pistas hasta 12 puntos con recompensas intermedias.
- Combate, vida hasta 40, eliminacion y objetivo en partidas de 3-4.
- Condiciones de victoria por tres misiones completadas o ultimo jugador vivo.
- En modo Lord Legislador: vida, dominancia, mazo automatico de desafios y victoria cooperativa al derrotarlo.
- Cartas con ilustraciones locales generadas por tipo de metal.

Las cartas del mercado son una baraja funcional creada para esta version digital, porque el PDF contiene normas pero no una lista textual completa de cartas reproducibles.
