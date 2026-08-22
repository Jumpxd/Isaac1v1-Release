# Isaac 1v1 v0.2.0-alpha.3

Isaac 1v1 is an experimental competitive mod for **The Binding of Isaac:
Repentance+**. Matchmaking and match synchronization use Steam lobbies and
peer-to-peer messages. Both players receive the same character, seed, and target
destination before the run starts.

This is an alpha release. It has passed automated protocol, handshake, gameplay
parity, and native core tests, but the published package has not been live-tested
in two running Isaac instances by the release automation. Expect rough edges and
report reproducible issues with the standard Isaac or REPENTOGON log attached.


## Requirements

- Windows and The Binding of Isaac: Repentance+ 1.9.7.12
- REPENTOGON v1.1.2e or newer
- Steam running online on both computers
- The same Isaac 1v1 release installed by both players

## Install

1. Close Isaac and the REPENTOGON launcher.
2. Download and extract `Isaac1v1-v0.2.0-alpha.3.zip`.
3. Copy `mods\isaac-1v1-p2p` into Isaac's `mods` directory.
4. Copy `Repentogon\zhlIsaac1v1SteamP2P.dll` into Isaac's `Repentogon` directory.
5. Disable any older Isaac 1v1 mod so only this release is active.
6. Start Isaac through REPENTOGON and enable **Isaac 1v1** in the Mods menu.

The final layout should contain:

```text
<Isaac>\mods\isaac-1v1-p2p\main.lua
<Isaac>\Repentogon\zhlIsaac1v1SteamP2P.dll
```

## Play

1. Both players start Steam online and launch Isaac through REPENTOGON.
2. Both players open the Isaac main menu and press **F8**.
3. Both choose **Find Match**.
4. Wait for the opponent and synchronized match settings.
5. The run starts automatically after both peers commit the same configuration.

The F8 interface shows the opponent, matchmaking state, character, seed, target,
live score, and final result. Competitive save protection, console protection,
death/revive handling, wrong-destination detection, boss targets, and the target
HUD are included.

## Troubleshooting

- Confirm both players use this exact version and are visible online in Steam.
- Confirm REPENTOGON loads `zhlIsaac1v1SteamP2P.dll` and no older Isaac 1v1 mod
  is enabled.
- Check the standard Isaac and REPENTOGON logs for entries prefixed
  `[Isaac1v1P2P]`.
- The extension does not create `isaac1v1-steam-p2p.log` or any other dedicated
  log file.

## Verify downloads

Compare the SHA-256 values with `SHA256SUMS.txt`. Release provenance and runtime
requirements are recorded in `release-manifest.json`.

## Uninstall

With Isaac closed, remove only `mods\isaac-1v1-p2p` and
`Repentogon\zhlIsaac1v1SteamP2P.dll` from the Isaac installation.
