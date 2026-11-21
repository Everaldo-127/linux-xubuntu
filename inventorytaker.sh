#!/usr/bin/env bash
# ============================================================
# LINUX - InventoryTaker
# Shell : bash >= 3.x | Kernel: Linux >= 3.10
# Read-only | Seguro | Diagnostico rapido
# Layout CLI: 3 blocos #### por linha, 01-09, maior -> menor
# 01 Hardware | 02 Portas | 03 Gerenciadores
# 04 Redes | 05 Memoria | 06 WiFi
# 07 Ambiente | 08 Sistema+Kernel+Boot | 09 Armazenamento
# Relatorios: .txt + .html a cada execucao, no Desktop, mesmo conteudo.
# HTML: CARDS 3 por linha igual CLI, escuro, cantos arredondados, cores vivas.
# Rodape: quebra + instrucao + quebra + 2 LINKS file:// puros + quebra + menu [1] TXT [2] HTML [ENTER] Exit. Sem timeout.
# FIRMWARE - CLASSE 0 / GPT - SEM INVENCAO:
#   Classe 0 = PC-AT BIOS = BIOS Legacy. 1=EFI, 2=UEFI, 3=UEFI+CSM.
#   SO /sys/firmware/efi + efibootmgr valem. dmidecode NAO classifica.
#   Sem EFI: Classe = BIOS (Classe 0 - PC-AT BIOS). Nunca UEFI.
#   GPT = tabela do disco, NAO e particao EFI. ESP = EF00. BIOS Boot = EF02.
#   Disco: SO /boot ou /. Prova: LBA1 == "EFI PART" => GPT. Sem isso + 55AA => MBR. Sem prova => N/A.
#   Boot / Disco / Secure / Atual: NO BLOCO 08, 1 unica fonte.
# TEMPERATURA (Bloco 01): sensors -> thermal -> hwmon -> smartctl/hddtemp. Sem sensor = N/A.
# PORTAS: nmap -sS -sU -sV -p- --open TCP+UDP 1-65535 + ss + /proc/net + lsof + ufw. 80 HTTP, 443 HTTPS explicitos.
# TITULO DO BLOCO: faixa branca de ponta a ponta, texto preto, no CLI e no HTML.
# CORRECOES APLICADAS (unicas alteracoes sobre o original):
#   1) ensure_tool idempotente: nao reinstala o que ja existe, nem repete no mesmo run.
#   2) HTML bloco 08: removido printf duplicado antes do card c8.
#   3) HTML bloco 08/09: geracao unica, sem printf duplicado antes do card.
# ============================================================
# Locale: UTF-8 para a largura contar caracteres (o grau conta 1 coluna, nao 2 bytes).
# Sem isso, as bordas laterais das colunas 2 e 3 deslocam 1 coluna nas linhas de temperatura.
_utf_loc=""
if command -v locale >/dev/null 2>&1; then
  _utf_loc=$(locale -a 2>/dev/null | grep -i -E '^C\.utf-?8$|^en_US\.utf-?8$' | head -n 1)
fi
if [ -n "$_utf_loc" ]; then
  export LC_ALL="$_utf_loc"
  export LANG="$_utf_loc"
else
  case "${LC_ALL:-${LANG:-}}" in
    *UTF-8|*utf8|*UTF8) export LC_ALL="${LC_ALL:-$LANG}" ;;
    *) export LC_ALL=C; export LANG=C ;;
  esac
fi
if [ "${BASH_VERSINFO[0]}" -lt 3 ]; then
  printf '%b\n' '\033[31mERRO: Bash >= 3.0 obrigatoria.\033[0m'
  printf 'Versao atual: %s\n' "$BASH_VERSION"
  exit 1
fi
ENV_DISTRO_ID=""; ENV_DISTRO_LIKE=""; ENV_FAMILY=""; ENV_MGR=""; ENV_PRIV=""; ENV_INIT=""
ENV_VIRT=""; ENV_ARCH=""; ENV_KERNEL=""; ENV_FW_MODE=""; ENV_NET="online"
if [ -f /etc/os-release ]; then
  ENV_DISTRO_ID=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | tr 'A-Z' 'a-z')
  ENV_DISTRO_LIKE=$(grep '^ID_LIKE=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | tr 'A-Z' 'a-z')
fi
case "$ENV_DISTRO_ID $ENV_DISTRO_LIKE" in
  *debian*|*ubuntu*|*linuxmint*|*pop*|*elementary*|*kali*|*raspbian*|*deepin*|*mx*) ENV_FAMILY="debian" ;;
  *fedora*|*rhel*|*centos*|*rocky*|*almalinux*|*oracle*|*amazon*) ENV_FAMILY="fedora" ;;
  *arch*|*manjaro*|*endeavouros*|*garuda*|*artix*) ENV_FAMILY="arch" ;;
  *suse*|*opensuse*|*sles*|*sled*) ENV_FAMILY="suse" ;;
  *alpine*) ENV_FAMILY="alpine" ;;
  *gentoo*) ENV_FAMILY="gentoo" ;;
  *slackware*) ENV_FAMILY="slackware" ;;
  *void*) ENV_FAMILY="void" ;;
  *nixos*) ENV_FAMILY="nixos" ;;
  *darwin*|*macos*) ENV_FAMILY="macos" ;;
  *freebsd*|*openbsd*|*netbsd*) ENV_FAMILY="bsd" ;;
  *) ENV_FAMILY="unknown" ;;
esac
for _c in apt-get dnf yum pacman zypper apk emerge slackpkg xbps-install nix-env brew pkg; do
  if command -v "$_c" >/dev/null 2>&1; then
    case "$_c" in
      apt-get) if [ "$ENV_FAMILY" = "debian" ] || [ "$ENV_FAMILY" = "unknown" ]; then ENV_MGR="apt-get"; fi ;;
      dnf) if [ "$ENV_FAMILY" = "fedora" ] || [ "$ENV_FAMILY" = "unknown" ]; then ENV_MGR="dnf"; fi ;;
      yum) if [ "$ENV_FAMILY" = "fedora" ] || [ "$ENV_FAMILY" = "unknown" ]; then ENV_MGR="yum"; fi ;;
      pacman) if [ "$ENV_FAMILY" = "arch" ]; then ENV_MGR="pacman"; fi ;;
      zypper) if [ "$ENV_FAMILY" = "suse" ]; then ENV_MGR="zypper"; fi ;;
      apk) if [ "$ENV_FAMILY" = "alpine" ]; then ENV_MGR="apk"; fi ;;
      emerge) if [ "$ENV_FAMILY" = "gentoo" ]; then ENV_MGR="emerge"; fi ;;
      xbps-install) if [ "$ENV_FAMILY" = "void" ]; then ENV_MGR="xbps-install"; fi ;;
      nix-env) if [ "$ENV_FAMILY" = "nixos" ]; then ENV_MGR="nix-env"; fi ;;
      brew) if [ "$ENV_FAMILY" = "macos" ]; then ENV_MGR="brew"; fi ;;
      pkg) if [ "$ENV_FAMILY" = "bsd" ]; then ENV_MGR="pkg"; fi ;;
    esac
    if [ -n "$ENV_MGR" ]; then break; fi
  fi
done
if [ -z "$ENV_MGR" ]; then
  for _c in apt-get dnf yum pacman zypper apk emerge xbps-install brew pkg; do
    if command -v "$_c" >/dev/null 2>&1; then ENV_MGR="$_c"; break; fi
  done
