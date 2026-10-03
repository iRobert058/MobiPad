# Requirements — mobiele gamecontroller-app

## 1. Doel

De app maakt van een smartphone een draadloze gamecontroller voor een computer. De telefoon maakt verbinding met een computer waarop een desktop companion-app draait. De touch-input van de telefoon wordt realtime doorgestuurd en door de desktop-app beschikbaar gemaakt als gamecontroller-input voor een game.

**Basisflow:**

`Telefoon → Wi-Fi / Bluetooth → Desktop companion-app → Virtuele controller → Game`

De eerste versie richt zich op een iPhone als controller en een Mac als computer. Android en andere desktopplatformen kunnen later volgen.

## 2. Functionele requirements

### FR-01 — Verbinding maken

De gebruiker moet een telefoon met een beschikbare computer kunnen verbinden.

- De mobiele app detecteert beschikbare computers op hetzelfde lokale netwerk.
- De gebruiker kan een computer selecteren.
- De app brengt de verbinding tot stand en toont duidelijke bevestiging.

**Prioriteit:** Must-have

### FR-02 — Verbinding verbreken

De gebruiker moet de actieve verbinding handmatig kunnen verbreken.

**Prioriteit:** Must-have

### FR-03 — Virtuele controller-layout

De mobiele app toont minimaal de volgende bedieningselementen:

- Linker joystick
- Rechter joystick
- D-pad
- A-, B-, X- en Y-knoppen
- Start/Menu-knop
- Select/View-knop

**Prioriteit:** Must-have

### FR-04 — Touch-input

De gebruiker moet de controller via het touchscreen kunnen bedienen.

- Knoppen registreren indrukken en loslaten.
- Joysticks ondersteunen analoge beweging.
- De app ondersteunt gelijktijdige aanrakingen, zodat bijvoorbeeld een joystick en knop tegelijk gebruikt kunnen worden.
- Input blijft actief zolang een knop of stick wordt vastgehouden.

**Prioriteit:** Must-have

### FR-05 — Haptische feedback

De app kan haptische feedback geven bij een knopdruk of andere relevante interactie.

**Prioriteit:** Should-have

### FR-06 — Input realtime doorsturen

Alle controller-input wordt realtime naar de desktop companion-app gestuurd, waaronder:

- Knop indrukken en loslaten
- Joystickbewegingen
- D-padbewegingen
- Triggerwaarden

**Prioriteit:** Must-have

### FR-07 — Virtuele controller op desktop

De desktop companion-app vertaalt ontvangen input naar een virtuele gamecontroller die games kunnen gebruiken.

```text
Telefoon: A-knop
        ↓
Desktop companion-app
        ↓
Virtuele gamecontroller
        ↓
Game
```

**Prioriteit:** Must-have

### FR-08 — Controller testen

De desktop-app biedt een testscherm waarop de gebruiker live kan zien of input correct wordt ontvangen, bijvoorbeeld actieve knoppen en stickposities.

**Prioriteit:** Should-have

### FR-09 — Automatisch opnieuw verbinden

Wanneer een tijdelijke netwerkonderbreking optreedt, probeert de app automatisch opnieuw te verbinden.

**Prioriteit:** Should-have

### FR-10 — Meerdere controllers

De desktop-app kan meerdere smartphones tegelijk als afzonderlijke controllers ondersteunen.

**Prioriteit:** Could-have

## 3. Connection requirements

### CR-01 — Lokaal netwerk

Wi-Fi is de primaire verbindingsmethode. Telefoon en computer moeten zonder internetverbinding kunnen communiceren wanneer zij zich op hetzelfde lokale netwerk bevinden.

**Prioriteit:** Must-have

### CR-02 — Automatische ontdekking

De desktop-app maakt zichzelf bekend op het lokale netwerk, zodat de mobiele app hem kan vinden. Geschikte opties zijn Bonjour/mDNS of UDP-discovery.

**Prioriteit:** Must-have

### CR-03 — Pairing

De gebruiker kan telefoon en computer veilig koppelen, bijvoorbeeld door een code op de telefoon in te voeren die de desktop-app toont.

**Prioriteit:** Should-have

### CR-04 — Lage latency

Controller-input moet met zo weinig mogelijk vertraging worden verzonden en verwerkt. Richtwaarde binnen een lokaal netwerk: **minder dan 20–30 ms van input tot desktop**.

**Prioriteit:** Must-have

## 4. Desktop companion app

### DR-01 — macOS-ondersteuning

De eerste versie ondersteunt macOS.

**Prioriteit:** Must-have

### DR-02 — Werken op de achtergrond

De companion-app kan op de achtergrond blijven draaien terwijl de gebruiker een game speelt.

**Prioriteit:** Must-have

### DR-03 — Verbindingsstatus

De gebruiker kan de verbindingsstatus, verbonden controller en indien beschikbaar de latency zien.

