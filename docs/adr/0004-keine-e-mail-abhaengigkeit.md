# 4. Hermes setzt keinen Mailserver voraus

Status: entschieden, umgesetzt in M1

## Worum es geht

Der Standard von `phx.gen.auth` in Phoenix 1.8 meldet Benutzer über Magic
Links an: Registrierung, Anmeldung und E-Mail-Wechsel laufen über Links, die
per Mail verschickt werden. Das setzt bei jeder Installation einen
funktionierenden Mailversand voraus.

## Entscheidung

Es gibt keine E-Mail-Abläufe. Anmeldung mit E-Mail und Passwort, keine
öffentliche Registrierung, Benutzer werden von anderen Benutzern angelegt. Ein
vergessenes Passwort setzt der Betreiber auf dem Server zurück
(`bin/reset_password`). Niemand kann das Passwort eines anderen Benutzers über
die Oberfläche ändern.

## Warum

Eine Installation beim Kunden soll aus `docker compose up` bestehen. Ein
Mailserver oder ein Versanddienst wäre eine zusätzliche Abhängigkeit, ein
zusätzliches Konto und eine zusätzliche Fehlerquelle — für eine Anwendung, die
typischerweise eine Handvoll Benutzer hat.

## Wie es weitergeht

Ein Passwort-Reset per E-Mail ist geplant. Entscheidend dabei: Der Mailserver
bleibt **optional**. Ist kein SMTP konfiguriert, erscheint „Passwort
vergessen?" gar nicht erst, und es bleibt beim Reset über die Kommandozeile.
Keine Installation darf von einem Mailserver abhängen.