fi
if [ "$(id -u 2>/dev/null)" = "0" ]; then ENV_PRIV="root"; elif command -v sudo >/dev/null 2>&1; then ENV_PRIV="sudo"; else ENV_PRIV="none"; fi
if [ -d /run/systemd/system ]; then ENV_INIT="systemd"; elif [ -d /etc/init.d ]; then ENV_INIT="sysvinit"; elif command -v rc-service >/dev/null 2>&1; then ENV_INIT="openrc"; else ENV_INIT="unknown"; fi
ENV_ARCH=$(uname -m 2>/dev/null); ENV_KERNEL=$(uname -r 2>/dev/null)
if [ -f /.dockerenv ] || grep -q "docker\|lxc\|kubepods" /proc/1/cgroup 2>/dev/null; then ENV_VIRT="container";
elif [ -d /run/systemd/system ] && command -v systemd-detect-virt >/dev/null 2>&1; then _vv=$(systemd-detect-virt 2>/dev/null); if [ -n "$_vv" ] && [ "$_vv" != "none" ]; then ENV_VIRT="vm:$_vv"; else ENV_VIRT="bare-metal"; fi
else ENV_VIRT="bare-metal"; fi
if [ -d /sys/firmware/efi ]; then ENV_FW_MODE="efi-present"; elif command -v efibootmgr >/dev/null 2>&1 && efibootmgr >/dev/null 2>&1; then ENV_FW_MODE="efi-efibootmgr"; else ENV_FW_MODE="legacy"; fi
DISTRO_ID="$ENV_DISTRO_ID"; DISTRO_LIKE="$ENV_DISTRO_LIKE"; DISTRO_FAMILY="$ENV_FAMILY"; PKG_MGR="$ENV_MGR"
HAS_SYSTEMD=0; [ "$ENV_INIT" = "systemd" ] && HAS_SYSTEMD=1
HAS_WIFI=0; ls /sys/class/net/*/wireless >/dev/null 2>&1 && HAS_WIFI=1; command -v nmcli >/dev/null 2>&1 && HAS_WIFI=1; command -v iw >/dev/null 2>&1 && HAS_WIFI=1
SUDO_CMD=""; [ "$ENV_PRIV" = "sudo" ] && SUDO_CMD="sudo"; [ "$ENV_PRIV" = "root" ] && SUDO_CMD=""
PKG_UPDATE_DONE=0
pkg_name_for() {
  _tool="$1"
  case "$PKG_MGR" in
    apt-get)
      case "$_tool" in
        tput) printf 'ncurses-bin' ;; ip|ss) printf 'iproute2' ;; nmcli) printf 'network-manager' ;;
        iw) printf 'iw' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;; nft) printf 'nftables' ;;
        iptables) printf 'iptables' ;; ufw) printf 'ufw' ;; dmidecode|biosdecode) printf 'dmidecode' ;;
        fdisk|lsblk|sfdisk) printf 'util-linux' ;; parted) printf 'parted' ;; mokutil) printf 'mokutil' ;;
        efibootmgr) printf 'efibootmgr' ;; efivar) printf 'efivar' ;; fwupdmgr) printf 'fwupd' ;;
        bootctl) printf 'systemd-boot' ;; lspci) printf 'pciutils' ;; lshw) printf 'lshw' ;;
        inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;; lscpu) printf 'util-linux' ;;
        lsusb) printf 'usbutils' ;; free) printf 'procps' ;;
        sensors) printf 'lm-sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;;
        systemd-detect-virt|timedatectl|systemctl) printf 'systemd' ;; *) return 1 ;;
      esac ;;
    dnf|yum)
      case "$_tool" in
        tput) printf 'ncurses' ;; ip|ss) printf 'iproute' ;; nmcli) printf 'NetworkManager' ;;
        iw) printf 'iw' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;; nft) printf 'nftables' ;;
        iptables) printf 'iptables' ;; ufw) printf 'ufw' ;; dmidecode|biosdecode) printf 'dmidecode' ;;
        fdisk|lsblk|sfdisk|lscpu) printf 'util-linux' ;; parted) printf 'parted' ;; mokutil) printf 'mokutil' ;;
        efibootmgr) printf 'efibootmgr' ;; efivar) printf 'efivar' ;; fwupdmgr) printf 'fwupd' ;;
        lspci) printf 'pciutils' ;; lshw) printf 'lshw' ;; inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;;
        lsusb) printf 'usbutils' ;; free) printf 'procps-ng' ;;
        sensors) printf 'lm_sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;;
        systemd-detect-virt|timedatectl|systemctl) printf 'systemd' ;; *) return 1 ;;
      esac ;;
    pacman)
      case "$_tool" in
        tput) printf 'ncurses' ;; ip|ss) printf 'iproute2' ;; nmcli) printf 'networkmanager' ;;
        iw) printf 'iw' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;; nft) printf 'nftables' ;;
        iptables) printf 'iptables' ;; ufw) printf 'ufw' ;; dmidecode|biosdecode) printf 'dmidecode' ;;
        fdisk|lsblk|sfdisk|lscpu) printf 'util-linux' ;; parted) printf 'parted' ;; mokutil) printf 'mokutil' ;;
        efibootmgr) printf 'efibootmgr' ;; efivar) printf 'efivar' ;; fwupdmgr) printf 'fwupd' ;;
        lspci) printf 'pciutils' ;; lshw) printf 'lshw' ;; inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;;
        lsusb) printf 'usbutils' ;; free) printf 'procps-ng' ;;
        sensors) printf 'lm_sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;;
        systemd-detect-virt|timedatectl|systemctl) printf 'systemd' ;; *) return 1 ;;
      esac ;;
    zypper)
      case "$_tool" in
        tput) printf 'ncurses-utils' ;; ip|ss) printf 'iproute2' ;; nmcli) printf 'NetworkManager' ;;
        iw) printf 'iw' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;; nft) printf 'nftables' ;;
        iptables) printf 'iptables' ;; ufw) printf 'ufw' ;; dmidecode|biosdecode) printf 'dmidecode' ;;
        fdisk|lsblk|sfdisk|lscpu) printf 'util-linux' ;; parted) printf 'parted' ;; mokutil) printf 'mokutil' ;;
        efibootmgr) printf 'efibootmgr' ;; efivar) printf 'efivar' ;; fwupdmgr) printf 'fwupd' ;;
        lspci) printf 'pciutils' ;; lshw) printf 'lshw' ;; inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;;
        lsusb) printf 'usbutils' ;; free) printf 'procps' ;;
        sensors) printf 'sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;;
        systemd-detect-virt|timedatectl|systemctl) printf 'systemd' ;; *) return 1 ;;
      esac ;;
    apk)
      case "$_tool" in
        tput) printf 'ncurses' ;; ip|ss) printf 'iproute2' ;; nmcli) printf 'networkmanager' ;;
        iw) printf 'iw' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;; nft) printf 'nftables' ;;
        iptables) printf 'iptables' ;; ufw) printf 'ufw' ;; dmidecode|biosdecode) printf 'dmidecode' ;;
        fdisk|lsblk|sfdisk|lscpu) printf 'util-linux' ;; parted) printf 'parted' ;; mokutil) printf 'mokutil' ;;
        efibootmgr) printf 'efibootmgr' ;; efivar) printf 'efivar' ;; fwupdmgr) printf 'fwupd' ;;
        lspci) printf 'pciutils' ;; lshw) printf 'lshw' ;; inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;;
        lsusb) printf 'usbutils' ;; free) printf 'procps' ;;
        sensors) printf 'lm-sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;; *) return 1 ;;
      esac ;;
    emerge)
      case "$_tool" in dmidecode|biosdecode) printf 'sys-apps/dmidecode' ;; lshw) printf 'sys-apps/lshw' ;; inxi) printf 'sys-apps/inxi' ;; hwinfo) printf 'sys-apps/hwinfo' ;; nmap) printf 'net-analyzer/nmap' ;; curl) printf 'net-misc/curl' ;; sensors) printf 'sys-apps/lm-sensors' ;; hddtemp) printf 'app-admin/hddtemp' ;; smartctl) printf 'sys-apps/smartmontools' ;; *) return 1 ;; esac ;;
    xbps-install)
      case "$_tool" in dmidecode) printf 'dmidecode' ;; lshw) printf 'lshw' ;; inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;; sensors) printf 'lm_sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;; *) return 1 ;; esac ;;
    brew)
      case "$_tool" in tput|ip|nmap|curl|iw|dmidecode|fdisk|lsblk|efibootmgr|lshw|inxi|hwinfo|sensors|hddtemp|smartctl) printf '%s' "$_tool" ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}
install_pkg() {
  _pkg="$1"
  if [ -z "$PKG_MGR" ] || [ -z "$_pkg" ]; then return 1; fi
  case "$PKG_MGR" in
    apt-get)
      if [ "$PKG_UPDATE_DONE" = "0" ]; then $SUDO_CMD apt-get update -qq >/dev/null 2>&1; PKG_UPDATE_DONE=1; fi
      $SUDO_CMD apt-get install -y -qq "$_pkg" >/dev/null 2>&1; return $? ;;
    dnf) $SUDO_CMD dnf install -y -q "$_pkg" >/dev/null 2>&1; return $? ;;
    yum) $SUDO_CMD yum install -y -q "$_pkg" >/dev/null 2>&1; return $? ;;
    pacman) $SUDO_CMD pacman -Sy --noconfirm --needed "$_pkg" >/dev/null 2>&1; return $? ;;
    zypper) $SUDO_CMD zypper --non-interactive install -y "$_pkg" >/dev/null 2>&1; return $? ;;
    apk) $SUDO_CMD apk add --no-cache "$_pkg" >/dev/null 2>&1; return $? ;;
    emerge) $SUDO_CMD emerge --quiet "$_pkg" >/dev/null 2>&1; return $? ;;
    xbps-install) $SUDO_CMD xbps-install -y "$_pkg" >/dev/null 2>&1; return $? ;;
    brew) brew install "$_pkg" >/dev/null 2>&1; return $? ;;
    pkg) $SUDO_CMD pkg install -y "$_pkg" >/dev/null 2>&1; return $? ;;
  esac
  return 1
}
ENSURE_DONE=" "
ensure_tool() {
  _tool="$1"
  case "$ENSURE_DONE" in *" $_tool "*) return 0 ;; esac
  ENSURE_DONE="$ENSURE_DONE$_tool "
  if command -v "$_tool" >/dev/null 2>&1; then return 0; fi
  if [ -x "/usr/sbin/$_tool" ] || [ -x "/sbin/$_tool" ] || [ -x "/usr/local/sbin/$_tool" ]; then return 0; fi
  if [ -f "/tmp/.inventorytaker_skip_$_tool" ]; then return 1; fi
  if [ "$_tool" = "hddtemp" ]; then
    if command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W -f='${Status}' hddtemp 2>/dev/null | grep -q "install ok installed"; then return 0; fi
    if command -v smartctl >/dev/null 2>&1 || [ -x "/usr/sbin/smartctl" ]; then return 1; fi
  fi
  case "$_tool" in
    systemd-detect-virt|timedatectl|systemctl|bootctl) if [ "$HAS_SYSTEMD" = "0" ]; then return 1; fi ;;
    nmcli|iw) if [ "$HAS_WIFI" = "0" ]; then return 1; fi ;;
    apt|dpkg|dnf|yum|pacman|zypper|snap|flatpak) return 1 ;;
    wget) return 1 ;;
  esac
  if [ -z "$PKG_MGR" ]; then touch "/tmp/.inventorytaker_skip_$_tool" 2>/dev/null; return 1; fi
  _pkg=$(pkg_name_for "$_tool")
  if [ $? -ne 0 ] || [ -z "$_pkg" ]; then touch "/tmp/.inventorytaker_skip_$_tool" 2>/dev/null; return 1; fi
  printf 'Instalando %s (%s) [%s/%s]...\n' "$_tool" "$_pkg" "$ENV_DISTRO_ID" "$ENV_MGR"
  install_pkg "$_pkg"
  if command -v "$_tool" >/dev/null 2>&1 || [ -x "/usr/sbin/$_tool" ] || [ -x "/sbin/$_tool" ]; then return 0; fi
  touch "/tmp/.inventorytaker_skip_$_tool" 2>/dev/null
  return 1
}
ensure_tools() { for _t in "$@"; do ensure_tool "$_t"; done; }
ensure_tools tput hostname date grep awk sed cut head tail tr sort uniq df uptime id uname free lscpu
ensure_tools dmidecode biosdecode fwupdmgr efibootmgr mokutil efivar fdisk lsblk sfdisk parted lspci lsusb lshw inxi hwinfo bootctl
ensure_tools sensors hddtemp smartctl
RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
C_TITLE=$'\033[38;5;220m'; C_VALUE=$'\033[37m'; C_BLUE=$'\033[38;5;39m'; C_OK=$'\033[38;5;82m'; C_SOFT=$'\033[38;5;245m'; C_HASH=$'\033[38;5;39m'; C_YELLOW=$'\033[38;5;220m'; BG=$'\033[48;5;235m'; BG_WHITE=$'\033[48;5;15m'; C_BLACK=$'\033[30m'
open_file_de_independent() {
  _f="$1"
  if [ ! -f "$_f" ]; then printf 'Arquivo nao encontrado: %s\n' "$_f"; return 1; fi
  if command -v xdg-open >/dev/null 2>&1; then (xdg-open "$_f" >/dev/null 2>&1 &); return 0; fi
  if command -v gio >/dev/null 2>&1; then (gio open "$_f" >/dev/null 2>&1 &); return 0; fi
  if command -v kde-open5 >/dev/null 2>&1; then (kde-open5 "$_f" >/dev/null 2>&1 &); return 0; fi
  if command -v kde-open >/dev/null 2>&1; then (kde-open "$_f" >/dev/null 2>&1 &); return 0; fi
  if command -v kioclient5 >/dev/null 2>&1; then (kioclient5 exec "$_f" >/dev/null 2>&1 &); return 0; fi
  if command -v gnome-open >/dev/null 2>&1; then (gnome-open "$_f" >/dev/null 2>&1 &); return 0; fi
  if command -v exo-open >/dev/null 2>&1; then (exo-open "$_f" >/dev/null 2>&1 &); return 0; fi
  if command -v open >/dev/null 2>&1; then (open "$_f" >/dev/null 2>&1 &); return 0; fi
  printf 'Nenhum abridor encontrado. Abra manualmente: %s\n' "$_f"; return 1
}
ensure_tool tput
if command -v tput >/dev/null 2>&1; then TERM_W=$(tput cols 2>/dev/null); else TERM_W=120; fi
if [ -z "$TERM_W" ] || [ "$TERM_W" -lt 60 ]; then TERM_W=120; fi
if [ "$TERM_W" -ge 120 ]; then BW=39; else BW=$(( (TERM_W - 2) / 3 )); fi
if [ "$BW" -lt 26 ]; then BW=26; fi
if [ "$BW" -gt 39 ]; then BW=39; fi
INNER=$(( BW - 2 ))
pad_right() {
  _t="$1"; _w=$2; _len=${#_t}; _out="$_t"
  while [ "$_len" -lt "$_w" ]; do _out="${_out} "; _len=$(( _len + 1 )); done
  printf '%s' "$_out" | cut -c "1-$_w"
}
pad_center() {
  _t="$1"; _w=$2; _len=${#_t}
  if [ "$_len" -ge "$_w" ]; then printf '%s' "$_t" | cut -c "1-$_w"; return; fi
  _total=$(( _w - _len )); _left=$(( _total / 2 )); _right=$(( _total - _left ))
  _l=""; _i=0; while [ "$_i" -lt "$_left" ]; do _l="${_l} "; _i=$(( _i + 1 )); done
  _r=""; _i=0; while [ "$_i" -lt "$_right" ]; do _r="${_r} "; _i=$(( _i + 1 )); done
  printf '%s%s%s' "$_l" "$_t" "$_r"
}
hash_line() { _s=""; _i=0; while [ "$_i" -lt "$BW" ]; do _s="${_s}#"; _i=$(( _i + 1 )); done; printf '%s' "$_s"; }
HASH_LINE=$(hash_line)
L=(); M=(); R=(); LS=(); MS=(); RS=()
add_L() { L[${#L[@]}]="$1"; LS[${#LS[@]}]="$2"; }
add_M() { M[${#M[@]}]="$1"; MS[${#MS[@]}]="$2"; }
add_R() { R[${#R[@]}]="$1"; RS[${#RS[@]}]="$2"; }
wrap_one() {
  _src=$1; _ssrc=$2; _dst=$3; _sdst=$4
  eval "_n=\${#${_src}[@]}"; _i=0
  while [ "$_i" -lt "$_n" ]; do
    eval "_t=\"\${${_src}[$_i]}\""
    eval "_s=\"\${${_ssrc}[$_i]}\""
    if [ "$_s" = "0" ]; then
      case "$_t" in
        ST:*)
          eval "${_dst}[\${#${_dst}[@]}]=\"\$_t\""; eval "${_sdst}[\${#${_sdst}[@]}]=\"\$_s\"" ;;
        *:*)
          _label=$(printf '%s' "$_t" | cut -d: -f1); _val=$(printf '%s' "$_t" | cut -d: -f2-)
          _label2="${_label}:"
          if [ "${#_t}" -le "$INNER" ]; then
            eval "${_dst}[\${#${_dst}[@]}]=\"\$_t\""; eval "${_sdst}[\${#${_sdst}[@]}]=\"\$_s\""
          else
            _rest="$_val"; _is_first=1; _avail=$(( INNER - ${#_label2} ))
            if [ "$_avail" -lt 4 ]; then _avail=4; fi
            while [ -n "$_rest" ]; do
              if [ "$_is_first" = "1" ]; then _lim=$_avail; else _lim=$(( INNER - 2 )); fi
              _chunk=$(printf '%s' "$_rest" | cut -c "1-$_lim")
              if [ "${#_rest}" -gt "$_lim" ]; then
                _head=$(printf '%s' "$_chunk" | sed 's/ [^ ]*$//')
                if [ -n "$_head" ] && [ "$_head" != "$_chunk" ]; then
                  _used=${#_head}; _chunk="$_head"
                  _rest=$(printf '%s' "$_rest" | cut -c "$(( _used + 2 ))-")
                else
                  _rest=$(printf '%s' "$_rest" | cut -c "$(( _lim + 1 ))-")
                fi
              else
                _rest=""
              fi
              if [ "$_is_first" = "1" ]; then _line="${_label2}${_chunk}"; _is_first=0; else _line="  ${_chunk}"; fi
              eval "${_dst}[\${#${_dst}[@]}]=\"\$_line\""; eval "${_sdst}[\${#${_sdst}[@]}]=\"0\""
              if [ -z "$_rest" ]; then break; fi
            done
          fi
          ;;
        *)
          if [ "${#_t}" -le "$INNER" ]; then
            eval "${_dst}[\${#${_dst}[@]}]=\"\$_t\""; eval "${_sdst}[\${#${_sdst}[@]}]=\"\$_s\""
          else
            _rest="$_t"; _is_first=1
            while [ -n "$_rest" ]; do
              if [ "$_is_first" = "1" ]; then _lim=$INNER; else _lim=$(( INNER - 2 )); fi
              _chunk=$(printf '%s' "$_rest" | cut -c "1-$_lim")
              if [ "${#_rest}" -gt "$_lim" ]; then
                _head=$(printf '%s' "$_chunk" | sed 's/ [^ ]*$//')
                if [ -n "$_head" ] && [ "$_head" != "$_chunk" ]; then
                  _used=${#_head}; _chunk="$_head"
                  _rest=$(printf '%s' "$_rest" | cut -c "$(( _used + 2 ))-")
                else
                  _rest=$(printf '%s' "$_rest" | cut -c "$(( _lim + 1 ))-")
                fi
              else
                _rest=""
              fi
              if [ "$_is_first" = "1" ]; then _line="$_chunk"; _is_first=0; else _line="  ${_chunk}"; fi
              eval "${_dst}[\${#${_dst}[@]}]=\"\$_line\""; eval "${_sdst}[\${#${_sdst}[@]}]=\"0\""
              if [ -z "$_rest" ]; then break; fi
            done
          fi
          ;;
      esac
    else
      eval "${_dst}[\${#${_dst}[@]}]=\"\$_t\""; eval "${_sdst}[\${#${_sdst}[@]}]=\"\$_s\""
    fi
    _i=$(( _i + 1 ))
  done
}
wrap_trio() {
  NL=(); NLS=(); NM=(); NMS=(); NR=(); NRS=()
  wrap_one L LS NL NLS; wrap_one M MS NM NMS; wrap_one R RS NR NRS
  L=(); LS=(); M=(); MS=(); R=(); RS=()
  _i=0; while [ "$_i" -lt "${#NL[@]}" ]; do L[${#L[@]}]="${NL[$_i]}"; LS[${#LS[@]}]="${NLS[$_i]}"; _i=$(( _i + 1 )); done
  _i=0; while [ "$_i" -lt "${#NM[@]}" ]; do M[${#M[@]}]="${NM[$_i]}"; MS[${#MS[@]}]="${NMS[$_i]}"; _i=$(( _i + 1 )); done
  _i=0; while [ "$_i" -lt "${#NR[@]}" ]; do R[${#R[@]}]="${NR[$_i]}"; RS[${#RS[@]}]="${NRS[$_i]}"; _i=$(( _i + 1 )); done
}
add_bottom_trio() {
  wrap_trio
  _la=${#L[@]}; _ma=${#M[@]}; _ra=${#R[@]}; _max=$_la
  if [ "$_ma" -gt "$_max" ]; then _max=$_ma; fi
  if [ "$_ra" -gt "$_max" ]; then _max=$_ra; fi
  while [ "${#L[@]}" -lt "$_max" ]; do add_L "" 0; done
  while [ "${#M[@]}" -lt "$_max" ]; do add_M "" 0; done
  while [ "${#R[@]}" -lt "$_max" ]; do add_R "" 0; done
}
render_one() {
  _t="$1"; _s="$2"
  if [ "$_t" = "__TOP__" ]; then printf '%s' "${C_HASH}${HASH_LINE}${RESET}"; return; fi
  if [ "$_s" = "1" ]; then _c=$(pad_center "$_t" "$INNER"); printf '%s' "${C_HASH}#${RESET}${BG_WHITE}${BOLD}${C_BLACK}${_c}${RESET}${C_HASH}#${RESET}"; return; fi
  if [ "$_s" = "2" ]; then _d=""; _k=0; while [ "$_k" -lt "$INNER" ]; do _d="${_d}-"; _k=$(( _k + 1 )); done; printf '%s' "${C_HASH}#${RESET}${BG}${C_SOFT}${_d}${RESET}${C_HASH}#${RESET}"; return; fi
  if [ "$_s" = "4" ]; then _p=$(pad_right "$_t" "$INNER"); printf '%s' "${C_HASH}#${RESET}${BG}${C_YELLOW}${_p}${RESET}${C_HASH}#${RESET}"; return; fi
  if [ "$_s" = "6" ]; then
    _status=$(printf '%s' "$_t" | awk '{print $NF}'); _rest=$(printf '%s' "$_t" | sed 's/ [^ ]*$//')
    _content_len=$(( 1 + ${#_rest} + 1 + ${#_status} )); _fill=$(( INNER - _content_len ))
    if [ "$_fill" -lt 0 ]; then _fill=0; fi
    _f=""; _k=0; while [ "$_k" -lt "$_fill" ]; do _f="${_f} "; _k=$(( _k + 1 )); done
    printf '%s' "${C_HASH}#${RESET}${BG}${C_VALUE} ${_rest} ${RESET}${BG}${C_YELLOW}${_status}${RESET}${BG}${_f}${RESET}${C_HASH}#${RESET}"; return
  fi
  case "$_t" in
    ST:*)
      _rest=$(printf '%s' "$_t" | cut -d: -f2-); _grande=$(printf '%s' "$_rest" | cut -d'|' -f1); _line=$(printf '%s' "$_rest" | cut -d'|' -f2)
      _line_p=$(pad_right "$_line" $(( INNER - 1 )))
      if [ "$_grande" = "1" ]; then
        _head=$(printf '%s' "$_line_p" | cut -c "1-$(( INNER - 9 ))")
        _livre=$(printf '%s' "$_line_p" | cut -c "$(( INNER - 8 ))-$(( INNER - 3 ))")
        _livre=$(pad_right "$_livre" 6)
        printf '%s' "${C_HASH}#${RESET}${BG}${C_VALUE}${_head}${RESET}${BG}${C_YELLOW}${_livre}${RESET}${BG}   ${RESET}${C_HASH}#${RESET}"
      else
        printf '%s' "${C_HASH}#${RESET}${BG}${C_VALUE}${_line_p} ${RESET}${C_HASH}#${RESET}"
      fi
      return ;;
  esac
  case "$_t" in
    *:*)
      _label=$(printf '%s' "$_t" | cut -d: -f1); _val=$(printf '%s' "$_t" | cut -d: -f2-); _label="${_label}:"
      _full_len=$(( ${#_label} + ${#_val} )); _pad_len=$(( INNER - _full_len ))
      if [ "$_pad_len" -lt 0 ]; then _pad_len=0; fi
      _pad=""; _k=0; while [ "$_k" -lt "$_pad_len" ]; do _pad="${_pad} "; _k=$(( _k + 1 )); done
      _val_cut=$(printf '%s' "$_val" | cut -c "1-$(( INNER - ${#_label} ))")
      printf '%s' "${C_HASH}#${RESET}${BG}${C_YELLOW}${_label}${RESET}${BG}${C_VALUE}${_val_cut}${_pad}${RESET}${C_HASH}#${RESET}"
      return ;;
  esac
  _p=$(pad_right "$_t" "$INNER")
  printf '%s' "${C_HASH}#${RESET}${BG}${C_VALUE}${_p}${RESET}${C_HASH}#${RESET}"
}
print_trio() {
  _la=${#L[@]}; _ma=${#M[@]}; _ra=${#R[@]}; _max=$_la
  if [ "$_ma" -gt "$_max" ]; then _max=$_ma; fi
  if [ "$_ra" -gt "$_max" ]; then _max=$_ra; fi
  _i=0
  while [ "$_i" -lt "$_max" ]; do
    _lt="${L[$_i]}"; _mt="${M[$_i]}"; _rt="${R[$_i]}"; _ls="${LS[$_i]}"; _ms="${MS[$_i]}"; _rs="${RS[$_i]}"
    if [ -z "$_ls" ]; then _ls=0; _lt=""; fi
    if [ -z "$_ms" ]; then _ms=0; _mt=""; fi
    if [ -z "$_rs" ]; then _rs=0; _rt=""; fi
    _a=$(render_one "$_lt" "$_ls"); _b=$(render_one "$_mt" "$_ms"); _c=$(render_one "$_rt" "$_rs")
    printf '%s %s %s\n' "$_a" "$_b" "$_c"
    _i=$(( _i + 1 ))
  done
  L=(); M=(); R=(); LS=(); MS=(); RS=()
}
print_close() { printf '%s %s %s\n' "${C_HASH}${HASH_LINE}${RESET}" "${C_HASH}${HASH_LINE}${RESET}" "${C_HASH}${HASH_LINE}${RESET}"; }
html_esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
to_gb() { awk "BEGIN {printf \"%.2f GB\", $1/1024/1024}"; }
is_large_free() {
  _v="$1"; _num=$(printf '%s' "$_v" | sed 's/[^0-9.]//g')
  case "$_v" in
    *T*) printf '1'; return ;;
    *G*) _big=$(awk -v n="$_num" 'BEGIN {print (n+0 >= 10) ? 1 : 0}'); printf '%s' "$_big"; return ;;
    *) printf '0'; return ;;
  esac
}
is_valid_ipv4() {
  _ip="$1"; case "$_ip" in *.*.*.*) ;; *) return 1 ;; esac
  _o1=$(printf '%s' "$_ip" | cut -d. -f1); _o2=$(printf '%s' "$_ip" | cut -d. -f2); _o3=$(printf '%s' "$_ip" | cut -d. -f3); _o4=$(printf '%s' "$_ip" | cut -d. -f4)
  for _o in "$_o1" "$_o2" "$_o3" "$_o4"; do case "$_o" in ''|*[!0-9]*) return 1 ;; esac; if [ "$_o" -gt 255 ]; then return 1; fi; done
  return 0
}
get_ext_ip() {
  ensure_tool curl; _cand=""
  if command -v curl >/dev/null 2>&1; then
    _cand=$(curl -s --max-time 3 https://ifconfig.me/ip 2>/dev/null | tr -d ' \n\r\t' | head -n 1)
    if is_valid_ipv4 "$_cand"; then printf '%s' "$_cand"; return; fi
    _cand=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null | tr -d ' \n\r\t' | head -n 1)
    if is_valid_ipv4 "$_cand"; then printf '%s' "$_cand"; return; fi
    _cand=$(curl -s --max-time 3 https://checkip.amazonaws.com 2>/dev/null | tr -d ' \n\r\t' | head -n 1)
    if is_valid_ipv4 "$_cand"; then printf '%s' "$_cand"; return; fi
  fi
  printf 'N/A'
}
get_cpu_gen() {
  _m="$1"
  case "$_m" in
    *Ryzen*)
      _num=$(printf '%s' "$_m" | sed -n 's/.*Ryzen [3579] \([0-9][0-9]*\).*/\1/p' | cut -c 1-1)
      if [ -n "$_num" ]; then printf '%sa geracao (Ryzen)' "$_num"; return; fi
      printf 'N/A'; return ;;
    *Core*2*Duo*|*Core*2*Quad*|*Core2*) printf 'Core 2 (pre-i)'; return ;;
    *Intel*)
      _num=$(printf '%s' "$_m" | sed -n 's/.*i[3579]-\([0-9][0-9]*\).*/\1/p')
      if [ -n "$_num" ]; then
        _len=${#_num}
        if [ "$_len" -ge 5 ]; then _gen=$(printf '%s' "$_num" | cut -c 1-2); printf '%sa geracao' "$_gen"; return; fi
        if [ "$_len" -eq 4 ]; then
          _pre=$(printf '%s' "$_num" | cut -c 1-2)
          if [ "$_pre" = "10" ] || [ "$_pre" = "11" ]; then printf '%sa geracao' "$_pre"; return; fi
          _gen=$(printf '%s' "$_num" | cut -c 1-1); printf '%sa geracao' "$_gen"; return
        fi
        printf '%sa geracao' "$_num"; return
      fi
      case "$_m" in *" M "*) printf '1a geracao (Nehalem)'; return ;; esac
      printf 'N/A'; return ;;
    *Xeon*) printf 'Xeon (servidor)'; return ;;
    *) printf 'N/A'; return ;;
  esac
}
service_for_port() {
  _pp="$1"; _nmap_svc="$2"; _num=$(printf '%s' "$_pp" | cut -d/ -f1)
  case "$_num" in
    80) printf 'HTTP'; return ;; 443) printf 'HTTPS'; return ;;
    8000) printf 'HTTP-ALT'; return ;; 8080) printf 'HTTP-ALT'; return ;; 8443) printf 'HTTPS-ALT'; return ;;
    3000) printf 'NODE'; return ;; 5000) printf 'FLASK'; return ;; 9000) printf 'PHP-FPM'; return ;;
    2222) printf 'SSH-ALT'; return ;; 9090) printf 'HTTP-ALT'; return ;;
    3306) printf 'MYSQL'; return ;; 5432) printf 'POSTGRESQL'; return ;; 6379) printf 'REDIS'; return ;;
    27017) printf 'MONGODB'; return ;; 51820) printf 'WIREGUARD'; return ;;
  esac
  if [ -f /etc/services ]; then
    _from_etc=$(awk -v want="$_pp" '$2 == want {print $1; exit}' /etc/services 2>/dev/null)
    if [ -n "$_from_etc" ]; then printf '%s' "$_from_etc" | tr 'a-z' 'A-Z'; return; fi
  fi
  if [ -n "$_nmap_svc" ] && [ "$_nmap_svc" != "open" ] && [ "$_nmap_svc" != "ss" ] && [ "$_nmap_svc" != "ufw" ]; then printf '%s' "$_nmap_svc" | tr 'a-z' 'A-Z' | tr '-' '_'; return; fi
  printf 'DESCONHECIDO'
}
add_port_unique() {
  _new_pp="$1"; _nmap_svc="$2"; _k=0
  while [ "$_k" -lt "${#PORTS_LINES[@]}" ]; do
    _ex=$(printf '%s' "${PORTS_LINES[$_k]}" | cut -d' ' -f1)
    if [ "$_ex" = "$_new_pp" ]; then return 0; fi
    _k=$(( _k + 1 ))
  done
  _svc=$(service_for_port "$_new_pp" "$_nmap_svc")
  PORTS_LINES[${#PORTS_LINES[@]}]="$_new_pp - $_svc"
}
resolve_boot_disk_name() {
  _cur_path="$1"; _n=0
  while [ "$_n" -lt 6 ]; do
    if [ -z "$_cur_path" ]; then return 1; fi
    case "$_cur_path" in /dev/loop*|/dev/ram*|/dev/zram*) return 1 ;; esac
    _info=$(LC_ALL=C lsblk -n -o NAME,TYPE,PKNAME "$_cur_path" 2>/dev/null | head -n 1)
    _name=$(printf '%s' "$_info" | awk '{print $1}'); _type=$(printf '%s' "$_info" | awk '{print $2}'); _parent=$(printf '%s' "$_info" | awk '{print $3}')
    if [ -z "$_name" ]; then return 1; fi
    if [ "$_type" = "disk" ]; then printf '%s' "$_name"; return 0; fi
    if [ -n "$_parent" ]; then _cur_path="/dev/$_parent"; _n=$(( _n + 1 )); continue; fi
    return 1
  done
  return 1
}
detect_pttype_signature() {
  _disk="$1"
  if [ -z "$_disk" ] || [ ! -b "$_disk" ]; then return 1; fi
  _sig=$($SUDO_CMD dd if="$_disk" bs=512 skip=1 count=1 2>/dev/null | head -c 8 | od -An -c 2>/dev/null | tr -d ' \n')
  _sig_norm=$(printf '%s' "$_sig" | tr -d ' ')
  case "$_sig_norm" in *EFIPART*) printf 'GPT'; return 0 ;; esac
  _mbr=$($SUDO_CMD dd if="$_disk" bs=1 skip=510 count=2 2>/dev/null | od -An -t x1 2>/dev/null | tr -d ' \n')
  case "$_mbr" in 55aa|55AA) printf 'MBR'; return 0 ;; esac
  return 1
}
clean_dmi() {
  _v=$(printf '%s' "$1" | sed 's/^ //;s/[[:space:]]*$//')
  case "$_v" in
    ""|"N/A"|"Not Specified"|"Not Available"|"None"|"Unknown"|*"To be filled"*|"To Be Filled By O.E.M."|"O.E.M."|"System Product Name"|"System Version") printf 'N/A'; return ;;
  esac
  printf '%s' "$_v"
}
dmi_field() {
  _want="$1"; _sysfile="$2"; _v=""
  if [ -n "$_DMI_BIOS" ]; then _v=$(printf '%s' "$_DMI_BIOS" | grep -i "^[[:space:]]*$_want:" | head -n 1 | cut -d: -f2-); fi
  _v=$(clean_dmi "$_v")
  if [ "$_v" = "N/A" ] && [ -n "$_sysfile" ] && [ -f "/sys/class/dmi/id/$_sysfile" ]; then _v=$(clean_dmi "$(cat "/sys/class/dmi/id/$_sysfile" 2>/dev/null | head -n 1)"); fi
  printf '%s' "$_v"
}
dmi_sys_field() {
  _want="$1"; _sysfile="$2"; _v=""
  if [ -n "$_DMI_SYS" ]; then _v=$(printf '%s' "$_DMI_SYS" | grep -i "^[[:space:]]*$_want:" | head -n 1 | cut -d: -f2-); fi
  _v=$(clean_dmi "$_v")
  if [ "$_v" = "N/A" ] && [ -n "$_sysfile" ] && [ -f "/sys/class/dmi/id/$_sysfile" ]; then _v=$(clean_dmi "$(cat "/sys/class/dmi/id/$_sysfile" 2>/dev/null | head -n 1)"); fi
  printf '%s' "$_v"
}
fmt_temp() {
  _raw=$(printf '%s' "$1" | tr -d ' +°C' | tr ',' '.')
  case "$_raw" in ''|*[!0-9.]*) return 1 ;; esac
  _int=$(printf '%s' "$_raw" | cut -d. -f1)
  if [ -z "$_int" ]; then return 1; fi
  if [ "$_int" -gt 1000 ]; then _int=$(( _int / 1000 )); fi
  if [ "$_int" -lt -50 ] || [ "$_int" -gt 150 ]; then return 1; fi
  printf '%s°C' "$_int"
}
collect_temps() {
  TEMP_CPU="N/A"; TEMP_GPU="N/A"; TEMP_DISK="N/A"; TEMP_BOARD="N/A"
  _sensors_out=""
  if command -v sensors >/dev/null 2>&1; then _sensors_out=$(LC_ALL=C sensors 2>/dev/null); fi
  if [ -n "$_sensors_out" ]; then
    for _pat in "Package id 0" "Tctl" "Tdie" "Core 0" "temp1"; do
      _cpu=$(printf '%s' "$_sensors_out" | grep -i -F "$_pat" | head -n 1 | grep -o -E "[-+][0-9]+(\.[0-9]+)?" | head -n 1)
      if [ -n "$_cpu" ]; then TEMP_CPU=$(fmt_temp "$_cpu" || printf 'N/A'); break; fi
    done
    for _pat in "edge" "junction"; do
      _gpu=$(printf '%s' "$_sensors_out" | grep -i -E "$_pat:" | head -n 1 | grep -o -E "[-+][0-9]+(\.[0-9]+)?" | head -n 1)
      if [ -n "$_gpu" ]; then TEMP_GPU=$(fmt_temp "$_gpu" || printf 'N/A'); break; fi
    done
    for _pat in "SYSTIN" "Motherboard" "MB Temp" "temp2" "temp3"; do
      _brd=$(printf '%s' "$_sensors_out" | grep -i -F "$_pat" | head -n 1 | grep -o -E "[-+][0-9]+(\.[0-9]+)?" | head -n 1)
      if [ -n "$_brd" ]; then TEMP_BOARD=$(fmt_temp "$_brd" || printf 'N/A'); break; fi
    done
  fi
  if [ "$TEMP_GPU" = "N/A" ] && command -v nvidia-smi >/dev/null 2>&1; then
    _ng=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -n 1 | grep -o -E "[0-9]+(\.[0-9]+)?" | head -n 1)
    if [ -n "$_ng" ]; then TEMP_GPU=$(fmt_temp "$_ng" || printf 'N/A'); fi
  fi
  if [ -d /sys/class/thermal ]; then
    for _z in /sys/class/thermal/thermal_zone*; do
      if [ ! -f "$_z/temp" ] || [ ! -f "$_z/type" ]; then continue; fi
      _zt=$(cat "$_z/type" 2>/dev/null); _zv=$(cat "$_z/temp" 2>/dev/null)
      _fmt=$(fmt_temp "$_zv" || printf '')
      if [ -z "$_fmt" ]; then continue; fi
      case "$_zt" in
        *cpu*|*CPU*|*x86*|*acpitz*|*thermal*)
          if [ "$TEMP_CPU" = "N/A" ]; then TEMP_CPU="$_fmt"; fi ;;
        *gpu*|*GPU*|*radeon*|*amdgpu*|*nouveau*|*nvidia*)
          if [ "$TEMP_GPU" = "N/A" ]; then TEMP_GPU="$_fmt"; fi ;;
        *board*|*sys*|*pch*|*skin*)
          if [ "$TEMP_BOARD" = "N/A" ]; then TEMP_BOARD="$_fmt"; fi ;;
      esac
    done
  fi
  if [ -d /sys/class/hwmon ]; then
    for _h in /sys/class/hwmon/hwmon*; do
      if [ ! -f "$_h/name" ]; then continue; fi
      _hn=$(cat "$_h/name" 2>/dev/null)
      for _tf in "$_h"/temp*_input; do
        if [ ! -f "$_tf" ]; then continue; fi
        _tv=$(cat "$_tf" 2>/dev/null); _fmt=$(fmt_temp "$_tv" || printf '')
        if [ -z "$_fmt" ]; then continue; fi
        case "$_hn" in
          *coretemp*|*k10temp*|*zenpower*|*cpu_thermal*|*acpitz*)
            if [ "$TEMP_CPU" = "N/A" ]; then TEMP_CPU="$_fmt"; fi ;;
          *amdgpu*|*nouveau*|*nvidia*|*radeon*)
            if [ "$TEMP_GPU" = "N/A" ]; then TEMP_GPU="$_fmt"; fi ;;
          *nvme*|*ata*|*drivetemp*|*sata*)
            if [ "$TEMP_DISK" = "N/A" ]; then TEMP_DISK="$_fmt"; fi ;;
          *nct*|*it87*|*w836*|*jc42*|*lm75*|*tmp*|*sht*|*pch*)
            if [ "$TEMP_BOARD" = "N/A" ]; then TEMP_BOARD="$_fmt"; fi ;;
        esac
      done
    done
  fi
  if [ "$TEMP_DISK" = "N/A" ] && [ -n "$BOOT_DISK" ] && [ "$BOOT_DISK" != "N/A" ]; then
    if command -v smartctl >/dev/null 2>&1; then
      _sd=$(LC_ALL=C $SUDO_CMD smartctl -A "$BOOT_DISK" 2>/dev/null | grep -i -E "Temperature_Celsius|Temperature:|Composite Temperature" | head -n 1 | grep -o -E "[0-9]+(\.[0-9]+)?" | tail -n 1)
      if [ -n "$_sd" ]; then TEMP_DISK=$(fmt_temp "$_sd" || printf 'N/A'); fi
    fi
    if [ "$TEMP_DISK" = "N/A" ] && command -v hddtemp >/dev/null 2>&1; then
      _hd=$(LC_ALL=C $SUDO_CMD hddtemp -n "$BOOT_DISK" 2>/dev/null | tr -d ' \n')
      if [ -n "$_hd" ]; then TEMP_DISK=$(fmt_temp "$_hd" || printf 'N/A'); fi
    fi
  fi
}
clear
print_banner() {
  _use_color="$1"
  _bw_line=""; _i=0; while [ "$_i" -lt "$TOTAL_W" ]; do _bw_line="${_bw_line}█"; _i=$(( _i + 1 )); done
  _c_l=$'\033[1;38;5;196m'; _c_i=$'\033[1;38;5;208m'; _c_n=$'\033[1;38;5;226m'; _c_u=$'\033[1;38;5;46m'; _c_x=$'\033[1;38;5;51m'; _c_cyn=$'\033[1;38;5;51m'; _c_wht=$'\033[1;37m'
  _banner_line() {
    _btxt="$1"; _bcol="$2"
    if [ -z "$_btxt" ]; then printf '\n'; return; fi
    _bc=$(pad_center "$_btxt" "$TOTAL_W")
    if [ "$_use_color" = "1" ]; then printf '%s%s%s\n' "$_bcol" "$_bc" "${RESET}"; else printf '%s\n' "$_bc"; fi
  }
  _banner_letters() {
    _l="$1"; _ii="$2"; _n="$3"; _u="$4"; _x="$5"
    _total=47
    _pad=$(( (TOTAL_W - _total) / 2 ))
    _left=""; _j=0; while [ "$_j" -lt "$_pad" ]; do _left="${_left} "; _j=$(( _j + 1 )); done
    _rlen=$(( TOTAL_W - _total - _pad ))
    _right=""; _j=0; while [ "$_j" -lt "$_rlen" ]; do _right="${_right} "; _j=$(( _j + 1 )); done
    if [ "$_use_color" = "1" ]; then printf '%s%s%s%s  %s%s%s  %s%s%s  %s%s%s  %s%s%s%s\n' "$_left" "$_c_l" "$_l" "${RESET}" "$_c_i" "$_ii" "${RESET}" "$_c_n" "$_n" "${RESET}" "$_c_u" "$_u" "${RESET}" "$_c_x" "$_x" "${RESET}" "$_right"; else printf '%s%s  %s  %s  %s  %s%s\n' "$_left" "$_l" "$_ii" "$_n" "$_u" "$_x" "$_right"; fi
  }
  _banner_inventory() {
    _grad="17 18 19 20 21 26 27 32 33 38 39 44 45 51"
    _r=0
    while [ "$_r" -lt 5 ]; do
      _row_plain=""; _row_color=""
      _p=0
      _word="INVENTORYTAKER"
      while [ "$_p" -lt "${#_word}" ]; do
        _ch=$(printf '%s' "$_word" | cut -c $(( _p + 1 )))
        case "$_ch" in
          I) case "$_r" in 0) _g="█████" ;; 1) _g="  █  " ;; 2) _g="  █  " ;; 3) _g="  █  " ;; 4) _g="█████" ;; esac ;;
          N) case "$_r" in 0) _g="█   █" ;; 1) _g="██  █" ;; 2) _g="█ █ █" ;; 3) _g="█  ██" ;; 4) _g="█   █" ;; esac ;;
          V) case "$_r" in 0) _g="█   █" ;; 1) _g="█   █" ;; 2) _g="█   █" ;; 3) _g=" █ █ " ;; 4) _g="  █  " ;; esac ;;
          E) case "$_r" in 0) _g="█████" ;; 1) _g="█    " ;; 2) _g="████ " ;; 3) _g="█    " ;; 4) _g="█████" ;; esac ;;
          T) case "$_r" in 0) _g="█████" ;; 1) _g="  █  " ;; 2) _g="  █  " ;; 3) _g="  █  " ;; 4) _g="  █  " ;; esac ;;
          O) case "$_r" in 0) _g=" ███ " ;; 1) _g="█   █" ;; 2) _g="█   █" ;; 3) _g="█   █" ;; 4) _g=" ███ " ;; esac ;;
          R) case "$_r" in 0) _g="████ " ;; 1) _g="█   █" ;; 2) _g="████ " ;; 3) _g="█  █ " ;; 4) _g="█   █" ;; esac ;;
          Y) case "$_r" in 0) _g="█   █" ;; 1) _g="█   █" ;; 2) _g=" █ █ " ;; 3) _g="  █  " ;; 4) _g="  █  " ;; esac ;;
          A) case "$_r" in 0) _g=" ███ " ;; 1) _g="█   █" ;; 2) _g="█████" ;; 3) _g="█   █" ;; 4) _g="█   █" ;; esac ;;
          K) case "$_r" in 0) _g="█   █" ;; 1) _g="█  █ " ;; 2) _g="███  " ;; 3) _g="█  █ " ;; 4) _g="█   █" ;; esac ;;
        esac
        _col=$(printf '%s' "$_grad" | cut -d' ' -f$(( _p + 1 )))
        _row_plain="${_row_plain}${_g} "
        if [ "$_use_color" = "1" ]; then _row_color="${_row_color}$(printf '\033[1;38;5;%sm' "$_col")${_g} ${RESET}"; else _row_color="${_row_color}${_g} "; fi
        _p=$(( _p + 1 ))
      done
      _pad_len=$(( (TOTAL_W - ${#_row_plain}) / 2 ))
      _left_pad=""; _j=0; while [ "$_j" -lt "$_pad_len" ]; do _left_pad="${_left_pad} "; _j=$(( _j + 1 )); done
      _right_len=$(( TOTAL_W - ${#_row_plain} - _pad_len ))
      _right_pad=""; _j=0; while [ "$_j" -lt "$_right_len" ]; do _right_pad="${_right_pad} "; _j=$(( _j + 1 )); done
      if [ "$_use_color" = "1" ]; then printf '%s%s%s\n' "$_left_pad" "$_row_color" "$_right_pad"; else printf '%s\n' "$_row_plain"; fi
      _r=$(( _r + 1 ))
    done
  }
  if [ "$_use_color" = "1" ]; then printf '%s%s%s\n' "${BOLD}${C_TITLE}" "$_bw_line" "${RESET}"; else printf '%s\n' "$_bw_line"; fi
  _banner_line "" ""
  _banner_letters '████  ' '██████' '███   ███' '███   ███' '███   ███'
  _banner_letters '████  ' ' ████ ' '████  ███' '███   ███' ' ██   ██ '
  _banner_letters '████  ' ' ████ ' '█████ ███' '███   ███' '  ██ ██  '
  _banner_letters '████  ' ' ████ ' '███ █████' '███   ███' '   ███   '
  _banner_letters '████  ' ' ████ ' '███  ████' '███   ███' '  ██ ██  '
  _banner_letters '████  ' ' ████ ' '███   ███' '███   ███' ' ██   ██ '
  _banner_letters '██████' '██████' '███   ███' ' ███████ ' '███   ███'
  _banner_line "" ""
  _banner_line '═════════════════════════════════════════════════════' "$_c_cyn"
  printf '\n\n'
  _banner_inventory
  printf '\n\n'
  _banner_line 'INVENTÁRIO COMPLETO DO SISTEMA' "$_c_wht"
  _banner_line "" ""
  if [ "$_use_color" = "1" ]; then printf '%s%s%s\n' "${BOLD}${C_TITLE}" "$_bw_line" "${RESET}"; else printf '%s\n' "$_bw_line"; fi
}
CHECK_MODE=0
if [ "${1:-}" = "--check" ]; then CHECK_MODE=1; fi
HOST=$(hostname); NOW=$(date "+%Y-%m-%d %H:%M:%S"); TOTAL_W=$(( BW * 3 + 2 ))
print_banner 1
printf '\n\n'
_host_line="Host: $HOST  |  Atualizado em: $NOW"; _host_c=$(pad_center "$_host_line" "$TOTAL_W")
printf '%s%s%s\n' "${C_BLUE}" "$_host_c" "${RESET}"
_compat_line="Compativel: Kernel >= 3.10 | Bash >= 3.x"; _compat_c=$(pad_center "$_compat_line" "$TOTAL_W")
printf '%s%s%s\n' "${C_BLUE}" "$_compat_c" "${RESET}"
printf '\n'
ensure_tools uname grep cut tr dmidecode lsblk fdisk findmnt
OS_NAME=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
OS_VER=$(grep VERSION_ID /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
KERNEL_V=$(uname -r); ARCH_V=$(uname -m); SHELL_V="$BASH_VERSION"
DE_VAL="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-${XDG_SESSION_DESKTOP:-$GDMSESSION}}}"
DE_VAL=$(printf '%s' "$DE_VAL" | tr ':' ' ' | awk '{print $1}')
if [ -z "$DE_VAL" ] || [ "$DE_VAL" = "N/A" ]; then
  if pgrep -x plasmashell >/dev/null 2>&1; then DE_VAL="KDE Plasma";
  elif pgrep -x gnome-shell >/dev/null 2>&1; then DE_VAL="GNOME";
  elif pgrep -x xfce4-session >/dev/null 2>&1; then DE_VAL="XFCE";
  elif pgrep -x cinnamon >/dev/null 2>&1; then DE_VAL="Cinnamon";
  elif pgrep -x mate-session >/dev/null 2>&1; then DE_VAL="MATE";
  elif pgrep -x lxqt-session >/dev/null 2>&1; then DE_VAL="LXQt";
  elif pgrep -x lxsession >/dev/null 2>&1; then DE_VAL="LXDE";
  elif pgrep -x budgie-wm >/dev/null 2>&1; then DE_VAL="Budgie";
  elif pgrep -x sway >/dev/null 2>&1; then DE_VAL="Sway";
  elif pgrep -x Hyprland >/dev/null 2>&1; then DE_VAL="Hyprland";
  elif pgrep -x i3 >/dev/null 2>&1; then DE_VAL="i3";
  else DE_VAL="N/A (sem GUI / TTY)"; fi
fi
case "$DE_VAL" in
  *KDE*|*Plasma*) DE_VAL="KDE Plasma" ;; *GNOME*|*gnome*) DE_VAL="GNOME" ;;
  *XFCE*|*Xfce*) DE_VAL="XFCE" ;; *Cinnamon*) DE_VAL="Cinnamon" ;; *MATE*) DE_VAL="MATE" ;;
  *LXQt*) DE_VAL="LXQt" ;; *LXDE*) DE_VAL="LXDE" ;; *Budgie*) DE_VAL="Budgie" ;;
  *Pantheon*) DE_VAL="Pantheon" ;; *Deepin*|*DDE*) DE_VAL="Deepin" ;; *Unity*) DE_VAL="Unity" ;;
