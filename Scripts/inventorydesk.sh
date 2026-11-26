#!/usr/bin/env bash
# INSTALADOR - INVENTORYTAKER - Desktop (GTK 3)
# Autor do InventoryTaker: Everaldo Costa Silva | Licença: MIT
# Transforma o script LINUX InventoryTaker em programa desktop (GTK 3 + Python):
#   - instala o script original (inalterado), a interface gráfica e o ícone;
#   - cria o ícone na "Área de trabalho" do usuário que executa (duplo clique abre);
#   - cria o atalho no menu de aplicativos;
#   - instala somente as dependências que faltarem (GTK 3 e PyGObject).
# Uso: bash instalar_inventorytaker.sh            (menu)
#      bash instalar_inventorytaker.sh --install  (instala/atualiza direto)
#      bash instalar_inventorytaker.sh --uninstall (rollback direto)
#      --no-deps  não verifica/instala dependências (uso offline)
# Compatibilidade: Bash >= 3.x. Execute como usuário normal (não use sudo).

PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/sbin
export PATH
IFS=$' \t\n'
CDPATH=
export CDPATH
umask 022

if [ "$(id -u 2>/dev/null)" = "0" ]; then
  printf 'ERRO: execute como usuario normal, sem sudo. O instalador pede a senha apenas quando precisar instalar pacotes.\n' >&2
  exit 1
fi
if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
  printf 'ERRO: HOME invalido.\n' >&2
  exit 1
fi

APP_ID="inventorytaker"
APP_DIR="$HOME/.local/share/$APP_ID"
APPS_DIR="$HOME/.local/share/applications"
DESK_DIR="$HOME/Área de trabalho"
BACKEND_F="$APP_DIR/LINUX_InventoryTaker.sh"
GUI_F="$APP_DIR/inventorytaker_gui.py"
ICON_F="$APP_DIR/inventorytaker.svg"
MENU_F="$APPS_DIR/inventorytaker.desktop"
DESK_F="$DESK_DIR/InventoryTaker.desktop"
REPORT_DIR="$DESK_DIR/INVENTÁRIO"

NO_DEPS=0
ACTION=""
for _arg in "$@"; do
  case "$_arg" in
    --install) ACTION=install ;;
    --uninstall) ACTION=uninstall ;;
    --no-deps) NO_DEPS=1 ;;
    *) printf 'Opcao desconhecida: %s\n' "$_arg" >&2; exit 1 ;;
  esac
done

C_Y=""; C_G=""; C_R=""; C_B=""; C_0=""
if [ -t 1 ] && [ "${NO_COLOR+x}" != x ] && [ "${TERM:-dumb}" != dumb ]; then
  C_Y=$'\033[1;33m'; C_G=$'\033[1;32m'; C_R=$'\033[1;31m'; C_B=$'\033[1;36m'; C_0=$'\033[0m'
fi

STAGE=""
cleanup_stage() {
  [ -z "${DEP_LOG:-}" ] || rm -f -- "$DEP_LOG"
  if [ -n "$STAGE" ] && [ -d "$STAGE" ]; then
    rm -f "$STAGE"/LINUX_InventoryTaker.sh "$STAGE"/inventorytaker_gui.py "$STAGE"/inventorytaker.svg
    rmdir "$STAGE" 2>/dev/null
  fi
}
trap cleanup_stage EXIT

PANEL_W=96
_pw=$(tput cols 2>/dev/null)
case $_pw in ""|*[!0-9]*) ;; *) [ "$_pw" -ge 40 ] && [ "$_pw" -lt 96 ] && PANEL_W=$_pw;; esac
PANEL_COLOR=0
PANEL_CELL='#'
case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in *UTF-8*|*utf8*|*UTF8*) PANEL_CELL='█';; esac
if [ -t 1 ] && [ "${NO_COLOR+x}" != x ] && command -v tput >/dev/null 2>&1; then
  _pc=$(tput colors 2>/dev/null)
  case $_pc in ''|*[!0-9]*) _pc=0;; esac
  [ "$_pc" -lt 256 ] || PANEL_COLOR=1
fi
PANEL_OPEN=0
panel_rule() {
  PANEL_OPEN=0
  local i=0 c
  while [ "$i" -lt "$PANEL_W" ]; do
    case $((i*5/PANEL_W)) in 0) c=136;; 1) c=178;; 2) c=220;; 3) c=226;; *) c=229;; esac
    if [ "$PANEL_COLOR" = 1 ]; then printf '\033[38;5;%sm%s' "$c" "$PANEL_CELL"; else printf '%s' "$PANEL_CELL"; fi
    i=$((i+1))
  done
  printf '%s\n' "$C_0"
}
panel_edge() {
  if [ "$PANEL_COLOR" = 1 ]; then printf '\033[38;5;220m%s\033[0m' "$PANEL_CELL"; else printf '%s' "$PANEL_CELL"; fi
}
panel_row() {
  local label="$1" value="$2" lw=29 w chunk lchunk
  if [ "$PANEL_OPEN" = 0 ]; then panel_rule; PANEL_OPEN=1; fi
  [ "$PANEL_W" -ge 78 ] || lw=16
  w=$((PANEL_W-lw-7))
  # Use ASCII for data cells: one byte and one terminal column per character.
  label=$(printf "%s" "$label" | tr -cd " -~")
  value=$(printf "%s" "$value" | sed 's/[^[:print:]]/?/g' )
  value=$(printf "%s" "$value" | LC_ALL=C tr -c " -~" "?")
  while :; do
    chunk=${value:0:$w}; lchunk=${label:0:$lw}
    panel_edge; printf ' %s%-*s%s ' "$C_Y" "$lw" "$lchunk" "$C_0"; panel_edge; printf ' %s%-*s%s ' "$C_B" "$w" "$chunk" "$C_0"; panel_edge; printf '\n'
    value=${value:$w}; label=${label:$lw}; [ -n "$value$label" ] || break
  done
}
panel_close() { if [ "$PANEL_OPEN" = 1 ]; then panel_rule; fi; }
panel_title() { panel_close; panel_row 'ETAPA' "$1"; }
banner() (
  printf '\n'
  local TOTAL_W=$((PANEL_W-2)) _use_color=$PANEL_COLOR RESET=$C_0
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
      if [ "$_use_color" = "1" ]; then panel_edge; printf '%s%s%s' "$_left_pad" "$_row_color" "$_right_pad"; panel_edge; printf '\n'; else panel_edge; printf '%s%s%s' "$_left_pad" "$_row_plain" "$_right_pad"; panel_edge; printf '\n'; fi
      _r=$(( _r + 1 ))
    done
  }
  panel_rule
  PANEL_OPEN=1
  panel_row '' ''
  if [ "$PANEL_W" -lt 86 ] || [ "$PANEL_CELL" = "#" ]; then panel_row "PROGRAMA" "INVENTORYTAKER"; else _banner_inventory; fi
  panel_row '' ''
  panel_row 'PROGRAMA' 'INVENTORYTAKER - Desktop'
  panel_row 'INSTALADOR' 'INTERFACE GRAFICA (GTK 3)'
  panel_row 'Autor' 'Everaldo Costa Silva | Licenca MIT'
  panel_rule
  printf '\n'
)
say()  { case "$*" in '') panel_close; printf '\n';; \[*\]*|Desinstalando*) panel_title "$*";; *) panel_row 'INFO' "$*";; esac; }
ok()   { panel_row '[ OK ]' "$*"; }
warn() { panel_row '[ !! ]' "$*"; }
fail() { panel_row '[FALHA]' "$*"; }

# ---------------------------------------------------------------- ambiente
PKG_MGR=""; DISTRO_NAME=""; PYBIN=""
DEPS_STATE="nao verificado"; INSTALLED_NOW=""; FAILED_PKGS=""
RESULT="NAO EXECUTADO"

detect_env() {
  local _release=/etc/os-release _id _like _c _managers
  [ -r "$_release" ] || _release=/usr/lib/os-release
  DISTRO_NAME=$(sed -n 's/^PRETTY_NAME=//p' "$_release" 2>/dev/null | head -n 1 | tr -d '"')
  _id=$(sed -n 's/^ID=//p' "$_release" 2>/dev/null | tr -d '"')
  _like=$(sed -n 's/^ID_LIKE=//p' "$_release" 2>/dev/null | tr -d '"')
  if [ -r /etc/slackware-version ]; then [ -n "$_id" ] || _id=slackware; [ -n "$DISTRO_NAME" ] || DISTRO_NAME=$(cat /etc/slackware-version); fi
  case " $_id $_like " in
    *' arch '*) _managers="pacman";;
    *' fedora '*|*' rhel '*|*' centos '*) _managers="dnf yum";;
    *' debian '*|*' ubuntu '*) _managers="apt-get";;
    *' slackware '*) _managers="slackpkg";;
    *' suse '*|*' opensuse '*) _managers="zypper";;
    *' alpine '*) _managers="apk";;
    *' void '*) _managers="xbps-install";;
    *' gentoo '*) _managers="emerge";;
    *) _managers="";;
  esac
  PKG_MGR=""
  for _c in $_managers; do command -v "$_c" >/dev/null 2>&1 && { PKG_MGR=$_c; break; }; done
  DISTRO_NAME=${DISTRO_NAME:-Linux desconhecido}
  DISTRO_ID=$_id
  KERNEL=$(uname -r)
}

# Nomes conferidos nas fontes oficiais de cada distribuicao.
gui_pkgs() {
  case "$PKG_MGR" in
    apt-get) printf '%s' "python3 python3-gi gir1.2-gtk-3.0" ;;
    dnf|yum) printf '%s' "python3 python3-gobject gtk3" ;;
    pacman) printf '%s' "python python-gobject gtk3" ;;
    zypper) printf '%s' "python3 python3-gobject python3-gobject-Gdk typelib-1_0-Gtk-3_0" ;;
    apk) printf '%s' "python3 py3-gobject3 gtk+3.0" ;;
    xbps-install) printf '%s' "python3 python3-gobject gtk+3" ;;
    emerge) printf '%s' "dev-lang/python dev-python/pygobject x11-libs/gtk+:3" ;;
    slackpkg) printf '%s' "python3 pygobject3 gtk+3 gobject-introspection glib2 cairo pango atk at-spi2-core gdk-pixbuf2 libepoxy libffi harfbuzz fontconfig freetype libpng libX11 libXext libXi libXrender libXrandr libXcursor libXfixes libXdamage libXcomposite libxkbcommon wayland" ;;
    *) printf '%s' "" ;;
  esac
}

pkg_is_installed() {
  local _p="$1"
  case "$PKG_MGR" in
    apt-get) dpkg-query -W -f='${Status}' "$_p" 2>/dev/null | grep -q "install ok installed" ;;
    dnf|yum|zypper) rpm -q "$_p" >/dev/null 2>&1 ;;
    pacman) pacman -Q "$_p" >/dev/null 2>&1 ;;
    apk) apk info -e "$_p" >/dev/null 2>&1 ;;
    xbps-install) xbps-query "$_p" >/dev/null 2>&1 ;;
    slackpkg) compgen -G "/var/lib/pkgtools/packages/$_p-[0-9]*" >/dev/null || compgen -G "/var/log/packages/$_p-[0-9]*" >/dev/null ;;
    emerge) compgen -G "/var/db/pkg/$_p-[0-9]*" >/dev/null ;;
    *) return 1 ;;
  esac
}

pkg_install_one() {
  local _p="$1" plan repo
  [ "$#" -ne 1 ] || ! pkg_is_installed "$_p" || return 0
  case "$PKG_MGR" in
    apt-get)
      local origin prefs
      case "$DISTRO_ID" in ubuntu) origin=Ubuntu;; debian) origin=Debian;; *) return 1;; esac
      prefs=$(mktemp) || return 1
      printf 'Package: *\nPin: release o=%s\nPin-Priority: 990\n\nPackage: *\nPin: release *\nPin-Priority: -1\n' "$origin" > "$prefs"
      local -a aptopts
      aptopts=(-o "Dir::Etc::preferences=$prefs" -o Dir::Etc::preferencesparts=- -o APT::Get::AllowUnauthenticated=false -o Acquire::AllowInsecureRepositories=false -o Acquire::AllowDowngradeToInsecureRepositories=false)
      plan=$(LC_ALL=C apt-get "${aptopts[@]}" -s --no-install-recommends --no-remove install "$@" 2>&1) || { rm -f -- "$prefs"; printf '%s\n' "$plan"; return 1; }
      if printf '%s\n' "$plan" | grep -Eq '^Remv |^Inst [^ ]+ \['; then rm -f -- "$prefs"; return 1; fi
      sudo apt-get "${aptopts[@]}" -y --no-upgrade --no-remove --no-install-recommends install "$@"
      local rc=$?; rm -f -- "$prefs"; return "$rc" ;;
    dnf|yum)
      [ "$DISTRO_ID" = fedora ] || return 1
      local -a opts
      opts=(--disablerepo='*' --enablerepo=fedora --enablerepo=updates --setopt=install_weak_deps=False --setopt=keepcache=True --setopt=gpgcheck=True --setopt=obsoletes=False)
      plan=$(LC_ALL=C sudo "$PKG_MGR" "${opts[@]}" --assumeno install "$@" 2>&1)
      printf '%s\n' "$plan"
      printf '%s\n' "$plan" | grep -Eq '^[[:space:]]*Installing([ :]|$)' || return 1
      if printf '%s\n' "$plan" | grep -Eiq '^[[:space:]]*(Upgrading|Downgrading|Removing|Reinstalling|Replacing|Obsoleting|Upgrade|Remove|Downgrade|Reinstall|Replace)([ :]|$)'; then return 1; fi
      sudo "$PKG_MGR" "${opts[@]}" install -y "$@" ;;
    pacman)
      plan=$(pacman -Sp --needed --print-format '%r %n %v' "$@" 2>/dev/null) || return 1
      while read -r repo name version; do
        [ -n "$name" ] || continue
        case "$repo" in core|extra|multilib) ;; *) return 1;; esac
        if pacman -Q "$name" >/dev/null 2>&1; then warn "Arch exige atualizacao de $name; instalacao bloqueada."; return 1; fi
      done <<< "$plan"
      [ -z "$(pacman -Qu 2>/dev/null)" ] || return 1
      sudo pacman -S --needed --noconfirm "$@" ;;
    zypper) sudo zypper --non-interactive install "$_p" ;;
    apk) sudo apk add "$_p" ;;
    xbps-install) sudo xbps-install -y "$_p" ;;
    emerge) sudo emerge --noreplace "$_p" ;;
    slackpkg)
      [ -s /var/lib/slackpkg/pkglist ] || sudo slackpkg -batch=on -default_answer=y update || return 1
      awk -v p="$_p" '$2==p {f=1} END{exit !f}' /var/lib/slackpkg/pkglist || return 1
      sudo slackpkg -batch=on -default_answer=y -checkgpg=on -checkmd5=on install "$_p" ;;
    *) return 1;;
  esac
}

py_ok() {
  env -u PYTHONPATH -u PYTHONHOME "$1" -Es -c 'import sys
if sys.version_info < (3, 6):
    raise SystemExit(1)
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gtk, Gdk, GLib, Gio, Pango' >/dev/null 2>&1
}

find_python() {
  local _c
  PYBIN=""
  for _c in /usr/bin/python3 "$(command -v python3 2>/dev/null)" /usr/bin/python3.[0-9]* /usr/local/bin/python3; do
    [ -n "$_c" ] && [ -x "$_c" ] || continue
    case "$_c" in *config*) continue ;; esac
    if py_ok "$_c"; then PYBIN="$_c"; return 0; fi
  done
  return 1
}

SUDO=""
DEP_LOG=""
install_deps() {
  local _pkgs _p _missing=""
  if find_python; then
    DEPS_STATE="ja presentes (nada a instalar)"
    ok "GTK 3 + PyGObject ja disponiveis ($PYBIN)."
    return 0
  fi
  _pkgs=$(gui_pkgs)
  if [ -z "$_pkgs" ]; then
    DEPS_STATE="FALHA: gerenciador de pacotes nao reconhecido"
    fail "Gerenciador de pacotes nao reconhecido. Instale manualmente: Python 3 (>= 3.6), GTK 3 e PyGObject."
    return 1
  fi
  for _p in $_pkgs; do
    if pkg_is_installed "$_p"; then say "  ja instalado: $_p"; else _missing="$_missing $_p"; fi
  done
  if [ -z "$_missing" ]; then
    DEPS_STATE="FALHA: pacotes presentes, mas GTK 3 nao importa"
    fail "Pacotes ja instalados, porem o GTK 3 nao pode ser importado pelo Python. Verifique o ambiente."
    return 1
  fi
  say "Faltam:$_missing"
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    say "Sera necessaria a senha de administrador para instalar os pacotes."
    if ! sudo -v; then
      DEPS_STATE="FALHA: sudo nao autorizado"
      fail "Sudo nao autorizado. Instale manualmente:$_missing"
      return 1
    fi
  else
    fail "Sem sudo. Como administrador, instale com $PKG_MGR:$_missing"
    DEPS_STATE="FALHA: sem sudo"
    return 1
  fi
  DEP_LOG=$(mktemp "${TMPDIR:-/tmp}/inventorytaker-deps.XXXXXXXX") || return 1
  case "$PKG_MGR" in apt-get|dnf|yum|pacman)
    if pkg_install_one $_missing >"$DEP_LOG" 2>&1; then INSTALLED_NOW="$_missing"; ok "Transacao concluida"; else FAILED_PKGS="$_missing"; while IFS= read -r _line; do panel_row "PACOTES" "$_line"; done < "$DEP_LOG"; fi ;;
  *)
  for _p in $_missing; do
    panel_row "INSTALANDO" "$_p"
    if pkg_install_one "$_p" >"$DEP_LOG" 2>&1; then
      ok "$_p"; INSTALLED_NOW="$INSTALLED_NOW $_p"
    else
      fail "$_p"; while IFS= read -r _line; do panel_row "PACOTES" "$_line"; done < "$DEP_LOG"; FAILED_PKGS="$FAILED_PKGS $_p"
    fi
  done
  ;; esac
  rm -f -- "$DEP_LOG"; DEP_LOG=""
  if find_python; then
    DEPS_STATE="instalados agora:${INSTALLED_NOW:- nenhum}"
    ok "GTK 3 + PyGObject prontos ($PYBIN)."
    return 0
  fi
  DEPS_STATE="FALHA: pacotes nao instalados:${FAILED_PKGS:- (todos)}"
  fail "Nao foi possivel disponibilizar o GTK 3. Pacotes com falha:${FAILED_PKGS:- (todos)}"
  return 1
}

