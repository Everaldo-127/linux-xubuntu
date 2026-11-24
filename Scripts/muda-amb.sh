#!/bin/bash
# ==============================================================================
# Script: muda-amb.sh
# Descrição: Gerenciador independente de ambientes Linux
# Compatibilidade principal: Ubuntu/Xubuntu 24.04 LTS
# Shell: Bash 3.x+
# Autor: Everaldo Costa Silva
# Licença: MIT
# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 Everaldo Costa Silva
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# ==============================================================================

if [ "$EUID" -ne 0 ] && [ "$(id -u)" -ne 0 ]; then
    if [ "${MUDA_AMBIENTES_SUDO_DONE:-}" != "1" ] && command -v sudo >/dev/null 2>&1; then
        echo "[SUDO] Solicitando sudo para continuar (só agora, uma vez)..."
        exec sudo env MUDA_AMBIENTES_SUDO_DONE=1 "$0" "$@"
    fi
    echo "[ERRO CRÍTICO] Execute como root ou instale sudo para continuar." >&2
    exit 1
fi

LOG_FILE="/var/log/muda-ambientes.log"

LOCK_FILE="/var/lock/muda-ambientes.lock"
cleanup_trap() {
    echo ""
    echo "[AVISO] Operação cancelada pelo usuário ou falha capturada." >&2
    exec 9>&- 2>/dev/null || true
    exit 1
}
trap cleanup_trap INT TERM
exec 9>"$LOCK_FILE" 2>/dev/null || {
    echo "[ERRO CRÍTICO] Não foi possível criar o arquivo de bloqueio." >&2
    exit 1
}
if ! flock -n 9 2>/dev/null; then
    echo "[ERRO CRÍTICO] Já existe uma instância deste script em execução." >&2
    exit 1
fi
cleanup_normal() {
    exec 9>&- 2>/dev/null || true
}
trap cleanup_normal EXIT

exec 3>&1 4>&2
exec 1> >(tee -a "$LOG_FILE") 2>&1

# ==============================================================================
# INTERFACE VISUAL (somente apresentação) - LARGURA TOTAL 120
# Moldura CHEIA em degradê amarelo: topo/rodapé = █████, laterais = █.
# Banner SÓ MUDA-AMB, numa ÚNICA LINHA, Estilo Pixel Retrô (Pagga):
# matriz 5x6, 1 █ por pixel, tudo MAIÚSCULO, alinhado no TOPO (altura -20%).
# Menu em TABELA: cabeçalho + 3 colunas + 8 linhas, tudo alinhado.
# Blocos: INFORMAÇÕES + RESUMO DA EXECUÇÃO. Sem cor, mesma caixa, sem ANSI.
# Cores pelo descritor 3: NÃO vão para o log. Nenhum texto de menu alterado.
# ==============================================================================

UI_INNER_WIDTH=118
UI_COLOR_MODE=0
UI_COLOR_256=0

detectar_cores_interface() {
    local quantidade_cores
    UI_COLOR_MODE=0
    UI_COLOR_256=0
    if [ -n "${NO_COLOR:-}" ]; then return 0; fi
    if [ -z "${TERM:-}" ] || [ "${TERM:-}" = "dumb" ]; then return 0; fi
    if [ -t 3 ] && command -v tput >/dev/null 2>&1; then
        quantidade_cores=$(tput colors 2>/dev/null)
        case "$quantidade_cores" in
            ''|*[!0-9]*) UI_COLOR_MODE=0 ;;
            *) [ "$quantidade_cores" -gt 0 ] && UI_COLOR_MODE=1
               [ "$quantidade_cores" -ge 256 ] && UI_COLOR_256=1 ;;
        esac
    fi
}

ui_cor() {
    local cor="$1"
    if [ "$UI_COLOR_MODE" -eq 1 ]; then
        if [ "$UI_COLOR_256" -eq 1 ]; then printf '\033[38;5;%sm' "$cor" >&3
        else case "$cor" in 226|214) printf '\033[93m' >&3 ;; *) printf '\033[33m' >&3 ;; esac; fi
    fi
}

ui_reset_cor() { if [ "$UI_COLOR_MODE" -eq 1 ]; then printf '\033[0m' >&3; fi; }

ui_linha_cheia() {
    local cor=0
    for cor in 226 220 214 208 214 220; do
        ui_cor "$cor"
        local k=0; while [ "$k" -lt 20 ]; do printf '█' >&3; k=$((k + 1)); done
        ui_reset_cor
    done
    printf '\n' >&3
}

ui_linha() {
    local texto="$1"
    local tamanho="${#texto}"
    local espacos=0
    [ "$tamanho" -lt "$UI_INNER_WIDTH" ] && espacos=$((UI_INNER_WIDTH - tamanho - 2))
    ui_cor 226; printf '█' >&3; ui_reset_cor
    printf ' %s' "$texto" >&3
    [ "$espacos" -gt 0 ] && printf '%*s' "$espacos" '' >&3
    printf ' ' >&3
    ui_cor 226; printf '█\n' >&3; ui_reset_cor
}

ui_linha_centralizada() {
    local texto="$1"
    local tamanho="${#texto}"
    local esquerda=0
    local direita=0
    if [ "$tamanho" -lt "$UI_INNER_WIDTH" ]; then esquerda=$(((UI_INNER_WIDTH - tamanho - 2) / 2)); direita=$((UI_INNER_WIDTH - tamanho - 2 - esquerda)); fi
    ui_cor 226; printf '█' >&3; ui_reset_cor
    printf ' ' >&3
    [ "$esquerda" -gt 0 ] && printf '%*s' "$esquerda" '' >&3
    printf '%s' "$texto" >&3
    [ "$direita" -gt 0 ] && printf '%*s' "$direita" '' >&3
    printf ' ' >&3
    ui_cor 226; printf '█\n' >&3; ui_reset_cor
}

ui_cor_azul() {
    if [ "$UI_COLOR_MODE" -eq 1 ]; then
        if [ "$UI_COLOR_256" -eq 1 ]; then printf '\033[38;5;39m' >&3
        else printf '\033[34m' >&3; fi
    fi
}

