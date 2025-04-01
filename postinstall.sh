#!/bin/bash

# === VARIABLES ===
## TIMESTAMP = génère un horodatage pour nommer les fichiers de log
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
## LOG_DIR and FILES définissent le répertoire et le fichier de log
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/postinstall_$TIMESTAMP.log"
CONFIG_DIR="./config"
## Fichier listant les paquets à installer
PACKAGE_LIST="./lists/packages.txt"
## USERNAME et USER_HOME détermine l'utilisateur connecté et son répertoire personnel
USERNAME=$(logname)
USER_HOME="/home/$USERNAME"

# === FUNCTIONS ===
## Enregistre les messages des le ficheir de log et les affiches à l'écran
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
## Vérifie si un paquet est installé et l'installe s'il manque
## dpkg -s <package> pour voir si paquet installé
check_and_install() {
  local pkg=$1
  if dpkg -s "$pkg" &>/dev/null; then
    log "$pkg is already installed."
  else
    log "Installing $pkg..."
    apt install -y "$pkg" &>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
      log "$pkg successfully installed."
    else
      log "Failed to install $pkg."
    fi
  fi
}
## Pose la question à l'utilisateur et attend une réponse q'il converti en oui ou non
ask_yes_no() {
  read -p "$1 [y/N]: " answer
  case "$answer" in
    [Yy]* ) return 0 ;;
    * ) return 1 ;;
  esac
}

# === INITIAL SETUP ===
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
log "Starting post-installation script. Logged user: $USERNAME"
## le script s'assure qu'il est éxécuté avec Sudo si non il affiche un message et s'arrête
if [ "$EUID" -ne 0 ]; then
  log "This script must be run as root."
  exit 1
fi

# === 1. SYSTEM UPDATE ===
## met à jour les paquets avec les sortie redirigé vers fichier de log crée au début du script
log "Updating system packages..."
apt update && apt upgrade -y &>>"$LOG_FILE"

# === 2. PACKAGE INSTALLATION ===
## le script lit ligne par ligne et isntalle les nom inscrit dans packages.txt
## si besoin ajouter les noms dans le fichiers de nouvelle features
if [ -f "$PACKAGE_LIST" ]; then
  log "Reading package list from $PACKAGE_LIST"
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
    check_and_install "$pkg"
  done < "$PACKAGE_LIST"
else
  log "Package list file $PACKAGE_LIST not found. Skipping package installation."
fi

# === 3. UPDATE MOTD ===
## mets à jour le fichier MOTD et si le fchier config/motd.txt existe il est copié dans /etc/motd pour personnalisé mle message de bienvenu à la connexion
if [ -f "$CONFIG_DIR/motd.txt" ]; then
  cp "$CONFIG_DIR/motd.txt" /etc/motd
  log "MOTD updated."
else
  log "motd.txt not found."
fi

# === 4. CUSTOM .bashrc ===
##Personnalise .bashrc et ajoute un fichier config/bashrc.append pour modifier l'expérience utilisateur
if [ -f "$CONFIG_DIR/bashrc.append" ]; then
  cat "$CONFIG_DIR/bashrc.append" >> "$USER_HOME/.bashrc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
  log ".bashrc customized."
else
  log "bashrc.append not found."
fi

# === 5. CUSTOM .nanorc ===
## personalise l'éditeur .nanorc 
if [ -f "$CONFIG_DIR/nanorc.append" ]; then
  cat "$CONFIG_DIR/nanorc.append" >> "$USER_HOME/.nanorc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.nanorc"
  log ".nanorc customized."
else
  log "nanorc.append not found."
fi

# === 6. ADD SSH PUBLIC KEY ===
## Propose l'ajout d'une clé SSH, propose de la copié, l'enregistre à l'endroit indiqué ci-dessous
if ask_yes_no "Would you like to add a public SSH key?"; then
  read -p "Paste your public SSH key: " ssh_key
  mkdir -p "$USER_HOME/.ssh"
  echo "$ssh_key" >> "$USER_HOME/.ssh/authorized_keys"
  chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
  chmod 700 "$USER_HOME/.ssh"
  chmod 600 "$USER_HOME/.ssh/authorized_keys"
  log "SSH public key added."
fi

# === 7. SSH CONFIGURATION: KEY AUTH ONLY ===
## Désactive l'authentification par mot de passe et redémarre le service ssh
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh
  log "SSH configured to accept key-based authentication only."
else
  log "sshd_config file not found."
fi

log "Post-installation script completed."

exit 0