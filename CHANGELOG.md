# Changelog

## v0.12.0 — 2026-10-10
- Panel **Admin** en el menú (solo admins): activar/desactivar, solo admins, espera entre cambios, tamaño máximo del addon, modos de juego bloqueados (con botón para el modo actual), addons bloqueados y lista de jugadores para quitar la skin, bloquear su addon, banear/desbanear o copiar SteamID.
- Convars del server `sv_skinshare_*` (replicadas) y comando `skinshare_admin` para consola/RCON. El baneo se guarda con PData.
- Si un admin bloquea algo, las skins afectadas se quitan al momento. El cliente tampoco descarga addons bloqueados.
- Hook `SkinShareCanUse(ply)` para que otros addons o gamemodes bloqueen SkinShare.
- Botón de modelo aleatorio, `skinshare_random` (favorito al azar), copiar ruta del modelo y reescanear modelos sin cambiar de mapa.
- Avisos en el chat cuando el server no te deja usar SkinShare y por qué.

## v0.11.1 — 2026-10-10
- Fix: las manos no cambiaban (salían las default o se quedaban las de la skin anterior). Ahora el cliente siempre manda las manos de su skin, también las de modelos registrados por Lua, y el server las pone con el hook `PlayerSetHandsModel`, así sobreviven cuando el gamemode rearma las manos.

## v0.11.0 — 2026-10-10
- Fix: `!skin` ahora funciona en Murder estando vivo (Murder reenvía el chat de los vivos; ahora lo detecta el server antes que el gamemode). También `/skin`.
- Si los demás no pueden descargar tu skin (addon privado, sin tag Model o de más de 300 MB), te avisa en el chat en vez de fallar en silencio.
- Ícono de SkinShare en el menú C de Sandbox.
- `skinshare_fav "nombre"` para usar un favorito sin abrir el menú (se puede bindear).
- Favoritos: clic derecho → Sobrescribir con el actual. Modelos: clic derecho → Regenerar ícono.

## v0.10.0 — 2026-10-10
- Interfaz nueva con skin de Derma propio (plano oscuro, acento azul): botones, pestañas, sliders, buscador, scroll y menús combinan. El preview muestra el nombre del modelo y los controles.
- Ícono nuevo del Workshop.
- Clic derecho en un modelo: Seleccionar / Agregar a favoritos. Clic derecho en el preview: guardar en favoritos lo que tienes puesto (bodygroups, cara, colores).
- Favoritos ahora en cuadrícula con íconos: clic carga y clic derecho deja cargar, renombrar o borrar.
- El preview solo gira con clic izquierdo.

## v0.9.1 — 2026-10-09
- Fix: volvieron las skins que faltaban. `util.IsValidModel` en el cliente rechazaba los modelos que el server no había precacheado. Ahora se filtran solo los que no existen y los de animaciones.

## v0.9.0 — 2026-10-09
- Interfaz en inglés y español: sigue el idioma de GMod, con botón EN/ES y el convar `skinshare_language`.
- Se ocultan los modelos inválidos (ERROR, animaciones) de la cuadrícula.
- Ícono y descripción del Workshop.

## v0.8.0 — 2026-10-09
- Fix: las skins ya no se pierden si el Lua se recarga en caliente (la tabla del server ahora es global).
- Fix: TTT ya no pisa tu color al empezar cada ronda (hook `TTTPlayerSetColor`).
- Seguridad: solo se montan items del Workshop con tag Model y de hasta 300 MB.

## v0.7.1 — 2026-10-09
- Fix: Quitar skin ya no deja a los jugadores negros fuera de Sandbox (`cl_playercolor` solo existe ahí).
- Fix: el ack incluye el modelo, así que un ack de una skin anterior ya no libera la nueva antes de tiempo.
- Manos: primero `<modelo>_arms.mdl` y luego `c_arms*` del mismo addon; no se tocan si el modelo ya está registrado. Se reinician el skin y los bodygroups de las manos.
- El fallback de 60 s usa un contador propio.
- Vuelve el filtro `models > 0` (escanear todos los addons era lento).

## v0.7.0 — 2026-10-09
- La skin se aplica cuando todos los clientes la montaron (ack) o a los 60 s; evita que se queden con ERROR.
- `resource.AddWorkshop` para quien se una después.
- Manos: se mandan las `*_arms.mdl` de la carpeta del modelo (el Lua del cliente que las registra no corre en el server).
- Quitar skin restaura los colores del jugador.
- Ya no se descartan addons con `models = 0` (pasa cuando Steam no responde).
- Detección de `_anm` sin distinguir mayúsculas; las rutas se pasan a minúsculas.
- Límite de flexes subido a 8192; aviso en el chat si se manda muy rápido (cooldown 1 s).
- Favoritos guardados como lista (los nombres numéricos rompían el JSON). Los favoritos viejos se descartan.
- Fixes de UI: cuadrícula con scroll, preview inválido ya no truena.
- `skinshare_debug` en consola y versión en el título/consola.

## v0.6.1 — 2026-10-09
- Fix: los playermodels de los addons de los clientes se detectan por las animaciones de jugador que incluye el .mdl (`m_anm`/`f_anm`/`z_anm`), no por la ruta. Ahora aparecen skins como Mirage o Realistic Fish Head.

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
