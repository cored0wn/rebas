# ReBaS - Remote Backup Scripts

## Projektziel
Bei der Planung und Einrichtung meines Homelabs stieß ich auf das Problem, eine Backup-Lösung zu finden, die meine Anforderungen erfüllt und gleichzeitig kostengünstig und einfach wartbar ist.

Meine Anforderungen waren:
 - Backups sollten aus von einem Backuphost aus durchgeführt werden können
 - Es sollte eine bestimmte Anzahl von Backups aufbewahrt werden können
 - Es sollte Befehle vor und nach der Erstellung eines Backups ausgeführt werden können
 - Es sollte einfach zu warten und zu debuggen sein, falls etwas schief geht
 - Es sollte mit den minimal erforderlichen Berechtigungen auf dem Zielsystem laufen können

Nach einigen Recherchen kam ich zu dem Schluss, dass einfache Bash-Skripte die beste Lösung wären.

## Anforderungen
Um dieses Projekt auszuführen, müssen die folgenden Anforderungen erfüllt sein:
 - Auf dem Backup-System müssen `yq`, `bash`, `ssh` und `rsync` installiert sein
 - Auf dem Zielsystem müssen `rsync`, `tar` (die GNU Version) und `sudo` installiert sein (es ist möglich, die Skripte ohne `sudo` auszuführen, aber es muss sichergestellt sein, dass der Backup-Benutzer Zugriff auf alle zu sichernden Dateien hat)

## Wie man die Skripte benutzt

Es gibt zwei Skripte:

Das `do_backup.sh` enthält die eigentliche Logik des Backups. Es akzeptiert mehrere Parameter zur Ausführung:


```
Erforderliche Parameter:
 -n		Name des Backups
 -h 	Ziel-Hostname (kann ein ssh-Verbindungsstring wie user@hostname sein)
 -d 	Liste der Verzeichnisse (durch Komma getrennt)

optionale Parameter:
 -t 	Art des Backups (daily, weekly, monthly) (Default: daily)
 -p 	Befehl, der vor der Erstellung des Archivs ausgeführt werden soll (z.B. Datenbank-Dump erstellen)
 -P 	Befehl, der nach der Erstellung des Archivs ausgeführt werden soll (z.B. Cleanup-Jobs usw.)
 -r 	retention count - wie viele Backups dieses Typs sollen aufbewahrt werden
 -l 	lokales Backup-Zielverzeichnis (Default: ./backup)
 -s 	soll die Ausgabe dieses Skripts in syslog protokolliert werden (Default: false)
```

Das `run_all_backups.sh` ist ein Hilfsskript, um mehrere Backups parallel auszuführen. Es akzeptiert 3 Parameter zur Ausführung:
```
 -c 	Pfad zum Konfigurationsverzeichnis (Default: ./config)
 -d 	dry-run; macht alles außer der Ausführung von do_backup.sh; es zeigt den Befehl mit allen Parametern an (Default: false)
 -t 	spezifiziert den Backup-Typ (Default: daily)
 -s 	soll die Ausgabe dieses Skripts im Syslog protokolliert werden (Default: false)
```

Eine Beispiel-Datei für die Konfiguration eines Backups [liegt hier](config/example/example.yml).

## Mögliche Probleme

### rsync code 12
```
| 2025-03-19 20:29:02 | backup_1 | NOK | bash: line 1: rsync: command not found
rsync: connection unexpectedly closed (0 bytes received so far) [Receiver]
rsync error: error in rsync protocol data stream (code 12) at io.c(232) [Receiver=3. 2.7]
bash: line 1: rsync: command not found
rsync: connection unexpectedly closed (0 bytes received so far) [Receiver]
rsync error: error in rsync protocol data stream (code 12) at io.c(232) [Receiver=3.2.7]
```

**Ursache**: rsync ist auf dem Zielhost nicht installiert. 

### rsync code 23 - file not found
```
rsync: [Absender] link_stat "/home/backup_user/backup_prod_daily_20250319_203857.tar.gz" fehlgeschlagen: No such file or directory (2)

sent 8 bytes received 6 bytes 28.00 bytes/sec
total size is 0 speedup is 0.00
rsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1865) [Receiver=3.2.7]
```

**Ursache**: Das Sicherungsarchiv ist nicht verfügbar. Überprüfe, ob das Archiv erfolgreich erstellt wurde und ob der Backup-Benutzer Zugriff auf die Datei hat.

### rsync code 23 - permission denied
```
rsync: [Absender] send_files konnte "/tmp/dns_prod_daily_20250319_204201.tar.gz" nicht öffnen: Permission denied (13)
```

**Ursache**: Der Backup-Benutzer hat unzureichende Berechtigungen für die Backup-Archiv. Überprüfe, ob der Benutzer Lese-/Schreibrechte für die Sicherungsdatei auf dem Zielsystem hat
