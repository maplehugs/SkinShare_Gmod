# SkinShare (Garry's Mod)

Un jugador elige uno de **sus** addons de modelos y todos los demás lo descargan y lo montan en plena partida, sin reiniciar.

## Uso
- En el chat escribe `!skin` (o `skinshare` en la consola).
- Se abre un selector con preview en 3D girando a la izquierda y todos tus playermodels como iconos a la derecha, con buscador.
- Pestañas **Favoritos**, **Bodygroups** (skin y partes intercambiables), **Cara** (flexes) y **Colores** (jugador y arma). Todo se ve en el preview: arrastra para girar y usa la rueda para zoom.
- Se acuerda de tu última skin (`data/skinshare.json`) y te la pone al entrar. **Quitar skin** te regresa a la del modo de juego.
- Escoge uno y dale a **Usar y compartir**. El mod detecta solo de qué addon del Workshop viene.
- El server lo valida y se lo manda a todos. Cada cliente lo descarga del Workshop y lo monta.
- La skin se **fuerza** por encima de la del gamemode (TTT, etc.) y se mantiene al respawnear y funciona en cualquier gamemode (TTT incluido).

Solo el host necesita el addon. Los clientes reciben el Lua al conectarse.

## Instalación (dev)
`garrysmod/addons/skinshare` es un symlink a este repo. Los cambios en el Lua se recargan en caliente.

## Pantalla de carga
Se configura en `lua/autorun/server/loadingurl.lua`: cambia la URL ahí.

## Presets por gamemode (sin código)
Menú principal → **Addons** → activa solo los que quieras → **Presets → Save** (p. ej. `TTT`, `Sandbox`).
En un listen server los clientes descargan los addons que tiene activos el host, así que cambiar el preset limita lo que se les envía.

## Limitaciones
- En los addons de los clientes, los playermodels se detectan leyendo el `.mdl` (que incluya `m_anm`/`f_anm`/`z_anm`), porque su Lua no se ejecuta en un server ajeno. La primera vez que se abre el menú puede tardar un poco.
- Solo aparecen los modelos que el addon registra como playermodel (`player_manager.AddValidModel`), igual que en el selector de Sandbox.
- El addon de la skin tiene que ser público en el Workshop (se descarga por ID).
- Si un jugador no estaba a la vista cuando se montó la skin, puede verse como ERROR hasta su próximo respawn.

## Versiones
Se usan tags de git con semver (`v0.1.0`). Los cambios están en `CHANGELOG.md`.

## Workshop
https://steamcommunity.com/sharedfiles/filedetails/?id=3816842120

Para publicar una actualización, desde `GarrysMod/bin` y con Steam abierto:
```sh
LD_LIBRARY_PATH=. ./gmad_linux create -folder ~/Documents/gmod-skinshare -out /tmp/skinshare.gma
LD_LIBRARY_PATH=. ./gmpublish_linux update -id 3816842120 -addon /tmp/skinshare.gma -changes "v0.x.0: ..."
```

Las capturas y la descripción de la página (`gmpublish` no las sube) se ponen con la API de Steamworks, con Steam abierto:
```sh
SteamAppId=4000 python3 workshop/previews.py ~/.local/share/Steam/steamrt64/libsteam_api.so 4000 3816842120 workshop/screenshot*.jpg
SteamAppId=4000 python3 workshop/previews.py ~/.local/share/Steam/steamrt64/libsteam_api.so 4000 3816842120 --desc workshop/description.txt
```
Ojo: agrega, no reemplaza. Las viejas se borran desde la página del item.
