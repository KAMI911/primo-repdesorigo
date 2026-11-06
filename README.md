# Repdeső Rigó

Flappy Bird a Primóra (Z80 assembly). Egy kazettafájl fut a monokróm A/B és a színes C/Pro gépen is:
indításkor a program felismeri a modellt (a ROM első bájtja `$C3` ⇒ színes).

## Madarak

A menüben a ←/→ billentyűkkel választható, hogy kivel repül a játékos:

| | madár |
|---|---|
| 1 | **Repdeső Rigó** |
| 2 | **Lebegő Lúd** |
| 3 | **Kacsázó Kacsa** |
| 4 | **Kapkodó Kakukk** |

A madarak kis mértékben másképp esnek: a Lúd lebegőbb, a Kacsa kicsit, a Kakukk **sokkal** jobban zuhan: kb. kétszeres gravitáció és 2 képponttal nagyobb végsebesség (`bird_dg`, `bird_dv` a `game.asm`-ben).
A gyorsabb szinteken a gravitáció és a végsebesség is nagyobb (`grav_tab`, `vmax_tab`).

## Irányítás

| billentyű | hatás |
|---|---|
| SPACE / ↑ / RETURN | szárnycsapás (a menüben: indítás) |
| ← / → | madár választása a menüben |
| M | játék után vissza a menübe |
| C | menüben, csak színes gépen: színes ↔ monokróm mód (a színes vezérlés kikapcsol, mint az A/B gépen) |

Pontot kapsz minden cső mögött, amin átrepülsz; a REKORD a gép kikapcsolásáig megmarad.
A betűkészlet csupa nagybetűs, az ékezetek (Á É Í Ó Ö Ő Ú Ü Ű) a betűk fölötti pixelsorban vannak.

## Fordítás és teszt

Szükséges: `make`, `python3` és vagy `z88dk` vagy `docker` (a Makefile a digesttel rögzített `z88dk/z88dk` image-et használja).

```
make test     # eszköz-tesztek + egységtesztek + játékmenet-tesztek emulált Z80-on (z88dk-ticks)
make          # build/repdesorigo.ptp (+ -bw, -col változat) és .wav, ellenőrzéssel
make shots    # képernyőképek a build/shots/ mappába (Pillow kell hozzá)
```

A betöltendő fájl: `build/repdesorigo.ptp` (vagy a `.wav`), gépi kódú program, indítás `$4400`-on.
A `-bw` és `-col` változat ugyanaz a kód a modellfelismerés nélkül; a legtöbb esetben az egyetlen `repdesorigo.ptp` elég.

## Felépítés

| fájl | szerep |
|---|---|
| `src/main.asm` | indulás, menü, játékmenet, game over |
| `src/game.asm` | tiszta logika: véletlen, csövek, fizika, ütközés, pontszám |
| `src/gfx.asm` | rajzolás: szöveg, sprite, csövek (8 pixeles eltolás-táblákkal) |
| `src/lib.asm` | modellfelismerés, memfill, vsync, billentyűk, hang, színes palettabeállítás |
| `src/data.inc` | betűkészlet, madársprite-ok, csőminták, szövegek |
| `tools/gen_assets.py` | a `data.inc` generátora (`--preview kep.png` a sprite-okhoz) |
| `tools/ptp.py` | `.ptp` író/ellenőrző, WAV |
| `tests/` | `run_tests.py` + `test_units.asm`: tábla-vezérelt egységtesztek Python-modell, játékmenet-futtatás autopilottal |

Háttér (parallax): minden játék elején véletlenszerűen egy téma kerül a képernyőre: **város** (ablakos épületek,
házak lámpákkal), **erdő** (fenyősor, lombos fák) vagy **mező** (dombok, kerítés virágokkal). Egy téma két 8 soros
réteg (távoli és közeli) közvetlenül a föld fölött (a 160–175. pixelsorban). Minden réteg egy 256 pixel széles,
körbeforgó sáv a RAM-ban, amit helyben forgatunk egy pixellel balra (`bg_rot`), majd a képernyőre másolunk. Képkockánként
legfeljebb egy réteg lép: a közeli 4., a távoli 8. kockánként (¼ és ⅛ pixel/kocka).

A csövek a háttér fölött úsznak: a cső ablaka a sávban a háttérrel összefésülődik (`seg`/`merge6` a `gfx.asm`-ben), a
cső 24 pixeles nyomán kívül a háttér látszik, a madár törlése is visszaállítja a hátteret. A másolás (`bg_blit_skip`)
kihagyja a csövek ablakai alatti bájtokat: ha a háttér-másolás egy pillanatra felülírná a csövet, és közben a
képernyősugár éppen ott haladna el, a cső villogna.
A képkocka sorrendje: előbb a csövek és a madár rajzolódik (közvetlenül a vsync után, a sugár előtt), és csak utána léptetjük a
háttérréteget (`bg_step`), hogy a ritkán futó, nehéz háttérléptetés ne csússzon a sugár mögé és ne villogtassa az alsó csövet.
A cső ablaka 6 bájt széles (24 px cső + 7 px eltolás + 2 üres záró bájt), így akár 16 px/kocka lépést is letöröl.

A rés teteje 40, 44 … 92 (4-gyel osztható), a rés 60 magas, a föld 176-nál kezdődik, így a cső minden széle a 4 pixeles
színes cellák határára esik. A rés alja legfeljebb a 152. sor, a háttérsáv pedig a 160. sortól indul: a sáv sorai az
ablak oszlopaiban mindig csőből vannak.

Színes modellen a rétegek témánként külön színt kapnak (város: acélkék / barna, erdő: sötét / világoszöld, mező: zöld /
olíva). A színes RAM cellái 4×4 pixelesek, ezért a cső 24 pixeles lábnyoma alatti cellák fehér tintát (0-s
paletta-csoport) kapnak, a cső ablakának többi cellája visszakapja a rétege színét (`pipe_colour` a `lib.asm`-ben);
a sáv fölött (ahol nincs háttér) nincs színezés. A színes menüben minden szövegsor betűinek felső 4 pixelsora fehér, az
alsó 4 sárga (`menu_colour`, 5-ös paletta-csoport).

Játékmenet: 256×192 pixel, a felső 16 sor a HUD, alul 16 sor föld. A csövek 3–16 pixelt lépnek játékkockánként (a cső 6 bájtos ablaka törli a nyomát),
25 játékkocka/s (két képváltásonként egy). A rajzolás lépésenként csak a mozgó csöveket és a madarat frissíti.