```text
● Verbonden
Controller: Sam's iPhone
Latency: 8 ms
```

**Prioriteit:** Must-have

### DR-04 — Virtuele controller aanbieden

De desktop-app biedt een virtuele controller aan het besturingssysteem aan. Voor macOS moet onderzocht worden welke virtual HID/gamepad-oplossing hiervoor geschikt is.

**Prioriteit:** Must-have

## 5. UX requirements

### UX-01 — Snelle installatie en setup

De gebruiker gaat in zo weinig mogelijk stappen van installatie naar een werkende controller.

```text
1. Open de mobiele app
2. Open de desktop-app
3. Selecteer de computer
4. Pair de apparaten
5. Speel
```

**Prioriteit:** Must-have

### UX-02 — Landscape-weergave

De controller wordt primair in landscape weergegeven, met bedieningselementen die logisch met beide duimen bereikbaar zijn.

**Prioriteit:** Must-have

### UX-03 — Aanpasbare layout

De gebruiker kan knoppen verplaatsen en eventueel de grootte ervan aanpassen.

**Prioriteit:** Could-have

### UX-04 — Controller-presets

De app kan verschillende layouts aanbieden, bijvoorbeeld Xbox, PlayStation, Generic en Custom.

**Prioriteit:** Could-have

### UX-05 — Donkere modus

De app ondersteunt dark mode en volgt bij voorkeur de systeeminstelling.

**Prioriteit:** Should-have

## 6. Non-functional requirements

### NFR-01 — Performance

De oplossing verwerkt minimaal 60 input-updates per seconde zonder merkbare haperingen.

**Prioriteit:** Must-have

### NFR-02 — Latency

De verwerking van input introduceert zo min mogelijk aanvullende vertraging en voldoet aan de richtwaarde uit CR-04.

**Prioriteit:** Must-have

### NFR-03 — Stabiliteit

Een tijdelijke netwerkonderbreking of foutieve input mag de mobiele of desktop-app niet laten crashen.

**Prioriteit:** Must-have

### NFR-04 — Batterijverbruik

De mobiele app beperkt batterijverbruik tijdens normaal gebruik, zonder de speelervaring merkbaar te schaden.

**Prioriteit:** Should-have

### NFR-05 — Privacy

Controller-input en communicatie blijven lokaal. De basisfunctionaliteit vereist geen gebruikersaccount of cloudserver.

**Prioriteit:** Must-have

### NFR-06 — Beveiliging

De communicatie tussen telefoon en computer is geauthenticeerd en bij voorkeur versleuteld.

**Prioriteit:** Must-have

## 7. MVP

De MVP bewijst de kernbelofte: een iPhone verbinden met een Mac en een game volledig besturen met de telefoon.

### Mobiele app

- [ ] Verbinden met de desktop-app
- [ ] Controller-layout tonen
- [ ] D-pad ondersteunen
- [ ] A/B/X/Y-knoppen ondersteunen
- [ ] Twee joysticks ondersteunen
- [ ] Start/Menu-knop ondersteunen
- [ ] Touch-input verwerken
- [ ] Input via het lokale netwerk versturen
- [ ] Landscape-weergave
- [ ] Verbindingsstatus tonen

### macOS companion-app

- [ ] Companion-app aanbieden
- [ ] Computer via lokaal netwerk vindbaar maken
- [ ] Pairing ondersteunen
- [ ] Input ontvangen
- [ ] Virtuele controller creëren
- [ ] Virtuele controller beschikbaar maken voor games
- [ ] Verbindingsstatus tonen
- [ ] Opnieuw verbinden na een tijdelijke onderbreking

### Eerste acceptatiecriterium

> Ik open de app op mijn iPhone, verbind met mijn Mac, open een game en kan die volledig besturen met mijn telefoon.

Na de MVP zijn aanpasbare layouts, meerdere controllers, haptische feedback, controller-presets en Android logische vervolgstappen.

## 8. Mogelijke architectuur

```text
             ┌─────────────────┐
             │    iPhone-app   │
             │                 │
             │ Touch Controls  │
             │       ↓         │
             │  Input Manager  │
             └────────┬────────┘
                      │
                 Wi-Fi / LAN
                      │
                      ↓
             ┌─────────────────┐
             │    macOS-app    │
             │                 │
             │ Network Manager │
             │       ↓         │
             │  Input Manager  │
             │       ↓         │
             │   Virtual HID   │
             └────────┬────────┘
                      │
                      ↓
                   🎮 Game
```

De belangrijkste technische verkenning aan het begin is hoe macOS een virtuele Xbox/XInput-achtige controller kan aanbieden. Dat is waarschijnlijk het lastigste onderdeel; de mobiele interface en lokale netwerkcommunicatie zijn relatief rechttoe rechtaan.
