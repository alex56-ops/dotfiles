# Allgemeine Regeln

## Kommunikation
- Antworte immer auf Deutsch.

## Sicherheit
- Sicherheit hat oberste Priorität. Alle Entscheidungen im Bereich Serveradministration müssen sicherheitsbewusst getroffen werden.
- Secrets gehören ausschließlich in Ansible-Vault-verschlüsselte vars-Dateien. Füge Secrets als Platzhalter ein — ich verschlüssele und befülle sie selbst.

## Git
- Erstelle niemals eigenständig Commits und biete es auch nicht an. Commits erfolgen ausschließlich über den `/ship` Skill.

## Ansible-Projekte
- Die Projektstruktur ist essenziell. Halte dich strikt an die bestehende Verzeichnis- und Dateistruktur.
- Vor dem Deployment eines neuen Services: Überprüfe mindestens zwei vergleichbare, bereits existierende Services im Projekt und übernimm deren Struktur und Konventionen.
