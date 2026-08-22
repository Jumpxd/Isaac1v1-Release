# Isaac 1v1

Competitive one-versus-one matchmaking for The Binding of Isaac: Repentance+.
The mod uses Steam lobbies and peer-to-peer messages through REPENTOGON and
`zhlIsaac1v1SteamP2P.dll`.

This is an experimental alpha. Both players need the same release, Repentance+,
REPENTOGON v1.1.2e or newer, and Steam running online. The optional production service receives
only completed-match statistics used by profiles and match history; matchmaking
and gameplay synchronization remain peer-to-peer.

Press F8 from the main menu, choose **Find Match**, and wait for the synchronized
match configuration. The match starts automatically after both peers commit the
same character, seed, and destination.

Before matchmaking and again immediately before the run starts, the native
component scans the complete Isaac `mods` directory and enforces the competitive
allowlist. This includes content-only and XML-only mods. The legacy `Isaac 1v1`
mod must be disabled while the P2P mod is active.

Final outcomes are produced only by the Steam lobby authority. Cancel and abandon
messages use bounded acknowledgements before the lobby is closed; reconnect is
not supported.

The native runtime starts inactive and is enabled only by this mod. Disabling or
unloading the mod closes any Isaac 1v1 lobby/session and restores vanilla save
and console behavior.