esac
SESSION_TYPE_VAL="${XDG_SESSION_TYPE:-}"
if [ -z "$SESSION_TYPE_VAL" ]; then
  if [ -n "$WAYLAND_DISPLAY" ]; then SESSION_TYPE_VAL="wayland";
  elif [ -n "$DISPLAY" ]; then SESSION_TYPE_VAL="x11";
  else SESSION_TYPE_VAL="tty"; fi
fi
DISPLAY_VAL="${DISPLAY:-${WAYLAND_DISPLAY:-N/A}}"
if [ "$SESSION_TYPE_VAL" = "wayland" ] && [ -n "$WAYLAND_DISPLAY" ]; then DISPLAY_VAL="$WAYLAND_DISPLAY"; fi
DE_VAL=$(printf '%s' "$DE_VAL" | cut -c 1-22); SESSION_TYPE_VAL=$(printf '%s' "$SESSION_TYPE_VAL" | cut -c 1-22); DISPLAY_VAL=$(printf '%s' "$DISPLAY_VAL" | cut -c 1-22)
if command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then FW="nftables ativo";
elif command -v iptables >/dev/null 2>&1 && iptables -L >/dev/null 2>&1; then FW="iptables ativo";
elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q active; then FW="ufw ativo";
else
  ensure_tool nft
  if command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then FW="nftables ativo"; else FW="nao detectado"; fi
fi
ensure_tools pidof getenforce
if command -v pidof >/dev/null 2>&1 && pidof systemd >/dev/null 2>&1; then INIT_SYS="systemd";
elif [ -d /etc/init.d ]; then INIT_SYS="sysvinit"; else INIT_SYS="desconhecido"; fi
if command -v getenforce >/dev/null 2>&1; then SEC_MOD="SELinux $(getenforce)";
elif [ -d /sys/kernel/security/apparmor ]; then SEC_MOD="AppArmor ativo"; else SEC_MOD="nao ativo"; fi
ensure_tool systemd-detect-virt
if command -v systemd-detect-virt >/dev/null 2>&1; then VIRT=$(systemd-detect-virt 2>/dev/null); else VIRT=""; fi
if [ -z "$VIRT" ]; then VIRT="Bare metal"; fi
ensure_tools uptime timedatectl
UPTIME_V=$(uptime -p 2>/dev/null)
if command -v timedatectl >/dev/null 2>&1; then TZ_V=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null); else TZ_V=$(cat /etc/timezone 2>/dev/null); fi
if [ -z "$TZ_V" ]; then TZ_V="N/A"; fi
ensure_tools awk
MEM_TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
MEM_AVAIL_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
MEM_USED_KB=$(( MEM_TOTAL_KB - MEM_AVAIL_KB ))
SWAP_TOTAL_KB=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
SWAP_FREE_KB=$(awk '/SwapFree/ {print $2}' /proc/meminfo)
SWAP_CACHED_KB=$(awk '/SwapCached/ {print $2}' /proc/meminfo)
if [ -z "$SWAP_TOTAL_KB" ]; then SWAP_TOTAL_KB=0; fi
if [ -z "$SWAP_FREE_KB" ]; then SWAP_FREE_KB=0; fi
if [ -z "$SWAP_CACHED_KB" ]; then SWAP_CACHED_KB=0; fi
SWAP_USED_KB=$(( SWAP_TOTAL_KB - SWAP_FREE_KB ))
MEM_ALL_KB=$(( MEM_TOTAL_KB + SWAP_TOTAL_KB ))
ensure_tools grep cat
_DMI_BIOS=""; _DMI_SYS=""; _DMI_BOARD=""; _DMI_PROC=""; _LSHW=""; _INXI=""; _FWUPD=""; _EFIBOOT=""
if command -v dmidecode >/dev/null 2>&1; then
  _DMI_BIOS=$(LC_ALL=C $SUDO_CMD dmidecode -t bios 2>/dev/null)
  _DMI_SYS=$(LC_ALL=C $SUDO_CMD dmidecode -t system 2>/dev/null)
  _DMI_BOARD=$(LC_ALL=C $SUDO_CMD dmidecode -t baseboard 2>/dev/null)
  _DMI_PROC=$(LC_ALL=C $SUDO_CMD dmidecode -t processor 2>/dev/null)
fi
if command -v lshw >/dev/null 2>&1; then _LSHW=$(LC_ALL=C $SUDO_CMD lshw -short 2>/dev/null | head -n 60); fi
if command -v inxi >/dev/null 2>&1; then _INXI=$(LC_ALL=C inxi -S -M -C 2>/dev/null); fi
if command -v fwupdmgr >/dev/null 2>&1; then _FWUPD=$(LC_ALL=C fwupdmgr get-devices 2>/dev/null | head -n 80); fi
if command -v efibootmgr >/dev/null 2>&1; then _EFIBOOT=$(LC_ALL=C $SUDO_CMD efibootmgr -v 2>/dev/null); fi
VENDOR_V=$(dmi_sys_field "Manufacturer" "sys_vendor")
if [ "$VENDOR_V" = "N/A" ]; then VENDOR_V=$(clean_dmi "$(printf '%s' "$_LSHW" | grep -i -m1 "system" | sed 's/.*system[[:space:]]*//;s/[[:space:]]*$//')"); fi
if [ "$VENDOR_V" = "N/A" ]; then VENDOR_V=$(clean_dmi "$(printf '%s' "$_INXI" | grep -i "Machine:" | sed 's/.*Type:[[:space:]]*//;s/.*Vendor:[[:space:]]*//;s/ Product.*//')"); fi
MODEL_V=$(dmi_sys_field "Product Name" "product_name")
if [ "$MODEL_V" = "N/A" ]; then MODEL_V=$(clean_dmi "$(printf '%s' "$_LSHW" | grep -i -m1 " HP\| Dell\| Lenovo\| ASUS\| Acer" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}')"); fi
if [ "$MODEL_V" = "N/A" ] && [ -n "$_DMI_BOARD" ]; then MODEL_V=$(clean_dmi "$(printf '%s' "$_DMI_BOARD" | grep -i "^[[:space:]]*Product Name:" | head -n 1 | cut -d: -f2-)"); fi
VENDOR_V=$(printf '%s' "$VENDOR_V" | cut -c 1-24); MODEL_V=$(printf '%s' "$MODEL_V" | cut -c 1-26)
CPU_MODEL=""
if command -v lscpu >/dev/null 2>&1; then
  _cand=$(LC_ALL=C lscpu 2>/dev/null | grep -i "^Model name" | cut -d: -f2- | sed 's/^ //;s/[[:space:]]*$//')
  _cand=$(clean_dmi "$_cand")
  if [ -n "$_cand" ] && [ "$_cand" != "N/A" ]; then CPU_MODEL="$_cand"; fi
