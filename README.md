ISAAC 1v1 Alpha v0.1.1-alpha.1


## Cum funcționează Isaac 1v1


1. Ambii jucători pornesc Steam, Companion-ul și Isaac prin REPENTOGON.
2. Din meniul principal Isaac, apasă `F8` pentru a deschide meniul `ISAAC 1V1`.
3. Intră în matchmaking și așteaptă găsirea unui adversar.
4. După `MATCH FOUND`, ambii jucători trebuie să confirme că sunt `READY`.
5. Run-ul competitiv pornește automat pentru ambii. Meniul afișează adversarul, personajul, seed-ul și target boss-ul meciului.
6. Scorurile sunt trimise live prin Companion și sunt afișate în interfața 1v1.

### Cum se decide câștigătorul

- dacă un jucător moare definitiv, pierde imediat, indiferent de scor;
- dacă un jucător omoară target boss-ul corect, run-ul se finalizează și se compară scorul vanilla;
- dacă un jucător omoară un destination boss incompatibil, pierde cu `WRONG_DESTINATION`;
- la scor egal, rezultatul este `DRAW`;
- dacă ieși din run, închizi Isaac sau pierzi conexiunea după începerea meciului, meciul este abandonat și adversarul câștigă.

### Target boss

- serverul alege un singur target random din destinațiile deblocate de ambii jucători;
- ambii primesc exact același target, seed și personaj;
- HUD-ul din joc și Companion-ul afișează target-ul negociat;
- alegerea rutei rămâne responsabilitatea jucătorului;
- pentru Mother sunt oferite resursele inițiale minime, iar pentru Mega Satan sunt oferite ambele Key Pieces.


## Moduri permise în meciurile competitive

Poți activa orice combinație a modurilor de mai jos. Modul `isaac-1v1` și REPENTOGON sunt permise automat. Orice alt mod trebuie dezactivat înainte de matchmaking, altfel meniul va afișa `MOD NOT ALLOWED`.

- Dynamic Minisaacs Forever! — Workshop `3388446591`
- Very Haunted Chests — Workshop `2487822714`
- cry — Workshop `2652244684`
- Unique MEGAIsaacs — Workshop `2697721144`
- Unique C-Section Fetuses! — Workshop `2821675000`
- Alternate Hairstyles! — Workshop `3402926130`
- unintrusive pause menu — Workshop `2769063897`
- Fireworks for Good Items — Workshop `3397128781`
- [AB+|Rep(+)] External Item Descriptions — Workshop `836319872`
- TimeMachine[Repentance] — Workshop `2617557401`
- Luckier Pennies — Workshop `2487805547`
- Not Mad, Just Disappointed for Quality 0 Items — Workshop `2612456876`
- Better Explosions — Workshop `2879232973`
- Improved Chargebars [REP+] — Workshop `2851861015`
- Antibirth music++ [OBSOLETE] — Workshop `1547034524`
- Custom Mr Dollys — Workshop `2489635144`
- Garry's Mod Death Animation — Workshop `2788453409`
- Animated Items — Workshop `2570913695`
- Regret Pedestals — Workshop `2766379837`
- Better Character Menu — Workshop `835236871`
- [REP(+)] Enhanced Boss Bars — Workshop `2635267643`
- Planetarium Chance [REP+] — Workshop `2489006943`
- Specialist Dance for Good Items — Workshop `2575911103`

## Instalare manuală

Este necesar The Binding of Isaac: Repentance+ prin Steam și REPENTOGON compatibil.
Poți descărca toate componentele manuale într-un singur pachet:

[Isaac1v1-Manual.zip](./Isaac1v1-Manual.zip)

Sau poți folosi separat [Isaac1v1Companion.exe](./Isaac1v1Companion.exe) și folderul [`manual`](./manual).

### 1. Companion

Păstrează `Isaac1v1Companion.exe` în orice folder dorești. Nu îl copia în folderul jocului.

### 2. DLL REPENTOGON

Copiază:

`manual\Repentogon\zhlIsaac1v1IPC.dll`

în:

`<Isaac>\Repentogon\zhlIsaac1v1IPC.dll`

Exemplu pentru instalarea Steam implicită:

`C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth\Repentogon\zhlIsaac1v1IPC.dll`

În același folder trebuie să existe deja fișierele REPENTOGON `isaac-ng.exe`, `libzhl.dll`, `zhlREPENTOGON.dll` și `Lua5.3.3r.dll`.

### 3. Modul Isaac 1v1

Copiază folderul:

`manual\mods\isaac-1v1`

în:

`<Isaac>\mods\isaac-1v1`

Fișierul trebuie să ajungă exact la:

`<Isaac>\mods\isaac-1v1\metadata.xml`

Nu crea accidental un folder dublu de forma `isaac-1v1\isaac-1v1`.

## Pornire

1. pornește Steam;
2. pornește `Isaac1v1Companion.exe`;
3. pornește Isaac prin REPENTOGON;
4. verifică în Companion că statusul nu mai este `INSTALLATION INCOMPLETE`;
5. folosește meniul Isaac 1v1 din joc pentru matchmaking.

## `INSTALLATION INCOMPLETE`

Dacă apare acest mesaj, verifică:

- `REPENTOGON_NOT_FOUND`: folderul REPENTOGON sau versiunea jocului nu a fost detectată;
- `ISAAC1V1_MOD_MISSING`: lipsește `<Isaac>\mods\isaac-1v1\metadata.xml`;
- `NATIVE_COMPONENT_MISSING`: lipsește `<Isaac>\Repentogon\zhlIsaac1v1IPC.dll`;
- `NATIVE_COMPONENT_HASH_MISMATCH`: DLL-ul instalat nu corespunde versiunii publicate.

După corectarea fișierelor, apasă `REFRESH` în Companion.

## Verificarea fișierelor

Hash-urile SHA-256 sunt publicate în [SHA256SUMS.txt](./SHA256SUMS.txt).
Această versiune a fost construită din source commit `fd29db7d02e4d893dba9d06b2481495017f8a647`.

## Statistici

Profilurile și istoricul meciurilor sunt disponibile la [isaac1v1.online](https://isaac1v1.online).

## Notă de securitate

Executabilele nu sunt încă semnate digital. Windows SmartScreen poate afișa un avertisment. Descarcă fișierele numai din acest repository și verifică hash-urile SHA-256.

Acest repository conține doar componentele necesare rulării. Backend-ul, configurațiile interne și funcțiile DEV/test nu sunt incluse.