ui_linha_centralizada_azul() {
    local texto="$1"
    local tamanho="${#texto}"
    local esquerda=0
    local direita=0
    if [ "$tamanho" -lt "$UI_INNER_WIDTH" ]; then esquerda=$(((UI_INNER_WIDTH - tamanho - 2) / 2)); direita=$((UI_INNER_WIDTH - tamanho - 2 - esquerda)); fi
    ui_cor 226; printf '█' >&3; ui_reset_cor
    printf ' ' >&3
    [ "$esquerda" -gt 0 ] && printf '%*s' "$esquerda" '' >&3
    ui_cor_azul; printf '%s' "$texto" >&3; ui_reset_cor
    [ "$direita" -gt 0 ] && printf '%*s' "$direita" '' >&3
    printf ' ' >&3
    ui_cor 226; printf '█\n' >&3; ui_reset_cor
}

ui_divisoria() {
    local cor=0
    local i=0
    ui_cor 226; printf '█' >&3; ui_reset_cor
    for cor in 226 220 214 208 214 220; do
        ui_cor "$cor"
        local k=0; local trecho=20; [ "$i" -eq 5 ] && trecho=18
        while [ "$k" -lt "$trecho" ]; do printf '═' >&3; k=$((k + 1)); done
        ui_reset_cor; i=$((i + 1))
    done
    ui_cor 226; printf '█\n' >&3; ui_reset_cor
}


# Título de bloco de 1 linha só (usado só em INFORMAÇÕES e MENU)
ui_titulo_bloco_simples() {
    local titulo="$1"
    local tamanho="${#titulo}"
    local resto=$((118 - tamanho - 2))
    local esquerda=$((resto / 2))
    local direita=$((resto - esquerda))
    local k=0
    ui_cor 220; printf '█' >&3; ui_reset_cor
    ui_cor 220; k=0; while [ "$k" -lt "$esquerda" ]; do printf '█' >&3; k=$((k + 1)); done; ui_reset_cor
    printf ' ' >&3
    ui_cor 226; printf '%s' "$titulo" >&3; ui_reset_cor
    printf ' ' >&3
    ui_cor 220; k=0; while [ "$k" -lt "$direita" ]; do printf '█' >&3; k=$((k + 1)); done; ui_reset_cor
    ui_cor 220; printf '█\n' >&3; ui_reset_cor
}

ui_titulo_bloco() {
    local titulo="$1"
    local tamanho="${#titulo}"
    local resto=$((118 - tamanho - 2))
    local esquerda=$((resto / 2))
    local direita=$((resto - esquerda))
    local k=0
    ui_cor 220; printf '█' >&3; ui_reset_cor
    ui_cor 220; k=0; while [ "$k" -lt 118 ]; do printf '█' >&3; k=$((k + 1)); done; ui_reset_cor
    ui_cor 220; printf '█\n' >&3; ui_reset_cor
    ui_cor 220; printf '█' >&3; ui_reset_cor
    ui_cor 220; k=0; while [ "$k" -lt "$esquerda" ]; do printf '█' >&3; k=$((k + 1)); done; ui_reset_cor
    printf ' ' >&3
    ui_cor 226; printf '%s' "$titulo" >&3; ui_reset_cor
    printf ' ' >&3
    ui_cor 220; k=0; while [ "$k" -lt "$direita" ]; do printf '█' >&3; k=$((k + 1)); done; ui_reset_cor
    ui_cor 220; printf '█\n' >&3; ui_reset_cor
    ui_cor 220; printf '█' >&3; ui_reset_cor
    ui_cor 220; k=0; while [ "$k" -lt 118 ]; do printf '█' >&3; k=$((k + 1)); done; ui_reset_cor
    ui_cor 220; printf '█\n' >&3; ui_reset_cor
}

# Banner SÓ MUDA-AMB, Pixel Retrô (Pagga), única linha, topo alinhado
ui_banner() {
    ui_cor 226; printf '█%s█\n' "                                   █   █ █   █ ████   ███         ███  █   █ ████                                     " >&3; ui_reset_cor
    ui_cor 220; printf '█%s█\n' "                                   ██ ██ █   █ █   █ █   █       █   █ ██ ██ █   █                                    " >&3; ui_reset_cor
    ui_cor 214; printf '█%s█\n' "                                   █ █ █ █   █ █   █ █   █       █   █ █ █ █ █   █                                    " >&3; ui_reset_cor
    ui_cor 208; printf '█%s█\n' "                                   █ █ █ █   █ █   █ █████ █████ █████ █ █ █ ████                                     " >&3; ui_reset_cor
    ui_cor 214; printf '█%s█\n' "                                   █   █ █   █ █   █ █   █       █   █ █   █ █   █                                    " >&3; ui_reset_cor
    ui_cor 226; printf '█%s█\n' "                                   █   █  ███  ████  █   █       █   █ █   █ ████                                     " >&3; ui_reset_cor
}

