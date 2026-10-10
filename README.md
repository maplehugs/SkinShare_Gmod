# SkinShare (Garry's Mod)

Un jugador elige uno de **sus** addons de modelos y todos los demás lo descargan y lo montan en plena partida, sin reiniciar.

## Uso
- En el chat escribe `!skin` (o `skinshare` en la consola).
- Se abre un selector con preview en 3D girando a la izquierda y todos tus playermodels como iconos a la derecha, con buscador.
- Pestañas **Bodygroups** (skin y partes intercambiables del modelo) y **Color** (color del jugador), y todo se ve en el preview.
- Escoge uno y dale a **Usar y compartir**. El mod detecta solo de qué addon del Workshop viene.
- El server lo valida y se lo manda a todos. Cada cliente lo descarga del Workshop y lo monta.
- La skin se **fuerza** por encima de la del gamemode (TTT, etc.) y se mantiene al respawnear y funciona en cualquier gamemode (TTT incluido).

Solo el host necesita el addon. Los clientes reciben el Lua al conectarse.

## Instalación (dev)
`garrysmod/addons/skinshare` es un symlink a este repo. Los cambios en el Lua se recargan en caliente.

## Presets por gamemode (sin código)
Menú principal → **Addons** → activa solo los que quieras → **Presets → Save** (p. ej. `TTT`, `Sandbox`).
En un listen server los clientes descargan los addons que tiene activos el host, así que cambiar el preset limita lo que se les envía.

## Limitaciones
- Solo aparecen los modelos que el addon registra como playermodel (`player_manager.AddValidModel`), igual que en el selector de Sandbox.
- El addon de la skin tiene que ser público en el Workshop (se descarga por ID).
- Si un jugador no estaba a la vista cuando se montó la skin, puede verse como ERROR hasta su próximo respawn.

## Versiones
Se usan tags de git con semver (`v0.1.0`). Los cambios están en `CHANGELOG.md`.