# ------------------------------------------------------------------ payloads
write_backend() {
  cat > "$1" <<'__INVENTORYTAKER_BACKEND_EOF__'
#!/usr/bin/env bash
# INVENTORYTAKER
# Autor: Everaldo Costa Silva
# Licença: MIT | Copyright (c) 2026 Everaldo Costa Silva
# Compatibilidade: Linux (kernel >= 3.10 como referência; anteriores em modo de melhor esforço), Bash >= 3.x.
# Finalidade: inventário técnico e diagnóstico de sistemas Linux.
# 01 Hardware | 02 Portas abertas | 03 Gerenciadores
# 04 Redes | 05 Memória | 06 WiFi
# 07 Ambiente | 08 Sistema, kernel e boot | 09 Armazenamento
# Interface: painéis CLI, progresso da coleta e menu de relatórios.
# Relatórios: TXT, HTML, CSV e JSON, com abertura gráfica pelo menu.
# Segurança: PATH controlado, sudo autorizado e relatórios privados.
# Dependências: identificação do ambiente e instalação de ferramentas ausentes.
# --read-only: coleta sem sudo, instalacao, consulta externa ou varredura Nmap.
# INVENTORY_AUTOINSTALL=0: desativa a instalação automática.
# INVENTORY_EXT_IP=1: habilita consulta externa de IP.
# INVENTORY_FULL_SCAN=1: habilita varredura ampliada de portas com Nmap.
#
# MIT License
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/sbin
export PATH
IFS=$' \t\n'
CDPATH=
export CDPATH
umask 077
PRE_START=$SECONDS
pre_clock_ms() {
  local up whole frac rest
  if IFS=' ' read -r up rest < /proc/uptime 2>/dev/null; then
    whole=${up%%.*}; frac=${up#*.}; frac=${frac}000; frac=${frac:0:3}
    case "$whole:$frac" in *[!0-9:]*) ;; *) printf '%s\n' "$((10#$whole * 1000 + 10#$frac))"; return;; esac
  fi
  printf '%s\n' "$((SECONDS * 1000))"
}
PRE_START_MS=$(pre_clock_ms)
pre_duration() {
  local ms=$1
  [ "$ms" -ge 0 ] || ms=0
  printf '%d,%03d s (%02d:%02d:%02d)' "$((ms/1000))" "$((ms%1000))" "$((ms/3600000))" "$((ms/60000%60))" "$((ms/1000%60))"
}
PRE_EVENTS=()
pre_log() { PRE_EVENTS[${#PRE_EVENTS[@]}]="[$((SECONDS-PRE_START))s] $*"; }
pre_log 'Inicio da preparacao; PATH controlado e umask 077.'
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
  printf '%s\n' 'ERRO: Bash >= 3.0 obrigatoria.'
  printf 'Versao atual: %s\n' "$BASH_VERSION"
  exit 1
fi
INVENTORY_AUTOINSTALL="${INVENTORY_AUTOINSTALL:-1}"
INVENTORY_EXT_IP="${INVENTORY_EXT_IP:-0}"
INVENTORY_READ_ONLY=0
for _arg in "$@"; do
  case "$_arg" in --read-only|--check) INVENTORY_READ_ONLY=1 ;; esac
done
if [ "$INVENTORY_READ_ONLY" = 1 ]; then
  INVENTORY_AUTOINSTALL=0; INVENTORY_EXT_IP=0; INVENTORY_FULL_SCAN=0
  pre_log 'Modo somente leitura: instalacao, sudo e consultas externas desabilitados.'
fi
ENV_DISTRO_ID=""; ENV_DISTRO_LIKE=""; ENV_FAMILY=""; ENV_MGR=""; ENV_PRIV=""; ENV_INIT=""
ENV_VIRT=""; ENV_ARCH=""; ENV_KERNEL=""; ENV_FW_MODE=""; ENV_NET="online"
if [ -r /etc/os-release ] || [ -r /usr/lib/os-release ]; then
  _release=/etc/os-release; [ -r "$_release" ] || _release=/usr/lib/os-release
  ENV_DISTRO_ID=$(grep '^ID=' "$_release" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr 'A-Z' 'a-z')
  ENV_DISTRO_LIKE=$(grep '^ID_LIKE=' "$_release" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr 'A-Z' 'a-z')
fi
if [ -z "$ENV_DISTRO_ID" ] && [ -r /etc/slackware-version ]; then ENV_DISTRO_ID=slackware; fi
if [ -z "$ENV_DISTRO_ID" ]; then
  if [ -r /etc/arch-release ]; then ENV_DISTRO_ID=arch
  elif [ -r /etc/fedora-release ]; then ENV_DISTRO_ID=fedora
  elif [ -r /etc/lsb-release ] && grep -qi '^DISTRIB_ID=Ubuntu' /etc/lsb-release; then ENV_DISTRO_ID=ubuntu
  elif [ -r /etc/debian_version ]; then ENV_DISTRO_ID=debian
  elif command -v lsb_release >/dev/null 2>&1; then ENV_DISTRO_ID=$(lsb_release -si 2>/dev/null | tr 'A-Z' 'a-z'); fi
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
      slackpkg) if [ "$ENV_FAMILY" = "slackware" ]; then ENV_MGR="slackpkg"; fi ;;
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
SUDO_CMD=""
if [ "$ENV_PRIV" = "sudo" ] && [ "$INVENTORY_READ_ONLY" = 0 ]; then
   :
  sudo -k >/dev/null 2>&1
  if [ -t 0 ] && sudo -v; then
    SUDO_CMD="sudo -n"
  else
    SUDO_CMD="false"
    :
  fi
fi
if [ "$INVENTORY_READ_ONLY" = 1 ] && [ "$ENV_PRIV" != root ]; then SUDO_CMD=false; fi
PKG_UPDATE_DONE=0
PKG_ATTEMPTED=" "
PRE_ERRORS=()
pre_error() { PRE_ERRORS[${#PRE_ERRORS[@]}]="$1"; pre_log "ALERTA: $1"; }
pre_log "Distribuicao: $ENV_DISTRO_ID; familia: $ENV_FAMILY; kernel: $ENV_KERNEL; arquitetura: $ENV_ARCH"
pre_log "Gerenciador: ${PKG_MGR:-indisponivel}; privilegio: $ENV_PRIV; init: $ENV_INIT; sudo: ${SUDO_CMD:-nao necessario}"
[ "$INVENTORY_READ_ONLY" = 1 ] || [ "$SUDO_CMD" != false ] || pre_error 'Sudo nao autorizado; consultas protegidas indisponiveis.'
[ "$ENV_PRIV" != none ] || pre_error 'Sem privilegios administrativos; instalacao indisponivel.'

pkg_name_for() {
  _tool="$1"
  case "$_tool" in
    grep) printf grep; return 0 ;;
    sed) printf sed; return 0 ;;
    awk) case "$PKG_MGR" in apt-get|dnf|yum|pacman|slackpkg) printf gawk; return 0 ;; esac ;;
    who|od|dd|df|date|cut|head|tail|tr|sort|uniq|id|uname|cat|mkdir|wc)
      case "$PKG_MGR" in apt-get|dnf|yum|pacman|zypper|apk|slackpkg|xbps-install) printf 'coreutils'; return 0 ;; esac ;;
    uptime|pgrep)
      case "$PKG_MGR" in
        apt-get|zypper|apk) printf 'procps'; return 0 ;;
        dnf|yum|pacman|slackpkg) printf 'procps-ng'; return 0 ;;
      esac ;;
    pidof)
      case "$PKG_MGR" in
        apt-get) printf 'sysvinit-utils'; return 0 ;;
        zypper|apk) printf 'procps'; return 0 ;;
        dnf|yum|pacman|slackpkg) printf 'procps-ng'; return 0 ;;
      esac ;;
  esac
  case "$PKG_MGR" in
    apt-get)
      case "$_tool" in
        tput) printf 'ncurses-bin' ;; ip|ss) printf 'iproute2' ;; nmcli) printf 'network-manager' ;;
        iw) printf 'iw' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;;
        dmidecode|biosdecode) printf 'dmidecode' ;;
        fdisk|sfdisk) printf 'fdisk' ;; lsblk|findmnt) printf 'util-linux' ;; parted) printf 'parted' ;; mokutil) printf 'mokutil' ;;
        efibootmgr) printf 'efibootmgr' ;; efivar) printf 'efivar' ;;
        lspci) printf 'pciutils' ;; lshw) printf 'lshw' ;;
        inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;; lscpu) printf 'util-linux' ;;
        lsusb) printf 'usbutils' ;; free) printf 'procps' ;; lsof) printf 'lsof' ;; hostname) printf 'hostname' ;;
        sensors) printf 'lm-sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;;
        getenforce) printf 'selinux-utils' ;;
        systemd-detect-virt|timedatectl|systemctl) printf 'systemd' ;; *) return 1 ;;
      esac ;;
    dnf|yum)
      case "$_tool" in
        tput) printf 'ncurses' ;; ip|ss) printf 'iproute' ;; nmcli) printf 'NetworkManager' ;;
        iw) printf 'iw' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;;
        dmidecode|biosdecode) printf 'dmidecode' ;;
        fdisk|lsblk|sfdisk|lscpu|findmnt) printf 'util-linux' ;; parted) printf 'parted' ;; mokutil) printf 'mokutil' ;;
        efibootmgr) printf 'efibootmgr' ;; efivar) printf 'efivar' ;;
        lspci) printf 'pciutils' ;; lshw) printf 'lshw' ;; inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;;
        lsusb) printf 'usbutils' ;; free) printf 'procps-ng' ;; lsof) printf 'lsof' ;; hostname) printf 'hostname' ;;
        getenforce) printf 'libselinux-utils' ;;
        sensors) printf 'lm_sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;;
        systemd-detect-virt|timedatectl|systemctl) printf 'systemd' ;; *) return 1 ;;
      esac ;;
    pacman)
      case "$_tool" in
        tput) printf 'ncurses' ;; ip|ss) printf 'iproute2' ;; nmcli) printf 'networkmanager' ;;
        iw) printf 'iw' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;;
        dmidecode|biosdecode) printf 'dmidecode' ;;
        fdisk|lsblk|sfdisk|lscpu|findmnt) printf 'util-linux' ;; parted) printf 'parted' ;; mokutil) printf 'mokutil' ;;
        efibootmgr) printf 'efibootmgr' ;; efivar) printf 'efivar' ;;
        lspci) printf 'pciutils' ;; lshw) printf 'lshw' ;; inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;;
        lsusb) printf 'usbutils' ;; free) printf 'procps-ng' ;; lsof) printf 'lsof' ;; hostname) printf 'inetutils' ;;
        sensors) printf 'lm_sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;;
        systemd-detect-virt|timedatectl|systemctl) printf 'systemd' ;; *) return 1 ;;
      esac ;;
    zypper)
      case "$_tool" in
        tput) printf 'ncurses-utils' ;; ip|ss) printf 'iproute2' ;; nmcli) printf 'NetworkManager' ;;
        iw) printf 'iw' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;;
        dmidecode|biosdecode) printf 'dmidecode' ;;
        fdisk|lsblk|sfdisk|lscpu|findmnt) printf 'util-linux' ;; parted) printf 'parted' ;; mokutil) printf 'mokutil' ;;
        efibootmgr) printf 'efibootmgr' ;; efivar) printf 'efivar' ;;
        lspci) printf 'pciutils' ;; lshw) printf 'lshw' ;; inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;;
        lsusb) printf 'usbutils' ;; free) printf 'procps' ;; lsof) printf 'lsof' ;; hostname) printf 'hostname' ;;
        sensors) printf 'sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;;
        systemd-detect-virt|timedatectl|systemctl) printf 'systemd' ;; *) return 1 ;;
      esac ;;
    apk)
      case "$_tool" in
        tput) printf 'ncurses' ;; ip|ss) printf 'iproute2' ;; nmcli) printf 'networkmanager' ;;
        iw) printf 'iw' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;;
        dmidecode|biosdecode) printf 'dmidecode' ;;
        fdisk|lsblk|sfdisk|lscpu) printf 'util-linux' ;; parted) printf 'parted' ;; mokutil) printf 'mokutil' ;;
        efibootmgr) printf 'efibootmgr' ;; efivar) printf 'efivar' ;;
        lspci) printf 'pciutils' ;; lshw) printf 'lshw' ;; inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;;
        lsusb) printf 'usbutils' ;; free) printf 'procps' ;; lsof) printf 'lsof' ;;
        sensors) printf 'lm-sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;; *) return 1 ;;
      esac ;;
    emerge)
      case "$_tool" in dmidecode|biosdecode) printf 'sys-apps/dmidecode' ;; lshw) printf 'sys-apps/lshw' ;; inxi) printf 'sys-apps/inxi' ;; hwinfo) printf 'sys-apps/hwinfo' ;; nmap) printf 'net-analyzer/nmap' ;; curl) printf 'net-misc/curl' ;; sensors) printf 'sys-apps/lm-sensors' ;; hddtemp) printf 'app-admin/hddtemp' ;; smartctl) printf 'sys-apps/smartmontools' ;; *) return 1 ;; esac ;;
    xbps-install)
      case "$_tool" in dmidecode) printf 'dmidecode' ;; lshw) printf 'lshw' ;; inxi) printf 'inxi' ;; hwinfo) printf 'hwinfo' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;; sensors) printf 'lm_sensors' ;; hddtemp) printf 'hddtemp' ;; smartctl) printf 'smartmontools' ;; *) return 1 ;; esac ;;
    slackpkg)
      case "$_tool" in
        ip|ss) printf 'iproute2' ;; nmap) printf 'nmap' ;; curl) printf 'curl' ;; iw) printf 'iw' ;;
        dmidecode|biosdecode) printf 'dmidecode' ;; efibootmgr) printf 'efibootmgr' ;;
        fdisk|lsblk|sfdisk|lscpu|findmnt|dmesg) printf 'util-linux' ;; parted) printf 'parted' ;;
        lspci) printf 'pciutils' ;; lsusb) printf 'usbutils' ;; lsof) printf 'lsof' ;;
        free|pgrep|pidof|uptime) printf 'procps-ng' ;; smartctl) printf 'smartmontools' ;;
        nmcli) printf 'NetworkManager' ;; sensors) printf 'lm_sensors' ;; hostname) printf 'net-tools' ;; who|od|dd|df) printf 'coreutils' ;; tput) printf 'ncurses' ;;
        *) return 1 ;;
      esac ;;
    brew)
      case "$_tool" in tput|ip|nmap|curl|iw|dmidecode|fdisk|lsblk|efibootmgr|lshw|inxi|hwinfo|sensors|hddtemp|smartctl) printf '%s' "$_tool" ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}
install_pkg() {
  local _pkg="$1"
  case "$_pkg" in ""|-*|*[!a-zA-Z0-9_./+:-]*) return 1 ;; esac
  [ "$INVENTORY_AUTOINSTALL" = 1 ] && [ "$INVENTORY_READ_ONLY" = 0 ] || return 1
  case "$ENV_PRIV" in none) return 1 ;; esac
  [ "$SUDO_CMD" != false ] || return 1
  case "$PKG_MGR" in
    apt-get) dpkg-query -W -f='${Status}' "$_pkg" 2>/dev/null | grep -qx "install ok installed" && { pre_log "Pacote previamente instalado: $_pkg"; return 0; } ;;
    dnf|yum) rpm -q "$_pkg" >/dev/null 2>&1 && { pre_log "Pacote previamente instalado: $_pkg"; return 0; } ;;
    pacman) pacman -Q "$_pkg" >/dev/null 2>&1 && { pre_log "Pacote previamente instalado: $_pkg"; return 0; } ;;
    slackpkg) compgen -G "/var/log/packages/$_pkg-[0-9]*" >/dev/null && { pre_log "Pacote previamente instalado: $_pkg"; return 0; }; compgen -G "/var/lib/pkgtools/packages/$_pkg-[0-9]*" >/dev/null && { pre_log "Pacote previamente instalado: $_pkg"; return 0; } ;;
  esac
  if [ -z "$PKG_MGR" ] || [ -z "$_pkg" ]; then return 1; fi
  case "$PKG_ATTEMPTED" in *" $_pkg "*) return 1 ;; esac
  PKG_ATTEMPTED="$PKG_ATTEMPTED$_pkg "
  pre_log "Tentativa de instalacao: $PKG_MGR / $_pkg"
  case "$PKG_MGR" in
    apt-get)
      if ! apt-cache show "$_pkg" >/dev/null 2>&1 && [ "$PKG_UPDATE_DONE" = 0 ]; then
        PKG_UPDATE_DONE=1
        $SUDO_CMD timeout 25s env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=5 -o Acquire::https::Timeout=5 update -qq >/dev/null 2>&1 || pre_error 'APT: falha ao atualizar indices.'
      fi
      apt-cache show "$_pkg" >/dev/null 2>&1 || return 1
      $SUDO_CMD env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=5 -o Acquire::https::Timeout=5 -o DPkg::Lock::Timeout=5 install -y -qq --no-remove --no-install-recommends "$_pkg" >/dev/null 2>&1; return $? ;;
    dnf) dnf -q list --available "$_pkg" >/dev/null 2>&1 || return 1; $SUDO_CMD dnf install -y -q "$_pkg" >/dev/null 2>&1; return $? ;;
    yum) yum -q list available "$_pkg" >/dev/null 2>&1 || return 1; $SUDO_CMD yum install -y -q "$_pkg" >/dev/null 2>&1; return $? ;;
    pacman) pacman -Si "$_pkg" >/dev/null 2>&1 || return 1; $SUDO_CMD pacman -S --noconfirm --needed "$_pkg" >/dev/null 2>&1; return $? ;;
    zypper) $SUDO_CMD zypper --non-interactive install -y "$_pkg" >/dev/null 2>&1; return $? ;;
    apk) $SUDO_CMD apk add --no-cache "$_pkg" >/dev/null 2>&1; return $? ;;
    emerge) $SUDO_CMD emerge --quiet "$_pkg" >/dev/null 2>&1; return $? ;;
    xbps-install) $SUDO_CMD xbps-install -y "$_pkg" >/dev/null 2>&1; return $? ;;
    slackpkg)
      if [ "$PKG_UPDATE_DONE" = "0" ] && [ ! -s /var/lib/slackpkg/pkglist ]; then $SUDO_CMD slackpkg -batch=on -default_answer=y update >/dev/null 2>&1; PKG_UPDATE_DONE=1; fi
      [ -s /var/lib/slackpkg/pkglist ] || return 1
      awk -v p="$_pkg" '$2 == p {found=1} END {exit !found}' /var/lib/slackpkg/pkglist || return 1
      $SUDO_CMD slackpkg -batch=on -default_answer=y install "$_pkg" >/dev/null 2>&1; return $? ;;
    brew) brew install "$_pkg" >/dev/null 2>&1; return $? ;;
    pkg) $SUDO_CMD pkg install -y "$_pkg" >/dev/null 2>&1; return $? ;;
  esac
  return 1
}
ENSURE_DONE=" "
ensure_tool() {
  local _tool="$1" _pkg
  if [ "$_tool" = nmap ] && [ "${INVENTORY_FULL_SCAN:-0}" != 1 ]; then return 1; fi
  case "$ENSURE_DONE" in *" $_tool "*) command -v "$_tool" >/dev/null 2>&1; return $? ;; esac
  ENSURE_DONE="$ENSURE_DONE$_tool "
  pre_log "Verificando ferramenta: $_tool"
  if command -v "$_tool" >/dev/null 2>&1; then pre_log "Presente: $_tool"; return 0; fi
  if [ -x "/usr/sbin/$_tool" ] || [ -x "/sbin/$_tool" ] || [ -x "/usr/local/sbin/$_tool" ]; then return 0; fi
  if [ "$INVENTORY_AUTOINSTALL" != "1" ]; then pre_log "Ausente: $_tool (instalacao desabilitada)"; return 1; fi
  if [ "$_tool" = "hddtemp" ]; then
    if command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W -f='${Status}' hddtemp 2>/dev/null | grep -q "install ok installed"; then return 0; fi
    if command -v smartctl >/dev/null 2>&1 || [ -x "/usr/sbin/smartctl" ]; then return 1; fi
  fi
  case "$_tool" in
    systemd-detect-virt|timedatectl|systemctl|bootctl) if [ "$HAS_SYSTEMD" = "0" ]; then return 1; fi ;;
    nmcli|iw) if [ "$HAS_WIFI" = "0" ]; then return 1; fi ;;
    apt|dpkg|dnf|yum|pacman|zypper|snap|flatpak) return 1 ;;
    wget) return 1 ;;
    bootctl|fwupdmgr|ufw|nft|iptables) return 1 ;;
  esac
  if [ -z "$PKG_MGR" ]; then return 1; fi
  _pkg=$(pkg_name_for "$_tool")
  if [ $? -ne 0 ] || [ -z "$_pkg" ]; then pre_error "$_tool: sem pacote mapeado para $PKG_MGR."; return 1; fi
  :
  pre_log "Consulta/instalacao se necessario: $PKG_MGR / $_pkg (repositorios configurados no sistema)"
  if install_pkg "$_pkg"; then pre_log "Verificacao/instalacao concluida: $_pkg"; else pre_error "$_tool: pacote $_pkg indisponivel ou falha na instalacao."; fi
  hash -r 2>/dev/null
  if command -v "$_tool" >/dev/null 2>&1 || [ -x "/usr/sbin/$_tool" ] || [ -x "/sbin/$_tool" ]; then return 0; fi
  pre_error "$_tool: executavel indisponivel apos verificacao."
  return 1
}
ensure_tools() { local _t; for _t in "$@"; do ensure_tool "$_t" || :; done; return 0; }
:
if [ "$INVENTORY_AUTOINSTALL" = "1" ] && [ "$ENV_PRIV" = "none" ]; then
  :
fi
bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout -k 1s 5s "$@"; else "$@"; fi
}
RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
C_TITLE=$'\033[38;5;220m'; C_VALUE=$'\033[37m'; C_BLUE=$'\033[38;5;39m'; C_OK=$'\033[38;5;82m'; C_SOFT=$'\033[38;5;245m'; C_HASH=$'\033[38;5;220m'; C_YELLOW=$'\033[38;5;220m'; BG=$'\033[48;5;235m'; BG_WHITE=$'\033[48;5;15m'; C_BLACK=$'\033[30m'
COLOR_ENABLED=0; CURSOR_ENABLED=0
if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && command -v tput >/dev/null 2>&1; then
  if tput el >/dev/null 2>&1 && tput cuu1 >/dev/null 2>&1; then CURSOR_ENABLED=1; fi
  _colors=$(tput colors 2>/dev/null)
  case "$_colors" in ''|*[!0-9]*) _colors=0 ;; esac
  if [ "$_colors" -ge 256 ] && [ "${NO_COLOR+x}" != x ]; then COLOR_ENABLED=1; fi
fi
if [ "$COLOR_ENABLED" = 0 ]; then
  RESET=; BOLD=; DIM=; C_TITLE=; C_VALUE=; C_BLUE=; C_OK=; C_SOFT=; C_HASH=; C_YELLOW=; BG=; BG_WHITE=; C_BLACK=
  CURSOR_ENABLED=0
