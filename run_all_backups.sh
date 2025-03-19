#!/bin/bash

# Funktion zum Anzeigen der Hilfe
usage() {
    echo "Usage: $0 [-c CONFIG_DIR] [-d] [-t BACKUP_TYPE] [-s]"
	echo "-c	Path to config dir, default is ./config"
    echo "-s	Redirect log messages to syslog"
    echo "-d	Dry-run"
    echo "-t	Specify backup type (daily, weekly, monthly)"
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
        logger -t BACKUP " $STATUS | $MESSAGE"
    else
        if [ "$STATUS" == "OK" ]; then
            STATUS_COLOR="\033[32m$STATUS\033[0m"  # grün für OK
        elif [ "$STATUS" == "NOK" ]; then
            STATUS_COLOR="\033[31m$STATUS\033[0m"  # rot für NOK
        fi
        echo -e "| $TIMESTAMP | $STATUS_COLOR | $MESSAGE"
    fi
}

CONFIG_DIR="./config"
DRY_RUN="false"
BACKUP_TYPE="daily"
LOG_TO_SYSLOG="false"

BACKUP_SCRIPT="./do_backup.sh"

while getopts ":c:d:t:s" opt; do
    case $opt in
        c) CONFIG_DIR="$OPTARG" ;;
	t) BACKUP_TYPE="$OPTARG" ;;
	s) LOG_TO_SYSLOG="true" ;;
	d) DRY_RUN="true" ;;
	\?) echo "Ungültige Option: -$OPTARG" >&2; usage ;;
	:) echo "Option -$OPTARG erfordert ein Argument." >&2; usage ;;
    esac
done


if [ ! -d "$CONFIG_DIR" ]; then
    log_message "NOK" "Der Ordner $CONFIG_DIR existiert nicht." "$LOG_TO_SYSLOG"
    exit 1
fi

for subdir in "$CONFIG_DIR"/*/; do
    if [ -d "$subdir" ]; then
        # Starten des Subprozesses für jeden Unterordner
        (
	    log_message "OK" "Verarbeite Backups für $(basename "$subdir")" "$LOG_TO_SYSLOG"

            # Alle yml-Dateien im aktuellen Unterordner finden und nach Namen sortieren
            for yml_file in $(find "$subdir" -maxdepth 1 -type f -name "*.yml" | sort); do
                log_message "OK" "Verarbeite Datei: $(basename "$yml_file")" "$LOG_TO_SYSLOG"

                # Werte aus der yml-Datei mit yq extrahieren und in Variablen speichern
                BACKUP_NAME=$(yq -r '.name' "$yml_file")
                TARGET_HOST=$(yq -r '.target' "$yml_file")
		DIRECTORIES=$(yq -r '.directories | join (",")' "$yml_file")
                PRE_COMMANDS=$(yq '.pre_command' "$yml_file")
                POST_COMMANDS=$(yq '.post_command' "$yml_file")
                LOCAL_DEST=$(yq -r '.local_dest' "$yml_file")

                # Überprüfen, ob der angegebene Backup-Typ in der Datei vorhanden ist
                BACKUP_TYPE_CONFIG=$(yq -r ".backups[] | select(.type == \"$BACKUP_TYPE\")" "$yml_file")
                if [ -z "$BACKUP_TYPE_CONFIG" ]; then
                    log_message "NOK" "Kein Backup mit dem Typ $BACKUP_TYPE gefunden in $yml_file" "$LOG_TO_SYSLOG"
                    continue  # Weiter mit der nächsten Datei
                fi
		
		# Extra-Parameter aus dem gefundenen Backup-Typ extrahieren
		BACKUP_TYPE=$(echo "$BACKUP_TYPE_CONFIG" | yq -r ".type")
                RETENTION=$(echo "$BACKUP_TYPE_CONFIG" | yq -r '.retention')

                # Aufbau der Argumente für do_backup.sh
                CMD="$BACKUP_SCRIPT"

		if [[ ! "$BACKUP_NAME" =~ _ ]]; then
	            BACKUP_NAME="$(basename "$subdir")_$BACKUP_NAME"
		fi

                # Überprüfen, ob die Variablen gesetzt sind und füge nur vorhandene Variablen hinzu
                if [ ! "$BACKUP_NAME" == "null" ]; then CMD="$CMD -n $BACKUP_NAME"; fi
                if [ ! "$BACKUP_TYPE" == "null" ]; then CMD="$CMD -t $BACKUP_TYPE"; fi
                if [ ! "$TARGET_HOST" == "null" ]; then CMD="$CMD -h $TARGET_HOST"; fi
                if [ ! "$DIRECTORIES" == "null" ]; then CMD="$CMD -d $DIRECTORIES"; fi
                if [ ! "$PRE_COMMANDS" == "null" ]; then CMD="$CMD -p $PRE_COMMANDS"; fi
                if [ ! "$POST_COMMANDS" == "null" ]; then CMD="$CMD -P $POST_COMMANDS"; fi
                if [ ! "$RETENTION" == "null" ]; then CMD="$CMD -r $RETENTION"; fi
                if [ ! "$LOCAL_DEST" == "null" ]; then CMD="$CMD -l $LOCAL_DEST"; fi
		if [ "$LOG_TO_SYSLOG" == "true" ]; then CMD="$CMD -s"; fi

                # Führe den Befehl aus
		if [ $DRY_RUN == "true" ]; then
		    echo "$CMD"
		else
                    eval "$CMD"
		fi
            done
        ) &
    fi
done

wait

log_message "OK" "Alle Backups abgeschlossen" "$LOG_TO_SYSLOG"