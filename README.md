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

A madarak kis mértékben másképp esnek: a Lúd lebegőbb, a Kacsa kicsit, a Kakukk jobban zuhan (`bird_dg` a `game.asm`-ben).
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
| `src/data.inc` | **generált**: betűkészlet, madársprite-ok, csőminták, szövegek |
| `tools/gen_assets.py` | a `data.inc` generátora (`--preview kep.png` a sprite-okhoz) |
| `tools/ptp.py` | `.ptp` író/ellenőrző, WAV (a Primo skill másolata) |
| `tests/` | `run_tests.py` + `test_units.asm`: tábla-vezérelt egységtesztek Python-modell ellen, játékmenet-futtatás autopilottal |

Háttér (parallax): minden játék elején véletlenszerűen egy téma kerül a képernyőre: **város** (ablakos épületek,
házak lámpákkal), **erdő** (fenyősor, lombos fák) vagy **mező** (dombok, kerítés virágokkal). Egy téma két 8 soros
réteg (távoli és közeli) közvetlenül a föld fölött (a 160–175. pixelsorban). Minden réteg egy 256 pixel széles,
körbeforgó sáv a RAM-ban, amit helyben forgatunk egy pixellel balra (`bg_rot`), majd a képernyőre másolunk. Képkockánként
legfeljebb egy réteg lép: a közeli 4., a távoli 8. kockánként (¼ és ⅛ pixel/kocka).

A csövek a háttér fölött úsznak: a cső ablaka a sávban a háttérrel összefésülődik (`seg`/`merge5` a `gfx.asm`-ben), a
cső 24 pixeles lábnyomán kívül a háttér látszik, a madár törlése is visszaállítja a hátteret. A másolás (`bg_blit_skip`)
kihagyja a csövek ablakai alatti bájtokat: ha a háttér-másolás egy pillanatra felülírná a csövet, és közben a
képernyősugár éppen ott haladna el, a cső villogna.

A rés teteje 40, 44 … 92 (4-gyel osztható), a rés 60 magas, a föld 176-nál kezdődik, így a cső minden széle a 4 pixeles
színes cellák határára esik. A rés alja legfeljebb a 152. sor, a háttérsáv pedig a 160. sortól indul: a sáv sorai az
ablak oszlopaiban mindig csőből vannak.

Színes modellen a rétegek témánként külön színt kapnak (város: acélkék / barna, erdő: sötét / világoszöld, mező: zöld /
olíva). A színes RAM cellái 4×4 pixelesek, ezért a cső 24 pixeles lábnyoma alatti cellák fehér tintát (0-s
paletta-csoport) kapnak, a cső ablakának többi cellája visszakapja a rétege színét (`pipe_colour` a `lib.asm`-ben);
a sáv fölött (ahol nincs háttér) nincs színezés. A színes menüben minden szövegsor betűinek felső 4 pixelsora fehér, az
alsó 4 sárga (`menu_colour`, 5-ös paletta-csoport).

Játékmenet: 256×192 pixel, a felső 16 sor a HUD, alul 16 sor föld. A csövek 2 pixelt lépnek játékkockánként,
25 játékkocka/s (két képváltásonként egy). A rajzolás lépésenként csak a mozgó csöveket és a madarat frissíti.

## Mit teszteltünk, és mit nem

Lefutott (`make test`):
- `row_addr` mind a 192 sorra, a véletlen-generátor periódusa (65535), `gap_map` tartománya, `to_dec3` 0..1100;
- `draw_pipe` 322 esetre (x = −34 … 265, szélső rések) pixelpontosan egy független Python-modell ellen,
  beleértve a képernyő széleinél való vágást és azt, hogy a rutin a saját ablakán kívül nem ír;
- sprite-, szöveg- és számrajzolás (vágással), `bird_step`, `collide_all`, `score_check`, `pipes_step`, `pipes_reset`;
- teljes játékhurok autopilottal mind a 4 madárral, 5 különböző véletlen magra és 4000 kockán át; tétlen játékos
  esetén game over; „új rekord” ág; színes építés (paletta, színes RAM);
- mutációs ellenőrzés: szándékosan elrontott csőszélesség, ütközési határ és pontszám-jelző mellett a tesztek elbuknak.

**Nem futott** Primón vagy Primo-emulátoron. A ROM-ot, a valódi videóhardvert, a billentyűzetet, a hangot és a
szalagbetöltőt a fejlesztői környezet nem látja. Első indításkor érdemes ellenőrizni: betöltés `.wav`-ból,
mindkét modellen indul-e, a billentyűk (SPACE, ←, →, M), a hang és a villogásmentes rajzolás.
Bizonytalan (hardver-dokumentáció alapján, nem mért) pontok:
- a színes modell palettája és a színes RAM kiosztása a `zsugabubus` projekt `hw_color.c` fájlján alapul;
- a hangot a `$403B` árnyékregiszter értékéből a D4 bit billegtetésével adjuk (az NMI nincs letiltva, ezért kattanhat);
- a 25 kocka/s feltételezi, hogy egy játékkocka (átlag ~66 000 T-state az emulátorban) belefér két képváltásba
  (2,5 MHz-es órajelnél 100 000 T-state); ha a gép lassabb, a játék egyszerűen lassabb lesz, nem áll le.

A szintek indulósebessége 3 / 4 / 5 képpont képkockánként (`speed_tab`), és játék közben **egyre gyorsul**: minden 4. pont után
1 képponttal gyorsabban jönnek a csövek, legfeljebb 8-ig (`SPEED_EVERY`, `SPEED_MAX` a `game.inc`-ben).