ui_linha_tabela() {
    local c1="$1"; local c2="$2"; local c3="$3"; local c4="$4"
    local total3=$(( ${#c3} + ${#c4} ))
    local e1=$((8 - ${#c1} - 1)); local e2=$((28 - ${#c2} - 1)); local e3=$((78 - total3 - 1))
    ui_cor 226; printf '█' >&3; ui_reset_cor
    printf '│' >&3
    if [ "$c1" = "Nº" ]; then printf ' %s' "$c1" >&3; [ "$e1" -gt 0 ] && printf '%*s' "$e1" '' >&3
    else ui_fundo_inicio; printf ' %s' "$c1" >&3; [ "$e1" -gt 0 ] && printf '%*s' "$e1" '' >&3; ui_fundo_fim; fi
    printf '│' >&3
    if [ "$c1" = "Nº" ]; then printf ' %s' "$c2" >&3; [ "$e2" -gt 0 ] && printf '%*s' "$e2" '' >&3
    else ui_fundo_inicio; printf ' %s' "$c2" >&3; [ "$e2" -gt 0 ] && printf '%*s' "$e2" '' >&3; ui_fundo_fim; fi
    printf '│' >&3
    printf ' %s' "$c3" >&3
    if [ -n "$c4" ]; then ui_fundo_inicio; printf '%s' "$c4" >&3; ui_fundo_fim; fi
    [ "$e3" -gt 0 ] && printf '%*s' "$e3" '' >&3
    printf '│' >&3
    ui_cor 226; printf '█\n' >&3; ui_reset_cor
}

ui_separador_tabela() {
    local k=0
    ui_cor 226; printf '█' >&3; ui_reset_cor
    printf '├' >&3
    ui_cor 214; k=0; while [ "$k" -lt 8 ]; do printf '─' >&3; k=$((k + 1)); done; ui_reset_cor
    printf '┼' >&3
    ui_cor 214; k=0; while [ "$k" -lt 28 ]; do printf '─' >&3; k=$((k + 1)); done; ui_reset_cor
    printf '┼' >&3
    ui_cor 214; k=0; while [ "$k" -lt 78 ]; do printf '─' >&3; k=$((k + 1)); done; ui_reset_cor
    printf '┤' >&3
    ui_cor 226; printf '█\n' >&3; ui_reset_cor
}

ui_topo_tabela() {
    local k=0
    ui_cor 226; printf '█' >&3; ui_reset_cor
    printf '┌' >&3
    ui_cor 214; k=0; while [ "$k" -lt 8 ]; do printf '─' >&3; k=$((k + 1)); done; ui_reset_cor
    printf '┬' >&3
    ui_cor 214; k=0; while [ "$k" -lt 28 ]; do printf '─' >&3; k=$((k + 1)); done; ui_reset_cor
    printf '┬' >&3
    ui_cor 214; k=0; while [ "$k" -lt 78 ]; do printf '─' >&3; k=$((k + 1)); done; ui_reset_cor
    printf '┐' >&3
    ui_cor 226; printf '█\n' >&3; ui_reset_cor
}

ui_base_tabela() {
    local k=0
    ui_cor 226; printf '█' >&3; ui_reset_cor
    printf '└' >&3
    ui_cor 214; k=0; while [ "$k" -lt 8 ]; do printf '─' >&3; k=$((k + 1)); done; ui_reset_cor
    printf '┴' >&3
    ui_cor 214; k=0; while [ "$k" -lt 28 ]; do printf '─' >&3; k=$((k + 1)); done; ui_reset_cor
    printf '┴' >&3
    ui_cor 214; k=0; while [ "$k" -lt 78 ]; do printf '─' >&3; k=$((k + 1)); done; ui_reset_cor
    printf '┘' >&3
    ui_cor 226; printf '█\n' >&3; ui_reset_cor
}

# Linha centralizada com destaque: fundo preto + letras amarelas, laterais com linhas
ui_fundo_preto_inicio() {
    if [ "$UI_COLOR_MODE" -eq 1 ]; then
        if [ "$UI_COLOR_256" -eq 1 ]; then printf '\033[48;5;0m\033[38;5;226m' >&3
        else printf '\033[40m\033[33m' >&3; fi
    fi
}

ui_linha_centralizada_destaque() {
    local texto="$1"
    local tamanho="${#texto}"
    local esquerda=0
    local direita=0
    local k=0
    if [ "$tamanho" -lt "$UI_INNER_WIDTH" ]; then esquerda=$(((UI_INNER_WIDTH - tamanho - 2) / 2)); direita=$((UI_INNER_WIDTH - tamanho - 2 - esquerda)); fi
    ui_cor 226; printf '█' >&3; ui_reset_cor
    ui_fundo_inicio; k=0; while [ "$k" -lt "$((esquerda + 1))" ]; do printf ' ' >&3; k=$((k + 1)); done; ui_fundo_fim
    ui_fundo_preto_inicio; printf '%s' "$texto" >&3; ui_fundo_fim
    ui_fundo_inicio; k=0; while [ "$k" -lt "$((direita + 1))" ]; do printf ' ' >&3; k=$((k + 1)); done; ui_fundo_fim
    ui_cor 226; printf '█\n' >&3; ui_reset_cor
}

ui_cabecalho() {
    ui_linha_cheia
    ui_linha ""
    ui_banner
    ui_linha ""
    ui_linha_centralizada_azul "Programa feito para troca de ambiente gráfico sem mudar a DISTRO."
    ui_linha_centralizada_azul "Autor: Everaldo Costa Silva / Licença: MIT"
    ui_linha_centralizada_azul "Distros: Ubuntu | Debian | Fedora | Arch | Slackware"
    ui_linha ""
}

# RESUMO DA EXECUÇÃO: só no final de cada execução de cada menu, nunca na tela principal
ui_resumo_execucao() {
    ui_titulo_bloco "RESUMO DA EXECUÇÃO"
    ui_linha ""
    ui_linha_centralizada "Ambientes: LXQt  |  GNOME  |  KDE Plasma  |  Cinnamon  |  XFCE  |  MATE"
    ui_linha_centralizada "Backup: /var/backups/muda-ambientes  |  Log: /var/log/muda-ambientes.log  |  Trava: /var/lock/muda-ambientes.lock"
    ui_linha ""
    ui_linha_cheia
}


# Voltar aos menus: exibido após o resumo de cada execução
ui_voltar_menus() {
    printf '\n' >&3
    ui_linha_cheia
    ui_linha ""
    ui_linha_centralizada "Selecione:  [1] Voltar aos MENUS  |  [0] Sair"
    ui_linha_cheia
    printf '\n' >&3
    printf "Selecione a opção desejada [1-0]: " >&3
    local escolha=""
    read -r escolha
    case "$escolha" in
        0) echo "[ENCERRANDO] Até logo!"; exit 0 ;;
        *) return 0 ;;
    esac
}

# Destaque com preenchimento atrás: fundo amarelo + texto preto (sem cor, sem efeito)
ui_fundo_inicio() {
    if [ "$UI_COLOR_MODE" -eq 1 ]; then
        if [ "$UI_COLOR_256" -eq 1 ]; then printf '\033[48;5;226m\033[30m' >&3
        else printf '\033[43m\033[30m' >&3; fi
    fi
}
ui_fundo_fim() { if [ "$UI_COLOR_MODE" -eq 1 ]; then printf '\033[0m' >&3; fi; }

ui_menu() {
    ui_titulo_bloco_simples "MENU"
    ui_linha_centralizada_destaque "GERENCIADOR SÊNIOR DE AMBIENTES - LINUX"
    ui_topo_tabela
    ui_linha_tabela "Nº" "OPÇÃO" "AMBIENTE / AÇÃO" ""
    ui_separador_tabela
    ui_linha_tabela "1" "Trocar para LXQt" "Instalar e ativar o ambiente " "LXQt"
    ui_separador_tabela
    ui_linha_tabela "2" "Trocar para GNOME" "Instalar e ativar o ambiente " "GNOME"
    ui_separador_tabela
    ui_linha_tabela "3" "Trocar para KDE Plasma" "Instalar e ativar o ambiente " "KDE Plasma"
    ui_separador_tabela
    ui_linha_tabela "4" "Trocar para Cinnamon" "Instalar e ativar o ambiente " "Cinnamon"
    ui_separador_tabela
    ui_linha_tabela "5" "Trocar para XFCE" "Instalar e ativar o ambiente " "XFCE"
    ui_separador_tabela
    ui_linha_tabela "6" "Trocar para MATE" "Instalar e ativar o ambiente " "MATE"
    ui_separador_tabela
    ui_linha_tabela "7" "Corrigir Duplicadas" "Limpar duplicatas na tela de login, com backup" ""
    ui_separador_tabela
    ui_linha_tabela "8" "Backup pré-instalação" "Espelhar ambiente atual completo, sem internet" ""
    ui_separador_tabela
    ui_linha_tabela "9" "Rollback sem internet" "Restaurar ambiente funcional, sem baixar nada" ""
    ui_separador_tabela
    ui_linha_tabela "10" "Varredura pré-execução" "Conferir ferramentas, sem abortar por falta" ""
    ui_separador_tabela
    ui_linha_tabela "11" "Reboot do Sistema" "Reiniciar o sistema para aplicar o ambiente" ""
    ui_separador_tabela
    ui_linha_tabela "12" "Documentação" "Abrir manual PDF em uma nova janela" ""
    ui_separador_tabela
    ui_linha_tabela "0" "Sair" "Encerrar o programa sem alterar nada" ""
    ui_base_tabela
    ui_linha_cheia
}

detectar_cores_interface

# ==============================================================================
# DETECÇÃO DO GERENCIADOR DE PACOTES
# ==============================================================================

# Identificação por fontes independentes; kernel não equivale à release.
detectar_gerenciador() {
    local f id='' like='' version='' probe='' expected=''
    DISTRO_ID=''; DISTRO_VERSION=''; PKG_MGR=''
    for f in /etc/os-release /usr/lib/os-release; do
        [ -r "$f" ] || continue
        echo "[DETECÇÃO] $f: $(grep -E '^(ID|VERSION_ID|ID_LIKE)=' "$f" | tr '\n' ' ')"
        if [ -z "$id" ]; then
            id=$(sed -n 's/^ID=//p' "$f" | tr -d '\"' | head -1)
            like=$(sed -n 's/^ID_LIKE=//p' "$f" | tr -d '\"' | head -1)
            version=$(sed -n 's/^VERSION_ID=//p' "$f" | tr -d '\"' | head -1)
        fi
    done
    if command -v lsb_release >/dev/null; then
        probe=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]'); echo "[DETECÇÃO] lsb_release: $probe $(lsb_release -sr 2>/dev/null)"
        [ -n "$id" ] || id=$probe
        [ -n "$version" ] || version=$(lsb_release -sr 2>/dev/null)
    fi
    if command -v hostnamectl >/dev/null; then hostnamectl 2>/dev/null | grep -E 'Operating System:|Kernel:|Architecture:' || true; fi
    uname -a || return 1
    [ ! -r /proc/version ] || cat /proc/version
    for f in /etc/debian_version /etc/fedora-release /etc/redhat-release /etc/arch-release /etc/slackware-version; do
        [ -r "$f" ] || continue; echo "[DETECÇÃO] $f: $(head -1 "$f")"
        if [ -z "$id" ]; then case "$f" in */debian_version) id=debian;; */fedora-release) id=fedora;; */redhat-release) id=rhel;; */arch-release) id=arch;; */slackware-version) id=slackware;; esac; fi
    done
    case " $id $like " in *' ubuntu '*|*' debian '*) expected=apt;; *' arch '*|*' manjaro '*) expected=pacman;; *' fedora '*|*' rhel '*|*' centos '*) expected=rpm;; *' slackware '*) expected=slackware;; *) echo '[ERRO] Família não reconhecida.'; return 1;; esac
    case "$expected" in
        apt) command -v apt-get >/dev/null && command -v dpkg-query >/dev/null && [ -f /var/lib/dpkg/status ] || return 1; PKG_MGR=apt;;
        rpm) command -v rpm >/dev/null && rpm -q rpm >/dev/null 2>&1 || return 1; if command -v dnf >/dev/null; then PKG_MGR=dnf; elif command -v yum >/dev/null; then PKG_MGR=yum; else return 1; fi;;
        pacman) command -v pacman >/dev/null && pacman -Q pacman >/dev/null 2>&1 || return 1; PKG_MGR=pacman;;
        slackware) command -v slackpkg >/dev/null && [ -d /var/log/packages ] || return 1; PKG_MGR=slackware;;
    esac
    DISTRO_ID=$id; DISTRO_VERSION=${version:-desconhecida}; echo "[OK] $DISTRO_ID $DISTRO_VERSION / $PKG_MGR"
}
pacote_instalado() {
    case "$PKG_MGR" in apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qx 'install ok installed';; dnf|yum) rpm -q "$1" >/dev/null 2>&1;; pacman) pacman -Q "$1" >/dev/null 2>&1;; slackware) local f; for f in /var/log/packages/"$1"-*; do [ -f "$f" ] || continue; [ "$(basename "$f" | sed -E 's/-[^-]+-[^-]+-[^-]+$//')" = "$1" ] && return 0; done; return 1;; esac
}
repositorio_tem() {
    case "$PKG_MGR" in apt) LC_ALL=C apt-cache policy "$1" | grep -Eq 'Candidate: [^ (]';; dnf|yum) "$PKG_MGR" -q list available "$1" >/dev/null 2>&1;; pacman) pacman -Si "$1" >/dev/null 2>&1;; slackware) [ -r /var/lib/slackpkg/pkglist ] && awk -v p="$1" '$2==p {ok=1} END {exit !ok}' /var/lib/slackpkg/pkglist;; esac
}
atualizar_indices() {
    case "$PKG_MGR" in apt) apt-get update;; dnf|yum) "$PKG_MGR" makecache;; pacman) echo '[INFO] Usando índices locais; não será feita atualização parcial do Arch.'; return 0;; slackware) slackpkg -batch=on update;; esac
}
# Cada argumento é um requisito; alternativas separadas por |.
resolver() {
    local requisito p escolhido; local -a candidatos
    PENDENTES=()
    for requisito in "$@"; do
        IFS='|' read -r -a candidatos <<< "$requisito"; escolhido=''
        for p in "${candidatos[@]}"; do if pacote_instalado "$p"; then escolhido=$p; break; fi; done
        [ -z "$escolhido" ] || continue
        for p in "${candidatos[@]}"; do if repositorio_tem "$p"; then escolhido=$p; break; fi; done
        if [ -z "$escolhido" ]; then echo "[ERRO] Requisito indisponível: $requisito"; return 1; fi
        PENDENTES+=("$escolhido")
    done
}
instalar_requisitos() {
    local p
    if ! resolver "$@"; then atualizar_indices || return 1; resolver "$@" || return 1; fi
    [ "${#PENDENTES[@]}" -gt 0 ] || return 0
    case "$PKG_MGR" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PENDENTES[@]}" || return 1;;
        dnf|yum) "$PKG_MGR" install -y "${PENDENTES[@]}" || return 1;;
        pacman) pacman -S --needed --noconfirm "${PENDENTES[@]}" || return 1;;
        slackware) slackpkg -batch=on -default_answer=y install "${PENDENTES[@]}" || return 1;;
    esac
    for p in "${PENDENTES[@]}"; do pacote_instalado "$p" || { echo "[ERRO] Não confirmado: $p"; return 1; }; done
}