fi
open_file_de_independent() {
  local _f="$1" _op _pid _i _user _uid _home _runtime _copy _auth _display _wayland
  local _desktop _mime _type _desktop_path _dir
  local -a _as _env _apps _args
  if [ ! -f "$_f" ] || [ ! -r "$_f" ]; then
    printf 'Relatorio inexistente ou sem permissao de leitura: %s\n' "$_f"
    return 1
  fi
  _as=(); _env=(); _display=${DISPLAY:-}; _wayland=${WAYLAND_DISPLAY:-}
  if [ "$(id -u)" = 0 ]; then
    _user=${SUDO_USER:-}
    [ -n "$_user" ] || _user=$(logname 2>/dev/null)
    _uid=$(id -u "$_user" 2>/dev/null) || _uid=0
    if [ "$_uid" = 0 ] || [ -z "$_user" ]; then
      printf 'Sessao grafica de usuario nao identificada. Execute como usuario normal.\n'; return 1
    fi
    _home=$(getent passwd "$_user" | cut -d: -f6)
    [ -d "$_home" ] || return 1
    if command -v runuser >/dev/null 2>&1; then _as=(runuser -u "$_user" --)
    elif command -v sudo >/dev/null 2>&1; then _as=(sudo -u "$_user" --)
    else printf 'Nao foi possivel acessar a sessao grafica do usuario.\n'; return 1; fi
    _runtime=/run/user/$_uid
    _auth=${XAUTHORITY:-$_home/.Xauthority}
    _env=(env -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR -u XAUTHORITY -u WAYLAND_DISPLAY "HOME=$_home" "USER=$_user" "LOGNAME=$_user" "DISPLAY=$_display")
    [ -r "$_auth" ] && _env+=("XAUTHORITY=$_auth")
    if [ -d "$_runtime" ]; then
      _env+=("XDG_RUNTIME_DIR=$_runtime")
      [ -S "$_runtime/bus" ] && _env+=("DBUS_SESSION_BUS_ADDRESS=unix:path=$_runtime/bus")
      if [ -z "$_wayland" ] && [ -S "$_runtime/wayland-0" ]; then _wayland=wayland-0; fi
    fi
    [ -n "$_wayland" ] && _env+=("WAYLAND_DISPLAY=$_wayland")
    _copy=$("${_as[@]}" "${_env[@]}" bash -c 'umask 077; mktemp -d "${HOME}/InventoryTaker-open.XXXXXX"') || return 1
    local _report
    for _report in "$REPORT_FILE" "$HTML_FILE" "$CSV_FILE" "$JSON_FILE" "$PREP_FILE"; do
      [ -f "$_report" ] || continue
      "${_as[@]}" "${_env[@]}" bash -c 'umask 077; cat > "$1"' bash "$_copy/${_report##*/}" < "$_report" || return 1
    done
    _copy="$_copy/${_f##*/}"
    _f=$_copy
  fi
  if [ -z "$_display" ] && [ -z "$_wayland" ]; then
    printf 'Sessao grafica indisponivel. Relatorio: %s\n' "$_f"; return 1
  fi
  local _uri="" _byte _hex _j
  if [ "${_f##*.}" = html ]; then
    if [ ! -s "$_f" ] || ! grep -qi '^<!doctype html>' "$_f" || ! grep -qi '</html>' "$_f"; then
      printf 'Relatorio HTML incompleto: %s\n' "$_f"; return 1
    fi
    _uri=$(LC_ALL=C; export LC_ALL; printf 'file://'; for ((_j=0; _j<${#_f}; _j++)); do
      _byte=${_f:$_j:1}; case "$_byte" in [a-zA-Z0-9/._~-]) printf '%s' "$_byte";; *) printf '%%%02X' "'$_byte";; esac
    done)
  fi
  case "${_f##*.}" in
    html) _apps=(browser-default firefox firefox-esr chromium chromium-browser google-chrome google-chrome-stable brave-browser microsoft-edge vivaldi opera librewolf epiphany falkon) ;;
    csv) _apps=(libreoffice localc gnumeric calligrasheets) ;;
    txt) _apps=(mime-default mousepad kate gedit xed featherpad geany pluma kwrite leafpad) ;;
    json) _apps=(editor-default mousepad kate gedit xed featherpad geany pluma kwrite leafpad medit) ;;
    *) return 1 ;;
  esac
  for _op in "${_apps[@]}"; do
    case "$_op" in
      browser-default)
        command -v xdg-settings >/dev/null 2>&1 && command -v gio >/dev/null 2>&1 || continue
        _desktop=$("${_as[@]}" "${_env[@]}" xdg-settings get default-web-browser 2>/dev/null)
        [ -n "$_desktop" ] || continue
        _mime="$_desktop" ;;
      mime-default|editor-default)
        command -v xdg-mime >/dev/null 2>&1 && command -v gio >/dev/null 2>&1 || continue
        case "${_f##*.}" in txt) _type=text/plain;; json) _type=text/plain;; esac
        _mime=$("${_as[@]}" "${_env[@]}" xdg-mime query default "$_type" 2>/dev/null)
        [ -n "$_mime" ] || continue ;;
    esac
    case "$_op" in
      browser-default|mime-default|editor-default)
        case "$_mime" in */*|*..*|*[!a-zA-Z0-9_.-]*) continue;; esac
        _desktop_path=""
        for _dir in "${_home:-$HOME}/.local/share/applications" /usr/local/share/applications /usr/share/applications /var/lib/snapd/desktop/applications /var/lib/flatpak/exports/share/applications "${_home:-$HOME}/.local/share/flatpak/exports/share/applications"; do
          if [ -f "$_dir/$_mime" ]; then _desktop_path="$_dir/$_mime"; break; fi
        done
        [ -n "$_desktop_path" ] || continue
        grep -qi '^Terminal=true' "$_desktop_path" && continue
        case "$_op" in
          browser-default) grep -Eiq '^Categories=.*WebBrowser;' "$_desktop_path" || continue
            grep -Eiq '^Exec=.*(pgadmin|pgAdmin)' "$_desktop_path" && continue ;;
          editor-default) grep -Eiq '^Categories=.*TextEditor;' "$_desktop_path" || continue ;;
        esac
        if [ "$_op" = browser-default ]; then _args=(launch "$_desktop_path" "$_uri"); else _args=(launch "$_desktop_path" "$_f"); fi; _op=gio ;;
      libreoffice) _args=(--calc "$_f") ;;
      *) if [ -n "$_uri" ]; then _args=("$_uri"); else _args=("$_f"); fi ;;
    esac
    command -v "$_op" >/dev/null 2>&1 || continue
    "${_as[@]}" "${_env[@]}" "$_op" "${_args[@]}" </dev/null >/dev/null 2>&1 &
    _pid=$!; _i=0
    while kill -0 "$_pid" 2>/dev/null && [ "$_i" -lt 2 ]; do
      sleep 1; _i=$((_i+1))
    done
    if kill -0 "$_pid" 2>/dev/null; then return 0; fi
    if wait "$_pid"; then return 0; fi
  done
  printf 'Nenhum aplicativo grafico compativel conseguiu abrir: %s\n' "$_f"
  return 1
}
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
BORDER_CELL='#'
case "${LC_ALL:-}" in *utf*|*UTF*) BORDER_CELL='█';; esac
if [ "$BORDER_CELL" = '█' ]; then HASH_LINE=${HASH_LINE//#/█}; fi
GRAD_LINE=""
for ((_g=0; _g<BW; _g++)); do
  case $((_g*5/BW)) in 0) _gc=136;; 1) _gc=178;; 2) _gc=220;; 3) _gc=226;; *) _gc=229;; esac
  if [ "$COLOR_ENABLED" = 0 ]; then GRAD_LINE="$GRAD_LINE$BORDER_CELL"; continue; fi
  GRAD_LINE="$GRAD_LINE$(printf '\033[38;5;%sm%s' "$_gc" "$BORDER_CELL")"
done
GRAD_LINE="$GRAD_LINE$RESET"
L=(); M=(); R=(); LS=(); MS=(); RS=()
add_L() { local _safe; _safe=$(printf '%s' "$1" | tr -d '\001-\037\177'); L[${#L[@]}]="$_safe"; LS[${#LS[@]}]="$2"; }
add_M() { local _safe; _safe=$(printf '%s' "$1" | tr -d '\001-\037\177'); M[${#M[@]}]="$_safe"; MS[${#MS[@]}]="$2"; }
add_R() { local _safe; _safe=$(printf '%s' "$1" | tr -d '\001-\037\177'); R[${#R[@]}]="$_safe"; RS[${#RS[@]}]="$2"; }
array_len() {
  case "$1" in
    L) printf '%s' "${#L[@]}" ;; LS) printf '%s' "${#LS[@]}" ;;
    M) printf '%s' "${#M[@]}" ;; MS) printf '%s' "${#MS[@]}" ;;
    R) printf '%s' "${#R[@]}" ;; RS) printf '%s' "${#RS[@]}" ;;
    NL) printf '%s' "${#NL[@]}" ;; NLS) printf '%s' "${#NLS[@]}" ;;
    NM) printf '%s' "${#NM[@]}" ;; NMS) printf '%s' "${#NMS[@]}" ;;
    NR) printf '%s' "${#NR[@]}" ;; NRS) printf '%s' "${#NRS[@]}" ;;
    *) return 1 ;;
  esac
}
array_get() {
  case "$1" in
    L) printf '%s' "${L[$2]}" ;; LS) printf '%s' "${LS[$2]}" ;;
    M) printf '%s' "${M[$2]}" ;; MS) printf '%s' "${MS[$2]}" ;;
    R) printf '%s' "${R[$2]}" ;; RS) printf '%s' "${RS[$2]}" ;;
    *) return 1 ;;
  esac
}
array_append() {
  case "$1" in
    NL) NL[${#NL[@]}]="$2" ;; NLS) NLS[${#NLS[@]}]="$2" ;;
    NM) NM[${#NM[@]}]="$2" ;; NMS) NMS[${#NMS[@]}]="$2" ;;
    NR) NR[${#NR[@]}]="$2" ;; NRS) NRS[${#NRS[@]}]="$2" ;;
    *) return 1 ;;
  esac
}
wrap_one() {
  _src=$1; _ssrc=$2; _dst=$3; _sdst=$4
  _n=$(array_len "$_src"); _i=0
  while [ "$_i" -lt "$_n" ]; do
    _t=$(array_get "$_src" "$_i")
    _s=$(array_get "$_ssrc" "$_i")
    if [ "$_s" = "0" ]; then
      case "$_t" in
        ST:*)
          array_append "$_dst" "$_t"; array_append "$_sdst" "$_s" ;;
        *:*)
          _label=$(printf '%s' "$_t" | cut -d: -f1); _val=$(printf '%s' "$_t" | cut -d: -f2-)
          _label2="${_label}:"
          if [ "${#_t}" -le "$INNER" ]; then
            array_append "$_dst" "$_t"; array_append "$_sdst" "$_s"
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
              array_append "$_dst" "$_line"; array_append "$_sdst" "0"
              if [ -z "$_rest" ]; then break; fi
            done
          fi
          ;;
        *)
          if [ "${#_t}" -le "$INNER" ]; then
            array_append "$_dst" "$_t"; array_append "$_sdst" "$_s"
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
              array_append "$_dst" "$_line"; array_append "$_sdst" "0"
              if [ -z "$_rest" ]; then break; fi
            done
          fi
          ;;
      esac
    else
      array_append "$_dst" "$_t"; array_append "$_sdst" "$_s"
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
  local _max=${#L[@]}
  [ "${#M[@]}" -le "$_max" ] || _max=${#M[@]}
  [ "${#R[@]}" -le "$_max" ] || _max=${#R[@]}
  while [ "${#L[@]}" -lt "$_max" ]; do add_L "" 0; done
  while [ "${#M[@]}" -lt "$_max" ]; do add_M "" 0; done
  while [ "${#R[@]}" -lt "$_max" ]; do add_R "" 0; done
  add_L "__TOP__" 3; add_M "__TOP__" 3; add_R "__TOP__" 3
}
render_one() {
  _t="$1"; _s="$2"
  if [ "$_s" = "7" ]; then printf "%*s" "$BW" ""; return; fi
  if [ "$_t" = "__TOP__" ]; then printf '%s' "${GRAD_LINE}"; return; fi
  if [ "$_s" = "1" ]; then _c=$(pad_center "$_t" "$INNER"); printf '%s' "${C_HASH}${BORDER_CELL}${RESET}${BG_WHITE}${BOLD}${C_BLACK}${_c}${RESET}${C_HASH}${BORDER_CELL}${RESET}"; return; fi
  if [ "$_s" = "2" ]; then _d=""; _k=0; while [ "$_k" -lt "$INNER" ]; do _d="${_d}-"; _k=$(( _k + 1 )); done; printf '%s' "${C_HASH}${BORDER_CELL}${RESET}${BG}${C_SOFT}${_d}${RESET}${C_HASH}${BORDER_CELL}${RESET}"; return; fi
  if [ "$_s" = "9" ]; then _p=$(pad_right "$_t" "$INNER"); printf '%s' "${C_HASH}${BORDER_CELL}${RESET}${BG}${C_OK}${_p}${RESET}${C_HASH}${BORDER_CELL}${RESET}"; return; fi
  if [ "$_s" = "8" ]; then _p=$(pad_right "$_t" "$INNER"); printf '%s' "${C_HASH}${BORDER_CELL}${RESET}${BG}${C_VALUE}${_p}${RESET}${C_HASH}${BORDER_CELL}${RESET}"; return; fi
  if [ "$_s" = "4" ]; then _p=$(pad_right "$_t" "$INNER"); printf '%s' "${C_HASH}${BORDER_CELL}${RESET}${BG}${C_YELLOW}${_p}${RESET}${C_HASH}${BORDER_CELL}${RESET}"; return; fi
  if [ "$_s" = "6" ]; then
    _status=$(printf '%s' "$_t" | awk '{print $NF}'); _rest=$(printf '%s' "$_t" | sed 's/ [^ ]*$//')
    _content_len=$(( 1 + ${#_rest} + 1 + ${#_status} )); _fill=$(( INNER - _content_len ))
    if [ "$_fill" -lt 0 ]; then _fill=0; fi
    _f=""; _k=0; while [ "$_k" -lt "$_fill" ]; do _f="${_f} "; _k=$(( _k + 1 )); done
    printf '%s' "${C_HASH}${BORDER_CELL}${RESET}${BG}${C_VALUE} ${_rest} ${RESET}${BG}${C_YELLOW}${_status}${RESET}${BG}${_f}${RESET}${C_HASH}${BORDER_CELL}${RESET}"; return
  fi
  case "$_t" in
    ST:*)
      _rest=$(printf '%s' "$_t" | cut -d: -f2-); _grande=$(printf '%s' "$_rest" | cut -d'|' -f1); _line=$(printf '%s' "$_rest" | cut -d'|' -f2)
      _line_p=$(pad_right "$_line" $(( INNER - 1 )))
      if [ "$_grande" = "1" ]; then
        _head=$(printf '%s' "$_line_p" | cut -c "1-$(( INNER - 9 ))")
        _livre=$(printf '%s' "$_line_p" | cut -c "$(( INNER - 8 ))-$(( INNER - 3 ))")
        _livre=$(pad_right "$_livre" 6)
        printf '%s' "${C_HASH}${BORDER_CELL}${RESET}${BG}${C_VALUE}${_head}${RESET}${BG}${C_YELLOW}${_livre}${RESET}${BG}   ${RESET}${C_HASH}${BORDER_CELL}${RESET}"
      else
        printf '%s' "${C_HASH}${BORDER_CELL}${RESET}${BG}${C_VALUE}${_line_p} ${RESET}${C_HASH}${BORDER_CELL}${RESET}"
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
      printf '%s' "${C_HASH}${BORDER_CELL}${RESET}${BG}${C_YELLOW}${_label}${RESET}${BG}${C_VALUE}${_val_cut}${_pad}${RESET}${C_HASH}${BORDER_CELL}${RESET}"
      return ;;
  esac
  _p=$(pad_right "$_t" "$INNER")
  printf '%s' "${C_HASH}${BORDER_CELL}${RESET}${BG}${C_VALUE}${_p}${RESET}${C_HASH}${BORDER_CELL}${RESET}"
}
print_trio() {
  _la=${#L[@]}; _ma=${#M[@]}; _ra=${#R[@]}; _max=$_la
  if [ "$_ma" -gt "$_max" ]; then _max=$_ma; fi
  if [ "$_ra" -gt "$_max" ]; then _max=$_ra; fi
  _i=0
  while [ "$_i" -lt "$_max" ]; do
    _lt="${L[$_i]}"; _mt="${M[$_i]}"; _rt="${R[$_i]}"; _ls="${LS[$_i]}"; _ms="${MS[$_i]}"; _rs="${RS[$_i]}"
    if [ -z "$_ls" ]; then _ls=7; _lt=""; fi
    if [ -z "$_ms" ]; then _ms=7; _mt=""; fi
    if [ -z "$_rs" ]; then _rs=7; _rt=""; fi
    _a=$(render_one "$_lt" "$_ls"); _b=$(render_one "$_mt" "$_ms"); _c=$(render_one "$_rt" "$_rs")
    printf '%s %s %s\n' "$_a" "$_b" "$_c"
    _i=$(( _i + 1 ))
  done
  L=(); M=(); R=(); LS=(); MS=(); RS=()
}
print_close() { printf '%s %s %s\n' "${GRAD_LINE}" "${GRAD_LINE}" "${GRAD_LINE}"; }
html_esc() { printf '%s' "$1" | tr '\r\n\t' '   ' | tr -d '\001-\010\013\014\016-\037' | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
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
  if [ "$INVENTORY_EXT_IP" != "1" ]; then printf 'N/A'; return; fi
  ensure_tool curl; _cand=""
  if command -v curl >/dev/null 2>&1; then
    _cand=$(curl -q -fsS --proto =https --max-time 3 https://ifconfig.me/ip 2>/dev/null | tr -d ' \n\r\t' | head -n 1)
    if is_valid_ipv4 "$_cand"; then printf '%s' "$_cand"; return; fi
    _cand=$(curl -q -fsS --proto =https --max-time 3 https://api.ipify.org 2>/dev/null | tr -d ' \n\r\t' | head -n 1)
    if is_valid_ipv4 "$_cand"; then printf '%s' "$_cand"; return; fi
    _cand=$(curl -q -fsS --proto =https --max-time 3 https://checkip.amazonaws.com 2>/dev/null | tr -d ' \n\r\t' | head -n 1)
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
      _sd=$(LC_ALL=C bounded $SUDO_CMD smartctl -A "$BOOT_DISK" 2>/dev/null | grep -i -E "Temperature_Celsius|Temperature:|Composite Temperature" | head -n 1 | grep -o -E "[0-9]+(\.[0-9]+)?" | tail -n 1)
      if [ -n "$_sd" ]; then TEMP_DISK=$(fmt_temp "$_sd" || printf 'N/A'); fi
    fi
    if [ "$TEMP_DISK" = "N/A" ] && command -v hddtemp >/dev/null 2>&1; then
      _hd=$(LC_ALL=C bounded $SUDO_CMD hddtemp -n "$BOOT_DISK" 2>/dev/null | tr -d ' \n')
      if [ -n "$_hd" ]; then TEMP_DISK=$(fmt_temp "$_hd" || printf 'N/A'); fi
    fi
  fi
}
[ "$CURSOR_ENABLED" = 0 ] || clear 2>/dev/null
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
  _banner_inventory
  _banner_line "" ""
  _banner_line 'INVENTORYTAKER - Desktop' "$_c_wht"
  _banner_line 'INVENTÁRIO COMPLETO DO SISTEMA' "$_c_wht"
  _banner_line "" ""
  if [ "$_use_color" = "1" ]; then printf '%s%s%s\n' "${BOLD}${C_TITLE}" "$_bw_line" "${RESET}"; else printf '%s\n' "$_bw_line"; fi
}
INVENTORY_DOC_URL='https://github.com/Everaldo-127/linux-xubuntu/blob/main/Documenta%C3%A7%C3%A3o/Manual_Inventorytaker.pdf'
open_inventory_documentation() {
  local _op _pid _i _user _uid _home _runtime _auth _display _wayland _desktop _desktop_path _dir
  local -a _as _env _apps _args
  _as=(); _env=(); _display=${DISPLAY:-}; _wayland=${WAYLAND_DISPLAY:-}
  if [ "$(id -u)" = 0 ]; then
    _user=${SUDO_USER:-}
    [ -n "$_user" ] || _user=$(logname 2>/dev/null)
    _uid=$(id -u "$_user" 2>/dev/null) || _uid=0
    if [ "$_uid" = 0 ] || [ -z "$_user" ]; then
      printf 'Sessao grafica de usuario nao identificada. Execute como usuario normal.\n'; return 1
    fi
    _home=$(getent passwd "$_user" | cut -d: -f6)
    [ -d "$_home" ] || return 1
    if command -v runuser >/dev/null 2>&1; then _as=(runuser -u "$_user" --)
    elif command -v sudo >/dev/null 2>&1; then _as=(sudo -u "$_user" --)
    else printf 'Nao foi possivel acessar a sessao grafica do usuario.\n'; return 1; fi
    _runtime=/run/user/$_uid
    _auth=${XAUTHORITY:-$_home/.Xauthority}
    _env=(env -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR -u XAUTHORITY -u WAYLAND_DISPLAY "HOME=$_home" "USER=$_user" "LOGNAME=$_user" "DISPLAY=$_display")
    [ -r "$_auth" ] && _env+=("XAUTHORITY=$_auth")
    if [ -d "$_runtime" ]; then
      _env+=("XDG_RUNTIME_DIR=$_runtime")
      [ -S "$_runtime/bus" ] && _env+=("DBUS_SESSION_BUS_ADDRESS=unix:path=$_runtime/bus")
      if [ -z "$_wayland" ] && [ -S "$_runtime/wayland-0" ]; then _wayland=wayland-0; fi
    fi
    [ -n "$_wayland" ] && _env+=("WAYLAND_DISPLAY=$_wayland")
  fi
  if [ -z "$_display" ] && [ -z "$_wayland" ]; then
    printf 'Sessao grafica indisponivel. Link: %s\n' "$INVENTORY_DOC_URL"; return 1
  fi
  _apps=(browser-default firefox firefox-esr chromium chromium-browser google-chrome google-chrome-stable brave-browser microsoft-edge vivaldi opera librewolf epiphany falkon xdg-open gio)
  for _op in "${_apps[@]}"; do
    _args=("$INVENTORY_DOC_URL")
    case "$_op" in
      browser-default)
        command -v xdg-settings >/dev/null 2>&1 && command -v gio >/dev/null 2>&1 || continue
        _desktop=$("${_as[@]}" "${_env[@]}" xdg-settings get default-web-browser 2>/dev/null) || continue
        case "$_desktop" in ''|*/*|*..*|*[!a-zA-Z0-9_.-]*) continue;; esac
        _desktop_path=""
        for _dir in "${_home:-$HOME}/.local/share/applications" /usr/local/share/applications /usr/share/applications /var/lib/snapd/desktop/applications /var/lib/flatpak/exports/share/applications "${_home:-$HOME}/.local/share/flatpak/exports/share/applications"; do
          if [ -f "$_dir/$_desktop" ]; then _desktop_path="$_dir/$_desktop"; break; fi
        done
        [ -n "$_desktop_path" ] || continue
        grep -qi '^Terminal=true' "$_desktop_path" && continue
        grep -Eiq '^Categories=.*WebBrowser;' "$_desktop_path" || continue
        grep -Eiq '^Exec=.*pgadmin' "$_desktop_path" && continue
        _op=gio; _args=(launch "$_desktop_path" "$INVENTORY_DOC_URL") ;;
      gio) _args=(open "$INVENTORY_DOC_URL") ;;
    esac
    command -v "$_op" >/dev/null 2>&1 || continue
    "${_as[@]}" "${_env[@]}" "$_op" "${_args[@]}" </dev/null >/dev/null 2>&1 &
    _pid=$!; _i=0
    while kill -0 "$_pid" 2>/dev/null && [ "$_i" -lt 2 ]; do sleep 1; _i=$((_i+1)); done
    if kill -0 "$_pid" 2>/dev/null; then return 0; fi
    if wait "$_pid" 2>/dev/null; then return 0; fi
  done
  printf 'Nao foi possivel abrir o navegador. Link: %s\n' "$INVENTORY_DOC_URL"
  return 1
}
CHECK_MODE=0
if [ "${1:-}" = "--check" ]; then CHECK_MODE=1; fi
HOST=$(hostname); NOW=$(date "+%Y-%m-%d %H:%M:%S"); TOTAL_W=$(( BW * 3 + 2 ))
print_banner "$COLOR_ENABLED"
printf '\n'
_author_line="Autor: Everaldo Costa Silva / Licença: MIT"; _author_c=$(pad_center "$_author_line" "$TOTAL_W")
printf '%s%s%s\n' "${C_BLUE}" "$_author_c" "${RESET}"
_host_line="Host: $HOST  |  Atualizado em: $NOW"; _host_c=$(pad_center "$_host_line" "$TOTAL_W")
printf '%s%s%s\n' "${C_BLUE}" "$_host_c" "${RESET}"
_compat_line="Compativel: Kernel >= 3.10 | Bash >= 3.x"; _compat_c=$(pad_center "$_compat_line" "$TOTAL_W")
printf '%s%s%s\n' "${C_BLUE}" "$_compat_c" "${RESET}"
printf '\n'
inventory_progress() {
  [ -t 1 ] && [ "$CHECK_MODE" = 0 ] || return 0
  local pct="$1" i color width=36 filled pad
  filled=$((pct * width / 100))
  if [ "$COLOR_ENABLED" = 0 ]; then
    printf 'Preparando o ambiente e coletando informações: ['
    for ((i=0; i<width; i++)); do if [ "$i" -lt "$filled" ]; then printf '#'; else printf '-'; fi; done
    printf '] %d%%\n' "$pct"
    return 0
  fi
  pad=$(((TOTAL_W - width - 53) / 2))
  [ "$pad" -ge 0 ] || pad=0
  printf '\r\033[0m\033[2K%*s%sPreparando o ambiente e coletando informações:%s [' "$pad" '' "$C_YELLOW" "$RESET"
  for ((i=0; i<width; i++)); do
    if [ "$i" -lt "$filled" ]; then
      case $((i*5/width)) in 0) color=136;; 1) color=178;; 2) color=220;; 3) color=226;; *) color=229;; esac
      printf '\033[48;5;%sm ' "$color"
    else
      printf '\033[48;5;238m '
    fi
  done
  printf '\033[0m] %d%%' "$pct"
  printf '\033[?25l'
}
if [ "$CURSOR_ENABLED" = 1 ]; then
  trap 'printf "\033[0m\033[?25h"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi
