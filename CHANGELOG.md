# Changelog

## v0.6.0 — 2026-10-09
- Pantalla de carga personalizada (`lua/autorun/server/loadingurl.lua`).

## v0.5.0 — 2026-10-09
- Preview: arrastrar para girar, rueda para zoom.
- Pestañas Favoritos, Cara (flexes) y Colores (jugador + arma).
- Las manos del viewmodel van con la skin.
- Recuerda tu última skin y te la pone al entrar.
- Botones Reiniciar y Quitar skin (vuelves a la del modo de juego).

## v0.4.1 — 2026-10-09
- Fix: error `SkinShareRawSetModel` nil (SetModel vive en la metatabla de Entity).
- Fix: los clientes ahora ven sus propias skins, buscando los .mdl en sus addons montados.

## v0.4.0 — 2026-10-09
- Fuerza la skin elegida por encima de la del gamemode (TTT, etc.). Solo reemplaza playermodels, así que Prop Hunt sigue funcionando.

## v0.3.0 — 2026-10-09
- Pestañas Bodygroups/Skin y Color. El server los aplica y se mantienen al respawnear.

## v0.2.0 — 2026-10-09
- Selector con preview 3D, cuadrícula de iconos y buscador (al estilo Enhanced PlayerModel Selector).
- El addon de origen se detecta solo. Los modelos del juego base se comparten sin descargar nada.

## v0.1.0 — 2026-10-09
- Primera versión: menú `!skin`, descarga y montaje en partida, se reaplica al respawnear y reenvía las skins a quien entra tarde.