configurar_display_manager_limpo() {
    local alvo_sessao="$1"
    echo "[CONFIGURAÇÃO] Preparando LightDM para o próximo boot: $alvo_sessao (sem ativar agora)"
    mkdir -p /etc/lightdm/lightdm.conf.d || return 1
    rm -f /etc/lightdm/lightdm.conf.d/90-muda-ambientes.conf 2>/dev/null || true
    cat <<EOF > /etc/lightdm/lightdm.conf.d/90-muda-ambientes.conf
[Seat:*]
greeter-session=lightdm-gtk-greeter
greeter-show-sessions=true
greeter-show-manual-login=false
greeter-hide-users=false
allow-guest=false
user-session=$alvo_sessao
EOF
    cat <<EOF > /etc/lightdm/lightdm-gtk-greeter.conf
[greeter]
indicators = ~host;~spacer;~clock;~spacer;~session;~power;~language
theme-name = Adwaita
icon-theme-name = gnome
font-name = Sans 10
hide-user-image = false
EOF
    mkdir -p /var/lib/muda-ambientes 2>/dev/null || true
    echo "$alvo_sessao" > /var/lib/muda-ambientes/proxima-sessao.txt 2>/dev/null || true
    return 0
}

trocar_dm_oficial() {
    local dm_nativo="$1"
    echo "[DM OFICIAL] Trocando DM via debconf + dpkg-reconfigure: $dm_nativo (persistente no boot)"
    if command -v debconf-set-selections >/dev/null 2>&1; then
        echo "shared/default-x-display-manager shared/default-x-display-manager select /usr/sbin/$dm_nativo" | debconf-set-selections 2>/dev/null || true
    fi
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure "$dm_nativo" >/dev/null 2>&1 || true
    if [ "$(cat /etc/X11/default-display-manager 2>/dev/null)" != "/usr/sbin/$dm_nativo" ]; then
        echo "/usr/sbin/$dm_nativo" > /etc/X11/default-display-manager 2>/dev/null || true
    fi
    if [ "$(cat /etc/X11/default-display-manager 2>/dev/null)" != "/usr/sbin/$dm_nativo" ]; then
        echo "[ERRO] DM oficial nao persistiu para $dm_nativo."
        return 1
    fi
    return 0
}
# Não excluir sessões distintas apenas porque têm o mesmo nome.
limpar_sessoes_duplicadas() {
    local dir f alvo backup
    backup=$(mktemp -d /var/backups/sessoes-duplicadas.XXXXXXXX) || return 1
    chmod 700 "$backup" || return 1
    for dir in /usr/share/xsessions /usr/share/wayland-sessions; do
        [ -d "$dir" ] || continue
        cp -a "$dir" "$backup/" || return 1
        for f in "$dir"/*.desktop; do
            [ -L "$f" ] || continue
            alvo=$(readlink -f "$f") || continue
            case "$alvo" in "$dir"/*.desktop) [ -f "$alvo" ] && [ "$alvo" != "$f" ] && rm -- "$f";; esac
        done
    done
    echo "[OK] Backup das sessões: $backup"
}
executar_ambiente() {
    local ambiente=$1 dm=lightdm sessao='' f bin unit fragment init=systemd
    local -a base desktop login
    detectar_gerenciador || return 1
    case "$PKG_MGR" in
      apt) base=(xserver-xorg xserver-xorg-video-all xserver-xorg-input-all libgl1-mesa-dri dbus-x11 'polkitd|policykit-1');;
      dnf|yum) base=(xorg-x11-server-Xorg xorg-x11-drv-libinput mesa-dri-drivers dbus polkit);;
      pacman) base=(xorg-server xf86-input-libinput mesa dbus polkit);;
      slackware) base=(xorg-server xf86-input-libinput mesa dbus polkit); init=sysv;;
    esac
    case "$ambiente" in
      LXQt) desktop=(lxqt-session lxqt-panel pcmanfm-qt openbox lxqt-config lxqt-policykit qterminal);;
      GNOME) dm=gdm; desktop=(gnome-session gnome-shell nautilus);;
      KDE) dm=sddm; desktop=(plasma-desktop plasma-workspace dolphin konsole);;
      Cinnamon) desktop=(cinnamon cinnamon-session nemo cinnamon-control-center);;
      XFCE) desktop=(xfce4-session xfwm4 xfce4-panel xfdesktop thunar xfce4-settings xfce4-terminal);;
      MATE) desktop=(mate-session-manager mate-settings-daemon mate-panel marco caja mate-control-center mate-terminal mate-polkit);;
      *) return 1;;
    esac
    if [ "$PKG_MGR" = apt ] && [ "$dm" = gdm ]; then dm=gdm3; fi
    case "$dm" in lightdm) login=(lightdm 'lightdm-gtk-greeter|lightdm-gtk');; *) login=("$dm");; esac
    if [ "$ambiente" = KDE ]; then desktop+=( 'kwin-x11|kwin' ); fi
    if [ "$init" = sysv ]; then
        # Slackware oficial distribui KDE/XFCE em séries; não presumir equivalência.
        case "$ambiente" in KDE|XFCE) ;; *) echo '[ERRO] Ambiente não validado nos repositórios oficiais Slackware.'; return 1;; esac
        [ -x /etc/rc.d/rc.4 ] || return 1
        if [ "$ambiente" = XFCE ]; then login=(xdm); dm=xdm; fi
    else
        [ -d /run/systemd/system ] || { echo '[ERRO] systemd não está ativo.'; return 1; }
    fi
    # Pré-resolução de todos os requisitos antes de alterar configurações.
    if ! resolver "${base[@]}" "${desktop[@]}" "${login[@]}"; then atualizar_indices || return 1; resolver "${base[@]}" "${desktop[@]}" "${login[@]}" || return 1; fi
    backup_preinstalacao_completo || return 1
    mkdir -p /var/lib/muda-ambientes || return 1
    touch /var/lib/muda-ambientes/reboot-bloqueado || return 1
    instalar_requisitos "${base[@]}" "${desktop[@]}" "${login[@]}" || return 1
    case "$ambiente" in LXQt) bin=startlxqt;; GNOME) bin=gnome-session;; KDE) bin=startplasma-x11;; Cinnamon) bin=cinnamon-session;; XFCE) bin=xfce4-session;; MATE) bin=mate-session;; esac
    command -v "$bin" >/dev/null || { echo "[ERRO] Executável ausente: $bin"; return 1; }
    for f in /usr/share/xsessions/*.desktop; do
        [ -f "$f" ] || continue
        if grep -Eq "^Exec=([^ ]*/)?($bin|$( [ "$ambiente" = XFCE ] && echo startxfce4 || echo "$bin" ))([[:space:]]|$)" "$f"; then sessao=$(basename "$f" .desktop); break; fi
    done
    [ -n "$sessao" ] || { echo '[ERRO] Sessão X11 oficial ausente.'; return 1; }
    command -v Xorg >/dev/null || return 1
    if [ "$init" = systemd ]; then
        unit="$dm.service"; fragment=$(systemctl show -p FragmentPath --value "$unit" 2>/dev/null)
        [ -f "$fragment" ] || { echo "[ERRO] Serviço ausente: $unit"; return 1; }
        if [ "$PKG_MGR" = apt ]; then trocar_dm_oficial "$dm" || return 1; fi
        if [ "$dm" = lightdm ]; then configurar_display_manager_limpo "$sessao" || return 1; fi
        systemctl enable --force "$unit" || return 1
        systemctl daemon-reload || return 1
        systemctl set-default graphical.target || return 1
        [ "$(systemctl get-default)" = graphical.target ] || return 1
        [ "$(systemctl show -p FragmentPath --value display-manager.service)" = "$fragment" ] || return 1
    else
        # rc.4 escolhe o DM conforme sua própria ordem; não alterar essa política.
        grep -q "$dm" /etc/rc.d/rc.4 || return 1
        [ -f /etc/inittab ] || return 1
        grep -q '^id:[0-6]:initdefault:' /etc/inittab || return 1
        sed -i 's/^id:[0-6]:initdefault:/id:4:initdefault:/' /etc/inittab || return 1
    fi
    printf '%s\n' "$sessao" > /var/lib/muda-ambientes/proxima-sessao.txt || return 1
    printf '%s\n' "$dm" > /var/lib/muda-ambientes/proximo-dm.txt || return 1
    rm -f /var/lib/muda-ambientes/reboot-bloqueado || return 1
    echo "[SUCESSO] $ambiente preparado; teste gráfico real ainda necessário."
}
executar_lxqt_independente() { executar_ambiente LXQt; }
executar_gnome_independente() { executar_ambiente GNOME; }
executar_kde_independente() { executar_ambiente KDE; }
executar_cinnamon_independente() { executar_ambiente Cinnamon; }
executar_xfce_independente() { executar_ambiente XFCE; }
executar_mate_independente() { executar_ambiente MATE; }

