## Főbb funkciók

- növényültetés, növekedés, betakarítás és újranövés
- talajtípusok és talajállapotok kezelése
- nedvesség, tápanyag, pH, kártevők és betegségek
- időjárás és napszak / időrendszer
- játékos-, növény-, terület- és felszerelésfejlődés
- pénz, bolt és inventory
- build mode különböző tile-okkal és objektumokkal
- Seed Storage
- Repair Anvil
- Field Sprinkler
- Fertilizer Injector
- Soil Neutralizer
- Plant Protection Station
- automation gépek fejlesztése és beállítása
- Random Event rendszer
- 3 külön mentési hely
- Save / Load és autosave
- Pause Menu
- minimap
- Plant Inspector
- 1× / 3× / 6× játéksebesség
- férfi és női karakterválasztás

## Irányítás

### Alap irányítás

- **WASD vagy nyilak** – játékos mozgatása
- **1–9** – tool kiválasztása
- **ALT nyomva tartása** – tool célzási mód és célterület megjelenítése
- **ALT + E** – a kiválasztott tool használata a kijelölt célon
- **Egérgörgő** – a hotbarban lévő növények közötti váltás
- **E** – közeli interaktív objektum használata
- **I** – Inventory megnyitása / bezárása
- **P** – Shop megnyitása / bezárása
- **B** – Build Mode megnyitása / bezárása
- **ESC** – aktuális menü bezárása vagy Pause Menu megnyitása
- **ALT + egérrel rámutatás egy növényre** – Plant Inspector
- **ALT + kattintás az 1× / 3× / 6× gombra** – játéksebesség módosítása

### Toolok

A toolok a számbillentyűkkel vagy a Tool Bar gombjaival választhatók ki.

1. **Plant** – a hotbarban kiválasztott növény elültetése
2. **Water** – a talaj nedvességének növelése
3. **Fertilize** – a talaj tápanyagszintjének növelése
4. **Lime (+pH)** – a talaj pH-jának növelése
5. **Acid (-pH)** – a talaj pH-jának csökkentése
6. **Pesticide** – kártevők csökkentése
7. **Fungicide** – betegség / gombás fertőzés csökkentése
8. **Shovel** – növény eltávolítása
9. **Harvest** – érett növény betakarítása

A tool használatához az **ALT** billentyűt nyomva kell tartani, majd az **E** billentyűvel lehet végrehajtani a műveletet. A kijelölés mutatja, hogy melyik cellára vagy növényre fog hatni az adott tool.

A toolok többségének van durability értéke. Használat közben kopnak, és a Repair Anvil segítségével javíthatók. A teljesen eltört tool helyett újat kell vásárolni.

### Növényválasztás és Inventory

Az **I** billentyű nyitja meg az Inventory menüt.

- **egyszeri kattintás** – növény adatainak megtekintése
- **dupla bal kattintás** – növény hozzáadása a hotbarhoz vagy eltávolítása onnan
- **drag and drop** – inventory slotok átrendezése
- a növény az inventory és a hotbar között is mozgatható
- a hotbar egyik növényére kattintva az lesz az aktív ültethető növény
- játék közben az **egérgörgővel** lehet a hotbarban lévő növények között váltani

A Plant tool mindig az aktuálisan kiválasztott növényt próbálja elültetni, és csak akkor működik, ha van hozzá megfelelő seed az inventoryban.

### Build Mode

A **B** billentyűvel kapcsolható be és ki.

Build Mode közben:

- **bal egérgomb** – kiválasztott tile vagy objektum lerakása
- **jobb egérgomb** – játékos által lerakott elem eltávolítása
- **R** – forgatható elem elforgatása
- **egérgörgő** – kamera zoom
- **középső egérgomb + húzás** – kamera mozgatása
- **WASD vagy nyilak** – kamera mozgatása
- a képernyő széléhez vitt egér szintén mozgathatja a kamerát
- **B vagy ESC** – kilépés Build Mode-ból

Az építés Build Creditet használ. Az egyes tile-oknak és objektumoknak eltérő ára van. Az automation gépek csak a megfelelő játékosszint elérése után válnak elérhetővé.

### Interaktív objektumok

Ha a játékos elég közel kerül egy használható objektumhoz, egy **E** jel jelenik meg fölötte.

**E** használatával nyitható meg például:

- Seed Storage
- Repair Anvil
- Field Sprinkler
- Fertilizer Injector
- Soil Neutralizer
- Plant Protection Station

Az automation gépek konfigurációs ablaka **E** vagy **ESC** használatával bezárható.

### Seed Storage

A Seed Storage seedek tárolására használható.

- **E** – megnyitás
- **bal kattintás** – 1 darab seed mozgatása
- **SHIFT + bal kattintás** – a teljes elérhető stack mozgatása
- **E vagy ESC** – bezárás

