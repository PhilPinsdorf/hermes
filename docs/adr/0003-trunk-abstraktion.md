# 3. Der Weg nach draußen liegt hinter einer Abstraktion

Status: entschieden, umgesetzt in M5

## Worum es geht

Heute gehen Anrufe über die Fritz!Box hinaus. Deren Anschluss erlaubt aber
meist nur zwei gleichzeitige Gespräche — und ein vermitteltes Gespräch belegt
beide: eines vom Anrufer, eines zum Handy. Ein zweiter Anrufer hört in dieser
Zeit das Besetztzeichen des Providers, bevor Hermes den Anruf überhaupt sieht.
Mit einem SIP-Trunk (sipgate, easybell, Placetel) wären es vier bis acht
Kanäle.

## Entscheidung

Wie ein Anruf nach draußen geht, steckt hinter dem Behaviour
`Hermes.Telephony.Trunk` mit drei Funktionen: Endpunkt für eine Nummer,
angezeigte Rufnummer, Zahl der gleichzeitigen Gespräche. `Trunk.FritzBox` ist
die heutige Umsetzung.

## Warum

Ein Wechsel auf einen SIP-Trunk ist damit eine neue Umsetzung dieses
Behaviours plus Konfiguration in Asterisk — und sonst nichts. Die Anruflogik,
der Dienstplan und die Oberfläche bleiben unverändert.

Die Zahl der Kanäle ist zudem kein Detail des Anschlusses, sondern bestimmt
das Verhalten: Gleichzeitiges Klingeln mehrerer Handys braucht mehrere freie
Kanäle. Bei zwei Kanälen bleibt nach dem Anrufer genau einer übrig, deshalb
klingelt „gleichzeitig" dort automatisch nacheinander. Diese Regel steht an
einer Stelle (`Hermes.Calls.Strategy`) und rechnet gegen die Zahl aus dem
Trunk.

## Womit wir leben

Die Fritz!Box erzwingt die Rufnummer, die beim IP-Telefon eingestellt ist. Ein
pro Anruf unterschiedlicher Absender ist damit nicht möglich — was ohnehin
nicht gewollt ist: Alle Angerufenen speichern genau eine Nummer unter einem
Namen im Adressbuch.