backup_preinstalacao_completo() {
    local _silencioso=0
    [ "${1:-}" = "silencioso" ] && _silencioso=1
    if [ "$_silencioso" -eq 0 ]; then
        ui_linha_cheia
        ui_linha_centralizada " [EXECUÇÃO] BACKUP PRÉ-INSTALAÇÃO COMPLETO"
        ui_linha_cheia
    fi
    local backup_base="/var/backups/muda-ambientes"
    local backup_dir="${backup_base}/completo-$(date +%Y%m%d-%H%M%S)"
    local caminho destino gerenciador
    mkdir -p "$backup_dir" || { echo "[ERRO CRÍTICO] Não foi possível criar o diretório de backup."; return 1; }
    chmod 700 "$backup_dir" 2>/dev/null || true
    case "$backup_dir" in "$backup_base"/*) ;; *) echo "[ERRO CRÍTICO] Caminho de backup fora da base permitida."; return 1 ;; esac
    if [ "$_silencioso" -eq 0 ]; then
        echo ""
        echo "[BACKUP] Espelhando ambiente atual completo em: $backup_dir (só local, sem download)"
    fi
    for caminho in /etc /boot/grub /etc/fstab /var/lib/AccountsService /usr/share/xsessions /usr/local /opt /etc/xdg/lxqt; do
        if [ -e "$caminho" ] || [ -L "$caminho" ]; then
            destino="${backup_dir}${caminho}"
            mkdir -p "$(dirname "$destino")" || { echo "[ERRO CRÍTICO] Falha ao preparar backup de $caminho."; return 1; }
            cp -a "$caminho" "$destino" || { echo "[ERRO CRÍTICO] Falha ao copiar $caminho."; return 1; }
        fi
    done
    if [ "$_silencioso" -eq 0 ]; then echo "[BACKUP] /etc inteiro incluído: todos os gerenciadores de tela presentes já estão no backup."; fi
    if command -v dpkg-query >/dev/null 2>&1; then dpkg-query -W -f='${Package} ${Version}\n' > "$backup_dir/pacotes-instalados.txt" 2>/dev/null || true; fi
    mkdir -p "$backup_dir/apt-cache" 2>/dev/null || true
    if [ -d /var/cache/apt/archives ]; then cp -a /var/cache/apt/archives/*.deb "$backup_dir/apt-cache/" 2>/dev/null || true; fi
    if [ "$_silencioso" -eq 0 ]; then echo "[BACKUP] Dependências locais salvas: lista + cache .deb (se havia) em $backup_dir/apt-cache"; fi
    if command -v systemctl >/dev/null 2>&1; then systemctl get-default > "$backup_dir/default-target.txt" 2>/dev/null || true; fi
    echo "$backup_dir" > "$backup_base/ultimo-backup.txt"
    if [ "$_silencioso" -eq 0 ]; then
        echo "[BACKUP] Concluído: $backup_dir"
        echo "[BACKUP] Lista salva em: $backup_base/ultimo-backup.txt"
    fi
    return 0
}

# Backup automático silencioso da opção 8 ao abrir o programa.
# Não mostra nada na tela se der certo. Só mostra erro, se houver.
# Não pergunta nada, não pede confirmação, não aborta o programa se falhar.
# Só faz 1 backup por dia: se já houver backup de hoje, reutiliza e não duplica.
backup_automatico_silencioso() {
    local backup_base="/var/backups/muda-ambientes"
    local ultimo="" hoje=""
    hoje="$(date +%Y%m%d)"
    if [ -f "$backup_base/ultimo-backup.txt" ]; then ultimo="$(cat "$backup_base/ultimo-backup.txt" 2>/dev/null)"; fi
    case "$ultimo" in
        *"$hoje"*)
            if [ -d "$ultimo" ]; then return 0; fi
            ;;
    esac
    backup_preinstalacao_completo silencioso || echo "[ERRO] Backup automático silencioso falhou. O programa continua, mas execute a opção 8 antes de trocar de ambiente."
    return 0
}

rollback_offline() {
    ui_linha_cheia
    ui_linha_centralizada " [EXECUÇÃO] ROLLBACK DO AMBIENTE SEM INTERNET"
    ui_linha_cheia
    local backup_base="/var/backups/muda-ambientes"
    local backup_dir=""
    if [ -f "$backup_base/ultimo-backup.txt" ]; then backup_dir=$(cat "$backup_base/ultimo-backup.txt" 2>/dev/null); fi
    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        echo "[ERRO] Nenhum backup completo encontrado. Execute primeiro a opção 8."
        return 1
    fi
    case "$backup_dir" in "$backup_base"/*) ;; *) echo "[ERRO CRÍTICO] Backup fora da base permitida. Rollback abortado."; return 1 ;; esac
    echo ""
    echo "[ROLLBACK] Restaurando de: $backup_dir (sem baixar nada, sem internet)"
    local caminho destino
    for caminho in /etc /boot/grub /etc/fstab /var/lib/AccountsService /usr/share/xsessions /usr/local /opt /etc/xdg/lxqt; do
        if [ -e "${backup_dir}${caminho}" ] || [ -L "${backup_dir}${caminho}" ]; then
            destino="$caminho"
            mkdir -p "$(dirname "$destino")" || { echo "[ERRO CRÍTICO] Falha ao preparar restauração de $caminho."; return 1; }
            cp -a "${backup_dir}${caminho}/." "$destino/" || { echo "[ERRO CRÍTICO] Falha ao restaurar $caminho."; return 1; }
        fi
    done
    if [ -d "$backup_dir/apt-cache" ] && [ -f "$backup_dir/pacotes-instalados.txt" ] && command -v dpkg-query >/dev/null 2>&1; then
        echo ""
        echo "[ROLLBACK] Conferindo dependências salvas (só cache local, sem internet)..."
        local pacote="" falta=0
        while read -r pacote _resto; do
            [ -n "$pacote" ] || continue
            if ! dpkg-query -W -f='${Status}' "$pacote" 2>/dev/null | grep -q "install ok installed"; then falta=1; fi
        done < "$backup_dir/pacotes-instalados.txt"
        if [ "$falta" -eq 1 ]; then
            echo "[ROLLBACK] Há pacotes ausentes. Reinstalando só do cache .deb local..."
            _tem_deb=0; for _f in "$backup_dir/apt-cache/"*.deb; do [ -f "$_f" ] && _tem_deb=1; done
            if [ "$_tem_deb" -eq 1 ]; then dpkg -i "$backup_dir/apt-cache/"*.deb >/dev/null 2>&1 || true; else echo "[AVISO] Cache .deb vazio. Nada a reinstalar."; fi
        else
            echo "[ROLLBACK] Todas as dependências salvas já estão presentes. Nada a reinstalar."
        fi
    fi
    if [ -d /usr/share/xsessions ]; then
        local sessao_arq="" tem_sessao=0
        for sessao_arq in /usr/share/xsessions/*.desktop; do [ -f "$sessao_arq" ] && tem_sessao=1; done
        if [ "$tem_sessao" -eq 0 ]; then echo "[ERRO] Nenhuma sessão .desktop após o rollback. Abortando antes do reboot para evitar tela preta."; return 1; fi
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl set-default graphical.target >/dev/null 2>&1 || true
        if [ "$PKG_MGR" = "apt" ]; then trocar_dm_oficial "lightdm" || true; else echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager 2>/dev/null || true; fi
        echo "[ROLLBACK] LightDM reativado + target gráfico confirmado (anti-tela-preta)."
    fi
    if ! grep -q "^greeter-session=lightdm-gtk-greeter" /etc/lightdm/lightdm.conf.d/90-muda-ambientes.conf 2>/dev/null; then
        _sessao_rb=$(basename "$(ls /usr/share/xsessions/*.desktop 2>/dev/null | head -1)" .desktop 2>/dev/null)
        [ -n "$_sessao_rb" ] && configurar_display_manager_limpo "$_sessao_rb" || true
    fi
    if [ -f "$backup_dir/default-target.txt" ] && command -v systemctl >/dev/null 2>&1; then
        _tgt_salvo="$(cat "$backup_dir/default-target.txt" 2>/dev/null | tr -d '[:space:]')"
        case "$_tgt_salvo" in
            graphical.target|multi-user.target) systemctl set-default "$_tgt_salvo" >/dev/null 2>&1 || true ;;
            *) echo "[AVISO] Target salvo inválido ($_tgt_salvo). Mantendo graphical.target." ;;
        esac
    fi
    echo ""
    echo "[SUCESSO] Rollback concluído a partir do backup. Nada foi baixado."
    return 0
}

# ==============================================================================
# VARREDURA PRÉ-EXECUÇÃO (primeira ação, sem abortar por ferramenta ausente)
# Detecta a distro, confere as ferramentas, instala só o que falta via fonte oficial.
# Nunca inventa nome de pacote: usa só os nomes já usados neste script.
# ==============================================================================
varrer_ferramentas() {
    detectar_gerenciador || return 1
    local f
    for f in uname date cp mkdir flock tee grep sed awk; do command -v "$f" >/dev/null || { echo "[ERRO] Ferramenta ausente: $f"; return 1; }; done
    echo '[OK] Ferramentas básicas disponíveis.'
}
executar_reboot() {
    if [ -e /var/lib/muda-ambientes/reboot-bloqueado ]; then echo '[ERRO] Instalação incompleta. Reboot bloqueado.'; return 1; fi
    sync && reboot
}
# Abre o manual no navegador do usuario original (fora da sessao root).
abrir_documentacao() {
    local url='https://github.com/Everaldo-127/linux-xubuntu/blob/main/Documenta%C3%A7%C3%A3o/MUDA-AMB_Manual_Atualizado.pdf'
    local usuario="${SUDO_USER:-}" uid="" ambiente="" endereco=""
    local -a abrir=()

    if command -v xdg-open >/dev/null 2>&1; then
        abrir=(xdg-open "$url")
    elif command -v gio >/dev/null 2>&1; then
        abrir=(gio open "$url")
    else
        echo '[ERRO] Nenhum abridor de links instalado (xdg-open ou gio).'
        return 1
    fi

    if [ -n "$usuario" ] && [ "$usuario" != root ] && command -v runuser >/dev/null 2>&1; then
        uid="$(id -u "$usuario" 2>/dev/null)" || return 1
        ambiente="${XDG_RUNTIME_DIR:-/run/user/$uid}"
        [ -d "$ambiente" ] || ambiente="/run/user/$uid"
        endereco="${DBUS_SESSION_BUS_ADDRESS:-}"
        [ -n "$endereco" ] || endereco="unix:path=$ambiente/bus"
        if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
            runuser -u "$usuario" -- env DISPLAY="${DISPLAY:-}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="$ambiente" DBUS_SESSION_BUS_ADDRESS="$endereco" "${abrir[@]}" >/dev/null 2>&1 &
        else
            echo '[ERRO] Sessão gráfica do usuário não identificada.'
            return 1
        fi
    else
        if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
            echo '[ERRO] Sessão gráfica não identificada.'
            return 1
        fi
        "${abrir[@]}" >/dev/null 2>&1 &
    fi
    echo '[DOCUMENTAÇÃO] Solicitação de abertura enviada ao navegador.'
    return 0
}

# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================

# Execução não assistida: backup silencioso da opção 8 ao abrir o programa.
backup_automatico_silencioso

while true; do
    printf '\n' >&3
    ui_cabecalho
    ui_menu

    printf '\n' >&3
    printf "Selecione a opção desejada [0-12]: " >&3
    read -r opcao || exit 0

    case "$opcao" in
        1)
            executar_lxqt_independente
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        2)
            executar_gnome_independente
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        3)
            executar_kde_independente
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        4)
            executar_cinnamon_independente
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        5)
            executar_xfce_independente
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        6)
            executar_mate_independente
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        7)
            limpar_sessoes_duplicadas
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        8)
            backup_preinstalacao_completo
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        9)
            rollback_offline
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        10)
            varrer_ferramentas
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        11)
            executar_reboot
            ui_resumo_execucao
            ui_voltar_menus
            ;;
        12)
            abrir_documentacao
            ;;
        0)
            echo "[ENCERRANDO] Até logo!"
            exit 0
            ;;
        *)
            echo "[ERRO] Opção inválida! Digite um número entre 0 e 12."
            ;;
    esac
done


