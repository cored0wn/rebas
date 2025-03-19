#!/bin/bash

# Funktion zum Anzeigen der Hilfe
usage() {
    echo "Usage: $0 -n BACKUP_NAME [-t BACKUP_TYPE] -h TARGET_HOST -d DIRECTORIES [-p PRE_COMMANDS] [-P POST_COMMANDS] [-r RETENTION] [-l LOCAL_DEST] [-s]"
    exit 1
}

# Funktion zum Loggen der Ausgaben
log_message() {
    local STATUS=$1
    local MESSAGE=$2
    local LOG_TO_SYSLOG=$3

    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    STATUS_COLOR=""


    # Entweder in den Syslog schreiben oder direkt auf der Konsole ausgeben
    if [ "$LOG_TO_SYSLOG" == "true" ]; then
        logger -t BACKUP "$BACKUP_NAME | $STATUS | $MESSAGE"
    else
        if [ "$STATUS" == "OK" ]; then
            STATUS_COLOR="\033[32m$STATUS\033[0m"  # grün für OK
        elif [ "$STATUS" == "NOK" ]; then
            STATUS_COLOR="\033[31m$STATUS\033[0m"  # rot für NOK
        fi
        echo -e "| $TIMESTAMP | $BACKUP_NAME | $STATUS_COLOR | $MESSAGE"
    fi
}

# Standardwerte setzen
BACKUP_TYPE="daily"
RETENTION=1
LOCAL_DEST="${BACKUP_DIR:-./backups}"
LOG_TO_SYSLOG="false"

# Parameter parsen
while getopts ":n:t:h:d:p:P:r:l:s" opt; do
    case $opt in
        n) BACKUP_NAME="$OPTARG" ;;
        t) BACKUP_TYPE="$OPTARG" ;;
        h) TARGET_HOST="$OPTARG" ;;
        d) DIRECTORIES="$OPTARG" ;;
        p) PRE_COMMANDS="$OPTARG" ;;
        P) POST_COMMANDS="$OPTARG" ;;
        r) RETENTION="$OPTARG" ;;
        l) LOCAL_DEST="$OPTARG" ;;
        s) LOG_TO_SYSLOG="true" ;;  # Flag setzen, um in den Syslog zu schreiben
        \?) echo "Ungültige Option: -$OPTARG" >&2; usage ;;
        :) echo "Option -$OPTARG erfordert ein Argument." >&2; usage ;;
    esac
done

# Überprüfen, ob die erforderlichen Parameter vorhanden sind
if [ -z "$BACKUP_NAME" ] || [ -z "$TARGET_HOST" ] || [ -z "$DIRECTORIES" ]; then
    log_message "NOK" "Fehlende erforderliche Parameter." "$LOG_TO_SYSLOG"
    usage
fi

# Datum und Uhrzeit für den Backup-Namen
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_NAME="${BACKUP_NAME}_${BACKUP_TYPE}_${TIMESTAMP}.tar.gz"

# Verzeichnisse in ein Array umwandeln
IFS=',' read -r -a DIR_ARRAY <<< "$DIRECTORIES"

if [ -f "$BACKUP_NAME-commands.tmp" ]; then
    rm "$BACKUP_NAME-commands.tmp"
fi

touch "$BACKUP_NAME-commands.tmp"

echo $PRE_COMMANDS >> "$BACKUP_NAME-commands.tmp"

echo "umask 177 && sudo /bin/tar -P -czf /tmp/$ARCHIVE_NAME ${DIR_ARRAY[*]}" >> "$BACKUP_NAME-commands.tmp"
echo "sudo chown \$(whoami) /tmp/$ARCHIVE_NAME" >> "$BACKUP_NAME-commands.tmp"

echo $POST_COMMANDS >> "$BACKUP_NAME-commands.tmp"

ERROR_MSG=$(ssh "$TARGET_HOST" 'bash -e -s' < "$BACKUP_NAME-commands.tmp" 2>&1)

if [ $? -ne 0 ]; then
    log_message "NOK" "Fehler beim Ausführen der Remote-Commands" "$LOG_TO_SYSLOG"
    log_message "NOK" "$ERROR_MSG" "$LOG_TO_SYSLOG"
    ERROR_MSG=""
    exit 1
else
    rm "$BACKUP_NAME-commands.tmp"
    log_message "OK" "Archiv $ARCHIV_NAME erstellt" "$LOG_TO_SYSLOG"
fi

# Archiv mit rsync übertragen
RSYNC_DEST="$LOCAL_DEST/$BACKUP_NAME/$BACKUP_TYPE/"

mkdir -p $RSYNC_DEST
ERROR_MSG=$(rsync -vz --no-perms --no-owner --no-group "$TARGET_HOST:/tmp/$ARCHIVE_NAME" "$RSYNC_DEST" 2>&1)

# Exit-Status von rsync überprüfen
RSYNC_EXIT_STATUS=$?

if [ $RSYNC_EXIT_STATUS -ne 0 ]; then
    # Spezifische Fehlermeldung für nicht existierende Datei
    if echo "$ERROR_MSG" | grep -q "No such file or directory"; then
        log_message "NOK" "Die Datei existiert nicht auf dem Zielhost $TARGET_HOST" "$LOG_TO_SYSLOG"
	log_message "NOK" "$ERROR_MSG" "$LOG_TO_SYSLOG"
    else
        log_message "NOK" "Fehler beim Übertragen des Archivs" "$LOG_TO_SYSLOG"
        log_message "NOK" "rsync -vz --no-perms --no-owner --no-group \"$TARGET_HOST:/tmp/$ARCHIVE_NAME\" \"$RSYNC_DEST\"" "$LOG_TO_SYSLOG"
        log_message "NOK" "$ERROR_MSG" "$LOG_TO_SYSLOG"
    fi

    # Ausgabe in der Konsole
    echo "$ERROR_MSG"
    exit 1
else
    # Erfolgreiche Übertragung
    log_message "OK" "Archiv $ARCHIVE_NAME übertragen" "$LOG_TO_SYSLOG"
fi

ssh "$TARGET_HOST" "rm -f /tmp/$ARCHIVE_NAME"
if [ $? -ne 0 ]; then
    log_message "NOK" "Fehler beim Löschen des Archivs." "$LOG_TO_SYSLOG"
    exit 1
fi

# Ältere Backups löschen, falls die Retention-Dauer überschritten wird
BACKUP_COUNT=$(ls "$LOCAL_DEST/$BACKUP_NAME/$BACKUP_TYPE" | wc -l)
if [ $BACKUP_COUNT -gt $RETENTION ]; then
    log_message "OK" "Anzahl Backups:   $BACKUP_COUNT" "$LOG_TO_SYSLOG"
    log_message "OK" "Retention:        $RETENTION" "$LOG_TO_SYSLOG"
fi

while [ $BACKUP_COUNT -gt $RETENTION ]; do
    OLDEST_BACKUP=$(ls -t "$LOCAL_DEST/$BACKUP_NAME/$BACKUP_TYPE" | tail -n 1)
    log_message "OK" "Lösche ältestes Backup $OLDEST_BACKUP" "$LOG_TO_SYSLOG"
    rm "$LOCAL_DEST/$BACKUP_NAME/$BACKUP_TYPE/$OLDEST_BACKUP"
    BACKUP_COUNT=$((BACKUP_COUNT - 1))
done

log_message "OK" "Backup erfolgreich abgeschlossen." "$LOG_TO_SYSLOG"