A Storage tartalma mentésre kerül.

### Repair Anvil

A Repair Anvil a jelenleg kiválasztott tool javítására használható.

- menj az Anvil közelébe
- válaszd ki a javítani kívánt toolt
- nyomj **E**-t
- a megjelenő ablakban lehet jóváhagyni a javítást vagy szükség esetén a cserét

Egy javítás legfeljebb 25 durability pontot állít vissza. A teljesen eltört tool nem javítható, azt ki kell cserélni.

### Játéksebesség

A felső TIME panelen három sebesség választható:

- **1×** – normál sebesség
- **3×** – gyorsított idő
- **6×** – erősen gyorsított idő

A sebesség módosításához az **ALT** billentyűt nyomva kell tartani, és rá kell kattintani a kívánt sebességre. Ez csak a játékidőt és a szimulációt gyorsítja, a játékos mozgását nem.

## Automation gépek

A játékban több automata gép segíti a kert fenntartását:

- **Field Sprinkler** – a talaj nedvességét kezeli
- **Fertilizer Injector** – a talaj tápanyagszintjét kezeli
- **Soil Neutralizer** – a talaj pH-ját módosítja
- **Plant Protection Station** – a kártevők és betegségek ellen dolgozik

A gépek közös automation rendszerre épülnek. Mindegyik:

- fejleszthető
- külön hatótávolsággal rendelkezik
- ki- és bekapcsolható
- több működési időközzel használható
- csak akkor dolgozik, amikor szükség van rá
- saját beállításait Save / Load között is megtartja

A gépek közelében megjelenő **E** segítségével nyitható meg a konfigurációs ablak.

## Növények és talaj

A növények állapotát több környezeti érték befolyásolja:

- nedvesség
- tápanyag
- pH
- kártevők
- betegségek
- időjárás

A különböző növényeknek eltérő ideális értékeik vannak. Ha a körülmények hosszabb ideig rosszak, a növény health értéke csökken.

A **Plant Inspector** az **ALT** nyomva tartása és a növényre történő rámutatás közben mutatja a fontosabb állapotokat.

A betakarítás eredményét a növény health értéke is befolyásolja.

## Időjárás és idő

A játékban változó időjárás működik, például:

- Clear
- Cloudy
- Rain
- Heatwave
- Cold Snap / Snow

Az időjárás hatással lehet a talajra és a növényekre. Egy teljes játéknap normál, 1× sebességen körülbelül 3 valós perc.

## Random Event rendszer

A Random Event rendszer pozitív, negatív és döntést igénylő eseményeket tartalmaz.

Az események többek között hatással lehetnek:

- pénzre
- seedekre
- növényekre
- időjárásra
- piaci árakra
- automation gépekre
- talajállapotokra

Egyes eseményeknél a játékosnak választania kell a megjelenő lehetőségek közül.

## Fejlődés

A játékos XP-t és szinteket szerezhet. A fejlődés során új lehetőségek nyílnak meg, például automation gépek és Build Credit jutalmak.

Külön fejleszthetők:

- a játékos
- a növények
- a talajtípusok
- a felszerelések

## Shop

A **P** billentyűvel nyitható meg.

A Shopban többek között:

- seedek vásárolhatók
- termékek eladhatók
- fejlesztések vásárolhatók

A Shop megnyitásakor a játék szünetel, és a menü egérrel kezelhető.

## Mentés

A játék 3 külön Garden mentési helyet támogat.

A mentés többek között tárolja:

- játékos fejlődését
- inventory tartalmát
- hotbar beállítását
- pénzt és Build Creditet
- növényeket
- talajállapotokat
- lerakott build objektumokat
- Seed Storage tartalmát
- tool durability értékeket
- automation gépek állapotát és beállításait
- aktuális időjárást és időt

Autosave is működik játék közben.

A Pause Menu tartalmaz külön **SAVE** és **LOAD** lehetőséget is.

## Projekt indítása

A projekt **Godot 4.7.1** verzióval készült.

1. Nyisd meg a projekt mappáját Godotban.
2. Nyisd meg a `project.godot` fájlt.
3. Indítsd el a projektet a Godot editorból.

A játék a Main Menu képernyőről indul.

## Projekt felépítése

A fontosabb mappák:

```text
Assets/      grafikai és egyéb assetek
Scenes/      Godot scene fájlok
Scripts/     GDScript fájlok
```

A legtöbb nagyobb rendszer külön scriptben található, a közösen használt rendszerek pedig Autoloadként futnak.

## Tesztelés

A projekt tartalmaz automatikus regression teszteket is.

Ezek a fontosabb rendszerek alapvető működését ellenőrzik, például:

- Save / Load
- növényrendszer
- progression
- build rendszer
- automation gépek
- időjárás és idő
- inventory és economy
- tool durability
- fontos gameplay szabályok
