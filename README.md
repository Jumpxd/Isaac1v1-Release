# Isaac 1v1

Pachetul public pentru instalarea și rularea Isaac 1v1 pe Windows.

Companion-ul folosește backend-ul Production:

`https://isaac1v1-production.up.railway.app`

## Cerințe

- Windows 10 sau Windows 11, 64-bit
- Steam pornit și autentificat
- The Binding of Isaac: Repentance+
- REPENTOGON `v1.1.2e` sau mai nou din familia `v1.1.2`
- Isaac build `v1.9.7.12.J273`

## Varianta 1 — Setup automat (recomandat)

Descarcă și pornește [Isaac1v1Setup.exe](./Isaac1v1Setup.exe).

Setup-ul:

1. detectează instalarea Steam a jocului;
2. verifică REPENTOGON și versiunea Isaac;
3. instalează sau actualizează modul `isaac-1v1`;
4. instalează `zhlIsaac1v1IPC.dll` în runtime-ul REPENTOGON;
5. instalează Companion-ul și creează shortcut-ul.

Închide Isaac și REPENTOGON Launcher înainte de instalare.

## Varianta 2 — Instalare manuală

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
- `NATIVE_COMPONENT_HASH_MISMATCH`: DLL-ul instalat nu corespunde versiunii din installer.

După corectarea fișierelor, apasă `REFRESH` în Companion.

## Verificarea fișierelor

Hash-urile SHA-256 sunt publicate în [SHA256SUMS.txt](./SHA256SUMS.txt).

## Notă de securitate

Executabilele nu sunt încă semnate digital. Windows SmartScreen poate afișa un avertisment. Descarcă fișierele numai din acest repository și verifică hash-urile SHA-256.

Acest repository conține doar componentele necesare rulării. Backend-ul, configurațiile interne și funcțiile DEV/test nu sunt incluse.