inventory_progress 0
ensure_tools tput hostname date grep awk sed cut head tail tr sort uniq df uptime id uname free lscpu who od dd mkdir cat wc pgrep pidof
inventory_progress 5
ensure_tools ip ss nmap lsof curl findmnt lsblk fdisk sfdisk parted lspci lsusb
inventory_progress 10
ensure_tools dmidecode biosdecode efibootmgr mokutil efivar lshw inxi hwinfo fwupdmgr bootctl
inventory_progress 15
ensure_tools sensors hddtemp smartctl nmcli iw systemd-detect-virt timedatectl systemctl getenforce
inventory_progress 20
pre_log "Fim da preparacao inicial; inicio das coletas."
PRE_INITIAL_END=$SECONDS
PRE_INITIAL_END_MS=$(pre_clock_ms)
ensure_tools uname grep cut tr dmidecode lsblk fdisk findmnt
OS_NAME=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
OS_VER=$(grep VERSION_ID /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
if [ "$ENV_FAMILY" = slackware ] && [ -r /etc/slackware-version ]; then OS_NAME=$(cat /etc/slackware-version); OS_VER=${OS_NAME#Slackware }; fi
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
inventory_progress 25
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
MEM_DEVICES=()
if command -v dmidecode >/dev/null 2>&1; then
  while IFS= read -r _memrow; do
    [ -n "$_memrow" ] && MEM_DEVICES[${#MEM_DEVICES[@]}]="$_memrow"
  done < <(LC_ALL=C bounded $SUDO_CMD dmidecode -t 17 2>/dev/null | awk '
    function emit(){if(size!="" && size !~ /No Module|Not Installed/) print "Slot: " loc " | " size " | " typ " | " speed " | " maker " | " part}
    /^Memory Device$/ {emit(); size=loc=typ=speed=maker=part=""; next}
    /^[[:space:]]+Size:/ {size=$0; sub(/^[^:]*: */,"",size)}
    /^[[:space:]]+Locator:/ {loc=$0; sub(/^[^:]*: */,"",loc)}
    /^[[:space:]]+Type:/ {typ=$0; sub(/^[^:]*: */,"",typ)}
    /^[[:space:]]+Speed:/ {speed=$0; sub(/^[^:]*: */,"",speed)}
    /^[[:space:]]+Manufacturer:/ {maker=$0; sub(/^[^:]*: */,"",maker)}
    /^[[:space:]]+Part Number:/ {part=$0; sub(/^[^:]*: */,"",part)}
    END {emit()}')
fi
[ "${#MEM_DEVICES[@]}" -gt 0 ] || MEM_DEVICES=("N/A (SMBIOS indisponivel)")

inventory_progress 30
ensure_tools grep cat
_DMI_BIOS=""; _DMI_SYS=""; _DMI_BOARD=""; _DMI_PROC=""; _LSHW=""; _INXI=""; _FWUPD=""; _EFIBOOT=""
if command -v dmidecode >/dev/null 2>&1; then
  _DMI_BIOS=$(LC_ALL=C bounded $SUDO_CMD dmidecode -t bios 2>/dev/null)
  _DMI_SYS=$(LC_ALL=C bounded $SUDO_CMD dmidecode -t system 2>/dev/null)
  _DMI_BOARD=$(LC_ALL=C bounded $SUDO_CMD dmidecode -t baseboard 2>/dev/null)
  _DMI_PROC=$(LC_ALL=C bounded $SUDO_CMD dmidecode -t processor 2>/dev/null)
fi
if command -v lshw >/dev/null 2>&1; then _LSHW=$(LC_ALL=C bounded $SUDO_CMD lshw -short 2>/dev/null | head -n 60); fi
if command -v inxi >/dev/null 2>&1; then _INXI=$(LC_ALL=C bounded inxi -S -M -C 2>/dev/null); fi
if command -v fwupdmgr >/dev/null 2>&1; then _FWUPD=$(LC_ALL=C bounded fwupdmgr get-devices 2>/dev/null | head -n 80); fi
if command -v efibootmgr >/dev/null 2>&1; then _EFIBOOT=$(LC_ALL=C bounded $SUDO_CMD efibootmgr -v 2>/dev/null); fi
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
  _cand=$(LC_ALL=C bounded $SUDO_CMD lshw -C cpu 2>/dev/null | grep -i -m1 "product:" | cut -d: -f2- | sed 's/^ //;s/[[:space:]]*$//')
  _cand=$(clean_dmi "$_cand")
  if [ -n "$_cand" ] && [ "$_cand" != "N/A" ]; then CPU_MODEL="$_cand"; fi
fi
if [ -z "$CPU_MODEL" ] && command -v inxi >/dev/null 2>&1; then
  _cand=$(LC_ALL=C bounded inxi -C 2>/dev/null | grep -i -m1 "model:" | sed 's/.*model:[[:space:]]*//;s/[[:space:]]*$//')
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
  _smbios_raw=$(LC_ALL=C bounded $SUDO_CMD dmidecode 2>/dev/null | grep -i "SMBIOS" | head -n 1)
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
inventory_progress 40
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
    _sfd_out=$(LC_ALL=C bounded $SUDO_CMD sfdisk -l "$BOOT_DISK" 2>/dev/null)
    if printf '%s' "$_sfd_out" | grep -qi "BIOS boot"; then BOOT_PART_TYPE="EF02 BIOS Boot";
    elif printf '%s' "$_sfd_out" | grep -qi "EFI System"; then BOOT_PART_TYPE="EF00 ESP"; fi
  fi
  if [ "$BOOT_PART_TYPE" = "N/A" ] && command -v parted >/dev/null 2>&1; then
    _pd_out=$(LC_ALL=C bounded $SUDO_CMD parted -s "$BOOT_DISK" print 2>/dev/null)
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
  _sm=$(LC_ALL=C bounded $SUDO_CMD smartctl -H "$BOOT_DISK" 2>/dev/null | grep -i -m1 'self-assessment\|SMART overall' | sed 's/.*: //')
  if [ -n "$_sm" ]; then SMART_STATUS="$_sm"; fi
  _hr=$(LC_ALL=C bounded $SUDO_CMD smartctl -A "$BOOT_DISK" 2>/dev/null | grep -i -m1 'Power_On_Hours' | awk '{print $NF}')
  if [ -n "$_hr" ]; then SMART_HOURS="${_hr}h"; fi
fi
inventory_progress 50
PKG_COUNT="N/A"; UPDATES="N/A"
if command -v dpkg-query >/dev/null 2>&1; then PKG_COUNT=$(dpkg-query -l 2>/dev/null | grep -c '^ii'); fi
if command -v rpm >/dev/null 2>&1; then PKG_COUNT=$(rpm -qa 2>/dev/null | wc -l | tr -d ' '); fi
if command -v pacman >/dev/null 2>&1; then PKG_COUNT=$(pacman -Q 2>/dev/null | wc -l | tr -d ' '); fi
if [ "$PKG_COUNT" = "N/A" ] && [ -d /var/log/packages ]; then PKG_COUNT=$(ls /var/log/packages 2>/dev/null | wc -l | tr -d ' '); fi
if command -v apt-get >/dev/null 2>&1; then UPDATES=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst'); fi
if command -v dnf >/dev/null 2>&1; then UPDATES=$(bounded dnf -C check-update --quiet 2>/dev/null | grep -cv '^$'); fi
LOGGED_N="0"; LOGGED_USERS="N/A"
if command -v who >/dev/null 2>&1; then
  LOGGED_N=$(who 2>/dev/null | wc -l | tr -d ' ')
  _lu=$(who 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//')
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
inventory_progress 55
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
NMAP_OPTS="-sS -sU -sV -p- --open -T4 --host-timeout 4s"
if [ "$ENV_PRIV" = none ] || [ "$SUDO_CMD" = false ]; then NMAP_OPTS="-sT -sV -p- --open -T4 --host-timeout 4s"; fi
NMAP_CMD="nmap $NMAP_OPTS 127.0.0.1"; [ "${INVENTORY_FULL_SCAN:-0}" = 1 ] || NMAP_CMD="Nmap opcional: INVENTORY_FULL_SCAN=1"; UFW_CMD="ufw status"; SS_CMD="ss -tulnp"; PORTS_LINES=()
if [ "$CHECK_MODE" = "0" ] && [ "${INVENTORY_FULL_SCAN:-0}" = 1 ] && command -v nmap >/dev/null 2>&1; then
  _nmap_out=$(bounded ${SUDO_CMD/false/} nmap $NMAP_OPTS 127.0.0.1 2>/dev/null)
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
    _nmap_out2=$(bounded ${SUDO_CMD/false/} nmap $NMAP_OPTS "$NET_IP_EARLY" 2>/dev/null)
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
  _lsof_out=$(bounded lsof -i -P -n -sTCP:LISTEN 2>/dev/null | tail -n +2)
  while IFS= read -r _ll; do
    _name=$(printf '%s' "$_ll" | awk '{print $9}')
    _port=$(printf '%s' "$_name" | sed 's/.*://' | tr -d '[]')
    case "$_port" in ''|*[!0-9]*) continue ;; esac
    _proc=$(printf '%s' "$_ll" | awk '{print $1}')
    case "$_proc" in *apache*|*httpd*) add_port_unique "$_port/tcp" "http" ;; *nginx*) add_port_unique "$_port/tcp" "http" ;; *) add_port_unique "$_port/tcp" "lsof" ;; esac
  done <<EOF_LSOF
$_lsof_out
EOF_LSOF
  _lsof_udp=$(bounded lsof -iUDP -P -n 2>/dev/null | tail -n +2)
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
  _ufw_stat=$(bounded $SUDO_CMD ufw status 2>/dev/null || ufw status 2>/dev/null)
  if printf '%s' "$_ufw_stat" | grep -qi "Status: active"; then UFW_STATUS="ufw ativo";
  elif printf '%s' "$_ufw_stat" | grep -qi "Status: inactive"; then UFW_STATUS="ufw inativo";
  else UFW_STATUS="ufw desconhecido"; fi
  _ufw_all="$_ufw_stat"
  _ufw_all="$_ufw_all
$(bounded $SUDO_CMD ufw status numbered 2>/dev/null || ufw status numbered 2>/dev/null)"
  _ufw_all="$_ufw_all
$(bounded $SUDO_CMD ufw show added 2>/dev/null || ufw show added 2>/dev/null)"
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
inventory_progress 65
ensure_tools ip
WIFI_IFACE="N/A"; WIFI_SSID="N/A"; WIFI_SIGNAL="N/A"; WIFI_IP="N/A"; WIFI_MAC="N/A"; WIFI_STATE="desconectado"; WIFI_FREQ="N/A"
WIFI_CMD="nmcli dev status"
if [ "$HAS_WIFI" = "1" ]; then
  ensure_tools nmcli iw
  if command -v nmcli >/dev/null 2>&1; then
    WIFI_IFACE=$(bounded nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep ":wifi" | cut -d: -f1 | head -n 1)
    if [ -n "$WIFI_IFACE" ]; then
      _wifi_cached=$(bounded nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi list --rescan no 2>/dev/null | grep "^yes:" | head -n 1)
      WIFI_SSID=$(printf "%s" "${_wifi_cached#yes:}" | sed 's/:[^:]*$//')
      if [ -z "$WIFI_SSID" ]; then WIFI_SSID="N/A"; fi
      WIFI_SIGNAL=${_wifi_cached##*:}
      if [ -n "$WIFI_SIGNAL" ]; then WIFI_SIGNAL="${WIFI_SIGNAL}%"; else WIFI_SIGNAL="N/A"; fi
      WIFI_STATE=$(bounded nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^${WIFI_IFACE}:" | cut -d: -f2)
      if [ -z "$WIFI_STATE" ]; then WIFI_STATE="N/A"; fi
    fi
  else WIFI_CMD="iw dev"; fi
  if [ "$WIFI_IFACE" = "N/A" ] || [ -z "$WIFI_IFACE" ]; then
    if command -v iw >/dev/null 2>&1; then WIFI_IFACE=$(bounded iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -n 1); fi
    if [ -z "$WIFI_IFACE" ]; then WIFI_IFACE="N/A"; fi
  fi
  if [ "$WIFI_IFACE" != "N/A" ]; then
    WIFI_IP=$(ip -4 -o addr show "$WIFI_IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)
    if [ -z "$WIFI_IP" ]; then WIFI_IP="N/A"; fi
    WIFI_MAC=$(ip link show "$WIFI_IFACE" 2>/dev/null | grep "link/ether" | awk '{print $2}' | head -n 1)
    if [ -z "$WIFI_MAC" ]; then WIFI_MAC="N/A"; fi
    if command -v iw >/dev/null 2>&1; then
      WIFI_FREQ=$(bounded iw dev "$WIFI_IFACE" link 2>/dev/null | grep "freq:" | awk '{print $2" MHz"}' | head -n 1)
      if [ -z "$WIFI_FREQ" ]; then WIFI_FREQ="N/A"; fi
    fi
  fi
fi
case "$WIFI_STATE" in
  *connected*|*conectado*|*up*) WIFI_ATIVO="ATIVO" ;;
  *) if [ "$WIFI_IP" != "N/A" ]; then WIFI_ATIVO="ATIVO"; else WIFI_ATIVO="INATIVO"; fi ;;
esac
inventory_progress 70
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
MANAGER_LABELS=(); MANAGER_VALUES=()
add_manager() {
  case "$2" in ''|N/A*|'nao instalado'|unknown|desconhecido) return 0 ;; esac
  MANAGER_LABELS[${#MANAGER_LABELS[@]}]="$1"
  MANAGER_VALUES[${#MANAGER_VALUES[@]}]="$2"
}
add_manager Servicos "$SVC_MGR"
add_manager 'Ambiente grafico' "$DE_VAL"
DM_FOUND=""
for _dm in lightdm gdm gdm3 sddm lxdm xdm slim greetd; do
  if pgrep -x "$_dm" >/dev/null 2>&1; then DM_FOUND="$_dm"; break; fi
done
if [ -z "$DM_FOUND" ] && [ -r /etc/X11/default-display-manager ]; then
  _dm_path=$(head -n 1 /etc/X11/default-display-manager)
  if [ -x "$_dm_path" ]; then DM_FOUND="${_dm_path##*/} (configurado)"; fi
fi
add_manager 'Gerenciador de login' "$DM_FOUND"
add_manager apt "$APT_V"; add_manager dpkg "$DPKG_V"
add_manager dnf "$DNF_V"; add_manager yum "$YUM_V"
add_manager pacman "$PACMAN_V"; add_manager zypper "$ZYPPER_V"
add_manager snap "$SNAP_V"; add_manager flatpak "$FLATPAK_V"
for _mgr in slackpkg pkgtool installpkg rpm dnf5 apk emerge xbps-install nix-env brew pkg; do
  if command -v "$_mgr" >/dev/null 2>&1; then add_manager "$_mgr" instalado; fi
done
inventory_progress 75
APP_LABELS=('Programa de E-mail' 'Programa de Edicao de Imagem' 'Programa de Edicao de Textos' 'Banco de Dados')
APP_GROUPS=(); APP_NAMES=()
add_app_name() {
  local group="$1" name="$2" i
  name=$(printf '%s' "$name" | tr -d '\000-\037\177')
  [ -n "$name" ] || return 0
  for ((i=0; i<${#APP_NAMES[@]}; i++)); do
    if [ "${APP_GROUPS[$i]}" = "$group" ] && [ "${APP_NAMES[$i]}" = "$name" ]; then return 0; fi
  done
  APP_GROUPS[${#APP_GROUPS[@]}]="$group"; APP_NAMES[${#APP_NAMES[@]}]="$name"
}
add_detected_app() {
  local group="$1" name="$2" appid="$3" cmd d
  shift 3
  for cmd in "$@"; do
    if command -v "$cmd" >/dev/null 2>&1 || [ -x "/snap/bin/$cmd" ]; then add_app_name "$group" "$name"; return 0; fi
  done
  if [ -n "$appid" ]; then
    for d in "${APP_DIRS[@]}"; do
      if [ -f "$d/$appid.desktop" ]; then add_app_name "$group" "$name"; return 0; fi
    done
  fi
  return 0
}
_app_home="$HOME"
if [ -n "${SUDO_USER:-}" ]; then
  _app_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
  _app_home=${_app_home:-$HOME}
fi
APP_DIRS=(/usr/share/applications /usr/local/share/applications /var/lib/snapd/desktop/applications /var/lib/flatpak/exports/share/applications "$_app_home/.local/share/applications" "$_app_home/.local/share/flatpak/exports/share/applications")
add_detected_app 0 Thunderbird org.mozilla.Thunderbird thunderbird
add_detected_app 0 Evolution org.gnome.Evolution evolution
add_detected_app 0 KMail org.kde.kmail kmail
add_detected_app 0 Geary org.gnome.Geary geary
add_detected_app 0 'Claws Mail' '' claws-mail
add_detected_app 0 Sylpheed '' sylpheed
add_detected_app 1 GIMP org.gimp.GIMP gimp gimp-3.0
add_detected_app 1 Krita org.kde.krita krita
add_detected_app 1 Inkscape org.inkscape.Inkscape inkscape
add_detected_app 1 Pinta com.github.PintaProject.Pinta pinta
add_detected_app 1 Darktable org.darktable.Darktable darktable
add_detected_app 1 KolourPaint org.kde.kolourpaint kolourpaint
add_detected_app 2 'LibreOffice Writer' org.libreoffice.LibreOffice lowriter
add_detected_app 2 AbiWord '' abiword
add_detected_app 2 Mousepad org.xfce.mousepad mousepad
add_detected_app 2 Gedit org.gnome.gedit gedit
add_detected_app 2 Kate org.kde.kate kate
add_detected_app 2 Pluma org.mate.pluma pluma
add_detected_app 2 FeatherPad '' featherpad
add_detected_app 2 Leafpad '' leafpad
add_detected_app 2 KWrite org.kde.kwrite kwrite
add_detected_app 2 'GNOME Text Editor' org.gnome.TextEditor gnome-text-editor
add_detected_app 2 'ONLYOFFICE' org.onlyoffice.desktopeditors desktopeditors
add_detected_app 3 PostgreSQL '' postgres
for _pg in /usr/lib/postgresql/*/bin/postgres /usr/pgsql-*/bin/postgres; do
  if [ -x "$_pg" ]; then add_app_name 3 PostgreSQL; fi
done
add_detected_app 3 MariaDB '' mariadbd
add_detected_app 3 MySQL '' mysqld
add_detected_app 3 SQLite '' sqlite3
add_detected_app 3 MongoDB '' mongod
add_detected_app 3 Redis '' redis-server
add_detected_app 3 Valkey '' valkey-server
add_detected_app 3 Firebird '' firebird fbserver
add_detected_app 3 DuckDB '' duckdb
add_detected_app 3 Cassandra '' cassandra
add_detected_app 3 CouchDB '' couchdb
[ ! -x /opt/mssql/bin/sqlservr ] || add_app_name 3 'Microsoft SQL Server'
for _ad in "${APP_DIRS[@]}"; do
  for _desktop in "$_ad"/*.desktop; do
    [ -r "$_desktop" ] || continue
    _meta=$(awk '/^\[Desktop Entry\]/{ok=1;next} /^\[/{if(ok)exit} ok && /^(Name|Categories|Hidden|NoDisplay)=/{print}' "$_desktop" 2>/dev/null)
    case "$_meta" in *Hidden=true*|*NoDisplay=true*) continue;; esac
    _name=$(printf '%s\n' "$_meta" | sed -n 's/^Name=//p' | head -n 1)
    _cats=$(printf '%s\n' "$_meta" | sed -n 's/^Categories=//p' | head -n 1)
    case ";$_cats;" in *';Email;'*) add_app_name 0 "$_name";; esac
    case ";$_cats;" in *';RasterGraphics;'*|*';VectorGraphics;'*|*';ImageProcessing;'*) add_app_name 1 "$_name";; esac
    case ";$_cats;" in *';TextEditor;'*|*';WordProcessor;'*) add_app_name 2 "$_name";; esac
  done
done
for ((_ag=0; _ag<${#APP_LABELS[@]}; _ag++)); do
  _found=0
  for _g in "${APP_GROUPS[@]}"; do [ "$_g" != "$_ag" ] || _found=1; done
  if [ "$_found" = 0 ]; then APP_GROUPS[${#APP_GROUPS[@]}]="$_ag"; APP_NAMES[${#APP_NAMES[@]}]='Nenhum encontrado'; fi
done
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
inventory_progress 80
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
  printf 'INVENTORYTAKER - Desktop - CHECK\n'
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
manager_panel_field() {
  local label="$1" rest prefix chunk head limit below="${3:-0}"
  rest=$(printf '%s' "$2" | tr '\r\n\t' '   ' | tr -d '\001-\010\013\014\016-\037\177')
  if command -v iconv >/dev/null 2>&1; then
    rest=$(printf '%s' "$rest" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$rest")
  fi
  rest=$(printf '%s' "$rest" | LC_ALL=C tr -cd ' -~')
  rest="${rest#"${rest%%[![:space:]]*}"}"
  prefix=" $label: "
  if [ "${#prefix}" -ge "$((INNER-3))" ]; then
    case "$label" in
      'Programa de Edicao de Imagem') prefix=' Edicao de Imagem: ' ;;
      'Programa de Edicao de Textos') prefix=' Edicao de Textos: ' ;;
      'Gerenciador de login') prefix=' Login: ' ;;
      'Programa de E-mail') prefix=' E-mail: ' ;;
    esac
  fi
  [ -n "$rest" ] || rest='Nenhum encontrado'
  if [ "$below" = 1 ]; then
    add_R " $label" 4
    prefix='  '
  fi
  while :; do
    limit=$((INNER-${#prefix}))
    chunk=${rest:0:$limit}
    if [ "${#rest}" -gt "$limit" ]; then
      head=${chunk% *}
      if [ -n "$head" ] && [ "$head" != "$chunk" ]; then chunk=$head; fi
    fi
    if [ "$prefix" = '  ' ]; then add_R "$prefix$chunk" 8; else add_R "$prefix$chunk" 0; fi
    rest=${rest:${#chunk}}
    rest="${rest#"${rest%%[![:space:]]*}"}"
    [ -n "$rest" ] || break
    prefix='  '
  done
}
inventory_render_panels() {
add_L "__TOP__" 3; add_L "01  PORTAS ABERTAS" 1; add_L "__SEP__" 2
if [ "$PORTS_TOTAL" -eq 0 ]; then
  add_L " Nenhuma porta aberta" 0; add_L " TCP: 0" 0; add_L " UDP: 0" 0; add_L " Firewall: $UFW_STATUS" 0; add_L " Total: $PORTS_TOTAL" 0
else
  _pi=0
  while [ "$_pi" -lt "${#PORTS_LINES[@]}" ]; do add_L " Porta: ${PORTS_LINES[$_pi]}" 0; _pi=$(( _pi + 1 )); done
  add_L " TCP: $PORTS_TCP" 0; add_L " UDP: $PORTS_UDP" 0; add_L " Firewall: $UFW_STATUS" 0
  add_L " Total: $PORTS_TOTAL" 0
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
for ((_mi=0; _mi<${#MANAGER_LABELS[@]}; _mi++)); do
  manager_panel_field "${MANAGER_LABELS[$_mi]}" "${MANAGER_VALUES[$_mi]}"
done
add_R "__SEP__" 2
_manager_list=''
for ((_bi=0; _bi<${#BROWSER_LINES[@]}; _bi++)); do
  _manager_list="${_manager_list}${_manager_list:+, }${BROWSER_LINES[$_bi]}"
done
manager_panel_field 'Browsers' "$_manager_list"
for ((_ag=0; _ag<${#APP_LABELS[@]}; _ag++)); do
  add_R "__SEP__" 2
  _manager_list=''
  for ((_ai=0; _ai<${#APP_NAMES[@]}; _ai++)); do
    if [ "${APP_GROUPS[$_ai]}" = "$_ag" ]; then
      _manager_list="${_manager_list}${_manager_list:+, }${APP_NAMES[$_ai]}"
    fi
  done
  if [ "$_ag" -lt 3 ]; then
    manager_panel_field "${APP_LABELS[$_ag]}" "$_manager_list" 1
  else
    manager_panel_field "${APP_LABELS[$_ag]}" "$_manager_list"
  fi
done
add_bottom_trio; print_trio
add_L "04  REDES" 1; add_L "__SEP__" 2
add_L " Interfaces: $NET_IFACES" 0; add_L " Principal: $NET_PRIMARY" 0; add_L " IP: $NET_IP" 0; add_L " IP Ext: $EXT_IP" 0
add_L " Gateway: $NET_GW" 0; add_L " DNS: $NET_DNS" 0; add_L " MAC: $NET_MAC" 0; add_L " MTU: $NET_MTU" 0
add_L "" 0; add_L "command: $NET_CMD $NET_ATIVO" 6; add_L "" 0
add_M "05  MEMORIA RAM + SWAP" 1; add_M "__SEP__" 2
add_M " MEMORIA FISICA" 4; add_M "" 0; add_M " RAM Total: $(to_gb "$MEM_TOTAL_KB")" 0; add_M " RAM Uso: $(to_gb "$MEM_USED_KB")" 0; add_M " RAM Livre: $(to_gb "$MEM_AVAIL_KB")" 0
add_M "__SEP__" 2
add_M " MEMORIA SWAP" 4; add_M "" 0; add_M " Swap Total: $(to_gb "$SWAP_TOTAL_KB")" 0; add_M " Swap Uso: $(to_gb "$SWAP_USED_KB")" 0
add_M " Swap Livre: $(to_gb "$SWAP_FREE_KB")" 0; add_M " Swap Cached: $(to_gb "$SWAP_CACHED_KB")" 0; add_M " Total RAM+Swap: $(to_gb "$MEM_ALL_KB")" 0
add_M "__SEP__" 2
add_M " DISPOSITIVOS RAM" 4
add_M "" 0
for _memrow in "${MEM_DEVICES[@]}"; do add_M " $_memrow" 0; done
add_M "__SEP__" 2
add_M " COMANDOS SWAP" 4; add_M "" 0
add_M " swapon: sudo swapon -a (ativar)" 0
add_M " swapoff: sudo swapoff -a (desativar)" 0
add_M "" 0
add_R "06  WIFI" 1; add_R "__SEP__" 2
add_R " CONEXAO SEM FIO" 4; add_R "" 0
add_R " Estado: $WIFI_STATE" 0; add_R " Interface: $WIFI_IFACE" 0; add_R " SSID: $WIFI_SSID" 0
add_R " Sinal: $WIFI_SIGNAL" 0; add_R " Freq: $WIFI_FREQ" 0
add_R "__SEP__" 2; add_R " ENDERECAMENTO" 4; add_R "" 0
add_R " IP: $WIFI_IP" 0; add_R " IP Ext: $EXT_IP" 0; add_R " MAC: $WIFI_MAC" 0
add_R "__SEP__" 2; add_R " COMANDOS WIFI" 4; add_R "" 0
add_R " $WIFI_CMD" 0; add_R " Status: $WIFI_ATIVO" 0; add_R "" 0
add_R " nmcli d wifi" 0; add_R " Lista os sinais" 9; add_R "" 0
add_R ' nmcli d wifi connect "SSID"' 0; add_R " Conecta a uma rede" 9; add_R "" 0
add_bottom_trio; print_trio
add_L "07  AMBIENTE & RUNTIME" 1; add_L "__SEP__" 2
add_L " Ambiente: $DE_VAL" 0; add_L " Sessao: $SESSION_TYPE_VAL" 0; add_L " Display: $DISPLAY_VAL" 0; add_L "__SEP__" 2
add_L " Shell: $SHELL_V" 0; add_L " Init: $INIT_SYS" 0; add_L " Firewall: $FW" 0; add_L " Seguranca: $SEC_MOD" 0
add_L " Virt: $VIRT" 0; add_L " Uptime: $UPTIME_V" 0; add_L " Timezone: $TZ_V" 0
add_L " Logados: $LOGGED_N ($LOGGED_USERS)" 0; add_L " Ultimo Boot: $LAST_BOOT" 0
add_M "08  SISTEMA + KERNEL" 1; add_M "__SEP__" 2
add_M " Distro: ${OS_NAME:-N/A}" 0; add_M " Versao: ${OS_VER:-N/A}" 0; add_M " Kernel: $KERNEL_V" 0; add_M " Arq: $ARCH_V" 0; add_M " UMASK: $UMASK_VAL" 0
add_M "__SEP__" 2
add_M " Boot: $BOOT_INFO" 0
add_M " Disco: $BOOT_DISK_INFO" 0
add_M " Secure Boot: $SECURE_BOOT" 0
add_M " Atual: $BOOT_INFO" 0
add_M " Pacotes: $PKG_COUNT" 0; add_M " Atualizacoes: $UPDATES" 0
add_R "09  ARMAZENAMENTO" 1; add_R "__SEP__" 2; add_R "$ST_HEADER" 0; add_R "__SEP__" 2
_si=0; while [ "$_si" -lt "${#STORAGE_LINES[@]}" ]; do add_R "${ST_FMT[$_si]}" 0; _si=$(( _si + 1 )); done
add_bottom_trio; print_trio
}
footer_rule() {
  local j color
  for ((j=0; j<TOTAL_W; j++)); do
    case $((j*5/TOTAL_W)) in 0) color=136;; 1) color=178;; 2) color=220;; 3) color=226;; *) color=229;; esac
    if [ "$COLOR_ENABLED" = 1 ]; then printf '\033[38;5;%sm%s' "$color" "$BORDER_CELL"; else printf '%s' "$BORDER_CELL"; fi
  done
  printf '%s\n' "$RESET"
}
footer_pad() {
  local text="$1" width="$2" n
  n=$((width-${#text})); [ "$n" -ge 0 ] || n=0
  printf '%s%*s' "$text" "$n" ''
}
footer_row() {
  local label="$1" value="$2" width=$((TOTAL_W-19)) part
  while :; do
    part=${value:0:width}
    printf '%s%s%s%s %s %s%s%s%s %s %s%s%s\n' "$C_HASH" "$BORDER_CELL" "$RESET" "$BG" "$(footer_pad "$label" 12)" "$C_HASH" "$BORDER_CELL" "$RESET" "$BG" "$(footer_pad "$part" "$width")" "$C_HASH" "$BORDER_CELL" "$RESET"
    value=${value:width}; label=""
    [ -n "$value" ] || break
  done
}
footer_full_row() {
  local value="$1" width=$((TOTAL_W-4))
  printf '%s%s%s%s %s %s%s%s\n' "$C_HASH" "$BORDER_CELL" "$RESET" "$BG" "$(footer_pad "$value" "$width")" "$C_HASH" "$BORDER_CELL" "$RESET"
}
footer_end() { footer_rule; }
inventory_render_alerts() {
if [ "${#PRE_ERRORS[@]}" -gt 0 ]; then
  printf '\n%s\n' "${C_YELLOW}RESUMO DA PRE-VERIFICACAO${RESET}"
  footer_rule
  printf '%s\n' "${PRE_ERRORS[@]}" | sort -u | while IFS= read -r _err; do footer_row 'ALERTA' "$_err"; done
  footer_row 'STATUS' 'Inventario mantido; dados indisponiveis podem aparecer como N/A.'
  footer_end
fi
}
ensure_tools mkdir
umask 077
REPORT_USER=$(id -un)
if [ "$(id -u)" = 0 ]; then REPORT_USER=${SUDO_USER:-$(logname 2>/dev/null)}; fi
REPORT_UID=$(id -u "$REPORT_USER" 2>/dev/null)
REPORT_HOME=$(getent passwd "$REPORT_USER" 2>/dev/null | cut -d: -f6)
if [ -z "$REPORT_UID" ] || [ "$REPORT_UID" = 0 ] || [ ! -d "$REPORT_HOME" ]; then
  printf 'Erro: usuario real nao identificado. Execute como usuario normal.\n' >&2; exit 1
fi
DEST_DIR="$REPORT_HOME/Área de trabalho/INVENTÁRIO"
REPORT_AS=()
if [ "$(id -u)" = 0 ]; then
  if command -v runuser >/dev/null 2>&1; then REPORT_AS=(runuser -u "$REPORT_USER" --)
  elif command -v sudo >/dev/null 2>&1; then REPORT_AS=(sudo -u "$REPORT_USER" --)
  else printf 'Erro: impossivel publicar como usuario real.\n' >&2; exit 1; fi
fi
"${REPORT_AS[@]}" bash -c 'umask 077; mkdir -p -- "$1"' bash "$DEST_DIR" || exit 1
DESKTOP_DIR="$DEST_DIR"
if [ "$(id -u)" = 0 ]; then
  DESKTOP_DIR=$(mktemp -d /tmp/InventoryTaker.XXXXXXXX) || exit 1
fi
NOW_SAFE=$(date "+%Y-%m-%d_%H%M%S")_$$
REPORT_FILE="$DESKTOP_DIR/LINUX_InventoryTaker_${NOW_SAFE}.txt"
HTML_FILE="$DESKTOP_DIR/LINUX_InventoryTaker_${NOW_SAFE}.html"
CSV_FILE="$DESKTOP_DIR/LINUX_InventoryTaker_${NOW_SAFE}.csv"
JSON_FILE="$DESKTOP_DIR/LINUX_InventoryTaker_${NOW_SAFE}.json"
PREP_FILE="$DESKTOP_DIR/LINUX_InventoryTaker_${NOW_SAFE}_preparacao.html"
# Reserva exclusiva dos quatro arquivos: nao sobrescreve arquivos nem links existentes.
for _report in "$REPORT_FILE" "$HTML_FILE" "$CSV_FILE" "$JSON_FILE" "$PREP_FILE"; do
  if ! (set -C; : > "$_report") 2>/dev/null; then
    printf 'Erro: nao foi possivel reservar relatorio com seguranca: %s\n' "$_report" >&2
    exit 1
  fi
done
{
  print_banner 0
  printf 'Host: %s | Atualizado em: %s\n' "$HOST" "$NOW"
  printf 'Compativel: Kernel >= 3.10 | Bash >= 3.x\n'; printf '\n'
  printf '01 PORTAS ABERTAS\n'
  if [ "$PORTS_TOTAL" -eq 0 ]; then printf 'Nenhuma porta aberta\n'; else _pi=0; while [ "$_pi" -lt "${#PORTS_LINES[@]}" ]; do printf 'Porta: %s\n' "${PORTS_LINES[$_pi]}"; _pi=$(( _pi + 1 )); done; fi
  printf 'TCP: %s\n' "$PORTS_TCP"; printf 'UDP: %s\n' "$PORTS_UDP"; printf 'Firewall: %s\n' "$UFW_STATUS"
  printf 'Total: %s\n' "$PORTS_TOTAL"; printf '\n'
  printf '02 HARDWARE\n'
  printf 'Fabricante: %s\n' "${VENDOR_V:-N/A}"; printf 'Modelo: %s\n' "${MODEL_V:-N/A}"; printf 'CPU: %s\n' "${CPU_DISPLAY:-N/A}"
  printf 'Geracao: %s\n' "$CPU_GEN"; printf 'Nucleos: %s\n' "$CPU_CORES"; printf 'Disco: %s\n' "$BOOT_DISK_INFO"; printf 'Video: %s\n' "$GPU_MODEL"; printf 'SMART: %s (%s)\n' "$SMART_STATUS" "$SMART_HOURS"; if [ "$BAT_CAP" = "N/A" ]; then printf 'Bateria: N/A (sem bateria)\n'; else printf 'Bateria: %s (%s)\n' "$BAT_CAP" "$BAT_STATUS"; printf 'Saude Bateria: %s (Ciclos: %s)\n' "$BAT_HEALTH" "$BAT_CYCLES"; fi
  printf 'Temperatura:\n'; printf 'CPU: %s\n' "$TEMP_CPU"; printf 'GPU: %s\n' "$TEMP_GPU"; printf 'Disco: %s\n' "$TEMP_DISK"; printf 'Placa: %s\n' "$TEMP_BOARD"
  printf 'Firmware: %s\n' "$FIRMWARE_VENDOR"; printf 'Versao Firmware: %s\n' "$FIRMWARE_VER"; printf 'Data Firmware: %s\n' "$FIRMWARE_DATE"
  printf 'Classe Firmware: %s\n' "$FIRMWARE_CLASS"; printf 'Revisao BIOS: %s\n' "$BIOS_REV"; printf 'Revisao Firmware: %s\n' "$FW_REV"
  printf 'ROM: %s\n' "$ROM_SIZE"; printf 'SMBIOS: %s\n' "$SMBIOS_VER"; printf '\n'
  printf '03 GERENCIADORES\n'
  for ((_mi=0; _mi<${#MANAGER_LABELS[@]}; _mi++)); do printf '%s: %s\n' "${MANAGER_LABELS[$_mi]}" "${MANAGER_VALUES[$_mi]}"; done
  printf '\n'; printf 'Browsers:\n'; printf '\n'
  if [ "${#BROWSER_LINES[@]}" -eq 0 ]; then printf 'Nenhum browser encontrado\n'; else _bi=0; while [ "$_bi" -lt "${#BROWSER_LINES[@]}" ]; do printf '%s\n' "${BROWSER_LINES[$_bi]}"; _bi=$(( _bi + 1 )); done; fi
  printf '\n'
  for ((_ag=0; _ag<${#APP_LABELS[@]}; _ag++)); do
    printf '\n%s\n' "${APP_LABELS[$_ag]}"
    for ((_ai=0; _ai<${#APP_NAMES[@]}; _ai++)); do if [ "${APP_GROUPS[$_ai]}" = "$_ag" ]; then printf '  %s\n' "${APP_NAMES[$_ai]}"; fi; done
  done
  printf '\n'
  printf '04 REDES\n'; printf 'Interfaces: %s\n' "$NET_IFACES"; printf 'Interface Principal: %s\n' "$NET_PRIMARY"; printf 'IP: %s\n' "$NET_IP"
  printf 'IP Externo: %s\n' "$EXT_IP"; printf 'Gateway: %s\n' "$NET_GW"; printf 'DNS: %s\n' "$NET_DNS"; printf 'MAC: %s\n' "$NET_MAC"; printf 'MTU: %s\n' "$NET_MTU"
  printf '\n'; printf 'command: %s %s\n' "$NET_CMD" "$NET_ATIVO"; printf '\n'; printf '\n'
  printf '05 MEMORIA RAM + SWAP\n'
  printf 'RAM Total: %s\n' "$(to_gb "$MEM_TOTAL_KB")"; printf 'RAM Em uso: %s\n' "$(to_gb "$MEM_USED_KB")"; printf 'RAM Disponivel: %s\n' "$(to_gb "$MEM_AVAIL_KB")"
  printf 'Swap Total: %s\n' "$(to_gb "$SWAP_TOTAL_KB")"; printf 'Swap Em uso: %s\n' "$(to_gb "$SWAP_USED_KB")"; printf 'Swap Livre: %s\n' "$(to_gb "$SWAP_FREE_KB")"
  printf 'Swap Cached: %s\n' "$(to_gb "$SWAP_CACHED_KB")"; printf 'Total RAM+Swap: %s\n' "$(to_gb "$MEM_ALL_KB")"
  for _memrow in "${MEM_DEVICES[@]}"; do printf 'Dispositivo RAM: %s\n' "$_memrow"; done
  printf 'swapon: sudo swapon -a (ativar)\n'; printf 'swapoff: sudo swapoff -a (desativar)\n'; printf '\n'
  printf '06 WIFI\n'; printf 'Interface: %s\n' "$WIFI_IFACE"; printf 'SSID: %s\n' "$WIFI_SSID"; printf 'Sinal: %s\n' "$WIFI_SIGNAL"
  printf 'IP: %s\n' "$WIFI_IP"; printf 'IP Externo: %s\n' "$EXT_IP"; printf 'MAC: %s\n' "$WIFI_MAC"; printf 'Estado: %s\n' "$WIFI_STATE"; printf 'Frequencia: %s\n' "$WIFI_FREQ"
  printf '\n'; printf 'command: %s %s\n' "$WIFI_CMD" "$WIFI_ATIVO"; printf '\nnmcli d wifi - Lista os sinais\n\nnmcli d wifi connect "SSID" - Conecta a uma rede\n'; printf '\n'; printf '\n'
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
inventory_progress 85
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
  printf '%s\n' '<!DOCTYPE html>' '<html lang="pt-BR">' '<head>' '<meta charset="UTF-8">' < /dev/null
  printf '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
  printf '<title>INVENTORYTAKER - Desktop</title>\n'
  printf '<style>\n'
  printf '*{box-sizing:border-box} body{margin:0;background:#1e1e1e;color:#d4d4d4;font-family:Consolas,"Fira Code",monospace;padding:10px;font-size:13px}\n'
  printf '.page{max-width:1280px;margin:0 auto}\n'
  printf '.hero{background:linear-gradient(90deg,#ff9900,#7c3aed,#2563eb);border-radius:14px;padding:12px 14px;color:#fff;text-align:center}\n'
  printf '.hero h1{margin:0;font-size:19px;text-align:center} .hero p{margin:4px 0 0;color:#bfdbfe;opacity:.95;font-size:12px;text-align:center}\n'
  printf '.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin-top:10px;align-items:stretch}\n'
  printf '.card{background:#252526;border:2px solid #eab308;border-radius:14px;padding:10px;font-size:13px;line-height:1.35}\n'
  printf '.c1{border-color:#eab308} .c2{border-color:#eab308} .c3{border-color:#eab308} .c4{border-color:#eab308} .c5{border-color:#eab308} .c6{border-color:#eab308} .c7{border-color:#eab308} .c8{border-color:#eab308} .c9{border-color:#eab308}\n'
  printf '.card h2{margin:-10px -10px 7px;background:linear-gradient(90deg,#b8860b,#facc15,#fef08a);color:#111111;font-size:14px;text-align:center;padding:7px 10px;border-radius:12px 12px 0 0}\n'
  printf '.row{display:flex;gap:6px;padding:2px 0;border-bottom:1px dashed #3c3c3c} .k{color:#facc15;min-width:88px;flex-shrink:0} .v{color:#ffffff;word-break:break-word}\n'
  printf '.row.st{display:grid;grid-template-columns:8ch 4ch 6ch 6ch 6ch;gap:8px} .row.st span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis} .row.st span:nth-child(n+2){text-align:right;color:#86efac}\n'
  printf '.sep{height:2px;background:linear-gradient(90deg,#b8860b,#fef08a);margin:5px 0} .cmd{margin:7px 0;background:#0b0f14;border:1px solid #facc15;border-radius:10px;padding:7px;color:#fde68a;line-height:1.45;font-size:12px}\n'
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
  printf '<div class="topbar"><span><b>INVENTORYTAKER - Desktop</b></span><span>Host: %s</span><span>Atualizado em: %s</span><span class="pill">SOMENTE LEITURA</span></div>\n' "$(html_esc "$HOST")" "$(html_esc "$NOW")"
  printf '<div class="header"><div class="brand">INVENTARIO COMPLETO DO SISTEMA</div><h1>INVENTORYTAKER - Desktop</h1><p>Relatorio completo do sistema, gerado em modo somente leitura.</p><div class="chips"><span class="chip">Host: <b>%s</b></span><span class="chip">Distro: <b>%s %s</b></span><span class="chip">Kernel: <b>%s</b></span><span class="chip">Arquitetura: <b>%s</b></span><span class="chip">IP: <b>%s</b></span><span class="chip">Boot: <b>%s</b></span></div></div>\n' "$(html_esc "$HOST")" "$(html_esc "${OS_NAME:-N/A}")" "$(html_esc "${OS_VER:-N/A}")" "$(html_esc "$KERNEL_V")" "$(html_esc "$ARCH_V")" "$(html_esc "$NET_IP")" "$(html_esc "$BOOT_INFO")"
  printf '<div class="grid">\n'
  printf '<div class="card c1"><h2>01 &nbsp; PORTAS ABERTAS</h2>%s\n' "$PORTS_HTML"
  printf '<div class="row"><span class="k">TCP:</span><span class="v">%s</span></div>\n' "$PORTS_TCP"
  printf '<div class="row"><span class="k">UDP:</span><span class="v">%s</span></div>\n' "$PORTS_UDP"
  printf '<div class="row"><span class="k">Firewall:</span><span class="v">%s</span></div>\n' "$(html_esc "$UFW_STATUS")"
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
  for ((_mi=0; _mi<${#MANAGER_LABELS[@]}; _mi++)); do
    printf '<div class="row"><span class="k">%s:</span><span class="v">%s</span></div>\n' "$(html_esc "${MANAGER_LABELS[$_mi]}")" "$(html_esc "${MANAGER_VALUES[$_mi]}")"
  done
  printf '<div class="sep"></div><div style="height:8px"></div>\n'
  printf '<div class="row"><span class="k">Browsers:</span><span class="v"></span></div><div style="height:8px"></div>%s<div style="height:8px"></div>\n' "$BROWSER_HTML"
  for ((_ag=0; _ag<${#APP_LABELS[@]}; _ag++)); do
    printf '<div class="sep"></div><h3>%s</h3>\n' "$(html_esc "${APP_LABELS[$_ag]}")"
    for ((_ai=0; _ai<${#APP_NAMES[@]}; _ai++)); do if [ "${APP_GROUPS[$_ai]}" = "$_ag" ]; then printf '<div class="row">%s</div>\n' "$(html_esc "${APP_NAMES[$_ai]}")"; fi; done
  done
  printf '</div>\n'
  printf '<div class="card c4"><h2>04 &nbsp; REDES</h2>\n'
  printf '<div class="row"><span class="k">Interfaces:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_IFACES")"
  printf '<div class="row"><span class="k">Principal:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_PRIMARY")"
  printf '<div class="row"><span class="k">IP:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_IP")"
  printf '<div class="row"><span class="k">IP Ext:</span><span class="v">%s</span></div>\n' "$(html_esc "$EXT_IP")"
  printf '<div class="row"><span class="k">Gateway:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_GW")"
  printf '<div class="row"><span class="k">DNS:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_DNS")"
  printf '<div class="row"><span class="k">MAC:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_MAC")"
  printf '<div class="row"><span class="k">MTU:</span><span class="v">%s</span></div>\n' "$(html_esc "$NET_MTU")"
  printf '<div class="cmd">command: %s %s</div><div class="sep"></div>\n' "$(html_esc "$NET_CMD")" "$NET_BADGE"
  printf '</div>\n' 
  printf '<div class="card c5"><h2>05 &nbsp; MEMORIA RAM + SWAP</h2>\n'
  printf '<div class="row"><span class="k">RAM Total:</span><span class="v">%s</span></div>\n' "$(to_gb "$MEM_TOTAL_KB")"
  printf '<div class="row"><span class="k">RAM Uso:</span><span class="v">%s</span></div>\n' "$(to_gb "$MEM_USED_KB")"
  printf '<div class="row"><span class="k">RAM Livre:</span><span class="v">%s</span></div><div class="bar"><i style="width:65%%"></i></div><div class="sep"></div>\n' "$(to_gb "$MEM_AVAIL_KB")"
  printf '<div class="row"><span class="k">Swap Total:</span><span class="v">%s</span></div>\n' "$(to_gb "$SWAP_TOTAL_KB")"
  printf '<div class="row"><span class="k">Swap Uso:</span><span class="v">%s</span></div>\n' "$(to_gb "$SWAP_USED_KB")"
  printf '<div class="row"><span class="k">Swap Livre:</span><span class="v">%s</span></div>\n' "$(to_gb "$SWAP_FREE_KB")"
  printf '<div class="row"><span class="k">Swap Cached:</span><span class="v">%s</span></div>\n' "$(to_gb "$SWAP_CACHED_KB")"
  printf '<div class="row"><span class="k">Total RAM+Swap:</span><span class="v">%s</span></div>\n' "$(to_gb "$MEM_ALL_KB")"
  for _memrow in "${MEM_DEVICES[@]}"; do printf '<div class="row"><span class="k">RAM:</span><span class="v">%s</span></div>\n' "$(html_esc "$_memrow")"; done
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
  printf '<div class="sep"></div><div class="cmd"><b>COMANDOS WIFI</b><br><br><code>%s</code><br>%s</div><div class="cmd"><code>nmcli d wifi</code><br>Lista os sinais</div><div class="cmd"><code>nmcli d wifi connect &quot;SSID&quot;</code><br>Conecta a uma rede</div></div>\n' "$(html_esc "$WIFI_CMD")" "$WIFI_BADGE"
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
  printf '<div class="files"><div class="files-meta"><span>Pasta: <b>%s</b></span><span>Arquivo base: <b>%s</b></span><span>Total: <b>5 arquivos</b></span><span>Gerado em: <b>%s</b></span></div>\n' "$(html_esc "$DEST_DIR")" "$(html_esc "$(basename "$REPORT_FILE" .txt)")" "$(html_esc "$NOW")"
  printf '<div class="files-head"><span>Tipo</span><span>Formato</span><span>Arquivo</span><span>Abrir</span></div>\n'
  printf '<div class="files-row"><span class="tipo">Relatorio</span><span class="fmt">TXT</span><span class="nome">%s</span><a href="%s" download>Baixar</a></div>\n' "$(html_esc "$(basename "$REPORT_FILE")")" "$(html_esc "$(basename "$REPORT_FILE")")"
  printf '<div class="files-row"><span class="tipo">Pagina</span><span class="fmt">HTML</span><span class="nome">%s</span><a href="%s" target="_blank" rel="noopener">Abrir</a></div>\n' "$(html_esc "$(basename "$HTML_FILE")")" "$(html_esc "$(basename "$HTML_FILE")")"
  printf '<div class="files-row"><span class="tipo">Planilha</span><span class="fmt">CSV</span><span class="nome">%s</span><a href="%s" download>Baixar</a></div>\n' "$(html_esc "$(basename "$CSV_FILE")")" "$(html_esc "$(basename "$CSV_FILE")")"
  printf '<div class="files-row"><span class="tipo">Dados</span><span class="fmt">JSON</span><span class="nome">%s</span><a href="%s" download>Baixar</a></div>\n' "$(html_esc "$(basename "$JSON_FILE")")" "$(html_esc "$(basename "$JSON_FILE")")"
  printf '<div class="files-row"><span class="tipo">Preparacao</span><span class="fmt">HTML</span><span class="nome">%s</span><a href="%s" target="_blank" rel="noopener">Abrir</a></div></div>\n' "$(html_esc "${PREP_FILE##*/}")" "$(html_esc "${PREP_FILE##*/}")"
  printf '</div>\n'
  printf '</div></body></html>\n'
} > "$HTML_FILE"
inventory_progress 90
if [ ! -s "$HTML_FILE" ] || ! grep -qi '</html>' "$HTML_FILE"; then
  INVENTORY_HTML_WARNING=1
fi
csv_safe() {
  local _CSV_VALUE _CSV_CHECK
  _CSV_VALUE=$(printf '%s' "$1" | tr '\r\n\t' '   ' | tr -d '\001-\010\013\014\016-\037\177')
  _CSV_CHECK=$(printf '%s' "$_CSV_VALUE" | sed 's/^[[:space:]]*//')
  case "$_CSV_CHECK" in =*|+*|-*|@*) _CSV_VALUE="'$_CSV_VALUE" ;; esac
  _CSV_VALUE=$(printf '%s' "$_CSV_VALUE" | sed 's/"/""/g')
  printf '"%s"' "$_CSV_VALUE"
}
{
  printf 'secao;rotulo;valor\n'
  printf 'CABECALHO;Host;%s\n' "$(csv_safe "$HOST")"
  printf 'CABECALHO;Atualizado em;%s\n' "$(csv_safe "$NOW")"
  printf 'CABECALHO;Compativel;Kernel >= 3.10 | Bash >= 3.x\n'
  printf ';;\n'
  printf '01 PORTAS ABERTAS;;\n'
  _pi=0; while [ "$_pi" -lt "${#PORTS_LINES[@]}" ]; do printf '01 PORTAS ABERTAS;Porta;%s\n' "$(csv_safe "${PORTS_LINES[$_pi]}")"; _pi=$(( _pi + 1 )); done
  if [ "$PORTS_TOTAL" -eq 0 ]; then printf '01 PORTAS ABERTAS;Porta;Nenhuma porta aberta\n'; fi
  printf '01 PORTAS ABERTAS;TCP;%s\n' "$(csv_safe "$PORTS_TCP")"
  printf '01 PORTAS ABERTAS;UDP;%s\n' "$(csv_safe "$PORTS_UDP")"
  printf '01 PORTAS ABERTAS;Firewall;%s\n' "$(csv_safe "$UFW_STATUS")"
  printf '01 PORTAS ABERTAS;Total;%s\n' "$(csv_safe "$PORTS_TOTAL")"
  printf ';;\n'
  printf '02 HARDWARE;;\n'
  printf '02 HARDWARE;Fabricante;%s\n' "$(csv_safe "$VENDOR_V")"
  printf '02 HARDWARE;Modelo;%s\n' "$(csv_safe "$MODEL_V")"
  printf '02 HARDWARE;CPU;%s\n' "$(csv_safe "$CPU_DISPLAY")"
  printf '02 HARDWARE;Geracao;%s\n' "$(csv_safe "$CPU_GEN")"
  printf '02 HARDWARE;Nucleos;%s\n' "$(csv_safe "$CPU_CORES")"
  printf '02 HARDWARE;Disco;%s\n' "$(csv_safe "$BOOT_DISK_INFO")"
  printf '02 HARDWARE;Video;%s\n' "$(csv_safe "$GPU_MODEL")"
  printf '02 HARDWARE;SMART;%s\n' "$(csv_safe "$SMART_STATUS ($SMART_HOURS)")"
  if [ "$BAT_CAP" = "N/A" ]; then printf '02 HARDWARE;Bateria;N/A (sem bateria)\n'; else printf '02 HARDWARE;Bateria;%s\n' "$(csv_safe "$BAT_CAP ($BAT_STATUS)")"; printf '02 HARDWARE;Saude Bateria;%s\n' "$(csv_safe "$BAT_HEALTH (Ciclos: $BAT_CYCLES)")"; fi
  printf '02 HARDWARE;Temperatura CPU;%s\n' "$(csv_safe "$TEMP_CPU")"
  printf '02 HARDWARE;Temperatura GPU;%s\n' "$(csv_safe "$TEMP_GPU")"
  printf '02 HARDWARE;Temperatura Disco;%s\n' "$(csv_safe "$TEMP_DISK")"
  printf '02 HARDWARE;Temperatura Placa;%s\n' "$(csv_safe "$TEMP_BOARD")"
  printf '02 HARDWARE;Firmware;%s\n' "$(csv_safe "$FIRMWARE_VENDOR")"
  printf '02 HARDWARE;Versao Firmware;%s\n' "$(csv_safe "$FIRMWARE_VER")"
  printf '02 HARDWARE;Data Firmware;%s\n' "$(csv_safe "$FIRMWARE_DATE")"
  printf '02 HARDWARE;Classe Firmware;%s\n' "$(csv_safe "$FIRMWARE_CLASS")"
  printf '02 HARDWARE;Revisao BIOS;%s\n' "$(csv_safe "$BIOS_REV")"
  printf '02 HARDWARE;Revisao Firmware;%s\n' "$(csv_safe "$FW_REV")"
  printf '02 HARDWARE;ROM;%s\n' "$(csv_safe "$ROM_SIZE")"
  printf '02 HARDWARE;SMBIOS;%s\n' "$(csv_safe "$SMBIOS_VER")"
  printf ';;\n'
  printf '03 GERENCIADORES;;\n'
  for ((_mi=0; _mi<${#MANAGER_LABELS[@]}; _mi++)); do printf '03 GERENCIADORES;%s;%s\n' "$(csv_safe "${MANAGER_LABELS[$_mi]}")" "$(csv_safe "${MANAGER_VALUES[$_mi]}")"; done
  printf '03 GERENCIADORES;Browsers;\n'
  _bi=0; while [ "$_bi" -lt "${#BROWSER_LINES[@]}" ]; do printf '03 GERENCIADORES;Browser;%s\n' "$(csv_safe "${BROWSER_LINES[$_bi]}")"; _bi=$(( _bi + 1 )); done
  if [ "${#BROWSER_LINES[@]}" -eq 0 ]; then printf '03 GERENCIADORES;Browser;Nenhum browser encontrado\n'; fi
  printf ';;\n'
  for ((_ai=0; _ai<${#APP_NAMES[@]}; _ai++)); do printf '03 GERENCIADORES;%s;%s\n' "$(csv_safe "${APP_LABELS[${APP_GROUPS[$_ai]}]}")" "$(csv_safe "${APP_NAMES[$_ai]}")"; done
  printf '04 REDES;;\n'
  printf '04 REDES;Interfaces;%s\n' "$(csv_safe "$NET_IFACES")"
  printf '04 REDES;Interface Principal;%s\n' "$(csv_safe "$NET_PRIMARY")"
  printf '04 REDES;IP;%s\n' "$(csv_safe "$NET_IP")"
  printf '04 REDES;IP Externo;%s\n' "$(csv_safe "$EXT_IP")"
  printf '04 REDES;Gateway;%s\n' "$(csv_safe "$NET_GW")"
  printf '04 REDES;DNS;%s\n' "$(csv_safe "$NET_DNS")"
  printf '04 REDES;MAC;%s\n' "$(csv_safe "$NET_MAC")"
  printf '04 REDES;MTU;%s\n' "$(csv_safe "$NET_MTU")"
  printf '04 REDES;command;%s\n' "$(csv_safe "$NET_CMD $NET_ATIVO")"
  printf ';;\n'
  printf '05 MEMORIA RAM + SWAP;;\n'
  printf '05 MEMORIA RAM + SWAP;RAM Total;%s\n' "$(csv_safe "$(to_gb "$MEM_TOTAL_KB")")"
  printf '05 MEMORIA RAM + SWAP;RAM Em uso;%s\n' "$(csv_safe "$(to_gb "$MEM_USED_KB")")"
  printf '05 MEMORIA RAM + SWAP;RAM Disponivel;%s\n' "$(csv_safe "$(to_gb "$MEM_AVAIL_KB")")"
  printf '05 MEMORIA RAM + SWAP;Swap Total;%s\n' "$(csv_safe "$(to_gb "$SWAP_TOTAL_KB")")"
  printf '05 MEMORIA RAM + SWAP;Swap Em uso;%s\n' "$(csv_safe "$(to_gb "$SWAP_USED_KB")")"
  printf '05 MEMORIA RAM + SWAP;Swap Livre;%s\n' "$(csv_safe "$(to_gb "$SWAP_FREE_KB")")"
  printf '05 MEMORIA RAM + SWAP;Swap Cached;%s\n' "$(csv_safe "$(to_gb "$SWAP_CACHED_KB")")"
  printf '05 MEMORIA RAM + SWAP;Total RAM+Swap;%s\n' "$(csv_safe "$(to_gb "$MEM_ALL_KB")")"
  for _memrow in "${MEM_DEVICES[@]}"; do printf '05 MEMORIA RAM + SWAP;Dispositivo;%s\n' "$(csv_safe "$_memrow")"; done
  printf '05 MEMORIA RAM + SWAP;swapon;sudo swapon -a (ativar)\n'
  printf '05 MEMORIA RAM + SWAP;swapoff;sudo swapoff -a (desativar)\n'
  printf ';;\n'
  printf '06 WIFI;;\n'
  printf '06 WIFI;Interface;%s\n' "$(csv_safe "$WIFI_IFACE")"
  printf '06 WIFI;SSID;%s\n' "$(csv_safe "$WIFI_SSID")"
  printf '06 WIFI;Sinal;%s\n' "$(csv_safe "$WIFI_SIGNAL")"
  printf '06 WIFI;IP;%s\n' "$(csv_safe "$WIFI_IP")"
  printf '06 WIFI;IP Externo;%s\n' "$(csv_safe "$EXT_IP")"
  printf '06 WIFI;MAC;%s\n' "$(csv_safe "$WIFI_MAC")"
  printf '06 WIFI;Estado;%s\n' "$(csv_safe "$WIFI_STATE")"
  printf '06 WIFI;Frequencia;%s\n' "$(csv_safe "$WIFI_FREQ")"
  printf '06 WIFI;nmcli d wifi;Lista os sinais\n'; printf '06 WIFI;"nmcli d wifi connect ""SSID""";Conecta a uma rede\n'
  printf '06 WIFI;command;%s\n' "$(csv_safe "$WIFI_CMD $WIFI_ATIVO")"
  printf ';;\n'
  printf '07 AMBIENTE & RUNTIME;;\n'
  printf '07 AMBIENTE & RUNTIME;Ambiente grafico;%s\n' "$(csv_safe "$DE_VAL")"
  printf '07 AMBIENTE & RUNTIME;Sessao;%s\n' "$(csv_safe "$SESSION_TYPE_VAL")"
  printf '07 AMBIENTE & RUNTIME;Display;%s\n' "$(csv_safe "$DISPLAY_VAL")"
  printf '07 AMBIENTE & RUNTIME;Shell (bash);%s\n' "$(csv_safe "$SHELL_V")"
  printf '07 AMBIENTE & RUNTIME;Init system;%s\n' "$(csv_safe "$INIT_SYS")"
  printf '07 AMBIENTE & RUNTIME;Firewall;%s\n' "$(csv_safe "$FW")"
  printf '07 AMBIENTE & RUNTIME;Seguranca kernel;%s\n' "$(csv_safe "$SEC_MOD")"
  printf '07 AMBIENTE & RUNTIME;Virtualizacao;%s\n' "$(csv_safe "$VIRT")"
  printf '07 AMBIENTE & RUNTIME;Uptime;%s\n' "$(csv_safe "$UPTIME_V")"
  printf '07 AMBIENTE & RUNTIME;Timezone;%s\n' "$(csv_safe "$TZ_V")"
  printf '07 AMBIENTE & RUNTIME;Logados;%s\n' "$(csv_safe "$LOGGED_N ($LOGGED_USERS)")"
  printf '07 AMBIENTE & RUNTIME;Ultimo Boot;%s\n' "$(csv_safe "$LAST_BOOT")"
  printf ';;\n'
  printf '08 SISTEMA + KERNEL;;\n'
  printf '08 SISTEMA + KERNEL;Distribuicao;%s\n' "$(csv_safe "$OS_NAME")"
  printf '08 SISTEMA + KERNEL;Versao;%s\n' "$(csv_safe "$OS_VER")"
  printf '08 SISTEMA + KERNEL;Kernel;%s\n' "$(csv_safe "$KERNEL_V")"
  printf '08 SISTEMA + KERNEL;Arquitetura;%s\n' "$(csv_safe "$ARCH_V")"
  printf '08 SISTEMA + KERNEL;UMASK;%s\n' "$(csv_safe "$UMASK_VAL")"
  printf '08 SISTEMA + KERNEL;Boot;%s\n' "$(csv_safe "$BOOT_INFO")"
  printf '08 SISTEMA + KERNEL;Disco Boot;%s\n' "$(csv_safe "$BOOT_DISK_INFO")"
  printf '08 SISTEMA + KERNEL;Secure Boot;%s\n' "$(csv_safe "$SECURE_BOOT")"
  printf '08 SISTEMA + KERNEL;Atual;%s\n' "$(csv_safe "$BOOT_INFO")"
  printf '08 SISTEMA + KERNEL;Pacotes;%s\n' "$(csv_safe "$PKG_COUNT")"
  printf '08 SISTEMA + KERNEL;Atualizacoes;%s\n' "$(csv_safe "$UPDATES")"
  printf ';;\n'
  printf '09 ARMAZENAMENTO;;\n'
  printf '09 ARMAZENAMENTO;MONTE;USO%% | TOTAL | USADO | LIVRE\n'
  _si=0; while [ "$_si" -lt "${#STORAGE_LINES[@]}" ]; do _raw="${STORAGE_LINES[$_si]}"; _m=$(printf '%s' "$_raw" | awk '{print $1}'); _pc=$(printf '%s' "$_raw" | awk '{print $2}'); _sz=$(printf '%s' "$_raw" | awk '{print $3}'); _us=$(printf '%s' "$_raw" | awk '{print $4}'); _av=$(printf '%s' "$_raw" | awk '{print $5}'); printf '09 ARMAZENAMENTO;%s;%s\n' "$(csv_safe "${_m}")" "$(csv_safe "${_pc} | ${_sz} | ${_us} | ${_av}")"; _si=$(( _si + 1 )); done
  printf ';;\n'
  printf 'RODAPE;Status;Dashboard carregado com sucesso.\n'
} > "$CSV_FILE" 2>/dev/null
inventory_progress 95
json_esc() { printf '%s' "$1" | tr '\r\n\t' '   ' | tr -d '\001-\010\013\014\016-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
{
  printf '{\n'
  printf '  "CABECALHO": {"Host": "%s", "Atualizado em": "%s", "Compativel": "Kernel >= 3.10 | Bash >= 3.x"},\n' "$(json_esc "$HOST")" "$(json_esc "$NOW")"
  printf '  "01 PORTAS ABERTAS": {"Porta": ['
  _pi=0; while [ "$_pi" -lt "${#PORTS_LINES[@]}" ]; do if [ "$_pi" -gt 0 ]; then printf ', '; fi; printf '"%s"' "$(json_esc "${PORTS_LINES[$_pi]}")"; _pi=$(( _pi + 1 )); done
  if [ "$PORTS_TOTAL" -eq 0 ]; then printf '"Nenhuma porta aberta"'; fi
  printf '], "TCP": "%s", "UDP": "%s", "Firewall": "%s", "Total": "%s"},\n' "$(json_esc "$PORTS_TCP")" "$(json_esc "$PORTS_UDP")" "$(json_esc "$UFW_STATUS")" "$(json_esc "$PORTS_TOTAL")"
  if [ "$BAT_CAP" = "N/A" ]; then _bat_txt="N/A (sem bateria)"; _saude_txt=""; else _bat_txt="$BAT_CAP ($BAT_STATUS)"; _saude_txt="$BAT_HEALTH (Ciclos: $BAT_CYCLES)"; fi
  printf '  "02 HARDWARE": {"Fabricante": "%s", "Modelo": "%s", "CPU": "%s", "Geracao": "%s", "Nucleos": "%s", "Disco": "%s", "Video": "%s", "SMART": "%s (%s)", "Bateria": "%s", "Saude Bateria": "%s", "Temperatura CPU": "%s", "Temperatura GPU": "%s", "Temperatura Disco": "%s", "Temperatura Placa": "%s", "Firmware": "%s", "Versao Firmware": "%s", "Data Firmware": "%s", "Classe Firmware": "%s", "Revisao BIOS": "%s", "Revisao Firmware": "%s", "ROM": "%s", "SMBIOS": "%s"},\n' "$(json_esc "$VENDOR_V")" "$(json_esc "$MODEL_V")" "$(json_esc "$CPU_DISPLAY")" "$(json_esc "$CPU_GEN")" "$(json_esc "$CPU_CORES")" "$(json_esc "$BOOT_DISK_INFO")" "$(json_esc "$GPU_MODEL")" "$(json_esc "$SMART_STATUS")" "$(json_esc "$SMART_HOURS")" "$(json_esc "$_bat_txt")" "$(json_esc "$_saude_txt")" "$(json_esc "$TEMP_CPU")" "$(json_esc "$TEMP_GPU")" "$(json_esc "$TEMP_DISK")" "$(json_esc "$TEMP_BOARD")" "$(json_esc "$FIRMWARE_VENDOR")" "$(json_esc "$FIRMWARE_VER")" "$(json_esc "$FIRMWARE_DATE")" "$(json_esc "$FIRMWARE_CLASS")" "$(json_esc "$BIOS_REV")" "$(json_esc "$FW_REV")" "$(json_esc "$ROM_SIZE")" "$(json_esc "$SMBIOS_VER")"
  printf '  "03 GERENCIADORES": {'
  for ((_mi=0; _mi<${#MANAGER_LABELS[@]}; _mi++)); do printf '"%s": "%s", ' "$(json_esc "${MANAGER_LABELS[$_mi]}")" "$(json_esc "${MANAGER_VALUES[$_mi]}")"; done
  printf '"Browser": ['
  _bi=0; while [ "$_bi" -lt "${#BROWSER_LINES[@]}" ]; do if [ "$_bi" -gt 0 ]; then printf ', '; fi; printf '"%s"' "$(json_esc "${BROWSER_LINES[$_bi]}")"; _bi=$(( _bi + 1 )); done
  if [ "${#BROWSER_LINES[@]}" -eq 0 ]; then printf '"Nenhum browser encontrado"'; fi
  printf ']'
  for ((_ag=0; _ag<${#APP_LABELS[@]}; _ag++)); do
    printf ', "%s": [' "$(json_esc "${APP_LABELS[$_ag]}")"; _first=1
    for ((_ai=0; _ai<${#APP_NAMES[@]}; _ai++)); do
      if [ "${APP_GROUPS[$_ai]}" = "$_ag" ]; then
        [ "$_first" = 1 ] || printf ', '; _first=0
        printf '"%s"' "$(json_esc "${APP_NAMES[$_ai]}")"
      fi
    done
    printf ']'
  done
  printf '},\n' 
  printf '  "04 REDES": {"Interfaces": "%s", "Interface Principal": "%s", "IP": "%s", "IP Externo": "%s", "Gateway": "%s", "DNS": "%s", "MAC": "%s", "MTU": "%s", "command": "%s %s"},\n' "$(json_esc "$NET_IFACES")" "$(json_esc "$NET_PRIMARY")" "$(json_esc "$NET_IP")" "$(json_esc "$EXT_IP")" "$(json_esc "$NET_GW")" "$(json_esc "$NET_DNS")" "$(json_esc "$NET_MAC")" "$(json_esc "$NET_MTU")" "$(json_esc "$NET_CMD")" "$(json_esc "$NET_ATIVO")"
  printf '  "05 MEMORIA RAM + SWAP": {"RAM Total": "%s", "RAM Em uso": "%s", "RAM Disponivel": "%s", "Swap Total": "%s", "Swap Em uso": "%s", "Swap Livre": "%s", "Swap Cached": "%s", "Total RAM+Swap": "%s", "swapon": "sudo swapon -a (ativar)", "swapoff": "sudo swapoff -a (desativar)"},\n' "$(json_esc "$(to_gb "$MEM_TOTAL_KB")")" "$(json_esc "$(to_gb "$MEM_USED_KB")")" "$(json_esc "$(to_gb "$MEM_AVAIL_KB")")" "$(json_esc "$(to_gb "$SWAP_TOTAL_KB")")" "$(json_esc "$(to_gb "$SWAP_USED_KB")")" "$(json_esc "$(to_gb "$SWAP_FREE_KB")")" "$(json_esc "$(to_gb "$SWAP_CACHED_KB")")" "$(json_esc "$(to_gb "$MEM_ALL_KB")")"
  printf '  "Dispositivos RAM": ['
  _mi=0; for _memrow in "${MEM_DEVICES[@]}"; do [ "$_mi" -eq 0 ] || printf ', '; printf '"%s"' "$(json_esc "$_memrow")"; _mi=$((_mi+1)); done
  printf '],\n'
  printf '  "06 WIFI": {"Interface": "%s", "SSID": "%s", "Sinal": "%s", "IP": "%s", "IP Externo": "%s", "MAC": "%s", "Estado": "%s", "Frequencia": "%s", "command": "%s %s", "nmcli d wifi": "Lista os sinais", "nmcli d wifi connect \\"SSID\\"": "Conecta a uma rede"},\n' "$(json_esc "$WIFI_IFACE")" "$(json_esc "$WIFI_SSID")" "$(json_esc "$WIFI_SIGNAL")" "$(json_esc "$WIFI_IP")" "$(json_esc "$EXT_IP")" "$(json_esc "$WIFI_MAC")" "$(json_esc "$WIFI_STATE")" "$(json_esc "$WIFI_FREQ")" "$(json_esc "$WIFI_CMD")" "$(json_esc "$WIFI_ATIVO")"
  printf '  "07 AMBIENTE & RUNTIME": {"Ambiente grafico": "%s", "Sessao": "%s", "Display": "%s", "Shell (bash)": "%s", "Init system": "%s", "Firewall": "%s", "Seguranca kernel": "%s", "Virtualizacao": "%s", "Uptime": "%s", "Timezone": "%s", "Logados": "%s (%s)", "Ultimo Boot": "%s"},\n' "$(json_esc "$DE_VAL")" "$(json_esc "$SESSION_TYPE_VAL")" "$(json_esc "$DISPLAY_VAL")" "$(json_esc "$SHELL_V")" "$(json_esc "$INIT_SYS")" "$(json_esc "$FW")" "$(json_esc "$SEC_MOD")" "$(json_esc "$VIRT")" "$(json_esc "$UPTIME_V")" "$(json_esc "$TZ_V")" "$(json_esc "$LOGGED_N")" "$(json_esc "$LOGGED_USERS")" "$(json_esc "$LAST_BOOT")"
  printf '  "08 SISTEMA + KERNEL": {"Distribuicao": "%s", "Versao": "%s", "Kernel": "%s", "Arquitetura": "%s", "UMASK": "%s", "Boot": "%s", "Disco Boot": "%s", "Secure Boot": "%s", "Atual": "%s", "Pacotes": "%s", "Atualizacoes": "%s"},\n' "$(json_esc "$OS_NAME")" "$(json_esc "$OS_VER")" "$(json_esc "$KERNEL_V")" "$(json_esc "$ARCH_V")" "$(json_esc "$UMASK_VAL")" "$(json_esc "$BOOT_INFO")" "$(json_esc "$BOOT_DISK_INFO")" "$(json_esc "$SECURE_BOOT")" "$(json_esc "$BOOT_INFO")" "$(json_esc "$PKG_COUNT")" "$(json_esc "$UPDATES")"
  printf '  "09 ARMAZENAMENTO": [ '
  _si=0; while [ "$_si" -lt "${#STORAGE_LINES[@]}" ]; do _raw="${STORAGE_LINES[$_si]}"; _m=$(printf '%s' "$_raw" | awk '{print $1}'); _pc=$(printf '%s' "$_raw" | awk '{print $2}'); _sz=$(printf '%s' "$_raw" | awk '{print $3}'); _us=$(printf '%s' "$_raw" | awk '{print $4}'); _av=$(printf '%s' "$_raw" | awk '{print $5}'); if [ "$_si" -gt 0 ]; then printf ', '; fi; printf '{\"MONTE\": \"%s\", \"USO%%\": \"%s\", \"TOTAL\": \"%s\", \"USADO\": \"%s\", \"LIVRE\": \"%s\"}' "$(json_esc "$_m")" "$(json_esc "$_pc")" "$(json_esc "$_sz")" "$(json_esc "$_us")" "$(json_esc "$_av")"; _si=$(( _si + 1 )); done
  printf ' ],\n'
  printf '  "RODAPE": {"Status": "Dashboard carregado com sucesso."}\n'
  printf '}\n'
} > "$JSON_FILE" 2>/dev/null
chmod 600 "$REPORT_FILE" "$HTML_FILE" "$CSV_FILE" "$JSON_FILE" 2>/dev/null
if command -v jq >/dev/null 2>&1; then
  jq -e 'type == "object"' "$JSON_FILE" >/dev/null 2>&1 || INVENTORY_JSON_WARNING=1
elif command -v python3 >/dev/null 2>&1; then
  python3 -I -m json.tool "$JSON_FILE" >/dev/null 2>&1 || INVENTORY_JSON_WARNING=1
else
  pre_error 'JSON: nenhum validador estrutural (jq ou Python 3) disponivel.'
fi
if [ "${INVENTORY_JSON_WARNING:-0}" = 1 ]; then pre_error 'JSON: validacao estrutural falhou.'; fi
PRE_REPORT_MS=$(pre_clock_ms)
{
  printf '<!doctype html>\n<html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>InventoryTaker - Preparação do ambiente</title><style>body{background:#171717;color:#eee;font:16px system-ui;max-width:1000px;margin:40px auto;padding:20px}h1,h2{color:#ffd54f}li{padding:9px;border-bottom:1px solid #444;overflow-wrap:anywhere}small{color:#bbb}dl{margin:0} .prep-row{display:grid;grid-template-columns:minmax(12em,35%%) minmax(0,1fr);gap:12px;padding:8px 0;border-bottom:1px solid #444;align-items:baseline} .prep-row dt{color:#ffd54f} .prep-row dd{margin:0;overflow-wrap:anywhere}</style></head><body><h1>INVENTORYTAKER - Desktop</h1><h2>Preparação do ambiente</h2><p>Autor: Everaldo Costa Silva / Licença: MIT</p><p>Preparação inicial: %s. Verificações adicionais de dependências durante a coleta estão incluídas no tempo total, não no tempo inicial.</p><p>Alertas: %s</p>\n' "$(pre_duration "$((PRE_INITIAL_END_MS-PRE_START_MS))")" "${#PRE_ERRORS[@]}"
  printf '<h2>Identificação e configuração</h2><dl>\n'
  for _key in 'Host' 'Distribuição' 'Família' 'Kernel' 'Arquitetura' 'Gerenciador de pacotes' 'Privilégio' 'Sistema de inicialização' 'Instalação automática' 'Data da execução'; do
    case "$_key" in
      Host) _val=$HOST;; Distribuição) _val=$ENV_DISTRO_ID;; Família) _val=$ENV_FAMILY;; Kernel) _val=$ENV_KERNEL;; Arquitetura) _val=$ENV_ARCH;; 'Gerenciador de pacotes') _val=$PKG_MGR;; Privilégio) _val=$ENV_PRIV;; 'Sistema de inicialização') _val=$ENV_INIT;; 'Instalação automática') _val=$INVENTORY_AUTOINSTALL;; *) _val=$NOW;;
    esac
    printf '<div class="prep-row"><dt><strong>%s:</strong></dt><dd>%s</dd></div>\n' "$(html_esc "$_key")" "$(html_esc "${_val:-N/A}")"
  done
  printf '</dl><h2>Resumo de dependências</h2><p>Ferramentas verificadas: %s | Pacotes com tentativa de instalação: %s</p><p>Coleta e geração dos relatórios anteriores: %s.<br>Tempo total decorrido até o início deste relatório: %s.</p>\n' "$(printf '%s\n' "$ENSURE_DONE" | awk '{print NF}')" "$(printf '%s\n' "$PKG_ATTEMPTED" | awk '{print NF}')" "$(pre_duration "$((PRE_REPORT_MS-PRE_INITIAL_END_MS))")" "$(pre_duration "$((PRE_REPORT_MS-PRE_START_MS))")"
  printf '<h2>Alertas e resultados</h2><ul>\n'
  if [ "${#PRE_ERRORS[@]}" -eq 0 ]; then printf '<li>Nenhum alerta registrado.</li>\n'; else
    for _event in "${PRE_ERRORS[@]}"; do printf '<li>%s</li>\n' "$(html_esc "$_event")"; done
  fi
  printf '</ul><h2>Cronologia da execução</h2><ol>\n'
  for _event in "${PRE_EVENTS[@]}"; do printf '<li>%s</li>\n' "$(html_esc "$_event")"; done
  printf '</ol><p><a style="color:#ffd54f" href="%s">Voltar ao inventário</a></p><small>Registro de eventos e resultados resumidos; não contém saída bruta dos comandos nem credenciais. Pacotes previamente instalados são registrados quando o gerenciador permite confirmação; demais eventos indicam o resultado da tentativa.</small></body></html>\n' "$(html_esc "${HTML_FILE##*/}")"
} > "$PREP_FILE"
if [ "$(id -u)" = 0 ]; then
  for _report in "$REPORT_FILE" "$HTML_FILE" "$CSV_FILE" "$JSON_FILE" "$PREP_FILE"; do
    "${REPORT_AS[@]}" bash -c 'umask 077; set -C; cat > "$1"' bash "$DEST_DIR/${_report##*/}" < "$_report" || { printf 'Erro ao publicar relatorio.\n' >&2; exit 1; }
  done
  for _var in REPORT_FILE HTML_FILE CSV_FILE JSON_FILE PREP_FILE; do
    _old=${!_var}; printf -v "$_var" '%s/%s' "$DEST_DIR" "${_old##*/}"; rm -f -- "$_old"
  done
  rmdir -- "$DESKTOP_DIR"; DESKTOP_DIR="$DEST_DIR"
fi
inventory_progress 100
if [ "$CURSOR_ENABLED" = 1 ] && [ "$CHECK_MODE" = 0 ]; then
  sleep 0.3
  printf '\r\033[2K\033[?25h'
fi
inventory_render_panels
inventory_render_alerts
[ "${INVENTORY_HTML_WARNING:-0}" != 1 ] || printf 'Aviso: falha na geracao do relatorio HTML.\n' >&2
[ "${INVENTORY_JSON_WARNING:-0}" != 1 ] || printf 'Aviso: JSON gerado, mas a validacao estrutural falhou.\n' >&2
printf '\n'
printf '%s\n' "${BG_WHITE}${C_BLACK}${BOLD}  RELATÓRIOS DO INVENTÁRIO  ${RESET}"
printf '\n%s\n' "${C_YELLOW}Arquivos gerados no caminho abaixo:${RESET}"
printf '\n'
footer_rule
footer_row '[1] TXT' "file://$REPORT_FILE"
footer_row '[2] HTML' "file://$HTML_FILE"
footer_row '[3] CSV' "file://$CSV_FILE"
footer_row '[4] JSON' "file://$JSON_FILE"
footer_row '[5] HTML' "file://$PREP_FILE"
footer_end
  printf '\n%s\n' "${BOLD}${C_YELLOW}ABRIR RELATÓRIO${RESET}"
  footer_rule
  footer_full_row '[1] TXT  [2] HTML  [3] CSV  [4] JSON  [5] Abrir PREPARAÇÃO do AMBIENTE  [6] DOCUMENTAÇÃO  [0] SAIR'
  footer_end
  printf '\n'
while true; do
  printf '%s' "${C_YELLOW}Digite a opção: ${RESET}"
  if ! read -r _escolha; then break; fi
  if [ "$CURSOR_ENABLED" = 1 ]; then printf '\033[1A\r\033[2K'; fi
  case "$_escolha" in
    1) if ! _open_msg=$(open_file_de_independent "$REPORT_FILE"); then [ "$CURSOR_ENABLED" = 0 ] || printf '\r\033[2K'; printf '%s\n' "$_open_msg"; fi ;;
    2) if ! _open_msg=$(open_file_de_independent "$HTML_FILE"); then [ "$CURSOR_ENABLED" = 0 ] || printf '\r\033[2K'; printf '%s\n' "$_open_msg"; fi ;;
    3) if ! _open_msg=$(open_file_de_independent "$CSV_FILE"); then [ "$CURSOR_ENABLED" = 0 ] || printf '\r\033[2K'; printf '%s\n' "$_open_msg"; fi ;;
    4) if ! _open_msg=$(open_file_de_independent "$JSON_FILE"); then [ "$CURSOR_ENABLED" = 0 ] || printf '\r\033[2K'; printf '%s\n' "$_open_msg"; fi ;;
    5) if ! _open_msg=$(open_file_de_independent "$PREP_FILE"); then [ "$CURSOR_ENABLED" = 0 ] || printf '\r\033[2K'; printf '%s\n' "$_open_msg"; fi ;;
    6) if ! _open_msg=$(open_inventory_documentation); then [ "$CURSOR_ENABLED" = 0 ] || printf '\r\033[2K'; printf '%s\n' "$_open_msg"; fi ;;
    0) break ;;
    "") printf 'ENTER nao sai. Digite 0 para sair.\n' ;;
    *) printf 'Opcao invalida. Digite 0 para sair.\n' ;;
  esac
done
printf '\n'
__INVENTORYTAKER_BACKEND_EOF__
}

write_gui() {
  cat > "$1" <<'__INVENTORYTAKER_GUI_EOF__'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# INVENTORYTAKER - Desktop (GTK 3)
# Interface gráfica do LINUX InventoryTaker (backend em bash, inalterado).
# Backend: Everaldo Costa Silva | Licença: MIT
#
# Fluxo: tela inicial com os 9 blocos vazios -> botão GERAR RELATÓRIO ->
# executa o script original (com senha de administrador, se informada) ->
# lê o JSON gerado -> preenche os blocos -> habilita as opções do rodapé.

import fcntl
import glob
import json
import os
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import termios
import threading
import time
from collections import OrderedDict

APP_DIR = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.join(APP_DIR, "LINUX_InventoryTaker.sh")
ICON = os.path.join(APP_DIR, "inventorytaker.svg")
DOC_URL = ("https://github.com/Everaldo-127/linux-xubuntu/blob/main/"
           "Documenta%C3%A7%C3%A3o/Manual_Inventorytaker.pdf")
REPORT_DIR = os.path.join(os.path.expanduser("~"), "Área de trabalho", "INVENTÁRIO")

# (chave no JSON, título exibido)
BLOCKS = [
    ("01 PORTAS ABERTAS", "01   PORTAS ABERTAS"),
    ("02 HARDWARE", "02   HARDWARE"),
    ("03 GERENCIADORES", "03   GERENCIADORES"),
    ("04 REDES", "04   REDES"),
    ("05 MEMORIA RAM + SWAP", "05   MEMORIA RAM + SWAP"),
    ("06 WIFI", "06   WIFI"),
    ("07 AMBIENTE & RUNTIME", "07   AMBIENTE & RUNTIME"),
    ("08 SISTEMA + KERNEL", "08   SISTEMA + KERNEL"),
    ("09 ARMAZENAMENTO", "09   ARMAZENAMENTO"),
]

MENU = [
    ("txt", "[1] TXT"),
    ("html", "[2] HTML"),
    ("csv", "[3] CSV"),
    ("json", "[4] JSON"),
    ("prep", "[5] PREPARAÇÃO DO AMBIENTE"),
    ("doc", "[6] DOCUMENTAÇÃO"),
    ("exit", "[0] SAIR"),
]

PROMPT_RE = re.compile(r"(\[sudo\]|password for|senha para)[^\n]*:\s*$", re.I)
PCT_RE = re.compile(r"\]\s*(\d{1,3})%")
READY_MARK = "Digite a op"
CTRL_RE = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")


# ---------------------------------------------------------------------------
# Núcleo (sem GTK): sudo, execução do backend em pty, leitura do JSON
# ---------------------------------------------------------------------------

def sudo_nopasswd():
    """True se o sudo funciona sem senha (NOPASSWD)."""
    try:
        subprocess.call(["sudo", "-k"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        rc = subprocess.call(["sudo", "-n", "-v"], stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return rc == 0
    except Exception:
        return False


def sudo_check(password):
    """Valida a senha de administrador sem gravá-la em lugar nenhum."""
    try:
        subprocess.call(["sudo", "-k"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        p = subprocess.Popen(["sudo", "-S", "-p", "", "-v"], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        p.communicate((password + "\n").encode("utf-8"), timeout=20)
        ok = (p.returncode == 0)
        subprocess.call(["sudo", "-k"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return ok
    except Exception:
        return False


def find_reports(since):
    """Localiza o conjunto de relatórios mais recente gerado após 'since'."""
    best = None
    for path in glob.glob(os.path.join(REPORT_DIR, "LINUX_InventoryTaker_*.json")):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtime >= since - 3 and (best is None or mtime > best[0]):
            best = (mtime, path)
    if best is None:
        return None
    stem = best[1][:-len(".json")]
    files = {
        "json": stem + ".json",
        "txt": stem + ".txt",
        "html": stem + ".html",
        "csv": stem + ".csv",
        "prep": stem + "_preparacao.html",
    }
    return dict((k, v) for k, v in files.items() if os.path.isfile(v))


class InventoryRunner(object):
    """Executa o script original num pseudo-terminal (o script exige tty para o sudo)."""

    def __init__(self, backend, password, readonly, on_progress, on_done):
        self.backend = backend
        self._pw = password
        self.readonly = readonly
        self.on_progress = on_progress
        self.on_done = on_done
        self._cancel = False
        self._proc = None

    def start(self):
        t = threading.Thread(target=self._run)
        t.daemon = True
        t.start()

    def cancel(self):
        self._cancel = True
        self._kill()

    def _kill(self):
        proc = self._proc
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, 15)
            except Exception:
                try:
                    proc.terminate()
                except Exception:
                    pass

    def _finish(self, **kw):
        result = {"cancelled": False, "error": None, "files": None, "tail": ""}
        result.update(kw)
        try:
            self.on_done(result)
        except Exception:
            pass

    def _run(self):
        started = time.time()
        env = dict(os.environ)
        env["TERM"] = "dumb"
        env.pop("NO_COLOR", None)
        args = ["bash", self.backend]
        if self.readonly:
            args.append("--read-only")
        try:
            master, slave = pty.openpty()
            try:
                fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
            except Exception:
                pass

            def child_setup():
                os.setsid()
                try:
                    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
                except Exception:
                    pass

            self._proc = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave,
                                          env=env, close_fds=True, preexec_fn=child_setup)
            os.close(slave)
        except Exception as exc:
            self._finish(error="Não foi possível iniciar o InventoryTaker: %s" % exc)
            return

        proc = self._proc
        buf = ""
        full_tail = ""
        prompts = 0
        sent_exit = False
        error = None
        last_pct = -1
        while True:
            if self._cancel:
                break
            try:
                ready = select.select([master], [], [], 0.3)[0]
            except Exception:
                break
            if not ready:
                if proc.poll() is not None:
                    break
                continue
            try:
                data = os.read(master, 4096)
            except OSError:
                break
            if not data:
                break
            text = data.decode("utf-8", "replace")
            buf = (buf + text)[-20000:]
            full_tail = (full_tail + text)[-4000:]

            found = PCT_RE.findall(text)
            if found:
                pct = int(found[-1])
                if pct != last_pct and 0 <= pct <= 100:
                    last_pct = pct
                    try:
                        self.on_progress(pct)
                    except Exception:
                        pass

            if PROMPT_RE.search(buf[-300:]):
                prompts += 1
                if prompts > 1:
                    error = "Senha de administrador incorreta."
                    break
                if self._pw is None:
                    error = "O sudo pediu senha, mas nenhuma senha foi informada."
                    break
                try:
                    os.write(master, (self._pw + "\n").encode("utf-8"))
                except OSError:
                    pass
                self._pw = None
                buf = ""
                full_tail = ""
                continue

            if not sent_exit and READY_MARK in buf:
                sent_exit = True
                try:
                    os.write(master, b"0\n")
                except OSError:
                    pass

        self._pw = None
        if error or self._cancel:
            self._kill()
        try:
            proc.wait(timeout=10)
        except Exception:
            try:
                os.killpg(proc.pid, 9)
            except Exception:
                pass
            try:
                proc.wait(timeout=3)
            except Exception:
                pass
        try:
            os.close(master)
        except OSError:
            pass

        tail = CTRL_RE.sub("", full_tail.replace("\r", "\n"))
        tail = "\n".join([ln for ln in tail.split("\n") if ln.strip()][-12:])
        if self._cancel:
            self._finish(cancelled=True)
            return
        if error:
            self._finish(error=error, tail=tail)
            return
        files = find_reports(started)
        if not files or "json" not in files:
            self._finish(error="O relatório não foi gerado. Veja a saída do programa abaixo.",
                         tail=tail)
            return
        self._finish(files=files, tail=tail)


def load_report(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh, object_pairs_hook=OrderedDict)


# ---------------------------------------------------------------------------
# Modelo de linhas dos blocos: (tipo, a, b, estilo)
#   kv: rótulo/valor | head: subtítulo | text: texto | sep: divisória
#   trow: linha de tabela (a = lista de colunas; estilo 'head' no cabeçalho)
# ---------------------------------------------------------------------------

def _style_for(value):
    text = str(value)
    if text.endswith(" INATIVO"):
        return "bad"
    if text.endswith(" ATIVO"):
        return "ok"
    return ""


def _dict_rows(section, seps=None, list_as_head=False):
    seps = seps or {}
    rows = []
    for key, value in section.items():
        if key in seps:
            rows.append(("sep", "", "", ""))
            if seps[key]:
                rows.append(("head", seps[key], "", ""))
        if isinstance(value, list):
            if list_as_head:
                rows.append(("sep", "", "", ""))
                rows.append(("head", key, "", ""))
                if not value:
                    rows.append(("text", "Nenhum", "", ""))
                for item in value:
                    rows.append(("text", str(item), "", ""))
            else:
                if not value:
                    rows.append(("kv", key, "Nenhum", ""))
                for item in value:
                    rows.append(("kv", key, str(item), ""))
        else:
            rows.append(("kv", key, str(value), _style_for(value)))
    return rows


def build_rows(key, data):
    section = data.get(key)
    if section is None:
        return [("text", "Sem dados nesta seção.", "", "")]
    if key == "09 ARMAZENAMENTO":
        cols = ["MONTE", "USO%", "TOTAL", "USADO", "LIVRE"]
        rows = [("trow", cols, "", "head")]
        for item in section:
            rows.append(("trow", [str(item.get(c, "")) for c in cols], "", ""))
        return rows
    if key == "01 PORTAS ABERTAS":
        return _dict_rows(section)
    if key == "02 HARDWARE":
        return _dict_rows(section, seps={"Temperatura CPU": "Temperatura", "Firmware": None})
    if key == "03 GERENCIADORES":
        return _dict_rows(section, list_as_head=True)
    if key == "05 MEMORIA RAM + SWAP":
        part_a, part_b, seen = OrderedDict(), OrderedDict(), False
        for k, v in section.items():
            if k == "swapon":
                seen = True
            (part_b if seen else part_a)[k] = v
        rows = [("head", "MEMORIA FISICA", "", "")]
        rows += _dict_rows(part_a, seps={"Swap Total": "MEMORIA SWAP"})
        rows.append(("sep", "", "", ""))
        rows.append(("head", "DISPOSITIVOS RAM", "", ""))
        for item in data.get("Dispositivos RAM", []) or ["N/A"]:
            rows.append(("text", str(item), "", ""))
        rows.append(("sep", "", "", ""))
        rows.append(("head", "COMANDOS SWAP", "", ""))
        rows += _dict_rows(part_b)
        return rows
    if key == "06 WIFI":
        rows = [("head", "CONEXAO SEM FIO", "", "")]
        rows += _dict_rows(section, seps={"IP": "ENDERECAMENTO", "command": "COMANDOS WIFI"})
        return rows
    if key == "07 AMBIENTE & RUNTIME":
        return _dict_rows(section, seps={"Shell (bash)": None})
    if key == "08 SISTEMA + KERNEL":
        return _dict_rows(section, seps={"Boot": None})
    return _dict_rows(section)


# ---------------------------------------------------------------------------
# Interface GTK 3
# ---------------------------------------------------------------------------

try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("Pango", "1.0")
    from gi.repository import Gtk, Gdk, GLib, Gio, Pango
except Exception as _exc:  # pragma: no cover
    sys.stderr.write("InventoryTaker GUI: GTK 3 / PyGObject indisponível (%s).\n"
                     "Reinstale com o instalador do InventoryTaker.\n" % _exc)
    sys.exit(1)

CSS = b"""
window, .app, scrolledwindow, viewport { background-color: #1e1e1e; color: #d4d4d4; }
label { color: #d4d4d4; }
.hero { background-image: linear-gradient(to right, #ff9900, #7c3aed, #2563eb);
        border-radius: 14px; padding: 0 16px 12px 16px; }
.hero-title { color: #ffffff; font-size: 32px; font-weight: 800;
              font-family: "Ubuntu", "Noto Sans", "DejaVu Sans", sans-serif;
              text-shadow: 0 3px 6px rgba(0, 0, 0, 0.55); }
.hero-sub { color: #fef9c3; font-size: 16px; font-weight: bold;
            font-family: "Ubuntu", "Noto Sans", "DejaVu Sans", sans-serif;
            text-shadow: 0 1px 3px rgba(0, 0, 0, 0.5); }
.hero-info { color: #ffffff; font-size: 13px; font-weight: bold;
             font-family: "Ubuntu", "Noto Sans", "DejaVu Sans", sans-serif;
             background-color: rgba(0, 0, 0, 0.32); border-radius: 999px;
             padding: 4px 18px; }
.hero-line { background-image: linear-gradient(to right, rgba(250, 204, 21, 0), #facc15, rgba(250, 204, 21, 0));
             min-height: 3px; }
.path-box { background-color: #1f2937; border: 2px solid #facc15; border-radius: 10px;
            padding: 6px 16px; }
.path-box label { font-size: 14px; }
.card { background-color: #252526; border: 2px solid #eab308; border-radius: 14px; }
.card-title { background-image: linear-gradient(to right, #b8860b, #facc15, #fef08a);
              color: #111111; font-weight: bold; font-size: 14px;
              border-radius: 11px 11px 0 0; padding: 7px 10px; }
label.key { color: #facc15; font-weight: bold; }
label.head { color: #facc15; font-weight: bold; margin-top: 3px; }
label.val { color: #ffffff; }
label.ok { color: #22c55e; font-weight: bold; }
label.bad { color: #ef4444; font-weight: bold; }
label.livre { color: #facc15; font-weight: bold; }
label.dim { color: #7c7c7c; font-style: italic; }
.sep { background-color: #b8860b; min-height: 2px; }
button.btn-gerar { background-image: linear-gradient(to bottom, #fde047, #eab308);
                   color: #111111; font-weight: bold; font-size: 15px; border: none;
                   border-radius: 10px; padding: 8px 26px; text-shadow: none; }
button.btn-gerar label { color: #111111; }
button.btn-gerar:disabled { opacity: 0.5; }
button.btn-menu { background-image: linear-gradient(to bottom, #3b82f6, #2563eb);
                  color: #ffffff; font-weight: bold; border: none; border-radius: 10px;
                  padding: 7px 14px; text-shadow: none; }
button.btn-menu label { color: #ffffff; }
button.btn-menu:disabled { background-image: none; background-color: #374151; opacity: 0.55; }
button.btn-sair { background-image: linear-gradient(to bottom, #ef4444, #b91c1c);
                  color: #ffffff; font-weight: bold; border: none; border-radius: 10px;
                  padding: 7px 14px; text-shadow: none; }
button.btn-sair label { color: #ffffff; }
.footer { background-color: #111827; border-radius: 12px; padding: 10px 14px; }
.footer-title { color: #facc15; font-weight: bold; font-size: 14px; }
progressbar trough { min-height: 16px; background-color: #111827; border-radius: 999px; }
progressbar progress { min-height: 16px; border-radius: 999px;
                       background-image: linear-gradient(to right, #b8860b, #facc15); }
progressbar text { color: #ffffff; font-weight: bold; }
"""


CSS += b"""
window, .app, scrolledwindow, viewport { background-color: #0d1117; color: #e6edf3; }
label { color: #e6edf3; font-family: "DejaVu Sans Mono", monospace; }
.hero, .footer, .path-box { background-image: none; background-color: #161b22; border: 1px solid #30363d; }
.card { background-color: #161b22; border: 1px solid #30363d; border-radius: 10px; }
.card-title { background-image: none; background-color: #ffd700; color: #111111; }
label.val { color: #e6edf3; } label.key { color: #58a6ff; }
label.dim { color: #a0aab5; } label.warn { color: #ffd700; }
.inventory-row { padding: 4px; } .alternate { background-color: #1c2430; }
scrollbar.vertical slider { min-width: 14px; min-height: 32px; background-color: #718096; }
scrollbar.vertical trough { background-color: #161b22; }
.metric progressbar progress { background-image: none; background-color: #3fb950; }
.metric.warn progressbar progress { background-color: #d29922; }
.metric.bad progressbar progress { background-color: #f85149; }
/* Light theme adapted from the supplied InventoryTaker GTK stylesheet. */
.light, .light scrolledwindow, .light viewport { background-color: #e5e7eb; color: #24292f; }
.light label, .light label.val { color: #24292f; }
.light .hero { background-image: linear-gradient(to right, #cf7600, #6530c8, #1d4ed8); border-color: #aeb6c0; }
.light .hero-title { color: #ffffff; text-shadow: 0 3px 6px rgba(0,0,0,0.8); }
.light .hero-sub { color: #ffffff; text-shadow: 0 1px 3px #222222; }
.light .hero-info { background-color: rgba(0,0,0,0.65); color: #ffffff; }
.light .hero-line { background-image: linear-gradient(to right, rgba(250,204,21,0), #d9ab12, rgba(250,204,21,0)); }
.light .card { background-color: #f0f1f3; border: 2px solid #b88a0a; border-radius: 14px; }
.light .card-title { background-image: linear-gradient(to right, #b8860b, #d9ab12, #e8ce65); color: #111111; border-radius: 11px 11px 0 0; }
.light label.key, .light label.head, .light .footer-title { color: #795000; }
.light label.dim { color: #57606a; }
.light label.ok { color: #116329; }
.light label.livre, .light label.warn { color: #795000; }
.light label.bad { color: #a40e26; }
.light .alternate { background-color: #e5e7eb; }
.light .sep { background-color: #b8860b; }
.light .footer, .light .path-box { background-color: #e9e4d5; border: 1px solid #b88a0a; }
.light entry, .light combobox button, .light button { background-image: none; background-color: #e9edf1; color: #24292f; border: 1px solid #aeb6c0; text-shadow: none; }
.light entry:focus { border-color: #0969da; }
.light entry selection { background-color: #0969da; color: #ffffff; }
.light button:hover { background-color: #d4d9df; }
.light button.btn-gerar { background-image: linear-gradient(to bottom, #e5c132, #b88a0a); color: #111111; border: none; }
.light button.btn-gerar label { color: #111111; }
.light button.btn-menu { background-image: linear-gradient(to bottom, #2867d5, #1d4ed8); color: #ffffff; border: none; }
.light button.btn-menu label { color: #ffffff; }
.light button.btn-sair { background-image: linear-gradient(to bottom, #d33434, #b91c1c); color: #ffffff; border: none; }
.light button.btn-sair label { color: #ffffff; }
.light button:disabled { background-image: none; background-color: #d4d9df; opacity: 0.65; }
.light button:disabled label { color: #57606a; }
.light progressbar trough { background-color: #d4d9df; }
.light progressbar progress { background-image: linear-gradient(to right, #b8860b, #d9ab12); }
.light progressbar text { color: #24292f; }
.light .hero progressbar text { color: #ffffff; text-shadow: 0 1px 3px #222222; }
.light .metric progressbar progress { background-image: none; background-color: #1a7f37; }
.light .metric.warn progressbar progress { background-color: #9a6700; }
.light .metric.bad progressbar progress { background-color: #cf222e; }
.light scrollbar.vertical slider { background-color: #8c959f; }
.light scrollbar.vertical trough { background-color: #d4d9df; }
.mono .card, .mono .hero, .mono .footer, .mono .path-box, .mono scrolledwindow, .mono viewport { background-color: #181818; border-color: #888888; }
.mono { background-color: #111111; } .mono label { color: #eeeeee; }
.mono .card-title, .mono button { background-image: none; background-color: #444444; color: #ffffff; }
.mono .alternate { background-color: #292929; }
.mono progressbar progress { background-image: none; background-color: #aaaaaa; }
.mono .hero-line, .mono .sep { background-image: none; background-color: #aaaaaa; }
"""

def banner_markup(text):
    """Título com degradê por letra (branco -> dourado -> branco) e espaçamento."""
    stops = [(255, 255, 255), (253, 224, 71), (255, 255, 255)]
    n = max(len(text) - 1, 1)
    out = []
    for i, ch in enumerate(text):
        pos = i / float(n) * (len(stops) - 1)
        lo = min(int(pos), len(stops) - 2)
        frac = pos - lo
        rgb = [int(stops[lo][k] + (stops[lo + 1][k] - stops[lo][k]) * frac) for k in range(3)]
        out.append('<span foreground="#%02x%02x%02x" letter_spacing="2000">%s</span>'
                   % (rgb[0], rgb[1], rgb[2], GLib.markup_escape_text(ch, -1)))
    return "".join(out)


def _label(text, classes=(), wrap=False, selectable=False):
    lbl = Gtk.Label(label=text)
    lbl.set_xalign(0.0)
    lbl.set_valign(Gtk.Align.START)
    for cls in classes:
        lbl.get_style_context().add_class(cls)
    if wrap:
        lbl.set_line_wrap(True)
        lbl.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        lbl.set_width_chars(8)
        lbl.set_max_width_chars(46)
    if selectable:
        lbl.set_selectable(True)
    return lbl


class Card(Gtk.Box):
    """Um bloco numerado (box com título dourado e conteúdo)."""

    def __init__(self, key, title):
        Gtk.Box.__init__(self, orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.key = key
        self.get_style_context().add_class("card")
        head = Gtk.Label(label=title)
        head.get_style_context().add_class("card-title")
        head.set_xalign(0.5)
        self.pack_start(head, False, False, 0)
        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        self.body.set_border_width(10)
        self.pack_start(self.body, True, True, 0)
        self.set_empty()

    def _clear(self):
        for child in self.body.get_children():
            self.body.remove(child)

    def set_empty(self):
        self._clear()
        self.body.pack_start(_label("Aguardando geração do relatório...", ["dim"]),
                             False, False, 0)
        self.body.show_all()

    def fill(self, rows):
        self._clear()
        if self.key == "09 ARMAZENAMENTO" and rows and rows[0][0] == "trow":
            self.fill_storage(rows)
            self.body.show_all()
            return
        for index, (kind, a, b, style) in enumerate(rows):
            if kind == "sep":
                sep = Gtk.Box()
                sep.set_size_request(-1, 2)
                sep.get_style_context().add_class("sep")
                self.body.pack_start(sep, False, False, 4)
            elif kind == "head":
                self.body.pack_start(_label(a, ["head"]), False, False, 0)
            elif kind == "text":
                self.body.pack_start(_label(a, ["val"], wrap=True, selectable=True),
                                     False, False, 0)
            elif kind == "kv":
                row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
                row.pack_start(_label(a + ":", ["key"]), False, False, 0)
                classes = ["val"] + ([style] if style else [])
                row.pack_start(_label(b, classes, wrap=True, selectable=True), True, True, 0)
                self.decorate(row, index)
                self.body.pack_start(row, False, False, 0)
            elif kind == "trow":
                row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
                for idx, cell in enumerate(a):
                    if style == "head":
                        classes = ["key"]
                    elif idx == len(a) - 1:
                        classes = ["livre"]
                    else:
                        classes = ["val"]
                    lbl = _label(cell, classes)
                    lbl.set_width_chars(10 if idx == 0 else 6)
                    lbl.set_xalign(0.0 if idx == 0 else 1.0)
                    row.pack_start(lbl, idx == 0, idx == 0, 0)
                self.decorate(row, index)
                self.body.pack_start(row, False, False, 0)
                if style != "head" and len(a) > 1:
                    self.metric(a[0], a[1])
        self.body.show_all()

    def fill_storage(self, rows):
        entries = [a for kind, a, b, style in rows
                   if kind == "trow" and style != "head" and len(a) == 5]
        if not entries:
            self.body.pack_start(_label("Nenhum ponto de montagem encontrado.", ["dim"], wrap=True), False, False, 0)
            return
        self.body.pack_start(_label("Pontos de montagem: %d" % len(entries), ["head"]), False, False, 4)
        for index, (mount, usage, total, used, free) in enumerate(entries):
            panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
            self.decorate(panel, index)
            title = _label(mount or "N/A", ["key"], wrap=True, selectable=True)
            panel.pack_start(title, False, False, 0)
            grid = Gtk.Grid(column_spacing=8, row_spacing=4, column_homogeneous=True)
            for col, (caption, value) in enumerate((("TOTAL", total), ("USADO", used), ("LIVRE", free))):
                heading = _label(caption, ["dim"])
                heading.set_xalign(0.5)
                cell = _label(value or "N/A", ["livre" if col == 2 else "val"], wrap=True, selectable=True)
                cell.set_xalign(0.5)
                grid.attach(heading, col, 0, 1, 1)
                grid.attach(cell, col, 1, 1, 1)
            panel.pack_start(grid, False, False, 0)
            try:
                pct = float(usage.strip().rstrip("%"))
            except (ValueError, TypeError):
                pct = -1
            if 0 <= pct <= 100:
                state = "CRÍTICO" if pct >= 90 else "ALERTA" if pct >= 75 else "NORMAL"
                metric = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
                ctx = metric.get_style_context()
                ctx.add_class("metric")
                if pct >= 75:
                    ctx.add_class("bad" if pct >= 90 else "warn")
                metric.pack_start(_label("Uso: %g%% | %s" % (pct, state), ["bad" if pct >= 90 else "warn" if pct >= 75 else "ok"]), False, False, 0)
                bar = Gtk.ProgressBar()
                bar.set_fraction(pct / 100.0)
                metric.pack_start(bar, False, False, 0)
                panel.pack_start(metric, False, False, 0)
            else:
                panel.pack_start(_label("Uso: " + (usage or "N/A"), ["dim"], wrap=True), False, False, 0)
            self.body.pack_start(panel, False, False, 3)
            if index < len(entries) - 1:
                sep = Gtk.Box()
                sep.set_size_request(-1, 2)
                sep.get_style_context().add_class("sep")
                self.body.pack_start(sep, False, False, 3)

    def decorate(self, row, index):
        ctx = row.get_style_context()
        ctx.add_class("inventory-row")
        if index % 2:
            ctx.add_class("alternate")

    def metric(self, name, value):
        try:
            pct = float(str(value).strip().rstrip("%"))
            if not 0 <= pct <= 100:
                return
        except (ValueError, TypeError):
            return
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        ctx = box.get_style_context()
        ctx.add_class("metric")
        state = "CRITICO" if pct >= 90 else "ALERTA" if pct >= 75 else "NORMAL"
        if pct >= 75:
            ctx.add_class("bad" if pct >= 90 else "warn")
        bar = Gtk.ProgressBar()
        bar.set_fraction(pct / 100.0)
        bar.set_show_text(True)
        bar.set_text("%s: %.1f%% | %s" % (name, pct, state))
        box.pack_start(bar, False, False, 0)
        self.body.pack_start(box, False, False, 3)
        box.show_all()


def open_target(target, kind):
    """Abre arquivo/URL no aplicativo gráfico padrão. Retorna mensagem de erro ou ''."""
    if kind == "doc":
        uri = target
    else:
        if not os.path.isfile(target):
            return "Arquivo não encontrado: %s" % target
        uri = Gio.File.new_for_path(target).get_uri()
    app = None
    try:
        if kind in ("txt", "json"):
            app = Gio.AppInfo.get_default_for_type("text/plain", False)
        elif kind == "csv":
            app = Gio.AppInfo.get_default_for_type("text/csv", False)
        elif kind in ("html", "prep", "doc"):
            app = Gio.AppInfo.get_default_for_type("x-scheme-handler/http", False)
    except Exception:
        app = None
    if app is not None:
        try:
            if app.launch_uris([uri], None):
                return ""
        except Exception:
            pass
    try:
        if Gio.AppInfo.launch_default_for_uri(uri, None):
            return ""
    except Exception:
        pass
    opener = shutil.which("xdg-open")
    if opener:
        try:
            subprocess.Popen([opener, uri], stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return ""
        except Exception:
            pass
    return "Nenhum aplicativo gráfico conseguiu abrir: %s" % target


class MainWindow(Gtk.Window):

    def __init__(self):
        Gtk.Window.__init__(self, title="INVENTORYTAKER - Desktop")
        self.set_default_size(1280, 860)
        self.set_position(Gtk.WindowPosition.CENTER)
        try:
            self.set_icon_from_file(ICON)
        except Exception:
            pass
        self.running = False
        self.runner = None
        self.files = {}
        self.cards = {}
        self.menu_buttons = {}

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        root.get_style_context().add_class("app")
        root.set_border_width(0)
        root.set_margin_start(0)
        root.set_margin_end(0)
        root.set_margin_bottom(10)
        self.add(root)
        self.root_box = root

        # Cabeçalho
        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        hero.get_style_context().add_class("hero")
        title = Gtk.Label()
        self.banner_title = title
        title.set_markup(banner_markup("INVENTORYTAKER - Desktop"))
        title.set_line_wrap(False)
        title.set_single_line_mode(True)
        title.set_justify(Gtk.Justification.CENTER)
        title.set_halign(Gtk.Align.CENTER)
        title.get_style_context().add_class("hero-title")
        line = Gtk.Box()
        line.set_size_request(-1, 3)
        line.set_margin_start(120)
        line.set_margin_end(120)
        line.get_style_context().add_class("hero-line")
        sub = Gtk.Label()
        sub.set_markup('<span letter_spacing="3000">INVENTÁRIO COMPLETO DO SISTEMA</span>')
        sub.get_style_context().add_class("hero-sub")
        self.info = Gtk.Label(label="Clique em GERAR RELATÓRIO para coletar as informações.")
        self.info.set_halign(Gtk.Align.CENTER)
        self.info.get_style_context().add_class("hero-info")
        ctrl = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.btn_gerar = Gtk.Button(label="GERAR RELATÓRIO")
        self.btn_gerar.get_style_context().add_class("btn-gerar")
        self.btn_gerar.connect("clicked", self.on_gerar)
        self.progress = Gtk.ProgressBar()
        self.progress.set_show_text(True)
        self.progress.set_text("Aguardando")
        self.progress.set_hexpand(True)
        self.progress.set_valign(Gtk.Align.CENTER)
        self.btn_cancel = Gtk.Button(label="Cancelar")
        self.btn_cancel.set_no_show_all(True)
        self.btn_cancel.connect("clicked", self.on_cancel)
        ctrl.pack_start(self.btn_gerar, False, False, 0)
        ctrl.pack_start(self.progress, True, True, 0)
        ctrl.pack_start(self.btn_cancel, False, False, 0)
        tools = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.search = Gtk.SearchEntry()
        self.search.set_placeholder_text("Pesquisar no inventário")
        self.search.connect("search-changed", self.filter_cards)
        self.theme = Gtk.ComboBoxText()
        for name in ("Escuro", "Claro", "Monocromático"):
            self.theme.append_text(name)
        self.theme.set_active(0)
        self.theme.connect("changed", self.change_theme)
        tools.pack_start(self.search, True, True, 0)
        tools.pack_start(self.theme, False, False, 0)
        hero.pack_start(title, False, False, 0)
        hero.pack_start(line, False, False, 2)
        hero.pack_start(sub, False, False, 0)
        hero.pack_start(self.info, False, False, 0)
        hero.pack_start(ctrl, False, False, 6)
        hero.pack_start(tools, False, False, 0)
        root.pack_start(hero, False, False, 0)

        # Blocos 01-09 em 3 colunas
        grid = Gtk.Grid()
        grid.set_column_spacing(10)
        grid.set_row_spacing(10)
        grid.set_column_homogeneous(True)
        for idx, (key, title_txt) in enumerate(BLOCKS):
            card = Card(key, title_txt)
            card.set_hexpand(True)
            card.set_vexpand(True)
            self.cards[key] = card
            grid.attach(card, idx % 3, idx // 3, 1, 1)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.add(grid)
        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        nav = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        for key, caption in BLOCKS:
            btn = Gtk.Button(label=caption[:2])
            btn.set_tooltip_text(caption)
            btn.connect("clicked", self.jump_card, key)
            nav.pack_start(btn, False, False, 0)
        content.pack_start(nav, False, False, 0)
        content.pack_start(scroll, True, True, 0)
        root.pack_start(content, True, True, 0)
        self.grid = grid
        self.inventory_scroll = scroll

        # Rodapé
        foot = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        foot.get_style_context().add_class("footer")
        foot_title = Gtk.Label(label="RELATÓRIOS DO INVENTÁRIO")
        foot_title.get_style_context().add_class("footer-title")
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_halign(Gtk.Align.CENTER)
        for key, text in MENU:
            btn = Gtk.Button(label=text)
            btn.get_style_context().add_class("btn-sair" if key == "exit" else "btn-menu")
            btn.set_sensitive(key == "exit")
            btn.connect("clicked", self.on_menu, key)
            self.menu_buttons[key] = btn
            row.pack_start(btn, False, False, 0)
        self.path_label = Gtk.Label()
        self.path_label.set_markup(
            '<b>Pasta dos relatórios: %s</b>' % GLib.markup_escape_text(REPORT_DIR, -1))
        self.path_label.set_line_wrap(False)
        self.path_label.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        self.path_label.set_selectable(True)
        self.path_label.set_halign(Gtk.Align.CENTER)
        path_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        path_box.set_halign(Gtk.Align.CENTER)
        path_box.get_style_context().add_class("path-box")
        path_box.pack_start(self.path_label, False, False, 0)
        self.status = Gtk.Label(label="")
        foot.pack_start(foot_title, False, False, 0)
        foot.pack_start(row, False, False, 0)
        foot.pack_start(path_box, False, False, 0)
        foot.pack_start(self.status, False, False, 0)
        self.clock = Gtk.Label()
        foot.pack_start(self.clock, False, False, 0)
        self.update_clock()
        self.clock_source = GLib.timeout_add_seconds(1, self.update_clock)
        root.pack_start(foot, False, False, 0)

        self.connect("destroy", self.on_destroy)
        self.connect("key-press-event", self.on_scroll_key)

    def update_clock(self):
        self.clock.set_text(time.strftime("%d/%m/%Y | %H:%M:%S"))
        return True

    def change_theme(self, combo):
        ctx = self.root_box.get_style_context()
        for name in ("light", "mono"):
            ctx.remove_class(name)
        active = combo.get_active()
        if active == 1:
            self.banner_title.set_markup('<span letter_spacing="2000">INVENTORYTAKER - Desktop</span>')
        else:
            self.banner_title.set_markup(banner_markup("INVENTORYTAKER - Desktop"))
        if active in (1, 2):
            ctx.add_class("light" if active == 1 else "mono")

    def filter_cards(self, entry):
        query = entry.get_text().casefold().strip()
        def labels(widget):
            if isinstance(widget, Gtk.Label):
                return widget.get_text()
            if isinstance(widget, Gtk.Container):
                return " ".join(labels(child) for child in widget.get_children())
            return ""
        for card in self.cards.values():
            card.set_visible(not query or query in labels(card).casefold())

    def jump_card(self, button, key):
        self.search.set_text("")
        self.filter_cards(self.search)
        def move():
            card = self.cards[key]
            pos = card.translate_coordinates(self.grid, 0, 0)
            if pos is not None:
                adj = self.inventory_scroll.get_vadjustment()
                adj.set_value(max(adj.get_lower(), min(pos[-1], adj.get_upper() - adj.get_page_size())))
            return False
        GLib.idle_add(move)

    def on_scroll_key(self, widget, event):
        # Intercepta as setas antes de o foco selecionar texto dos blocos.
        if event.keyval not in (Gdk.KEY_Up, Gdk.KEY_Down, Gdk.KEY_KP_Up, Gdk.KEY_KP_Down):
            return False
        adj = self.inventory_scroll.get_vadjustment()
        step = max(adj.get_step_increment(), 24.0)
        direction = -1 if event.keyval in (Gdk.KEY_Up, Gdk.KEY_KP_Up) else 1
        lower = adj.get_lower()
        upper = max(lower, adj.get_upper() - adj.get_page_size())
        adj.set_value(max(lower, min(upper, adj.get_value() + direction * step)))
        return True

    # -- utilidades -------------------------------------------------------
    def message(self, kind, text, secondary=None):
        dlg = Gtk.MessageDialog(transient_for=self, modal=True, message_type=kind,
                                buttons=Gtk.ButtonsType.OK, text=text)
        if secondary:
            dlg.format_secondary_text(secondary)
        dlg.run()
        dlg.destroy()

    def ask_password(self):
        """Retorna (senha, False), (None, True) para modo somente leitura, ou None."""
        dlg = Gtk.Dialog(title="Senha de administrador", transient_for=self, modal=True)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        dlg.add_button("Sem senha (somente leitura)", Gtk.ResponseType.REJECT)
        dlg.add_button("OK", Gtk.ResponseType.OK)
        dlg.set_default_response(Gtk.ResponseType.OK)
        area = dlg.get_content_area()
        area.set_spacing(8)
        area.set_border_width(14)
        user = os.environ.get("USER") or os.environ.get("LOGNAME") or "usuário"
        area.pack_start(_label("Informe a senha de administrador (sudo) de %s.\n"
                               "Ela é usada somente nesta execução e não é gravada." % user,
                               [], wrap=True), False, False, 0)
        entry = Gtk.Entry()
        entry.set_visibility(False)
        entry.set_activates_default(True)
        area.pack_start(entry, False, False, 0)
        err = _label("", ["bad"])
        area.pack_start(err, False, False, 0)
        dlg.show_all()
        result = None
        attempts = 0
        while attempts < 3:
            entry.grab_focus()
            resp = dlg.run()
            if resp == Gtk.ResponseType.OK:
                pw = entry.get_text()
                if pw and sudo_check(pw):
                    result = (pw, False)
                    break
                attempts += 1
                entry.set_text("")
                err.set_text("Senha incorreta (%d/3). Tente novamente." % attempts)
                continue
            if resp == Gtk.ResponseType.REJECT:
                result = (None, True)
            break
        dlg.destroy()
        if result is None and attempts >= 3:
            self.message(Gtk.MessageType.ERROR, "Senha incorreta",
                         "Três tentativas sem sucesso. Nada foi executado.")
        return result

    # -- ações ------------------------------------------------------------
    def on_gerar(self, _btn):
        if self.running:
            return
        if os.geteuid() == 0:
            self.message(Gtk.MessageType.ERROR, "Execute como usuário normal",
                         "O InventoryTaker não deve ser aberto como root. Use sua conta de usuário.")
            return
        if not os.path.isfile(BACKEND):
            self.message(Gtk.MessageType.ERROR, "Script não encontrado", BACKEND)
            return
        password, readonly = None, False
        if shutil.which("sudo"):
            if not sudo_nopasswd():
                choice = self.ask_password()
                if choice is None:
                    return
                password, readonly = choice
        else:
            readonly = True
        self.reset_view()
        if readonly:
            self.status.set_text("Modo somente leitura: dados que exigem administrador podem aparecer como N/A.")
        self.running = True
        self.btn_gerar.set_sensitive(False)
        self.btn_cancel.show()
        self.runner = InventoryRunner(
            BACKEND, password, readonly,
            lambda pct: GLib.idle_add(self.ui_progress, pct),
            lambda res: GLib.idle_add(self.ui_done, res))
        password = None
        self.runner.start()

    def on_cancel(self, _btn):
        if self.runner is not None:
            self.runner.cancel()

    def reset_view(self):
        for card in self.cards.values():
            card.set_empty()
        for key, btn in self.menu_buttons.items():
            btn.set_sensitive(key == "exit")
        self.files = {}
        self.progress.set_fraction(0.0)
        self.progress.set_text("Preparando o ambiente...")
        self.info.set_text("Coletando informações do sistema. Aguarde...")
        self.status.set_text("")

    def ui_progress(self, pct):
        self.progress.set_fraction(min(max(pct, 0), 100) / 100.0)
        self.progress.set_text("Preparando o ambiente e coletando informações: %d%%" % pct)
        return False

    def ui_done(self, result):
        self.running = False
        self.runner = None
        self.btn_gerar.set_sensitive(True)
        self.btn_cancel.hide()
        if result.get("cancelled"):
            self.progress.set_fraction(0.0)
            self.progress.set_text("Cancelado")
            self.info.set_text("Coleta cancelada. Clique em GERAR RELATÓRIO para tentar novamente.")
            return False
        if result.get("error"):
            self.progress.set_fraction(0.0)
            self.progress.set_text("Falha")
            self.info.set_text("Não foi possível gerar o relatório.")
            self.message(Gtk.MessageType.ERROR, result["error"], result.get("tail") or None)
            return False
        files = result["files"]
        try:
            data = load_report(files["json"])
        except Exception as exc:
            self.progress.set_text("Falha")
            self.message(Gtk.MessageType.ERROR, "Não foi possível ler o JSON do relatório",
                         "%s\n%s" % (files.get("json", ""), exc))
            return False
        for key, _title in BLOCKS:
            try:
                self.cards[key].fill(build_rows(key, data))
            except Exception as exc:
                self.cards[key].fill([("text", "Erro ao montar bloco: %s" % exc, "", "")])
        memory = data.get("05 MEMORIA RAM + SWAP", {})
        for name in ("RAM", "Swap"):
            try:
                def number(value):
                    return float(str(value).split()[0].replace(",", "."))
                total = number(memory[name + " Total"])
                used = number(memory[name + " Em uso"])
                if total > 0:
                    self.cards["05 MEMORIA RAM + SWAP"].metric(name, 100 * used / total)
            except (KeyError, ValueError, IndexError, TypeError):
                pass
        self.filter_cards(self.search)
        head = data.get("CABECALHO", {})
        self.info.set_text("Host: %s  |  Atualizado em: %s" % (
            head.get("Host", "N/A"), head.get("Atualizado em", "N/A")))
        self.progress.set_fraction(1.0)
        self.progress.set_text("Concluído: 100%")
        self.files = files
        for key, btn in self.menu_buttons.items():
            if key in ("doc", "exit"):
                btn.set_sensitive(True)
            elif key in files:
                btn.set_sensitive(True)
        self.status.set_text(data.get("RODAPE", {}).get("Status", "Dashboard carregado com sucesso."))
        return False

    def on_menu(self, _btn, key):
        if key == "exit":
            self.destroy()
            return
        if key == "doc":
            msg = open_target(DOC_URL, "doc")
        else:
            msg = open_target(self.files.get(key, ""), key)
        self.status.set_text(msg)

    def on_destroy(self, _widget):
        GLib.source_remove(self.clock_source)
        if self.runner is not None:
            self.runner.cancel()
        Gtk.main_quit()


def main():
    GLib.set_prgname("inventorytaker")
    GLib.set_application_name("INVENTORYTAKER - Desktop")
    settings = Gtk.Settings.get_default()
    if settings is not None:
        settings.set_property("gtk-application-prefer-dark-theme", True)
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win = MainWindow()
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
__INVENTORYTAKER_GUI_EOF__
}

write_icon() {
  cat > "$1" <<'__INVENTORYTAKER_ICON_EOF__'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ff9900"/>
      <stop offset="0.5" stop-color="#7c3aed"/>
      <stop offset="1" stop-color="#2563eb"/>
    </linearGradient>
  </defs>
  <rect x="8" y="8" width="240" height="240" rx="48" fill="url(#g)"/>
  <rect x="48" y="54" width="104" height="22" rx="6" fill="#ffffff" opacity="0.95"/>
  <rect x="48" y="92" width="136" height="22" rx="6" fill="#ffffff" opacity="0.85"/>
  <rect x="48" y="130" width="90" height="22" rx="6" fill="#ffffff" opacity="0.75"/>
  <circle cx="162" cy="162" r="34" fill="none" stroke="#facc15" stroke-width="14"/>
  <line x1="187" y1="187" x2="220" y2="220" stroke="#facc15" stroke-width="16" stroke-linecap="round"/>
</svg>
__INVENTORYTAKER_ICON_EOF__
}

# ------------------------------------------------------------------ desktop
write_desktop() {
  local _t="$1"
  {
    printf '[Desktop Entry]\n'
    printf 'Version=1.0\n'
    printf 'Type=Application\n'
    printf 'Name=INVENTORYTAKER - Desktop\n'
    printf 'GenericName=Inventário do sistema\n'
    printf 'Comment=Inventário técnico e diagnóstico do sistema Linux\n'
    printf 'Exec="%s" "%s"\n' "$PYBIN" "$GUI_F"
    printf 'Icon=%s\n' "$ICON_F"
    printf 'Terminal=false\n'
    printf 'Categories=System;Monitor;GTK;\n'
    printf 'StartupNotify=true\n'
    printf 'StartupWMClass=inventorytaker\n'
  } > "$_t"
  chmod 755 "$_t"
}

trust_desktop() {
  local _f="$1" _sum
  if command -v gio >/dev/null 2>&1; then
    gio set "$_f" metadata::trusted true >/dev/null 2>&1
    if command -v sha256sum >/dev/null 2>&1; then
      _sum=$(sha256sum "$_f" 2>/dev/null | cut -d' ' -f1)
      [ -z "$_sum" ] || gio set -t string "$_f" metadata::xfce-exe-checksum "$_sum" >/dev/null 2>&1
    fi
  fi
  return 0
}

# ------------------------------------------------------------------ resumo
summary() {
  panel_title "RESUMO"
  panel_row "Sistema" "$DISTRO_NAME"
  panel_row "Kernel" "$KERNEL"
  panel_row "Gerenciador de pacotes" "${PKG_MGR:-nao detectado}"
  panel_row "Dependencias (GTK 3)" "$DEPS_STATE"
  panel_row "Python" "${PYBIN:-N/A}"
  panel_row "Aplicativo" "$APP_DIR"
  panel_row "Icone na Area de trabalho" "$DESK_F"
  panel_row "Atalho no menu" "$MENU_F"
  panel_row "Relatorios em" "$REPORT_DIR"
  panel_row "Resultado" "$RESULT"
  panel_rule
}

# ------------------------------------------------------------------ instalar
do_install() {
  local _bad=""
  RESULT="FALHA"
  detect_env
  say ""
  say "[1/4] Verificando dependencias..."
  if [ "$NO_DEPS" = 1 ]; then
    if ! find_python; then DEPS_STATE="FALHA (offline)"; fail "GTK 3/Python indisponivel; instalacao bloqueada."; summary; return 1; fi
    DEPS_STATE="validado offline"
  elif ! install_deps; then
    RESULT="FALHA (dependencias)"; summary; return 1
  fi
  if ! "$PYBIN" -Es -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk; raise SystemExit(0 if Gtk.init_check()[0] else 1)' >/dev/null 2>&1; then
    fail "Sessao grafica GTK indisponivel; nenhuma implantacao realizada."
    RESULT="FALHA (sessao grafica)"; summary; return 1
  fi
  case "$APP_DIR$PYBIN" in
    *\"*|*\`*|*\$*|*\\*) fail "Caminho com caracteres nao suportados: $APP_DIR $PYBIN"; RESULT="FALHA (caminho)"; summary; return 1 ;;
  esac

  say ""
  say "[2/4] Preparando e verificando os arquivos..."
  STAGE=$(mktemp -d "${TMPDIR:-/tmp}/inventorytaker.XXXXXXXX") || { fail "Nao foi possivel criar pasta temporaria."; summary; return 1; }
  write_backend "$STAGE/LINUX_InventoryTaker.sh" || _bad="backend"
  write_gui "$STAGE/inventorytaker_gui.py" || _bad="$_bad gui"
  write_icon "$STAGE/inventorytaker.svg" || _bad="$_bad icone"
  bash -n "$STAGE/LINUX_InventoryTaker.sh" 2>/dev/null || _bad="$_bad sintaxe-bash"
  "$PYBIN" -c 'import ast, sys
ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$STAGE/inventorytaker_gui.py" 2>/dev/null || _bad="$_bad sintaxe-python"
  grep -q '</svg>' "$STAGE/inventorytaker.svg" 2>/dev/null || _bad="$_bad svg"
  if [ -n "$_bad" ]; then
    fail "Verificacao falhou:$_bad. Nada foi alterado no sistema."
    RESULT="FALHA (verificacao)"; summary; return 1
  fi
  ok "Script original, interface e icone verificados."

  say ""
  say "[3/4] Instalando arquivos..."
  local _target
  for _target in "$APP_DIR" "$APPS_DIR" "$DESK_DIR" "$BACKEND_F" "$GUI_F" "$ICON_F" "$MENU_F" "$DESK_F"; do
    if [ -L "$_target" ]; then fail "Link simbolico recusado: $_target"; RESULT="FALHA (seguranca)"; summary; return 1; fi
  done
  mkdir -p "$APP_DIR" "$APPS_DIR" "$DESK_DIR" || { fail "Nao foi possivel criar as pastas."; RESULT="FALHA (pastas)"; summary; return 1; }
  cp "$STAGE/LINUX_InventoryTaker.sh" "$BACKEND_F" && chmod 700 "$BACKEND_F" || _bad="backend"
  cp "$STAGE/inventorytaker_gui.py" "$GUI_F" && chmod 755 "$GUI_F" || _bad="$_bad gui"
  cp "$STAGE/inventorytaker.svg" "$ICON_F" && chmod 644 "$ICON_F" || _bad="$_bad icone"
  if [ -n "$_bad" ]; then
    fail "Falha ao copiar:$_bad"; RESULT="FALHA (copia)"; summary; return 1
  fi
  ok "Arquivos instalados em $APP_DIR"

  say ""
  say "[4/4] Criando icone na Area de trabalho e atalho no menu..."
  write_desktop "$MENU_F" || _bad="menu"
  write_desktop "$DESK_F" || _bad="$_bad desktop"
  if [ -n "$_bad" ]; then
    fail "Falha ao criar atalhos:$_bad"; RESULT="FALHA (atalhos)"; summary; return 1
  fi
  trust_desktop "$DESK_F"
  trust_desktop "$MENU_F"
  if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$APPS_DIR" >/dev/null 2>&1; fi
  ok "Icone criado em: $DESK_F"
  RESULT="INSTALADO COM SUCESSO"
  summary
  say "Abrindo INVENTORYTAKER - Desktop..."
  if command -v nohup >/dev/null 2>&1; then
    nohup "$PYBIN" "$GUI_F" </dev/null >/dev/null 2>&1 &
  else
    "$PYBIN" "$GUI_F" </dev/null >/dev/null 2>&1 &
    disown "$!" 2>/dev/null || true
  fi
  panel_rule
  return 0
}

# --------------------------------------------------------------- desinstalar
do_uninstall() {
  local _f _removed=""
  RESULT="FALHA"
  detect_env
  say ""
  say "Desinstalando (rollback)..."
  for _f in "$DESK_F" "$MENU_F" "$BACKEND_F" "$GUI_F" "$ICON_F"; do
    if [ -e "$_f" ] || [ -L "$_f" ]; then
      if rm -f "$_f"; then _removed="$_removed $(basename "$_f")"; else fail "Nao foi possivel remover $_f"; fi
    fi
  done
  rmdir "$APP_DIR" 2>/dev/null
  if command -v update-desktop-database >/dev/null 2>&1 && [ -d "$APPS_DIR" ]; then update-desktop-database "$APPS_DIR" >/dev/null 2>&1; fi
  DEPS_STATE="mantidas (GTK 3 nao e removido)"
  PYBIN="N/A"
  if [ -e "$DESK_F" ] || [ -e "$BACKEND_F" ] || [ -e "$GUI_F" ]; then
    RESULT="FALHA (restaram arquivos)"
  elif [ -n "$_removed" ]; then
    RESULT="DESINSTALADO:$_removed"
  else
    RESULT="NADA A REMOVER (nao estava instalado)"
  fi
  summary
  say "Os relatorios em $REPORT_DIR e os pacotes do sistema foram preservados."
  panel_rule
  return 0
}

# --------------------------------------------------------------------- menu
pause_menu() {
  printf '\nPressione ENTER para voltar ao menu...'
  read -r _dummy || true
}

main_menu() {
  local _op
  while true; do
    banner
    panel_title "MENU PRINCIPAL"
    panel_row '1' 'INSTALAR / ATUALIZAR'
    panel_row '2' 'DESINSTALAR (ROLLBACK)'
    panel_row '0' 'SAIR'
    panel_rule
    printf '\n%sOpção:%s ' "$C_Y" "$C_0"
    if ! read -r _op; then printf '\n'; panel_rule; break; fi
    printf '\n'
    panel_rule
    case "$_op" in
      1) do_install; pause_menu ;;
      2) do_uninstall; pause_menu ;;
      0) break ;;
      "") printf 'ENTER nao sai. Digite 0 para sair.\n' ;;
      *) printf 'Opcao invalida. Digite 0 para sair.\n' ;;
    esac
  done
  printf '\n'
}

case "$ACTION" in
  install) banner; do_install; exit $? ;;
  uninstall) banner; do_uninstall; exit $? ;;
  *) main_menu ;;
esac