fi
if [ -z "$CPU_MODEL" ] && [ -f /proc/cpuinfo ]; then
  _cand=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //;s/[[:space:]]*$//')
  _cand=$(clean_dmi "$_cand")
  if [ -n "$_cand" ] && [ "$_cand" != "N/A" ]; then CPU_MODEL="$_cand"; fi
fi
if [ -z "$CPU_MODEL" ] && [ -n "$_DMI_PROC" ]; then
  _cand=$(printf '%s' "$_DMI_PROC" | grep -i "^[[:space:]]*Version:" | head -n 1 | cut -d: -f2- | sed 's/^ //;s/[[:space:]]*$//')
  _cand=$(clean_dmi "$_cand")
  if [ -n "$_cand" ] && [ "$_cand" != "N/A" ]; then CPU_MODEL="$_cand"; fi
fi
if [ -z "$CPU_MODEL" ] && command -v lshw >/dev/null 2>&1; then
  _cand=$(LC_ALL=C $SUDO_CMD lshw -C cpu 2>/dev/null | grep -i -m1 "product:" | cut -d: -f2- | sed 's/^ //;s/[[:space:]]*$//')
  _cand=$(clean_dmi "$_cand")
  if [ -n "$_cand" ] && [ "$_cand" != "N/A" ]; then CPU_MODEL="$_cand"; fi
fi
if [ -z "$CPU_MODEL" ] && command -v inxi >/dev/null 2>&1; then
  _cand=$(LC_ALL=C inxi -C 2>/dev/null | grep -i -m1 "model:" | sed 's/.*model:[[:space:]]*//;s/[[:space:]]*$//')
  _cand=$(clean_dmi "$_cand")
  if [ -n "$_cand" ] && [ "$_cand" != "N/A" ]; then CPU_MODEL="$_cand"; fi
fi
if [ -z "$CPU_MODEL" ] && [ -f /sys/devices/cpu/cpu0/cpufreq/scaling_cur_freq ]; then CPU_MODEL="CPU detectado via /sys (modelo em /proc/cpuinfo indisponivel)"; fi
if [ -z "$CPU_MODEL" ]; then CPU_MODEL="N/A"; fi
CPU_MODEL=$(printf '%s' "$CPU_MODEL")
CPU_DISPLAY=$(printf '%s' "$CPU_MODEL" | sed -e 's/(R)//g' -e 's/(TM)//g' -e 's/  */ /g' -e 's/ CPU @ / @ /' -e 's/^ //;s/ $//')
CPU_CORES=$(grep -c '^processor' /proc/cpuinfo)
if [ -z "$CPU_CORES" ] || [ "$CPU_CORES" = "0" ]; then CPU_CORES=$(LC_ALL=C lscpu 2>/dev/null | grep -i "^CPU(s):" | awk '{print $2}'); fi
CPU_GEN=$(get_cpu_gen "$CPU_MODEL")
FIRMWARE_VENDOR=$(dmi_field "Vendor" "bios_vendor")
if [ "$FIRMWARE_VENDOR" = "N/A" ]; then FIRMWARE_VENDOR=$(clean_dmi "$(printf '%s' "$_INXI" | grep -i "UEFI\|BIOS" | head -n 1 | sed 's/.*UEFI:[[:space:]]*//;s/.*BIOS:[[:space:]]*//')"); fi
FIRMWARE_VER=$(dmi_field "Version" "bios_version")
FIRMWARE_DATE=$(dmi_field "Release Date" "bios_date")
BIOS_REV=$(dmi_field "BIOS Revision" "bios_release")
FW_REV=$(dmi_field "Firmware Revision" "ec_firmware_release")
ROM_SIZE=$(dmi_field "ROM Size" "")
SMBIOS_VER="N/A"
if command -v dmidecode >/dev/null 2>&1; then
  _smbios_raw=$(LC_ALL=C $SUDO_CMD dmidecode 2>/dev/null | grep -i "SMBIOS" | head -n 1)
  if [ -n "$_smbios_raw" ]; then SMBIOS_VER=$(printf '%s' "$_smbios_raw" | sed 's/.*SMBIOS //;s/ present.*//;s/^ //'); fi
fi
if [ "$FIRMWARE_VER" = "N/A" ] && [ -n "$_FWUPD" ]; then
  _fwv=$(printf '%s' "$_FWUPD" | grep -i -A2 "System Firmware" | grep -i "Current version" | head -n 1 | cut -d: -f2- | sed 's/^ //')
  if [ -n "$_fwv" ]; then FIRMWARE_VER=$(clean_dmi "$_fwv"); fi
fi
if [ -z "$FIRMWARE_VER" ]; then FIRMWARE_VER="N/A"; fi
if [ -z "$FIRMWARE_DATE" ]; then FIRMWARE_DATE="N/A"; fi
if [ -z "$FIRMWARE_VENDOR" ]; then FIRMWARE_VENDOR="N/A"; fi
if [ -z "$BIOS_REV" ]; then BIOS_REV="N/A"; fi
if [ -z "$FW_REV" ]; then FW_REV="N/A"; fi
if [ -z "$ROM_SIZE" ]; then ROM_SIZE="N/A"; fi
if [ -z "$SMBIOS_VER" ]; then SMBIOS_VER="N/A"; fi
FIRMWARE_VER=$(printf '%s' "$FIRMWARE_VER" | cut -c 1-22)
FIRMWARE_DATE=$(printf '%s' "$FIRMWARE_DATE" | cut -c 1-22)
FIRMWARE_VENDOR=$(printf '%s' "$FIRMWARE_VENDOR" | cut -c 1-22)
BIOS_REV=$(printf '%s' "$BIOS_REV" | cut -c 1-22); FW_REV=$(printf '%s' "$FW_REV" | cut -c 1-22)
ROM_SIZE=$(printf '%s' "$ROM_SIZE" | cut -c 1-22); SMBIOS_VER=$(printf '%s' "$SMBIOS_VER" | cut -c 1-22)
_EFI_PRESENT=0; _EFIBOOT_OK=0
if [ -d /sys/firmware/efi ]; then _EFI_PRESENT=1; fi
if printf '%s' "$_EFIBOOT" | grep -q "Boot[0-9A-F]"; then _EFIBOOT_OK=1; fi
if [ "$_EFI_PRESENT" = "1" ] || [ "$_EFIBOOT_OK" = "1" ]; then
  BOOT_MODE="UEFI"; FIRMWARE_CLASS="UEFI (Classe 2 - UEFI)"
else
  BOOT_MODE="BIOS Legacy"; FIRMWARE_CLASS="BIOS (Classe 0 - PC-AT BIOS)"
fi
DISK_TABLE="N/A"; BOOT_DISK="N/A"; BOOT_DISK_NAME=""
ensure_tool lsblk; ensure_tool findmnt
_BOOT_SRC=""
if command -v findmnt >/dev/null 2>&1; then _BOOT_SRC=$(LC_ALL=C findmnt -n -o SOURCE /boot 2>/dev/null | head -n 1); fi
if [ -z "$_BOOT_SRC" ] && command -v findmnt >/dev/null 2>&1; then _BOOT_SRC=$(LC_ALL=C findmnt -n -o SOURCE / 2>/dev/null | head -n 1); fi
if [ -z "$_BOOT_SRC" ]; then _BOOT_SRC=$(LC_ALL=C df /boot 2>/dev/null | tail -n 1 | awk '{print $1}'); fi
if [ -z "$_BOOT_SRC" ]; then _BOOT_SRC=$(LC_ALL=C df / 2>/dev/null | tail -n 1 | awk '{print $1}'); fi
_BOOT_SRC=$(printf '%s' "$_BOOT_SRC" | sed 's/\[//g;s/\]//g')
if [ -n "$_BOOT_SRC" ]; then BOOT_DISK_NAME=$(resolve_boot_disk_name "$_BOOT_SRC" 2>/dev/null); fi
if [ -n "$BOOT_DISK_NAME" ]; then BOOT_DISK="/dev/$BOOT_DISK_NAME"; fi
if [ -n "$BOOT_DISK" ] && [ "$BOOT_DISK" != "N/A" ]; then
  _SIG_TABLE=$(detect_pttype_signature "$BOOT_DISK" 2>/dev/null)
  if [ -n "$_SIG_TABLE" ]; then DISK_TABLE="$_SIG_TABLE"; else DISK_TABLE="N/A"; fi
fi
BOOT_PART_TYPE="N/A"
if [ "$DISK_TABLE" = "GPT" ] && [ -n "$BOOT_DISK" ] && [ "$BOOT_DISK" != "N/A" ]; then
  if command -v sfdisk >/dev/null 2>&1; then
    _sfd_out=$(LC_ALL=C $SUDO_CMD sfdisk -l "$BOOT_DISK" 2>/dev/null)
    if printf '%s' "$_sfd_out" | grep -qi "BIOS boot"; then BOOT_PART_TYPE="EF02 BIOS Boot";
    elif printf '%s' "$_sfd_out" | grep -qi "EFI System"; then BOOT_PART_TYPE="EF00 ESP"; fi
  fi
  if [ "$BOOT_PART_TYPE" = "N/A" ] && command -v parted >/dev/null 2>&1; then
    _pd_out=$(LC_ALL=C $SUDO_CMD parted -s "$BOOT_DISK" print 2>/dev/null)
    if printf '%s' "$_pd_out" | grep -qi "bios_grub"; then BOOT_PART_TYPE="EF02 BIOS Boot";
    elif printf '%s' "$_pd_out" | grep -qi "esp"; then BOOT_PART_TYPE="EF00 ESP"; fi
  fi
fi
if [ -z "$DISK_TABLE" ]; then DISK_TABLE="N/A"; fi
if [ -z "$BOOT_DISK" ]; then BOOT_DISK="N/A"; fi
BOOT_INFO="$BOOT_MODE / $DISK_TABLE"
if [ "$BOOT_PART_TYPE" != "N/A" ]; then BOOT_DISK_INFO="$BOOT_DISK ($DISK_TABLE - $BOOT_PART_TYPE)"; else BOOT_DISK_INFO="$BOOT_DISK ($DISK_TABLE)"; fi
BOOT_DISK_INFO=$(printf '%s' "$BOOT_DISK_INFO" | cut -c 1-28)
GPU_MODEL="N/A"
if command -v lspci >/dev/null 2>&1; then
  _gpus=""
  while IFS= read -r _gl; do
    _gclean=$(printf '%s' "$_gl" | sed 's/^.*: //;s/ (rev.*//;s/ Corporation//;s/ Inc\.//;s/  */ /g;s/^ //;s/ $//')
    if [ -n "$_gclean" ]; then
      if [ -z "$_gpus" ]; then _gpus="$_gclean"; else _gpus="$_gpus + $_gclean"; fi
    fi
  done < <(LC_ALL=C lspci 2>/dev/null | grep -i -E 'VGA|3D controller')
  if [ -n "$_gpus" ]; then GPU_MODEL="$_gpus"; fi
fi
BAT_CAP="N/A"; BAT_STATUS="N/A"; BAT_HEALTH="N/A"; BAT_CYCLES="N/A"
for _bat in /sys/class/power_supply/BAT* /sys/class/power_supply/battery*; do
  if [ -d "$_bat" ]; then
    _s=$(cat "$_bat/status" 2>/dev/null); if [ -n "$_s" ]; then BAT_STATUS="$_s"; fi
    _c=$(cat "$_bat/capacity" 2>/dev/null); if [ -n "$_c" ]; then BAT_CAP="$_c%"; fi
    if [ "$BAT_CAP" = "N/A" ]; then
      _now=$(cat "$_bat/charge_now" 2>/dev/null); _full=$(cat "$_bat/charge_full" 2>/dev/null)
      if [ -z "$_now" ]; then _now=$(cat "$_bat/energy_now" 2>/dev/null); _full=$(cat "$_bat/energy_full" 2>/dev/null); fi
      if [ -n "$_now" ] && [ -n "$_full" ] && [ "$_full" != "0" ]; then BAT_CAP=$(( _now * 100 / _full )); BAT_CAP="$BAT_CAP%"; fi
    fi
    _full=$(cat "$_bat/energy_full" 2>/dev/null); _design=$(cat "$_bat/energy_full_design" 2>/dev/null)
    if [ -z "$_full" ] || [ -z "$_design" ]; then _full=$(cat "$_bat/charge_full" 2>/dev/null); _design=$(cat "$_bat/charge_full_design" 2>/dev/null); fi
    if [ -n "$_full" ] && [ -n "$_design" ] && [ "$_design" != "0" ]; then BAT_HEALTH=$(( _full * 100 / _design )); BAT_HEALTH="$BAT_HEALTH%"; fi
    _cy=$(cat "$_bat/cycle_count" 2>/dev/null); if [ -n "$_cy" ]; then BAT_CYCLES="$_cy"; fi
    break
  fi
done
SMART_STATUS="N/A"; SMART_HOURS="N/A"
if [ -n "$BOOT_DISK" ] && [ "$BOOT_DISK" != "N/A" ] && command -v smartctl >/dev/null 2>&1; then
  _sm=$(LC_ALL=C $SUDO_CMD smartctl -H "$BOOT_DISK" 2>/dev/null | grep -i -m1 'self-assessment\|SMART overall' | sed 's/.*: //')
  if [ -n "$_sm" ]; then SMART_STATUS="$_sm"; fi
  _hr=$(LC_ALL=C $SUDO_CMD smartctl -A "$BOOT_DISK" 2>/dev/null | grep -i -m1 'Power_On_Hours' | awk '{print $NF}')
  if [ -n "$_hr" ]; then SMART_HOURS="${_hr}h"; fi
fi
PKG_COUNT="N/A"; UPDATES="N/A"
if command -v dpkg-query >/dev/null 2>&1; then PKG_COUNT=$(dpkg-query -l 2>/dev/null | grep -c '^ii'); fi
if command -v rpm >/dev/null 2>&1; then PKG_COUNT=$(rpm -qa 2>/dev/null | wc -l | tr -d ' '); fi
if command -v pacman >/dev/null 2>&1; then PKG_COUNT=$(pacman -Q 2>/dev/null | wc -l | tr -d ' '); fi
if command -v apt-get >/dev/null 2>&1; then UPDATES=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst'); fi
if command -v dnf >/dev/null 2>&1; then UPDATES=$(dnf check-update --quiet 2>/dev/null | grep -cv '^$'); fi
LOGGED_N="0"; LOGGED_USERS="N/A"
if command -v who >/dev/null 2>&1; then
  LOGGED_N=$(who 2>/dev/null | wc -l | tr -d ' ')
  _lu=$(who 2>/dev/null | awk '{print $1}' | sort -u | tr '
' ',' | sed 's/,$//')
  if [ -n "$_lu" ]; then LOGGED_USERS="$_lu"; fi
fi
LAST_BOOT="N/A"
if command -v uptime >/dev/null 2>&1; then _lb=$(uptime -s 2>/dev/null); if [ -n "$_lb" ]; then LAST_BOOT="$_lb"; fi; fi
if [ "$LAST_BOOT" = "N/A" ] && command -v who >/dev/null 2>&1; then _lb=$(who -b 2>/dev/null | awk '{print $3, $4}'); if [ -n "$_lb" ]; then LAST_BOOT="$_lb"; fi; fi
if [ "$BOOT_MODE" = "BIOS Legacy" ]; then
  SECURE_BOOT="N/A (Legacy)"
else
  SECURE_BOOT="N/A"
  if command -v mokutil >/dev/null 2>&1; then
    _sb=$(LC_ALL=C mokutil --sb-state 2>/dev/null)
    case "$_sb" in *enabled*) SECURE_BOOT="Ativado" ;; *disabled*) SECURE_BOOT="Desativado" ;; esac
  fi
  if [ "$SECURE_BOOT" = "N/A" ] && command -v efivar >/dev/null 2>&1; then
    _ef=$(LC_ALL=C efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SecureBoot 2>/dev/null | od -An -t u1 2>/dev/null | awk '{print $NF}')
    if [ "$_ef" = "1" ]; then SECURE_BOOT="Ativado"; elif [ "$_ef" = "0" ]; then SECURE_BOOT="Desativado"; fi
  fi
  if [ "$SECURE_BOOT" = "N/A" ]; then
    _sbfile=$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -n 1)
    if [ -n "$_sbfile" ]; then
      _sbval=$(od -An -t u1 "$_sbfile" 2>/dev/null | awk '{print $NF}')
      if [ "$_sbval" = "1" ]; then SECURE_BOOT="Ativado"; elif [ "$_sbval" = "0" ]; then SECURE_BOOT="Desativado"; fi
    fi
  fi
  if [ "$SECURE_BOOT" = "N/A" ] && command -v bootctl >/dev/null 2>&1; then
    _bc=$(LC_ALL=C bootctl status 2>/dev/null | grep -i "Secure Boot" | head -n 1)
    case "$_bc" in *enabled*) SECURE_BOOT="Ativado" ;; *disabled*) SECURE_BOOT="Desativado" ;; esac
  fi
fi
collect_temps
ensure_tools df
DF_OUT=$(LC_ALL=C df -h --output=target,pcent,size,used,avail 2>/dev/null | tail -n +2)
STORAGE_LINES=()
while IFS= read -r _line; do STORAGE_LINES[${#STORAGE_LINES[@]}]="$_line"; done <<EOF_DF
$DF_OUT
EOF_DF
UMASK_VAL=$(umask)
ensure_tools ip hostname curl
NET_PRIMARY_EARLY=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1)
NET_IP_EARLY=$(ip -4 -o addr show "$NET_PRIMARY_EARLY" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)
if [ -z "$NET_IP_EARLY" ]; then NET_IP_EARLY=$(hostname -I 2>/dev/null | awk '{print $1}'); fi
ensure_tool nmap; ensure_tool ufw; ensure_tool ss; ensure_tool lsof
NMAP_CMD="nmap -sS -sU -sV -p- --open -T4 127.0.0.1"; UFW_CMD="ufw status"; SS_CMD="ss -tulnp"; PORTS_LINES=()
if [ "$CHECK_MODE" = "0" ] && command -v nmap >/dev/null 2>&1; then
  _nmap_out=$(nmap -sS -sU -sV -p- --open -T4 127.0.0.1 2>/dev/null)
  while IFS= read -r _pl; do
    case "$_pl" in
      *"/tcp open"*|*"/udp open"*)
        _portproto=$(printf '%s' "$_pl" | awk '{print $1}'); _svc=$(printf '%s' "$_pl" | awk '{print $3}')
        if [ -z "$_svc" ]; then _svc="open"; fi
        add_port_unique "$_portproto" "$_svc" ;;
    esac
  done <<EOF_NMAP
$_nmap_out
EOF_NMAP
  if [ -n "$NET_IP_EARLY" ] && [ "$NET_IP_EARLY" != "127.0.0.1" ]; then
    _nmap_out2=$(nmap -sS -sU -sV -p- --open -T4 "$NET_IP_EARLY" 2>/dev/null)
    while IFS= read -r _pl; do
      case "$_pl" in
        *"/tcp open"*|*"/udp open"*)
          _portproto=$(printf '%s' "$_pl" | awk '{print $1}'); _svc=$(printf '%s' "$_pl" | awk '{print $3}')
          if [ -z "$_svc" ]; then _svc="open"; fi
          add_port_unique "$_portproto" "$_svc" ;;
      esac
    done <<EOF_NMAP2
$_nmap_out2
EOF_NMAP2
  fi
fi
if command -v ss >/dev/null 2>&1; then
  _ss_out=$(ss -tulnp 2>/dev/null | tail -n +2)
  while IFS= read -r _sl; do
    _proto=$(printf '%s' "$_sl" | awk '{print $1}'); _local=$(printf '%s' "$_sl" | awk '{print $5}')
    _port=$(printf '%s' "$_local" | sed 's/.*://' | tr -d '[]')
    case "$_port" in ''|*[!0-9]*) continue ;; esac
    _ps="tcp"; case "$_proto" in *udp*|*UDP*|*u*) _ps="udp" ;; esac
    _proc=$(printf '%s' "$_sl" | grep -o '"[^"]*"' | head -n 1 | tr -d '"')
    if [ -n "$_proc" ]; then
      case "$_proc" in *apache*|*httpd*) add_port_unique "$_port/$_ps" "http" ;; *nginx*) add_port_unique "$_port/$_ps" "http" ;; *) add_port_unique "$_port/$_ps" "ss" ;; esac
    else add_port_unique "$_port/$_ps" "ss"; fi
  done <<EOF_SS
$_ss_out
EOF_SS
  _ss_out2=$(ss -tnp 2>/dev/null | tail -n +2)
  while IFS= read -r _sl; do
    _local=$(printf '%s' "$_sl" | awk '{print $4}')
    _port=$(printf '%s' "$_local" | sed 's/.*://' | tr -d '[]')
    case "$_port" in ''|*[!0-9]*) continue ;; esac
    add_port_unique "$_port/tcp" "ss"
  done <<EOF_SS2
