# SkinShare (Garry's Mod)

Un jugador elige uno de **sus** addons de modelos y todos los demás lo descargan y lo montan en plena partida, sin reiniciar.

## Uso
- En el chat escribe `!skin` (o `skinshare` en la consola).
- Elige el addon y luego el `.mdl` del modelo.
- El server lo valida y se lo manda a todos. Cada cliente lo descarga del Workshop y lo monta.
- La skin se mantiene al respawnear y funciona en cualquier gamemode (TTT incluido).

Solo el host necesita el addon. Los clientes reciben el Lua al conectarse.

## Instalación (dev)
`garrysmod/addons/skinshare` es un symlink a este repo. Los cambios en el Lua se recargan en caliente.

## Presets por gamemode (sin código)
Menú principal → **Addons** → activa solo los que quieras → **Presets → Save** (p. ej. `TTT`, `Sandbox`).
En un listen server los clientes descargan los addons que tiene activos el host, así que cambiar el preset limita lo que se les envía.

## Limitaciones
- El addon de la skin tiene que ser público en el Workshop (se descarga por ID).
- Si un jugador no estaba a la vista cuando se montó la skin, puede verse como ERROR hasta su próximo respawn.

## Versiones
Se usan tags de git con semver (`v0.1.0`). Los cambios están en `CHANGELOG.md`.