$_ss_out2
EOF_SS2
fi
for _pf in /proc/net/tcp /proc/net/tcp6; do
  if [ -f "$_pf" ]; then
    while IFS= read -r _nl; do
      case "$_nl" in sl*|*local_address*) continue ;; esac
      _la=$(printf '%s' "$_nl" | awk '{print $2}'); _st=$(printf '%s' "$_nl" | awk '{print $4}')
      if [ "$_st" != "0A" ]; then continue; fi
      _hexport=$(printf '%s' "$_la" | cut -d: -f2)
      case "$_hexport" in ''|*[!0-9A-Fa-f]*) continue ;; esac
      _decport=$(( 16#$_hexport ))
      add_port_unique "$_decport/tcp" "proc"
    done < "$_pf"
  fi
done
for _pf in /proc/net/udp /proc/net/udp6; do
  if [ -f "$_pf" ]; then
    while IFS= read -r _nl; do
      case "$_nl" in sl*|*local_address*) continue ;; esac
      _la=$(printf '%s' "$_nl" | awk '{print $2}')
      _hexport=$(printf '%s' "$_la" | cut -d: -f2)
      case "$_hexport" in ''|*[!0-9A-Fa-f]*) continue ;; esac
      _decport=$(( 16#$_hexport ))
      add_port_unique "$_decport/udp" "proc"
    done < "$_pf"
  fi
done
if command -v lsof >/dev/null 2>&1; then
  _lsof_out=$(lsof -i -P -n -sTCP:LISTEN 2>/dev/null | tail -n +2)
  while IFS= read -r _ll; do
    _name=$(printf '%s' "$_ll" | awk '{print $9}')
    _port=$(printf '%s' "$_name" | sed 's/.*://' | tr -d '[]')
    case "$_port" in ''|*[!0-9]*) continue ;; esac
    _proc=$(printf '%s' "$_ll" | awk '{print $1}')
    case "$_proc" in *apache*|*httpd*) add_port_unique "$_port/tcp" "http" ;; *nginx*) add_port_unique "$_port/tcp" "http" ;; *) add_port_unique "$_port/tcp" "lsof" ;; esac
  done <<EOF_LSOF
$_lsof_out
EOF_LSOF
  _lsof_udp=$(lsof -iUDP -P -n 2>/dev/null | tail -n +2)
  while IFS= read -r _ll; do
    _name=$(printf '%s' "$_ll" | awk '{print $9}')
    _port=$(printf '%s' "$_name" | sed 's/.*://' | tr -d '[]')
    case "$_port" in ''|*[!0-9]*) continue ;; esac
    add_port_unique "$_port/udp" "lsof"
  done <<EOF_LSOFU
$_lsof_udp
EOF_LSOFU
fi
UFW_STATUS="nao instalado"
if command -v ufw >/dev/null 2>&1; then
  _ufw_stat=$($SUDO_CMD ufw status 2>/dev/null || ufw status 2>/dev/null)
  if printf '%s' "$_ufw_stat" | grep -qi "Status: active"; then UFW_STATUS="ufw ativo";
  elif printf '%s' "$_ufw_stat" | grep -qi "Status: inactive"; then UFW_STATUS="ufw inativo";
  else UFW_STATUS="ufw desconhecido"; fi
  _ufw_all="$_ufw_stat"
  _ufw_all="$_ufw_all
$($SUDO_CMD ufw status numbered 2>/dev/null || ufw status numbered 2>/dev/null)"
  _ufw_all="$_ufw_all
$($SUDO_CMD ufw show added 2>/dev/null || ufw show added 2>/dev/null)"
  while IFS= read -r _ul; do
    case "$_ul" in
      *"ALLOW"*|*"allow"*|*"ufw allow"*)
        _rest=$(printf '%s' "$_ul" | tr ',' ' ')
        for _tok in $_rest; do
          case "$_tok" in
            [0-9]*/tcp|[0-9]*/udp) add_port_unique "$_tok" "ufw" ;;
            [0-9]*":"[0-9]*"/tcp"|[0-9]*":"[0-9]*"/udp") add_port_unique "$_tok" "ufw" ;;
            [0-9]*) case "$_ul" in *"allow $_tok"*|*"allow  $_tok"*) add_port_unique "$_tok/tcp" "ufw" ;; esac ;;
          esac
        done ;;
    esac
  done <<EOF_UFW
$_ufw_all
EOF_UFW
fi
PORTS_TOTAL=${#PORTS_LINES[@]}
PORTS_TCP=0; PORTS_UDP=0; _ci=0
while [ "$_ci" -lt "${#PORTS_LINES[@]}" ]; do
  case "${PORTS_LINES[$_ci]}" in *"/tcp"*) PORTS_TCP=$(( PORTS_TCP + 1 )) ;; *"/udp"*) PORTS_UDP=$(( PORTS_UDP + 1 )) ;; esac
  _ci=$(( _ci + 1 ))
done
ensure_tools ip
WIFI_IFACE="N/A"; WIFI_SSID="N/A"; WIFI_SIGNAL="N/A"; WIFI_IP="N/A"; WIFI_MAC="N/A"; WIFI_STATE="desconectado"; WIFI_FREQ="N/A"
WIFI_CMD="nmcli dev status"
if [ "$HAS_WIFI" = "1" ]; then
  ensure_tools nmcli iw
  if command -v nmcli >/dev/null 2>&1; then
    WIFI_IFACE=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep ":wifi" | cut -d: -f1 | head -n 1)
    if [ -n "$WIFI_IFACE" ]; then
      WIFI_SSID=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | grep "^yes" | cut -d: -f2 | head -n 1)
      if [ -z "$WIFI_SSID" ]; then WIFI_SSID="N/A"; fi
      WIFI_SIGNAL=$(nmcli -t -f ACTIVE,SIGNAL dev wifi 2>/dev/null | grep "^yes" | cut -d: -f2 | head -n 1)
      if [ -n "$WIFI_SIGNAL" ]; then WIFI_SIGNAL="${WIFI_SIGNAL}%"; else WIFI_SIGNAL="N/A"; fi
      WIFI_STATE=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^${WIFI_IFACE}:" | cut -d: -f2)
      if [ -z "$WIFI_STATE" ]; then WIFI_STATE="N/A"; fi
    fi
  else WIFI_CMD="iw dev"; fi
  if [ "$WIFI_IFACE" = "N/A" ] || [ -z "$WIFI_IFACE" ]; then
    if command -v iw >/dev/null 2>&1; then WIFI_IFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -n 1); fi
    if [ -z "$WIFI_IFACE" ]; then WIFI_IFACE="N/A"; fi
  fi
  if [ "$WIFI_IFACE" != "N/A" ]; then
    WIFI_IP=$(ip -4 -o addr show "$WIFI_IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)
    if [ -z "$WIFI_IP" ]; then WIFI_IP="N/A"; fi
    WIFI_MAC=$(ip link show "$WIFI_IFACE" 2>/dev/null | grep "link/ether" | awk '{print $2}' | head -n 1)
    if [ -z "$WIFI_MAC" ]; then WIFI_MAC="N/A"; fi
    if command -v iw >/dev/null 2>&1; then
      WIFI_FREQ=$(iw dev "$WIFI_IFACE" link 2>/dev/null | grep "freq:" | awk '{print $2" MHz"}' | head -n 1)
      if [ -z "$WIFI_FREQ" ]; then WIFI_FREQ="N/A"; fi
    fi
  fi
fi
case "$WIFI_STATE" in
  *connected*|*conectado*|*up*) WIFI_ATIVO="ATIVO" ;;
  *) if [ "$WIFI_IP" != "N/A" ]; then WIFI_ATIVO="ATIVO"; else WIFI_ATIVO="INATIVO"; fi ;;
esac
ensure_tools ip hostname curl
NET_IFACES=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v "^lo" | tr '\n' ',' | sed 's/,$//')
if [ -z "$NET_IFACES" ]; then NET_IFACES="N/A"; fi
NET_IFACES=$(printf '%s' "$NET_IFACES" | cut -c 1-26)
NET_PRIMARY=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1)
if [ -z "$NET_PRIMARY" ]; then NET_PRIMARY="N/A"; fi
NET_IP=$(ip -4 -o addr show "$NET_PRIMARY" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)
if [ -z "$NET_IP" ]; then NET_IP=$(hostname -I 2>/dev/null | awk '{print $1}'); fi
if [ -z "$NET_IP" ]; then NET_IP="N/A"; fi
NET_GW=$(ip route show default 2>/dev/null | awk '{print $3}' | head -n 1)
if [ -z "$NET_GW" ]; then NET_GW="N/A"; fi
NET_DNS=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
if [ -z "$NET_DNS" ]; then NET_DNS="N/A"; fi
NET_DNS=$(printf '%s' "$NET_DNS" | cut -c 1-28)
NET_MAC=$(ip link show "$NET_PRIMARY" 2>/dev/null | grep "link/ether" | awk '{print $2}' | head -n 1)
if [ -z "$NET_MAC" ]; then NET_MAC="N/A"; fi
NET_MTU=$(ip link show "$NET_PRIMARY" 2>/dev/null | grep -o "mtu [0-9]*" | awk '{print $2}' | head -n 1)
if [ -z "$NET_MTU" ]; then NET_MTU="N/A"; fi
EXT_IP=$(get_ext_ip)
NET_CMD="ip link show $NET_PRIMARY"
if ip link show "$NET_PRIMARY" 2>/dev/null | grep -q "state UP"; then NET_ATIVO="ATIVO"; else NET_ATIVO="INATIVO"; fi
ensure_tool systemctl
mgr_ver() {
  if command -v "$1" >/dev/null 2>&1; then
    _v=$("$1" --version 2>/dev/null | head -n 1 | cut -c 1-22)
    if [ -z "$_v" ]; then _v="instalado"; fi
    printf '%s' "$_v"
  else printf 'nao instalado'; fi
}
APT_V=$(mgr_ver apt); DPKG_V=$(mgr_ver dpkg); DNF_V=$(mgr_ver dnf); YUM_V=$(mgr_ver yum)
PACMAN_V=$(mgr_ver pacman); ZYPPER_V=$(mgr_ver zypper); SNAP_V=$(mgr_ver snap); FLATPAK_V=$(mgr_ver flatpak)
if command -v systemctl >/dev/null 2>&1; then SVC_MGR="systemd $(systemctl --version 2>/dev/null | head -n 1 | awk '{print $2}')";
elif [ -d /etc/init.d ]; then SVC_MGR="sysvinit";
elif command -v rc-service >/dev/null 2>&1; then SVC_MGR="OpenRC";
else SVC_MGR="$INIT_SYS"; fi
SVC_MGR=$(printf '%s' "$SVC_MGR" | cut -c 1-24)
BROWSER_LINES=()
add_browser() {
  _cmd="$1"; _name="$2"
  if command -v "$_cmd" >/dev/null 2>&1; then
    _dup=0; _di=0
    while [ "$_di" -lt "${#BROWSER_LINES[@]}" ]; do
      if [ "$(printf '%s' "${BROWSER_LINES[$_di]}" | cut -d: -f1)" = "$_name" ]; then _dup=1; break; fi
      _di=$(( _di + 1 ))
    done
    if [ "$_dup" = "0" ]; then
      _bv=$("$_cmd" --version 2>/dev/null | head -n 1 | sed -e 's/Google Chrome/Chrome/' -e 's/Chromium/Chromium/' -e 's/Mozilla Firefox/ Firefox/' | cut -c 1-24)
      if [ -z "$_bv" ]; then _bv="instalado"; fi
      BROWSER_LINES[${#BROWSER_LINES[@]}]="$_name: $_bv"
    fi
  fi
}
add_browser google-chrome "Chrome"; add_browser google-chrome-stable "Chrome"
add_browser chromium "Chromium"; add_browser chromium-browser "Chromium"
add_browser firefox "Firefox"; add_browser firefox-esr "Firefox ESR"
add_browser brave-browser "Brave"; add_browser brave "Brave"
add_browser microsoft-edge "Edge"; add_browser microsoft-edge-stable "Edge"
add_browser opera " Opera"; add_browser vivaldi "Vivaldi"; add_browser tor-browser "Tor"
add_browser librewolf "LibreWolf"; add_browser floorp "Floorp"; add_browser zen "Zen"
ST_FMT=(); _si=0
while [ "$_si" -lt "${#STORAGE_LINES[@]}" ]; do
  _raw="${STORAGE_LINES[$_si]}"
  _mount=$(printf '%s' "$_raw" | awk '{print $1}'); _pct=$(printf '%s' "$_raw" | awk '{print $2}')
  _size=$(printf '%s' "$_raw" | awk '{print $3}'); _used=$(printf '%s' "$_raw" | awk '{print $4}'); _avail=$(printf '%s' "$_raw" | awk '{print $5}')
  _mcut=$(printf '%s' "$_mount" | cut -c 1-8)
  _full=$(printf '%-8s %4s %6s %6s %6s' "$_mcut" "$_pct" "$_size" "$_used" "$_avail")
  _grande=$(is_large_free "$_avail")
  ST_FMT[${#ST_FMT[@]}]="ST:${_grande}|${_full}"
  _si=$(( _si + 1 ))
done
ST_HEADER=$(printf '%-8s %4s %6s %6s %6s' "MONTE" "USO%" "TOTAL" "USADO" "LIVRE")
if [ "$CHECK_MODE" = "1" ]; then
  printf 'LINUX - InventoryTaker - CHECK\n'
  chk() { if [ -z "$2" ] || [ "$2" = "N/A" ]; then printf '[N/A] %s\n' "$1"; else printf '[OK] %s: %s\n' "$1" "$2"; fi; }
  chk "Fabricante" "$VENDOR_V"
  chk "Modelo" "$MODEL_V"
  chk "CPU" "$CPU_DISPLAY"
  chk "Geracao" "$CPU_GEN"
  chk "Video" "$GPU_MODEL"
  chk "Bateria" "$BAT_CAP"
  chk "SMART" "$SMART_STATUS"
  chk "Disco Boot" "$BOOT_DISK_INFO"
  chk "Firmware" "$FIRMWARE_VENDOR"
  chk "IP" "$NET_IP"
  chk "Gateway" "$NET_GW"
  chk "RAM Total (KB)" "$MEM_TOTAL_KB"
  chk "Swap Total (KB)" "$SWAP_TOTAL_KB"
  chk "Pacotes" "$PKG_COUNT"
  chk "Atualizacoes" "$UPDATES"
  chk "Logados" "$LOGGED_USERS"
  chk "Ultimo Boot" "$LAST_BOOT"
  printf 'Portas (nmap pulado no check): %s\n' "$PORTS_TOTAL"
  printf 'Ferramentas ausentes:\n'
  for _ct in dmidecode lscpu lsblk smartctl lspci ss uptime who; do if ! command -v "$_ct" >/dev/null 2>&1; then printf ' - %s\n' "$_ct"; fi; done
  exit 0
fi
add_L "__TOP__" 3; add_L "01  PORTAS ABERTAS" 1; add_L "__SEP__" 2
if [ "$PORTS_TOTAL" -eq 0 ]; then
  add_L " Nenhuma porta aberta" 0; add_L " TCP: 0" 0; add_L " UDP: 0" 0; add_L " Firewall: $UFW_STATUS" 0; add_L "" 0; add_L " command:" 0; add_L "" 0; add_L " $NMAP_CMD" 0; add_L "" 0; add_L " Total: $PORTS_TOTAL" 0
else
  _pi=0
  while [ "$_pi" -lt "${#PORTS_LINES[@]}" ]; do add_L " Porta: ${PORTS_LINES[$_pi]}" 0; _pi=$(( _pi + 1 )); done
  add_L " TCP: $PORTS_TCP" 0; add_L " UDP: $PORTS_UDP" 0; add_L " Firewall: $UFW_STATUS" 0
  add_L "" 0; add_L " command:" 0; add_L "" 0
  add_L " $NMAP_CMD" 0; add_L " $UFW_CMD" 0; add_L " $SS_CMD" 0; add_L "" 0; add_L " Total: $PORTS_TOTAL" 0
fi
add_M "__TOP__" 3; add_M "02  HARDWARE" 1; add_M "__SEP__" 2
add_M " Fabricante: ${VENDOR_V:-N/A}" 0
add_M " Modelo: ${MODEL_V:-N/A}" 0
add_M " CPU: ${CPU_DISPLAY:-N/A}" 0
add_M " Geracao: $CPU_GEN" 0
add_M " Nucleos: $CPU_CORES" 0
add_M " Disco: $BOOT_DISK_INFO" 0
add_M " Video: $GPU_MODEL" 0
add_M " SMART: $SMART_STATUS ($SMART_HOURS)" 0
if [ "$BAT_CAP" = "N/A" ]; then add_M " Bateria: N/A (sem bateria)" 0; else add_M " Bateria: $BAT_CAP ($BAT_STATUS)" 0; add_M " Saude Bateria: $BAT_HEALTH (Ciclos: $BAT_CYCLES)" 0; fi
add_M "__SEP__" 2
add_M " Temperatura:" 4
add_M " CPU: $TEMP_CPU" 0
add_M " GPU: $TEMP_GPU" 0
add_M " Disco: $TEMP_DISK" 0
add_M " Placa: $TEMP_BOARD" 0
add_M "__SEP__" 2
add_M " Firmware: $FIRMWARE_VENDOR" 0
add_M " Versao: $FIRMWARE_VER" 0
add_M " Data: $FIRMWARE_DATE" 0
add_M " Classe: $FIRMWARE_CLASS" 0
add_M " Rev BIOS: $BIOS_REV" 0
add_M " Rev FW: $FW_REV" 0
add_M " ROM: $ROM_SIZE" 0
add_M " SMBIOS: $SMBIOS_VER" 0
add_R "__TOP__" 3; add_R "03  GERENCIADORES" 1; add_R "__SEP__" 2
add_R " Servicos: $SVC_MGR" 0
add_R " apt: $APT_V" 0; add_R " dpkg: $DPKG_V" 0; add_R " dnf: $DNF_V" 0; add_R " yum: $YUM_V" 0
add_R " pacman: $PACMAN_V" 0; add_R " zypper: $ZYPPER_V" 0; add_R " snap: $SNAP_V" 0; add_R " flatpak: $FLATPAK_V" 0
add_R "__SEP__" 2; add_R "" 0; add_R " Browsers:" 4; add_R "" 0
if [ "${#BROWSER_LINES[@]}" -eq 0 ]; then add_R " Nenhum browser encontrado" 0;
else _bi=0; while [ "$_bi" -lt "${#BROWSER_LINES[@]}" ]; do add_R " ${BROWSER_LINES[$_bi]}" 0; _bi=$(( _bi + 1 )); done; fi
add_R "" 0
add_bottom_trio; print_trio; print_close
add_L "__TOP__" 3; add_L "04  REDES" 1; add_L "__SEP__" 2
add_L " Interfaces: $NET_IFACES" 0; add_L " Principal: $NET_PRIMARY" 0; add_L " IP: $NET_IP" 0; add_L " IP Ext: $EXT_IP" 0
add_L " Gateway: $NET_GW" 0; add_L " DNS: $NET_DNS" 0; add_L " MAC: $NET_MAC" 0; add_L " MTU: $NET_MTU" 0
add_L "" 0; add_L "command: $NET_CMD $NET_ATIVO" 6; add_L "" 0
add_M "__TOP__" 3; add_M "05  MEMORIA RAM + SWAP" 1; add_M "__SEP__" 2
add_M " RAM Total: $(to_gb "$MEM_TOTAL_KB")" 0; add_M " RAM Uso: $(to_gb "$MEM_USED_KB")" 0; add_M " RAM Livre: $(to_gb "$MEM_AVAIL_KB")" 0
add_M "__SEP__" 2
add_M " Swap Total: $(to_gb "$SWAP_TOTAL_KB")" 0; add_M " Swap Uso: $(to_gb "$SWAP_USED_KB")" 0
add_M " Swap Livre: $(to_gb "$SWAP_FREE_KB")" 0; add_M " Swap Cached: $(to_gb "$SWAP_CACHED_KB")" 0; add_M " Total RAM+Swap: $(to_gb "$MEM_ALL_KB")" 0
add_M " swapon: sudo swapon -a (ativar)" 0
add_M " swapoff: sudo swapoff -a (desativar)" 0
add_R "__TOP__" 3; add_R "06  WIFI" 1; add_R "__SEP__" 2
add_R " Interface: $WIFI_IFACE" 0; add_R " SSID: $WIFI_SSID" 0; add_R " Sinal: $WIFI_SIGNAL" 0; add_R " IP: $WIFI_IP" 0
add_R " IP Ext: $EXT_IP" 0; add_R " MAC: $WIFI_MAC" 0; add_R " Estado: $WIFI_STATE" 0; add_R " Freq: $WIFI_FREQ" 0
add_R "" 0; add_R "command: $WIFI_CMD $WIFI_ATIVO" 6; add_R "" 0
add_bottom_trio; print_trio; print_close
add_L "__TOP__" 3; add_L "07  AMBIENTE & RUNTIME" 1; add_L "__SEP__" 2
add_L " Ambiente: $DE_VAL" 0; add_L " Sessao: $SESSION_TYPE_VAL" 0; add_L " Display: $DISPLAY_VAL" 0; add_L "__SEP__" 2
add_L " Shell: $SHELL_V" 0; add_L " Init: $INIT_SYS" 0; add_L " Firewall: $FW" 0; add_L " Seguranca: $SEC_MOD" 0
add_L " Virt: $VIRT" 0; add_L " Uptime: $UPTIME_V" 0; add_L " Timezone: $TZ_V" 0
add_L " Logados: $LOGGED_N ($LOGGED_USERS)" 0; add_L " Ultimo Boot: $LAST_BOOT" 0
add_M "__TOP__" 3; add_M "08  SISTEMA + KERNEL" 1; add_M "__SEP__" 2
add_M " Distro: ${OS_NAME:-N/A}" 0; add_M " Versao: ${OS_VER:-N/A}" 0; add_M " Kernel: $KERNEL_V" 0; add_M " Arq: $ARCH_V" 0; add_M " UMASK: $UMASK_VAL" 0
add_M "__SEP__" 2
add_M " Boot: $BOOT_INFO" 0
add_M " Disco: $BOOT_DISK_INFO" 0
add_M " Secure Boot: $SECURE_BOOT" 0
add_M " Atual: $BOOT_INFO" 0
add_M " Pacotes: $PKG_COUNT" 0; add_M " Atualizacoes: $UPDATES" 0
add_R "__TOP__" 3; add_R "09  ARMAZENAMENTO" 1; add_R "__SEP__" 2; add_R "$ST_HEADER" 0; add_R "__SEP__" 2
_si=0; while [ "$_si" -lt "${#STORAGE_LINES[@]}" ]; do add_R "${ST_FMT[$_si]}" 0; _si=$(( _si + 1 )); done
add_bottom_trio; print_trio; print_close
ensure_tools mkdir
DESKTOP_DIR=""
if [ -n "$XDG_DESKTOP_DIR" ] && [ -d "$XDG_DESKTOP_DIR" ]; then DESKTOP_DIR="$XDG_DESKTOP_DIR";
elif [ -d "$HOME/Desktop" ]; then DESKTOP_DIR="$HOME/Desktop";
elif [ -d "$HOME/Área de Trabalho" ]; then DESKTOP_DIR="$HOME/Área de Trabalho";
elif [ -d "$HOME/Area de Trabalho" ]; then DESKTOP_DIR="$HOME/Area de Trabalho";
else DESKTOP_DIR="$HOME/Desktop"; fi
mkdir -p "$DESKTOP_DIR" 2>/dev/null
NOW_SAFE=$(date "+%Y-%m-%d_%H%M%S")
REPORT_FILE="$DESKTOP_DIR/LINUX_InventoryTaker_${NOW_SAFE}.txt"
HTML_FILE="$DESKTOP_DIR/LINUX_InventoryTaker_${NOW_SAFE}.html"
CSV_FILE="$DESKTOP_DIR/LINUX_InventoryTaker_${NOW_SAFE}.csv"
JSON_FILE="$DESKTOP_DIR/LINUX_InventoryTaker_${NOW_SAFE}.json"
{
  print_banner 0
  printf 'Host: %s | Atualizado em: %s\n' "$HOST" "$NOW"
  printf 'Compativel: Kernel >= 3.10 | Bash >= 3.x\n'; printf '\n'
  printf '01 PORTAS ABERTAS (nmap -sS -sU -sV -p- --open + ss + /proc/net + lsof + ufw)\n'
  if [ "$PORTS_TOTAL" -eq 0 ]; then printf 'Nenhuma porta aberta\n'; else _pi=0; while [ "$_pi" -lt "${#PORTS_LINES[@]}" ]; do printf 'Porta: %s\n' "${PORTS_LINES[$_pi]}"; _pi=$(( _pi + 1 )); done; fi
  printf 'TCP: %s\n' "$PORTS_TCP"; printf 'UDP: %s\n' "$PORTS_UDP"; printf 'Firewall: %s\n' "$UFW_STATUS"
  printf '\n'; printf 'command:\n'; printf '\n'; printf '%s\n' "$NMAP_CMD"; printf '%s\n' "$UFW_CMD"; printf '%s\n' "$SS_CMD"; printf '\n'; printf 'Total: %s\n' "$PORTS_TOTAL"; printf '\n'
  printf '02 HARDWARE\n'
  printf 'Fabricante: %s\n' "${VENDOR_V:-N/A}"; printf 'Modelo: %s\n' "${MODEL_V:-N/A}"; printf 'CPU: %s\n' "${CPU_DISPLAY:-N/A}"
  printf 'Geracao: %s\n' "$CPU_GEN"; printf 'Nucleos: %s\n' "$CPU_CORES"; printf 'Disco: %s\n' "$BOOT_DISK_INFO"; printf 'Video: %s\n' "$GPU_MODEL"; printf 'SMART: %s (%s)\n' "$SMART_STATUS" "$SMART_HOURS"; if [ "$BAT_CAP" = "N/A" ]; then printf 'Bateria: N/A (sem bateria)\n'; else printf 'Bateria: %s (%s)\n' "$BAT_CAP" "$BAT_STATUS"; printf 'Saude Bateria: %s (Ciclos: %s)\n' "$BAT_HEALTH" "$BAT_CYCLES"; fi
  printf 'Temperatura:\n'; printf 'CPU: %s\n' "$TEMP_CPU"; printf 'GPU: %s\n' "$TEMP_GPU"; printf 'Disco: %s\n' "$TEMP_DISK"; printf 'Placa: %s\n' "$TEMP_BOARD"
  printf 'Firmware: %s\n' "$FIRMWARE_VENDOR"; printf 'Versao Firmware: %s\n' "$FIRMWARE_VER"; printf 'Data Firmware: %s\n' "$FIRMWARE_DATE"
  printf 'Classe Firmware: %s\n' "$FIRMWARE_CLASS"; printf 'Revisao BIOS: %s\n' "$BIOS_REV"; printf 'Revisao Firmware: %s\n' "$FW_REV"
  printf 'ROM: %s\n' "$ROM_SIZE"; printf 'SMBIOS: %s\n' "$SMBIOS_VER"; printf '\n'
  printf '03 GERENCIADORES\n'; printf 'Servicos: %s\n' "$SVC_MGR"
  printf 'apt: %s\n' "$APT_V"; printf 'dpkg: %s\n' "$DPKG_V"; printf 'dnf: %s\n' "$DNF_V"; printf 'yum: %s\n' "$YUM_V"
  printf 'pacman: %s\n' "$PACMAN_V"; printf 'zypper: %s\n' "$ZYPPER_V"; printf 'snap: %s\n' "$SNAP_V"; printf 'flatpak: %s\n' "$FLATPAK_V"
  printf '\n'; printf 'Browsers:\n'; printf '\n'
  if [ "${#BROWSER_LINES[@]}" -eq 0 ]; then printf 'Nenhum browser encontrado\n'; else _bi=0; while [ "$_bi" -lt "${#BROWSER_LINES[@]}" ]; do printf '%s\n' "${BROWSER_LINES[$_bi]}"; _bi=$(( _bi + 1 )); done; fi
  printf '\n'
  printf '04 REDES\n'; printf 'Interfaces: %s\n' "$NET_IFACES"; printf 'Interface Principal: %s\n' "$NET_PRIMARY"; printf 'IP: %s\n' "$NET_IP"
  printf 'IP Externo: %s\n' "$EXT_IP"; printf 'Gateway: %s\n' "$NET_GW"; printf 'DNS: %s\n' "$NET_DNS"; printf 'MAC: %s\n' "$NET_MAC"; printf 'MTU: %s\n' "$NET_MTU"
  printf '\n'; printf 'command: %s %s\n' "$NET_CMD" "$NET_ATIVO"; printf '\n'; printf '\n'
  printf '05 MEMORIA RAM + SWAP\n'
  printf 'RAM Total: %s\n' "$(to_gb "$MEM_TOTAL_KB")"; printf 'RAM Em uso: %s\n' "$(to_gb "$MEM_USED_KB")"; printf 'RAM Disponivel: %s\n' "$(to_gb "$MEM_AVAIL_KB")"
  printf 'Swap Total: %s\n' "$(to_gb "$SWAP_TOTAL_KB")"; printf 'Swap Em uso: %s\n' "$(to_gb "$SWAP_USED_KB")"; printf 'Swap Livre: %s\n' "$(to_gb "$SWAP_FREE_KB")"
  printf 'Swap Cached: %s\n' "$(to_gb "$SWAP_CACHED_KB")"; printf 'Total RAM+Swap: %s\n' "$(to_gb "$MEM_ALL_KB")"
  printf 'swapon: sudo swapon -a (ativar)\n'; printf 'swapoff: sudo swapoff -a (desativar)\n'; printf '\n'
  printf '06 WIFI\n'; printf 'Interface: %s\n' "$WIFI_IFACE"; printf 'SSID: %s\n' "$WIFI_SSID"; printf 'Sinal: %s\n' "$WIFI_SIGNAL"
  printf 'IP: %s\n' "$WIFI_IP"; printf 'IP Externo: %s\n' "$EXT_IP"; printf 'MAC: %s\n' "$WIFI_MAC"; printf 'Estado: %s\n' "$WIFI_STATE"; printf 'Frequencia: %s\n' "$WIFI_FREQ"
  printf '\n'; printf 'command: %s %s\n' "$WIFI_CMD" "$WIFI_ATIVO"; printf '\n'; printf '\n'
  printf '07 AMBIENTE & RUNTIME\n'; printf 'Ambiente grafico: %s\n' "$DE_VAL"; printf 'Sessao: %s\n' "$SESSION_TYPE_VAL"; printf 'Display: %s\n' "$DISPLAY_VAL"
  printf 'Shell (bash): %s\n' "$SHELL_V"; printf 'Init system: %s\n' "$INIT_SYS"; printf 'Firewall: %s\n' "$FW"; printf 'Seguranca kernel: %s\n' "$SEC_MOD"
  printf 'Virtualizacao: %s\n' "$VIRT"; printf 'Uptime: %s\n' "$UPTIME_V"; printf 'Timezone: %s\n' "$TZ_V"; printf 'Logados: %s (%s)\n' "$LOGGED_N" "$LOGGED_USERS"; printf 'Ultimo Boot: %s\n' "$LAST_BOOT"; printf '\n'
  printf '08 SISTEMA + KERNEL\n'; printf 'Distribuicao: %s\n' "${OS_NAME:-N/A}"; printf 'Versao: %s\n' "${OS_VER:-N/A}"
  printf 'Kernel: %s\n' "$KERNEL_V"; printf 'Arquitetura: %s\n' "$ARCH_V"; printf 'UMASK: %s\n' "$UMASK_VAL"
  printf 'Boot: %s\n' "$BOOT_INFO"; printf 'Disco Boot: %s\n' "$BOOT_DISK_INFO"; printf 'Secure Boot: %s\n' "$SECURE_BOOT"; printf 'Atual: %s\n' "$BOOT_INFO"; printf 'Pacotes: %s\n' "$PKG_COUNT"; printf 'Atualizacoes: %s\n' "$UPDATES"; printf '\n'
  printf '09 ARMAZENAMENTO\n'; printf '%-8s %4s %6s %6s %6s\n' "MONTE" "USO%" "TOTAL" "USADO" "LIVRE"
  _si=0
  while [ "$_si" -lt "${#STORAGE_LINES[@]}" ]; do
    _m=$(printf '%s' "${STORAGE_LINES[$_si]}" | awk '{print $1}' | cut -c 1-8)
    _p=$(printf '%s' "${STORAGE_LINES[$_si]}" | awk '{print $2}'); _s=$(printf '%s' "${STORAGE_LINES[$_si]}" | awk '{print $3}')
    _u=$(printf '%s' "${STORAGE_LINES[$_si]}" | awk '{print $4}'); _a=$(printf '%s' "${STORAGE_LINES[$_si]}" | awk '{print $5}')
    printf '%-8s %4s %6s %6s %6s\n' "$_m" "$_p" "$_s" "$_u" "$_a"
    _si=$(( _si + 1 ))
  done
  printf '\n'; printf 'Dashboard carregado com sucesso.\n'
} > "$REPORT_FILE" 2>/dev/null
PORTS_HTML=""
if [ "$PORTS_TOTAL" -eq 0 ]; then PORTS_HTML='<div class="row"><span class="k">Porta:</span><span class="v">Nenhuma porta aberta</span></div>';
else _pi=0; while [ "$_pi" -lt "${#PORTS_LINES[@]}" ]; do PORTS_HTML="$PORTS_HTML<div class=\"row\"><span class=\"k\">Porta:</span><span class=\"v\">$(html_esc "${PORTS_LINES[$_pi]}")</span></div>"; _pi=$(( _pi + 1 )); done; fi
BROWSER_HTML=""
if [ "${#BROWSER_LINES[@]}" -eq 0 ]; then BROWSER_HTML='<div class="row"><span class="k">Browser:</span><span class="v">Nenhum browser encontrado</span></div>';
else _bi=0; while [ "$_bi" -lt "${#BROWSER_LINES[@]}" ]; do _blabel=$(printf '%s' "${BROWSER_LINES[$_bi]}" | cut -d: -f1); _bval=$(printf '%s' "${BROWSER_LINES[$_bi]}" | cut -d: -f2- | sed 's/^ //'); BROWSER_HTML="$BROWSER_HTML<div class=\"row\"><span class=\"k\">$(html_esc "$_blabel"):</span><span class=\"v\">$(html_esc "$_bval")</span></div>"; _bi=$(( _bi + 1 )); done; fi
ST_HTML=""; _si=0
while [ "$_si" -lt "${#STORAGE_LINES[@]}" ]; do
  _m=$(printf '%s' "${STORAGE_LINES[$_si]}" | awk '{print $1}' | cut -c 1-8)
  _p=$(printf '%s' "${STORAGE_LINES[$_si]}" | awk '{print $2}'); _s=$(printf '%s' "${STORAGE_LINES[$_si]}" | awk '{print $3}')
  _u=$(printf '%s' "${STORAGE_LINES[$_si]}" | awk '{print $4}'); _a=$(printf '%s' "${STORAGE_LINES[$_si]}" | awk '{print $5}')
  ST_HTML="$ST_HTML<div class=\"row st\"><span>$(html_esc "$_m")</span><span>$_p</span><span>$_s</span><span>$_u</span><span><b style=\"color:#facc15\">$_a</b></span></div>"
  _si=$(( _si + 1 ))
done
if [ "$NET_ATIVO" = "ATIVO" ]; then NET_BADGE='<span class="badge ok">ATIVO</span>'; else NET_BADGE='<span class="badge off">INATIVO</span>'; fi
if [ "$WIFI_ATIVO" = "ATIVO" ]; then WIFI_BADGE='<span class="badge ok">ATIVO</span>'; else WIFI_BADGE='<span class="badge off">INATIVO</span>'; fi
{
  printf '<!doctype html>\n<html lang="pt-BR"><head><meta charset="utf-8">\n'
  printf '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
  printf '<title>LINUX SYSTEM DASHBOARD - SYSADMIN</title>\n'
  printf '<style>\n'
  printf '*{box-sizing:border-box} body{margin:0;background:#1e1e1e;color:#d4d4d4;font-family:Consolas,"Fira Code",monospace;padding:10px;font-size:13px}\n'
  printf '.page{max-width:1280px;margin:0 auto}\n'
  printf '.hero{background:linear-gradient(90deg,#ff9900,#7c3aed,#2563eb);border-radius:14px;padding:12px 14px;color:#fff;text-align:center}\n'
  printf '.hero h1{margin:0;font-size:19px;text-align:center} .hero p{margin:4px 0 0;color:#bfdbfe;opacity:.95;font-size:12px;text-align:center}\n'
  printf '.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin-top:10px;align-items:stretch}\n'
  printf '.card{background:#252526;border:2px solid #3c3c3c;border-radius:14px;padding:10px;font-size:13px;line-height:1.35}\n'
  printf '.c1{border-color:#ff9900} .c2{border-color:#2563eb} .c3{border-color:#22c55e} .c4{border-color:#06b6d4} .c5{border-color:#ec4899} .c6{border-color:#a855f7} .c7{border-color:#eab308} .c8{border-color:#f97316} .c9{border-color:#14b8a6}\n'
  printf '.card h2{margin:-10px -10px 7px;background:#ffffff;color:#111111;font-size:14px;text-align:center;padding:7px 10px;border-radius:12px 12px 0 0}\n'
  printf '.row{display:flex;gap:6px;padding:2px 0;border-bottom:1px dashed #3c3c3c} .k{color:#facc15;min-width:88px;flex-shrink:0} .v{color:#ffffff;word-break:break-word}\n'
  printf '.row.st{display:grid;grid-template-columns:8ch 4ch 6ch 6ch 6ch;gap:8px} .row.st span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis} .row.st span:nth-child(n+2){text-align:right;color:#86efac}\n'
  printf '.sep{border-top:1px solid #3c3c3c;margin:5px 0} .cmd{margin:7px 0;background:#0b0f14;border:1px solid #facc15;border-radius:10px;padding:7px;color:#fde68a;line-height:1.45;font-size:12px}\n'
  printf '.badge{padding:2px 8px;border-radius:999px;font-weight:800;font-size:11px} .ok{background:#22c55e;color:#04120a} .off{background:#ef4444;color:#fff}\n'
  printf '.bar{height:8px;background:#111;border-radius:999px;overflow:hidden;margin:6px 0} .bar>i{display:block;height:100%%;background:linear-gradient(90deg,#22c55e,#facc15)}\n'
  printf '.footer{margin-top:10px;background:#111827;border-radius:12px;padding:14px;text-align:left;line-height:1.6;font-size:13px}\n'
  printf '.footer h3{margin:0 0 8px;color:#facc15;font-size:14px;text-align:center}\n'
  printf '.footer-summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin:10px 0}\n'
  printf '.kpi{background:#1f2937;border:1px solid #374151;border-radius:10px;padding:10px;text-align:center} .kpi b{display:block;font-size:22px;color:#ffffff} .kpi span{color:#9ca3af;font-size:12px}\n'
  printf '.footer-cols{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px;margin-top:10px}\n'
  printf '.footer-col h3{border-bottom:1px solid #374151;padding-bottom:6px;text-align:left}\n'
  printf '.footer-info{display:flex;gap:8px;padding:3px 0;border-bottom:1px dashed #374151} .footer-info .k{color:#facc15;min-width:110px;flex-shrink:0;font-weight:700} .footer-info .v{color:#ffffff;word-break:break-word}\n'
  printf '.footer-links{margin-top:12px;text-align:center} .footer a{color:#4fc3f7;font-weight:700;word-break:break-all} .footer a:hover{color:#fff}\n'
  printf '.topbar{display:flex;justify-content:space-between;gap:10px;align-items:center;background:#0b0f14;border:1px solid #374151;border-radius:12px;padding:8px 12px;margin-bottom:10px;font-size:12px}\n'
  printf '.topbar b{color:#facc15;letter-spacing:1px} .topbar span{color:#9ca3af} .pill{background:#22c55e;color:#04120a;border-radius:999px;padding:2px 10px;font-weight:800;font-size:11px}\n'
  printf '.header{background:linear-gradient(90deg,#ff9900,#7c3aed,#2563eb);border-radius:14px;padding:16px;color:#fff;text-align:center}\n'
  printf '.header .brand{font-size:11px;letter-spacing:4px;color:#fde68a;font-weight:800} .header h1{margin:4px 0;font-size:26px;letter-spacing:1px} .header p{margin:0;color:#dbeafe;font-size:13px}\n'
  printf '.chips{display:flex;flex-wrap:wrap;gap:8px;justify-content:center;margin-top:12px} .chip{background:rgba(0,0,0,.35);border:1px solid rgba(255,255,255,.45);border-radius:999px;padding:4px 12px;font-size:12px} .chip b{color:#facc15}\n'
  printf '.files{margin-top:14px;background:#0b0f14;border:1px solid #374151;border-radius:12px;overflow:hidden}\n'
  printf '.files-head{display:grid;grid-template-columns:110px 100px 1fr 80px;gap:10px;background:#1f2937;padding:9px 12px;font-weight:800;color:#facc15;font-size:12px;text-transform:uppercase;letter-spacing:.5px}\n'
  printf '.files-row{display:grid;grid-template-columns:110px 100px 1fr 80px;gap:10px;align-items:center;padding:9px 12px;border-top:1px dashed #374151} .files-row:nth-child(even){background:#111827}\n'
  printf '.files-row .tipo{color:#ffffff;font-weight:700} .files-row .fmt{color:#9ca3af} .files-row .nome{color:#e5e7eb;word-break:break-all;font-family:Consolas,monospace;font-size:12px} .files-row a{background:#2563eb;color:#fff;border-radius:999px;padding:4px 10px;text-align:center;text-decoration:none;font-weight:800;font-size:12px} .files-row a:hover{background:#fff;color:#111}\n'
  printf '.files-meta{display:flex;flex-wrap:wrap;gap:8px 22px;justify-content:center;padding:10px 12px;color:#9ca3af;font-size:12px} .files-meta b{color:#ffffff}\n'
  printf '@media(max-width:900px){.files-head,.files-row{grid-template-columns:1fr 1fr} .files-row .nome{grid-column:1/-1} .topbar{flex-direction:column;text-align:center}}\n'
  printf '@media(max-width:900px){.footer-summary{grid-template-columns:repeat(2,1fr)} .footer-cols{grid-template-columns:1fr}}\n'
  printf '@media(max-width:900px){.grid{grid-template-columns:1fr}}\n'
  printf '</style></head><body><div class="page">\n'
  printf '<div class="topbar"><span><b>LINUX &nbsp; INVENTORYTAKER</b></span><span>Host: %s</span><span>Atualizado em: %s</span><span class="pill">SOMENTE LEITURA</span></div>\n' "$(html_esc "$HOST")" "$(html_esc "$NOW")"
  printf '<div class="header"><div class="brand">INVENTARIO COMPLETO DO SISTEMA</div><h1>LINUX &nbsp; INVENTORYTAKER</h1><p>Relatorio completo do sistema, gerado em modo somente leitura.</p><div class="chips"><span class="chip">Host: <b>%s</b></span><span class="chip">Distro: <b>%s %s</b></span><span class="chip">Kernel: <b>%s</b></span><span class="chip">Arquitetura: <b>%s</b></span><span class="chip">IP: <b>%s</b></span><span class="chip">Boot: <b>%s</b></span></div></div>\n' "$(html_esc "$HOST")" "$(html_esc "${OS_NAME:-N/A}")" "$(html_esc "${OS_VER:-N/A}")" "$(html_esc "$KERNEL_V")" "$(html_esc "$ARCH_V")" "$(html_esc "$NET_IP")" "$(html_esc "$BOOT_INFO")"
  printf '<div class="grid">\n'
  printf '<div class="card c1"><h2>01 &nbsp; PORTAS ABERTAS</h2>%s\n' "$PORTS_HTML"
  printf '<div class="row"><span class="k">TCP:</span><span class="v">%s</span></div>\n' "$PORTS_TCP"
  printf '<div class="row"><span class="k">UDP:</span><span class="v">%s</span></div>\n' "$PORTS_UDP"
  printf '<div class="row"><span class="k">Firewall:</span><span class="v">%s</span></div>\n' "$(html_esc "$UFW_STATUS")"
  printf '<div style="height:8px"></div><div class="cmd">command:<br><br>%s<br>%s<br>%s</div><div style="height:8px"></div>\n' "$(html_esc "$NMAP_CMD")" "$(html_esc "$UFW_CMD")" "$(html_esc "$SS_CMD")"
  printf '<div class="row"><span class="k">Total:</span><span class="v">%s</span></div></div>\n' "$PORTS_TOTAL"
  printf '<div class="card c2"><h2>02 &nbsp; HARDWARE</h2>\n'
  printf '<div class="row"><span class="k">Fabricante:</span><span class="v">%s</span></div>\n' "$(html_esc "${VENDOR_V:-N/A}")"
  printf '<div class="row"><span class="k">Modelo:</span><span class="v">%s</span></div>\n' "$(html_esc "${MODEL_V:-N/A}")"
  printf '<div class="row"><span class="k">CPU:</span><span class="v">%s</span></div>\n' "$(html_esc "${CPU_DISPLAY:-N/A}")"
  printf '<div class="row"><span class="k">Geracao:</span><span class="v">%s</span></div>\n' "$(html_esc "$CPU_GEN")"
  printf '<div class="row"><span class="k">Nucleos:</span><span class="v">%s</span></div>\n' "$(html_esc "$CPU_CORES")"
  printf '<div class="row"><span class="k">Disco:</span><span class="v">%s</span></div>\n' "$(html_esc "$BOOT_DISK_INFO")"
  printf '<div class="row"><span class="k">Video:</span><span class="v">%s</span></div>\n' "$(html_esc "$GPU_MODEL")"
  printf '<div class="row"><span class="k">SMART:</span><span class="v">%s (%s)</span></div>\n' "$(html_esc "$SMART_STATUS")" "$(html_esc "$SMART_HOURS")"
  if [ "$BAT_CAP" = "N/A" ]; then printf '<div class="row"><span class="k">Bateria:</span><span class="v">N/A (sem bateria)</span></div>\n'; else printf '<div class="row"><span class="k">Bateria:</span><span class="v">%s (%s)</span></div>\n' "$(html_esc "$BAT_CAP")" "$(html_esc "$BAT_STATUS")"; printf '<div class="row"><span class="k">Saude Bateria:</span><span class="v">%s (Ciclos: %s)</span></div>\n' "$(html_esc "$BAT_HEALTH")" "$(html_esc "$BAT_CYCLES")"; fi
  printf '<div class="sep"></div>\n'
  printf '<div class="row"><span class="k">Temperatura:</span><span class="v"></span></div>\n'
  printf '<div class="row"><span class="k">CPU:</span><span class="v">%s</span></div>\n' "$(html_esc "$TEMP_CPU")"
  printf '<div class="row"><span class="k">GPU:</span><span class="v">%s</span></div>\n' "$(html_esc "$TEMP_GPU")"
  printf '<div class="row"><span class="k">Disco:</span><span class="v">%s</span></div>\n' "$(html_esc "$TEMP_DISK")"
  printf '<div class="row"><span class="k">Placa:</span><span class="v">%s</span></div><div class="sep"></div>\n' "$(html_esc "$TEMP_BOARD")"
  printf '<div class="row"><span class="k">Firmware:</span><span class="v">%s</span></div>\n' "$(html_esc "$FIRMWARE_VENDOR")"
  printf '<div class="row"><span class="k">Versao:</span><span class="v">%s</span></div>\n' "$(html_esc "$FIRMWARE_VER")"
  printf '<div class="row"><span class="k">Data Firmware:</span><span class="v">%s</span></div>\n' "$(html_esc "$FIRMWARE_DATE")"
  printf '<div class="row"><span class="k">Classe:</span><span class="v">%s</span></div>\n' "$(html_esc "$FIRMWARE_CLASS")"
  printf '<div class="row"><span class="k">Rev BIOS:</span><span class="v">%s</span></div>\n' "$(html_esc "$BIOS_REV")"
  printf '<div class="row"><span class="k">Rev FW:</span><span class="v">%s</span></div>\n' "$(html_esc "$FW_REV")"
  printf '<div class="row"><span class="k">ROM:</span><span class="v">%s</span></div>\n' "$(html_esc "$ROM_SIZE")"
  printf '<div class="row"><span class="k">SMBIOS:</span><span class="v">%s</span></div></div>\n' "$(html_esc "$SMBIOS_VER")"
  printf '<div class="card c3"><h2>03 &nbsp; GERENCIADORES</h2>\n'
  printf '<div class="row"><span class="k">Servicos:</span><span class="v">%s</span></div>\n' "$(html_esc "$SVC_MGR")"
  printf '<div class="row"><span class="k">apt:</span><span class="v">%s</span></div>\n' "$(html_esc "$APT_V")"
  printf '<div class="row"><span class="k">dpkg:</span><span class="v">%s</span></div>\n' "$(html_esc "$DPKG_V")"
  printf '<div class="row"><span class="k">dnf:</span><span class="v">%s</span></div>\n' "$(html_esc "$DNF_V")"
  printf '<div class="row"><span class="k">yum:</span><span class="v">%s</span></div>\n' "$(html_esc "$YUM_V")"
  printf '<div class="row"><span class="k">pacman:</span><span class="v">%s</span></div>\n' "$(html_esc "$PACMAN_V")"
  printf '<div class="row"><span class="k">zypper:</span><span class="v">%s</span></div>\n' "$(html_esc "$ZYPPER_V")"
  printf '<div class="row"><span class="k">snap:</span><span class="v">%s</span></div>\n' "$(html_esc "$SNAP_V")"
  printf '<div class="row"><span class="k">flatpak:</span><span class="v">%s</span></div><div class="sep"></div><div style="height:8px"></div>\n' "$(html_esc "$FLATPAK_V")"
  printf '<div class="row"><span class="k">Browsers:</span><span class="v"></span></div><div style="height:8px"></div>%s<div style="height:8px"></div></div>\n' "$BROWSER_HTML"
  printf '<div class="card c4"><h2>04 &nbsp; REDES</h2>\n'
  printf '<div class="row"><span class="k">Interfaces:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_IFACES")"
  printf '<div class="row"><span class="k">Principal:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_PRIMARY")"
  printf '<div class="row"><span class="k">IP:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_IP")"
  printf '<div class="row"><span class="k">IP Ext:</span><span class="v">%s</span></div>\n' "$(html_esc "$EXT_IP")"
  printf '<div class="row"><span class="k">Gateway:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_GW")"
  printf '<div class="row"><span class="k">DNS:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_DNS")"
  printf '<div class="row"><span class="k">MAC:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_MAC")"
  printf '<div class="row"><span class="k">MTU:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_MTU")"
  printf '<div class="cmd">command: %s %s</div></div>\n' "$(html_esc "$NET_CMD")" "$NET_BADGE"
  printf '<div class="card c5"><h2>05 &nbsp; MEMORIA RAM + SWAP</h2>\n'
  printf '<div class="row"><span class="k">RAM Total:</span><span class="v">%s</span></div>\n' "$(to_gb "$MEM_TOTAL_KB")"
  printf '<div class="row"><span class="k">RAM Uso:</span><span class="v">%s</span></div>\n' "$(to_gb "$MEM_USED_KB")"
  printf '<div class="row"><span class="k">RAM Livre:</span><span class="v">%s</span></div><div class="bar"><i style="width:65%%"></i></div><div class="sep"></div>\n' "$(to_gb "$MEM_AVAIL_KB")"
  printf '<div class="row"><span class="k">Swap Total:</span><span class="v">%s</span></div>\n' "$(to_gb "$SWAP_TOTAL_KB")"
  printf '<div class="row"><span class="k">Swap Uso:</span><span class="v">%s</span></div>\n' "$(to_gb "$SWAP_USED_KB")"
  printf '<div class="row"><span class="k">Swap Livre:</span><span class="v">%s</span></div>\n' "$(to_gb "$SWAP_FREE_KB")"
  printf '<div class="row"><span class="k">Swap Cached:</span><span class="v">%s</span></div>\n' "$(to_gb "$SWAP_CACHED_KB")"
  printf '<div class="row"><span class="k">Total RAM+Swap:</span><span class="v">%s</span></div>\n' "$(to_gb "$MEM_ALL_KB")"
  printf '<div class="row"><span class="k">swapon:</span><span class="v">sudo swapon -a (ativar)</span></div>\n'
  printf '<div class="row"><span class="k">swapoff:</span><span class="v">sudo swapoff -a (desativar)</span></div></div>\n'
  printf '<div class="card c6"><h2>06 &nbsp; WIFI</h2>\n'
  printf '<div class="row"><span class="k">Interface:</span><span class="v">%s</span></div>\n' "$(html_esc "$WIFI_IFACE")"
  printf '<div class="row"><span class="k">SSID:</span><span class="v">%s</span></div>\n' "$(html_esc "$WIFI_SSID")"
  printf '<div class="row"><span class="k">Sinal:</span><span class="v">%s</span></div>\n' "$(html_esc "$WIFI_SIGNAL")"
  printf '<div class="row"><span class="k">IP:</span><span class="v">%s</span></div>\n' "$(html_esc "$WIFI_IP")"
  printf '<div class="row"><span class="k">IP Ext:</span><span class="v">%s</span></div>\n' "$(html_esc "$EXT_IP")"
  printf '<div class="row"><span class="k">MAC:</span><span class="v">%s</span></div>\n' "$(html_esc "$WIFI_MAC")"
  printf '<div class="row"><span class="k">Estado:</span><span class="v">%s</span></div>\n' "$(html_esc "$WIFI_STATE")"
  printf '<div class="row"><span class="k">Freq:</span><span class="v">%s</span></div>\n' "$(html_esc "$WIFI_FREQ")"
  printf '<div class="cmd">command: %s %s</div></div>\n' "$(html_esc "$WIFI_CMD")" "$WIFI_BADGE"
  printf '<div class="card c7"><h2>07 &nbsp; AMBIENTE &amp; RUNTIME</h2>\n'
  printf '<div class="row"><span class="k">Ambiente:</span><span class="v">%s</span></div>\n' "$(html_esc "$DE_VAL")"
  printf '<div class="row"><span class="k">Sessao:</span><span class="v">%s</span></div>\n' "$(html_esc "$SESSION_TYPE_VAL")"
  printf '<div class="row"><span class="k">Display:</span><span class="v">%s</span></div><div class="sep"></div>\n' "$(html_esc "$DISPLAY_VAL")"
  printf '<div class="row"><span class="k">Shell:</span><span class="v">%s</span></div>\n' "$(html_esc "$SHELL_V")"
  printf '<div class="row"><span class="k">Init:</span><span class="v">%s</span></div>\n' "$(html_esc "$INIT_SYS")"
  printf '<div class="row"><span class="k">Firewall:</span><span class="v">%s</span></div>\n' "$(html_esc "$FW")"
  printf '<div class="row"><span class="k">Seguranca:</span><span class="v">%s</span></div>\n' "$(html_esc "$SEC_MOD")"
  printf '<div class="row"><span class="k">Virt:</span><span class="v">%s</span></div>\n' "$(html_esc "$VIRT")"
  printf '<div class="row"><span class="k">Uptime:</span><span class="v">%s</span></div>\n' "$(html_esc "$UPTIME_V")"
  printf '<div class="row"><span class="k">Timezone:</span><span class="v">%s</span></div>\n' "$(html_esc "$TZ_V")"
  printf '<div class="row"><span class="k">Logados:</span><span class="v">%s (%s)</span></div>\n' "$(html_esc "$LOGGED_N")" "$(html_esc "$LOGGED_USERS")"
  printf '<div class="row"><span class="k">Ultimo Boot:</span><span class="v">%s</span></div></div>\n' "$(html_esc "$LAST_BOOT")"
  printf '<div class="card c8"><h2>08 &nbsp; SISTEMA + KERNEL</h2>\n'
  printf '<div class="row"><span class="k">Distro:</span><span class="v">%s</span></div>\n' "$(html_esc "${OS_NAME:-N/A}")"
  printf '<div class="row"><span class="k">Versao:</span><span class="v">%s</span></div>\n' "$(html_esc "${OS_VER:-N/A}")"
  printf '<div class="row"><span class="k">Kernel:</span><span class="v">%s</span></div>\n' "$(html_esc "$KERNEL_V")"
  printf '<div class="row"><span class="k">Arq:</span><span class="v">%s</span></div>\n' "$(html_esc "$ARCH_V")"
  printf '<div class="row"><span class="k">UMASK:</span><span class="v">%s</span></div><div class="sep"></div>\n' "$(html_esc "$UMASK_VAL")"
  printf '<div class="row"><span class="k">Boot:</span><span class="v">%s</span></div>\n' "$(html_esc "$BOOT_INFO")"
  printf '<div class="row"><span class="k">Disco:</span><span class="v">%s</span></div>\n' "$(html_esc "$BOOT_DISK_INFO")"
  printf '<div class="row"><span class="k">Secure Boot:</span><span class="v">%s</span></div>\n' "$(html_esc "$SECURE_BOOT")"
  printf '<div class="row"><span class="k">Atual:</span><span class="v">%s</span></div>\n' "$(html_esc "$BOOT_INFO")"
  printf '<div class="row"><span class="k">Pacotes:</span><span class="v">%s</span></div>\n' "$(html_esc "$PKG_COUNT")"
  printf '<div class="row"><span class="k">Atualizacoes:</span><span class="v">%s</span></div></div>\n' "$(html_esc "$UPDATES")"
  printf '<div class="card c9"><h2>09 &nbsp; ARMAZENAMENTO</h2>\n'
  printf '<div class="row st"><span>MONTE</span><span>USO%%</span><span>TOTAL</span><span>USADO</span><span>LIVRE</span></div><div class="sep"></div>%s\n' "$ST_HTML"
  printf '</div>\n'
  printf '</div>\n'
  printf '<div class="footer"><h3>Resumo &mdash; Dashboard carregado com sucesso.</h3>\n'
  printf '<div style="text-align:center;color:#9ca3af">Host: %s &nbsp;|&nbsp; Atualizado em: %s</div>\n' "$(html_esc "$HOST")" "$(html_esc "$NOW")"
  printf '<div class="footer-summary">\n'
  printf '<div class="kpi"><b>%s</b><span>Portas abertas</span></div>\n' "$PORTS_TOTAL"
  printf '<div class="kpi"><b>%s</b><span>Pacotes instalados</span></div>\n' "$(html_esc "$PKG_COUNT")"
  printf '<div class="kpi"><b>%s</b><span>Atualizacoes pendentes</span></div>\n' "$(html_esc "$UPDATES")"
  printf '<div class="kpi"><b>%s</b><span>RAM total</span></div>\n' "$(html_esc "$(to_gb "$MEM_TOTAL_KB")")"
  printf '</div>\n'
  printf '<div class="footer-cols">\n'
  printf '<div class="footer-col"><h3>Programa</h3>\n'
  printf '<div class="footer-info"><span class="k">Programa:</span><span class="v">Linux InventoryTaker</span></div>\n'
  printf '<div class="footer-info"><span class="k">Modo:</span><span class="v">Somente leitura</span></div>\n'
  printf '<div class="footer-info"><span class="k">Shell:</span><span class="v">bash &gt;= 3.x</span></div>\n'
  printf '<div class="footer-info"><span class="k">Kernel minimo:</span><span class="v">Linux &gt;= 3.10</span></div>\n'
  printf '<div class="footer-info"><span class="k">Relatorios:</span><span class="v">TXT, HTML, CSV, JSON</span></div>\n'
  printf '</div>\n'
  printf '<div class="footer-col"><h3>Maquina</h3>\n'
  printf '<div class="footer-info"><span class="k">Host:</span><span class="v">%s</span></div>\n' "$(html_esc "$HOST")"
  printf '<div class="footer-info"><span class="k">Fabricante:</span><span class="v">%s</span></div>\n' "$(html_esc "${VENDOR_V:-N/A}")"
  printf '<div class="footer-info"><span class="k">Modelo:</span><span class="v">%s</span></div>\n' "$(html_esc "${MODEL_V:-N/A}")"
  printf '<div class="footer-info"><span class="k">CPU:</span><span class="v">%s</span></div>\n' "$(html_esc "${CPU_DISPLAY:-N/A}")"
  printf '<div class="footer-info"><span class="k">Disco:</span><span class="v">%s</span></div>\n' "$(html_esc "$BOOT_DISK_INFO")"
  printf '</div>\n'
  printf '<div class="footer-col"><h3>Sistema</h3>\n'
  printf '<div class="footer-info"><span class="k">Distro:</span><span class="v">%s</span></div>\n' "$(html_esc "${OS_NAME:-N/A}")"
  printf '<div class="footer-info"><span class="k">Versao:</span><span class="v">%s</span></div>\n' "$(html_esc "${OS_VER:-N/A}")"
  printf '<div class="footer-info"><span class="k">Kernel:</span><span class="v">%s</span></div>\n' "$(html_esc "$KERNEL_V")"
  printf '<div class="footer-info"><span class="k">Arquitetura:</span><span class="v">%s</span></div>\n' "$(html_esc "$ARCH_V")"
  printf '<div class="footer-info"><span class="k">Boot:</span><span class="v">%s</span></div>\n' "$(html_esc "$BOOT_INFO")"
  printf '<div class="footer-info"><span class="k">Secure Boot:</span><span class="v">%s</span></div>\n' "$(html_esc "$SECURE_BOOT")"
  printf '<div class="footer-info"><span class="k">IP:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_IP")"
  printf '<div class="footer-info"><span class="k">Gateway:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_GW")"
  printf '</div>\n'
  printf '</div>\n'
  printf '<div class="files"><div class="files-meta"><span>Pasta: <b>%s</b></span><span>Arquivo base: <b>%s</b></span><span>Total: <b>4 arquivos</b></span><span>Gerado em: <b>%s</b></span></div>\n' "$(html_esc "$DESKTOP_DIR")" "$(html_esc "$(basename "$REPORT_FILE" .txt)")" "$(html_esc "$NOW")"
  printf '<div class="files-head"><span>Tipo</span><span>Formato</span><span>Arquivo</span><span>Abrir</span></div>\n'
  printf '<div class="files-row"><span class="tipo">Relatorio</span><span class="fmt">TXT</span><span class="nome">%s</span><a href="file://%s" target="_blank" rel="noopener">Abrir</a></div>\n' "$(html_esc "$(basename "$REPORT_FILE")")" "$(html_esc "$REPORT_FILE")"
  printf '<div class="files-row"><span class="tipo">Pagina</span><span class="fmt">HTML</span><span class="nome">%s</span><a href="file://%s" target="_blank" rel="noopener">Abrir</a></div>\n' "$(html_esc "$(basename "$HTML_FILE")")" "$(html_esc "$HTML_FILE")"
  printf '<div class="files-row"><span class="tipo">Planilha</span><span class="fmt">CSV</span><span class="nome">%s</span><a href="file://%s" target="_blank" rel="noopener">Abrir</a></div>\n' "$(html_esc "$(basename "$CSV_FILE")")" "$(html_esc "$CSV_FILE")"
  printf '<div class="files-row"><span class="tipo">Dados</span><span class="fmt">JSON</span><span class="nome">%s</span><a href="file://%s" target="_blank" rel="noopener">Abrir</a></div></div>\n' "$(html_esc "$(basename "$JSON_FILE")")" "$(html_esc "$JSON_FILE")"
  printf '</div>\n'
  printf '</div></body></html>\n'
} > "$HTML_FILE" 2>/dev/null
{
  printf 'secao;rotulo;valor\n'
  printf 'CABECALHO;Host;%s\n' "${HOST//;/,}"
  printf 'CABECALHO;Atualizado em;%s\n' "${NOW//;/,}"
  printf 'CABECALHO;Compativel;Kernel >= 3.10 | Bash >= 3.x\n'
  printf ';;\n'
  printf '01 PORTAS ABERTAS;;\n'
  _pi=0; while [ "$_pi" -lt "${#PORTS_LINES[@]}" ]; do printf '01 PORTAS ABERTAS;Porta;%s\n' "${PORTS_LINES[$_pi]//;/,}"; _pi=$(( _pi + 1 )); done
  if [ "$PORTS_TOTAL" -eq 0 ]; then printf '01 PORTAS ABERTAS;Porta;Nenhuma porta aberta\n'; fi
  printf '01 PORTAS ABERTAS;TCP;%s\n' "${PORTS_TCP//;/,}"
  printf '01 PORTAS ABERTAS;UDP;%s\n' "${PORTS_UDP//;/,}"
  printf '01 PORTAS ABERTAS;Firewall;%s\n' "${UFW_STATUS//;/,}"
  printf '01 PORTAS ABERTAS;Total;%s\n' "${PORTS_TOTAL//;/,}"
  printf ';;\n'
  printf '02 HARDWARE;;\n'
  printf '02 HARDWARE;Fabricante;%s\n' "${VENDOR_V//;/,}"
  printf '02 HARDWARE;Modelo;%s\n' "${MODEL_V//;/,}"
  printf '02 HARDWARE;CPU;%s\n' "${CPU_DISPLAY//;/,}"
  printf '02 HARDWARE;Geracao;%s\n' "${CPU_GEN//;/,}"
  printf '02 HARDWARE;Nucleos;%s\n' "${CPU_CORES//;/,}"
  printf '02 HARDWARE;Disco;%s\n' "${BOOT_DISK_INFO//;/,}"
  printf '02 HARDWARE;Video;%s\n' "${GPU_MODEL//;/,}"
  printf '02 HARDWARE;SMART;%s (%s)\n' "${SMART_STATUS//;/,}" "${SMART_HOURS//;/,}"
  if [ "$BAT_CAP" = "N/A" ]; then printf '02 HARDWARE;Bateria;N/A (sem bateria)\n'; else printf '02 HARDWARE;Bateria;%s (%s)\n' "${BAT_CAP//;/,}" "${BAT_STATUS//;/,}"; printf '02 HARDWARE;Saude Bateria;%s (Ciclos: %s)\n' "${BAT_HEALTH//;/,}" "${BAT_CYCLES//;/,}"; fi
  printf '02 HARDWARE;Temperatura CPU;%s\n' "${TEMP_CPU//;/,}"
  printf '02 HARDWARE;Temperatura GPU;%s\n' "${TEMP_GPU//;/,}"
  printf '02 HARDWARE;Temperatura Disco;%s\n' "${TEMP_DISK//;/,}"
  printf '02 HARDWARE;Temperatura Placa;%s\n' "${TEMP_BOARD//;/,}"
  printf '02 HARDWARE;Firmware;%s\n' "${FIRMWARE_VENDOR//;/,}"
  printf '02 HARDWARE;Versao Firmware;%s\n' "${FIRMWARE_VER//;/,}"
  printf '02 HARDWARE;Data Firmware;%s\n' "${FIRMWARE_DATE//;/,}"
  printf '02 HARDWARE;Classe Firmware;%s\n' "${FIRMWARE_CLASS//;/,}"
  printf '02 HARDWARE;Revisao BIOS;%s\n' "${BIOS_REV//;/,}"
  printf '02 HARDWARE;Revisao Firmware;%s\n' "${FW_REV//;/,}"
  printf '02 HARDWARE;ROM;%s\n' "${ROM_SIZE//;/,}"
  printf '02 HARDWARE;SMBIOS;%s\n' "${SMBIOS_VER//;/,}"
  printf ';;\n'
  printf '03 GERENCIADORES;;\n'
  printf '03 GERENCIADORES;Servicos;%s\n' "${SVC_MGR//;/,}"
  printf '03 GERENCIADORES;apt;%s\n' "${APT_V//;/,}"
  printf '03 GERENCIADORES;dpkg;%s\n' "${DPKG_V//;/,}"
  printf '03 GERENCIADORES;dnf;%s\n' "${DNF_V//;/,}"
  printf '03 GERENCIADORES;yum;%s\n' "${YUM_V//;/,}"
  printf '03 GERENCIADORES;pacman;%s\n' "${PACMAN_V//;/,}"
  printf '03 GERENCIADORES;zypper;%s\n' "${ZYPPER_V//;/,}"
  printf '03 GERENCIADORES;snap;%s\n' "${SNAP_V//;/,}"
  printf '03 GERENCIADORES;flatpak;%s\n' "${FLATPAK_V//;/,}"
  printf '03 GERENCIADORES;Browsers;;\n'
  _bi=0; while [ "$_bi" -lt "${#BROWSER_LINES[@]}" ]; do printf '03 GERENCIADORES;Browser;%s\n' "${BROWSER_LINES[$_bi]//;/,}"; _bi=$(( _bi + 1 )); done
  if [ "${#BROWSER_LINES[@]}" -eq 0 ]; then printf '03 GERENCIADORES;Browser;Nenhum browser encontrado\n'; fi
  printf ';;\n'
  printf '04 REDES;;\n'
  printf '04 REDES;Interfaces;%s\n' "${NET_IFACES//;/,}"
  printf '04 REDES;Interface Principal;%s\n' "${NET_PRIMARY//;/,}"
  printf '04 REDES;IP;%s\n' "${NET_IP//;/,}"
  printf '04 REDES;IP Externo;%s\n' "${EXT_IP//;/,}"
  printf '04 REDES;Gateway;%s\n' "${NET_GW//;/,}"
  printf '04 REDES;DNS;%s\n' "${NET_DNS//;/,}"
  printf '04 REDES;MAC;%s\n' "${NET_MAC//;/,}"
  printf '04 REDES;MTU;%s\n' "${NET_MTU//;/,}"
  printf '04 REDES;command;%s %s\n' "${NET_CMD//;/,}" "${NET_ATIVO//;/,}"
  printf ';;\n'
  printf '05 MEMORIA RAM + SWAP;;\n'
  printf '05 MEMORIA RAM + SWAP;RAM Total;%s\n' "$(to_gb "$MEM_TOTAL_KB")"
  printf '05 MEMORIA RAM + SWAP;RAM Em uso;%s\n' "$(to_gb "$MEM_USED_KB")"
  printf '05 MEMORIA RAM + SWAP;RAM Disponivel;%s\n' "$(to_gb "$MEM_AVAIL_KB")"
  printf '05 MEMORIA RAM + SWAP;Swap Total;%s\n' "$(to_gb "$SWAP_TOTAL_KB")"
  printf '05 MEMORIA RAM + SWAP;Swap Em uso;%s\n' "$(to_gb "$SWAP_USED_KB")"
  printf '05 MEMORIA RAM + SWAP;Swap Livre;%s\n' "$(to_gb "$SWAP_FREE_KB")"
  printf '05 MEMORIA RAM + SWAP;Swap Cached;%s\n' "$(to_gb "$SWAP_CACHED_KB")"
  printf '05 MEMORIA RAM + SWAP;Total RAM+Swap;%s\n' "$(to_gb "$MEM_ALL_KB")"
  printf '05 MEMORIA RAM + SWAP;swapon;sudo swapon -a (ativar)\n'
  printf '05 MEMORIA RAM + SWAP;swapoff;sudo swapoff -a (desativar)\n'
  printf ';;\n'
  printf '06 WIFI;;\n'
  printf '06 WIFI;Interface;%s\n' "${WIFI_IFACE//;/,}"
  printf '06 WIFI;SSID;%s\n' "${WIFI_SSID//;/,}"
  printf '06 WIFI;Sinal;%s\n' "${WIFI_SIGNAL//;/,}"
  printf '06 WIFI;IP;%s\n' "${WIFI_IP//;/,}"
  printf '06 WIFI;IP Externo;%s\n' "${EXT_IP//;/,}"
  printf '06 WIFI;MAC;%s\n' "${WIFI_MAC//;/,}"
  printf '06 WIFI;Estado;%s\n' "${WIFI_STATE//;/,}"
  printf '06 WIFI;Frequencia;%s\n' "${WIFI_FREQ//;/,}"
  printf '06 WIFI;command;%s %s\n' "${WIFI_CMD//;/,}" "${WIFI_ATIVO//;/,}"
  printf ';;\n'
  printf '07 AMBIENTE & RUNTIME;;\n'
  printf '07 AMBIENTE & RUNTIME;Ambiente grafico;%s\n' "${DE_VAL//;/,}"
  printf '07 AMBIENTE & RUNTIME;Sessao;%s\n' "${SESSION_TYPE_VAL//;/,}"
  printf '07 AMBIENTE & RUNTIME;Display;%s\n' "${DISPLAY_VAL//;/,}"
  printf '07 AMBIENTE & RUNTIME;Shell (bash);%s\n' "${SHELL_V//;/,}"
  printf '07 AMBIENTE & RUNTIME;Init system;%s\n' "${INIT_SYS//;/,}"
  printf '07 AMBIENTE & RUNTIME;Firewall;%s\n' "${FW//;/,}"
  printf '07 AMBIENTE & RUNTIME;Seguranca kernel;%s\n' "${SEC_MOD//;/,}"
  printf '07 AMBIENTE & RUNTIME;Virtualizacao;%s\n' "${VIRT//;/,}"
  printf '07 AMBIENTE & RUNTIME;Uptime;%s\n' "${UPTIME_V//;/,}"
  printf '07 AMBIENTE & RUNTIME;Timezone;%s\n' "${TZ_V//;/,}"
  printf '07 AMBIENTE & RUNTIME;Logados;%s (%s)\n' "${LOGGED_N//;/,}" "${LOGGED_USERS//;/,}"
  printf '07 AMBIENTE & RUNTIME;Ultimo Boot;%s\n' "${LAST_BOOT//;/,}"
  printf ';;\n'
  printf '08 SISTEMA + KERNEL;;\n'
  printf '08 SISTEMA + KERNEL;Distribuicao;%s\n' "${OS_NAME//;/,}"
  printf '08 SISTEMA + KERNEL;Versao;%s\n' "${OS_VER//;/,}"
  printf '08 SISTEMA + KERNEL;Kernel;%s\n' "${KERNEL_V//;/,}"
  printf '08 SISTEMA + KERNEL;Arquitetura;%s\n' "${ARCH_V//;/,}"
  printf '08 SISTEMA + KERNEL;UMASK;%s\n' "${UMASK_VAL//;/,}"
  printf '08 SISTEMA + KERNEL;Boot;%s\n' "${BOOT_INFO//;/,}"
  printf '08 SISTEMA + KERNEL;Disco Boot;%s\n' "${BOOT_DISK_INFO//;/,}"
  printf '08 SISTEMA + KERNEL;Secure Boot;%s\n' "${SECURE_BOOT//;/,}"
  printf '08 SISTEMA + KERNEL;Atual;%s\n' "${BOOT_INFO//;/,}"
  printf '08 SISTEMA + KERNEL;Pacotes;%s\n' "${PKG_COUNT//;/,}"
  printf '08 SISTEMA + KERNEL;Atualizacoes;%s\n' "${UPDATES//;/,}"
  printf ';;\n'
  printf '09 ARMAZENAMENTO;;\n'
  printf '09 ARMAZENAMENTO;MONTE;USO%% | TOTAL | USADO | LIVRE\n'
  _si=0; while [ "$_si" -lt "${#STORAGE_LINES[@]}" ]; do _raw="${STORAGE_LINES[$_si]}"; _m=$(printf '%s' "$_raw" | awk '{print $1}'); _pc=$(printf '%s' "$_raw" | awk '{print $2}'); _sz=$(printf '%s' "$_raw" | awk '{print $3}'); _us=$(printf '%s' "$_raw" | awk '{print $4}'); _av=$(printf '%s' "$_raw" | awk '{print $5}'); printf '09 ARMAZENAMENTO;%s;%s | %s | %s | %s\n' "${_m//;/,}" "${_pc//;/,}" "${_sz//;/,}" "${_us//;/,}" "${_av//;/,}"; _si=$(( _si + 1 )); done
  printf ';;\n'
  printf 'RODAPE;Status;Dashboard carregado com sucesso.\n'
} > "$CSV_FILE" 2>/dev/null
json_esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' '; }
{
  printf '{\n'
  printf '  "CABECALHO": {"Host": "%s", "Atualizado em": "%s", "Compativel": "Kernel >= 3.10 | Bash >= 3.x"},\n' "$(json_esc "$HOST")" "$(json_esc "$NOW")"
  printf '  "01 PORTAS ABERTAS": {"Porta": ['
  _pi=0; while [ "$_pi" -lt "${#PORTS_LINES[@]}" ]; do if [ "$_pi" -gt 0 ]; then printf ', '; fi; printf '"%s"' "$(json_esc "${PORTS_LINES[$_pi]}")"; _pi=$(( _pi + 1 )); done
  if [ "$PORTS_TOTAL" -eq 0 ]; then printf '"Nenhuma porta aberta"'; fi
  printf '], "TCP": "%s", "UDP": "%s", "Firewall": "%s", "command": ["%s", "%s", "%s"], "Total": "%s"},\n' "$(json_esc "$PORTS_TCP")" "$(json_esc "$PORTS_UDP")" "$(json_esc "$UFW_STATUS")" "$(json_esc "$NMAP_CMD")" "$(json_esc "$UFW_CMD")" "$(json_esc "$SS_CMD")" "$(json_esc "$PORTS_TOTAL")"
  if [ "$BAT_CAP" = "N/A" ]; then _bat_txt="N/A (sem bateria)"; _saude_txt=""; else _bat_txt="$BAT_CAP ($BAT_STATUS)"; _saude_txt="$BAT_HEALTH (Ciclos: $BAT_CYCLES)"; fi
  printf '  "02 HARDWARE": {"Fabricante": "%s", "Modelo": "%s", "CPU": "%s", "Geracao": "%s", "Nucleos": "%s", "Disco": "%s", "Video": "%s", "SMART": "%s (%s)", "Bateria": "%s", "Saude Bateria": "%s", "Temperatura CPU": "%s", "Temperatura GPU": "%s", "Temperatura Disco": "%s", "Temperatura Placa": "%s", "Firmware": "%s", "Versao Firmware": "%s", "Data Firmware": "%s", "Classe Firmware": "%s", "Revisao BIOS": "%s", "Revisao Firmware": "%s", "ROM": "%s", "SMBIOS": "%s"},\n' "$(json_esc "$VENDOR_V")" "$(json_esc "$MODEL_V")" "$(json_esc "$CPU_DISPLAY")" "$(json_esc "$CPU_GEN")" "$(json_esc "$CPU_CORES")" "$(json_esc "$BOOT_DISK_INFO")" "$(json_esc "$GPU_MODEL")" "$(json_esc "$SMART_STATUS")" "$(json_esc "$SMART_HOURS")" "$(json_esc "$_bat_txt")" "$(json_esc "$_saude_txt")" "$(json_esc "$TEMP_CPU")" "$(json_esc "$TEMP_GPU")" "$(json_esc "$TEMP_DISK")" "$(json_esc "$TEMP_BOARD")" "$(json_esc "$FIRMWARE_VENDOR")" "$(json_esc "$FIRMWARE_VER")" "$(json_esc "$FIRMWARE_DATE")" "$(json_esc "$FIRMWARE_CLASS")" "$(json_esc "$BIOS_REV")" "$(json_esc "$FW_REV")" "$(json_esc "$ROM_SIZE")" "$(json_esc "$SMBIOS_VER")"
  printf '  "03 GERENCIADORES": {"Servicos": "%s", "apt": "%s", "dpkg": "%s", "dnf": "%s", "yum": "%s", "pacman": "%s", "zypper": "%s", "snap": "%s", "flatpak": "%s", "Browser": [' "$(json_esc "$SVC_MGR")" "$(json_esc "$APT_V")" "$(json_esc "$DPKG_V")" "$(json_esc "$DNF_V")" "$(json_esc "$YUM_V")" "$(json_esc "$PACMAN_V")" "$(json_esc "$ZYPPER_V")" "$(json_esc "$SNAP_V")" "$(json_esc "$FLATPAK_V")"
  _bi=0; while [ "$_bi" -lt "${#BROWSER_LINES[@]}" ]; do if [ "$_bi" -gt 0 ]; then printf ', '; fi; printf '"%s"' "$(json_esc "${BROWSER_LINES[$_bi]}")"; _bi=$(( _bi + 1 )); done
  if [ "${#BROWSER_LINES[@]}" -eq 0 ]; then printf '"Nenhum browser encontrado"'; fi
  printf ']},\n'
  printf '  "04 REDES": {"Interfaces": "%s", "Interface Principal": "%s", "IP": "%s", "IP Externo": "%s", "Gateway": "%s", "DNS": "%s", "MAC": "%s", "MTU": "%s", "command": "%s %s"},\n' "$(json_esc "$NET_IFACES")" "$(json_esc "$NET_PRIMARY")" "$(json_esc "$NET_IP")" "$(json_esc "$EXT_IP")" "$(json_esc "$NET_GW")" "$(json_esc "$NET_DNS")" "$(json_esc "$NET_MAC")" "$(json_esc "$NET_MTU")" "$(json_esc "$NET_CMD")" "$(json_esc "$NET_ATIVO")"
  printf '  "05 MEMORIA RAM + SWAP": {"RAM Total": "%s", "RAM Em uso": "%s", "RAM Disponivel": "%s", "Swap Total": "%s", "Swap Em uso": "%s", "Swap Livre": "%s", "Swap Cached": "%s", "Total RAM+Swap": "%s", "swapon": "sudo swapon -a (ativar)", "swapoff": "sudo swapoff -a (desativar)"},\n' "$(json_esc "$(to_gb "$MEM_TOTAL_KB")")" "$(json_esc "$(to_gb "$MEM_USED_KB")")" "$(json_esc "$(to_gb "$MEM_AVAIL_KB")")" "$(json_esc "$(to_gb "$SWAP_TOTAL_KB")")" "$(json_esc "$(to_gb "$SWAP_USED_KB")")" "$(json_esc "$(to_gb "$SWAP_FREE_KB")")" "$(json_esc "$(to_gb "$SWAP_CACHED_KB")")" "$(json_esc "$(to_gb "$MEM_ALL_KB")")"
  printf '  "06 WIFI": {"Interface": "%s", "SSID": "%s", "Sinal": "%s", "IP": "%s", "IP Externo": "%s", "MAC": "%s", "Estado": "%s", "Frequencia": "%s", "command": "%s %s"},\n' "$(json_esc "$WIFI_IFACE")" "$(json_esc "$WIFI_SSID")" "$(json_esc "$WIFI_SIGNAL")" "$(json_esc "$WIFI_IP")" "$(json_esc "$EXT_IP")" "$(json_esc "$WIFI_MAC")" "$(json_esc "$WIFI_STATE")" "$(json_esc "$WIFI_FREQ")" "$(json_esc "$WIFI_CMD")" "$(json_esc "$WIFI_ATIVO")"
  printf '  "07 AMBIENTE & RUNTIME": {"Ambiente grafico": "%s", "Sessao": "%s", "Display": "%s", "Shell (bash)": "%s", "Init system": "%s", "Firewall": "%s", "Seguranca kernel": "%s", "Virtualizacao": "%s", "Uptime": "%s", "Timezone": "%s", "Logados": "%s (%s)", "Ultimo Boot": "%s"},\n' "$(json_esc "$DE_VAL")" "$(json_esc "$SESSION_TYPE_VAL")" "$(json_esc "$DISPLAY_VAL")" "$(json_esc "$SHELL_V")" "$(json_esc "$INIT_SYS")" "$(json_esc "$FW")" "$(json_esc "$SEC_MOD")" "$(json_esc "$VIRT")" "$(json_esc "$UPTIME_V")" "$(json_esc "$TZ_V")" "$(json_esc "$LOGGED_N")" "$(json_esc "$LOGGED_USERS")" "$(json_esc "$LAST_BOOT")"
  printf '  "08 SISTEMA + KERNEL": {"Distribuicao": "%s", "Versao": "%s", "Kernel": "%s", "Arquitetura": "%s", "UMASK": "%s", "Boot": "%s", "Disco Boot": "%s", "Secure Boot": "%s", "Atual": "%s", "Pacotes": "%s", "Atualizacoes": "%s"},\n' "$(json_esc "$OS_NAME")" "$(json_esc "$OS_VER")" "$(json_esc "$KERNEL_V")" "$(json_esc "$ARCH_V")" "$(json_esc "$UMASK_VAL")" "$(json_esc "$BOOT_INFO")" "$(json_esc "$BOOT_DISK_INFO")" "$(json_esc "$SECURE_BOOT")" "$(json_esc "$BOOT_INFO")" "$(json_esc "$PKG_COUNT")" "$(json_esc "$UPDATES")"
  printf '  "09 ARMAZENAMENTO": [ '
  _si=0; while [ "$_si" -lt "${#STORAGE_LINES[@]}" ]; do _raw="${STORAGE_LINES[$_si]}"; _m=$(printf '%s' "$_raw" | awk '{print $1}'); _pc=$(printf '%s' "$_raw" | awk '{print $2}'); _sz=$(printf '%s' "$_raw" | awk '{print $3}'); _us=$(printf '%s' "$_raw" | awk '{print $4}'); _av=$(printf '%s' "$_raw" | awk '{print $5}'); if [ "$_si" -gt 0 ]; then printf ', '; fi; printf '{\"MONTE\": \"%s\", \"USO%%\": \"%s\", \"TOTAL\": \"%s\", \"USADO\": \"%s\", \"LIVRE\": \"%s\"}' "$(json_esc "$_m")" "$(json_esc "$_pc")" "$(json_esc "$_sz")" "$(json_esc "$_us")" "$(json_esc "$_av")"; _si=$(( _si + 1 )); done
  printf ' ],\n'
  printf '  "RODAPE": {"Status": "Dashboard carregado com sucesso."}\n'
  printf '}\n'
} > "$JSON_FILE" 2>/dev/null
printf '\n'
printf '%s\n' "${BOLD}${C_YELLOW}Arquivos gerados no caminho abaixo:${RESET}"
printf '\n'
printf '%s\n' "file://$REPORT_FILE"
printf '%s\n' "file://$HTML_FILE"
printf '%s\n' "file://$CSV_FILE"
printf '%s\n' "file://$JSON_FILE"
printf '\n'
while true; do
  printf '%s [1] TXT  [2] HTML  [3] CSV  [4] JSON  [0] SAIR\n' "${BOLD}${C_YELLOW}Opções:${RESET}"
  printf '\n'
  printf 'Digite a opcao: '
  if ! read -r _escolha; then break; fi
  case "$_escolha" in
    1) open_file_de_independent "$REPORT_FILE" ;;
    2) open_file_de_independent "$HTML_FILE" ;;
    3) open_file_de_independent "$CSV_FILE" ;;
    4) open_file_de_independent "$JSON_FILE" ;;
    0) break ;;
    "") printf 'ENTER nao sai. Digite 0 para sair.\n' ;;
    *) printf 'Opcao invalida. Digite 0 para sair.\n' ;;
  esac
done
printf '\n'

