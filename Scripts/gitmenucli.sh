#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Everaldo Costa Silva
set -o pipefail
umask 077
PROGRAM_NAME="GitHub Manager"
API_URL="https://api.github.com"
API_VERSION="2022-11-28"
GITHUB_USER=""
GITHUB_TOKEN=""
SSH_KEY=""
DESKTOP_DIR="${HOME:-/tmp}/Desktop"
[ -d "$DESKTOP_DIR" ] ||
DESKTOP_DIR="${HOME:-/tmp}"
LOG_FILE="$DESKTOP_DIR/github-manager-security-review.log"
TMP_DIR="${TMPDIR:-/tmp}/github-manager-${UID:-0}-$$"
if [ -L "$TMP_DIR" ]
then
printf 'Erro: caminho temporário é um link simbólico.\n' >&2
exit 1
fi
mkdir -p -m 0700 "$TMP_DIR" ||
exit 1
secure_wipe_dir() {
local target="$1"
if [ -n "$target" ] &&
[ -d "$target" ] &&
[ ! -L "$target" ]
then
if command -v shred >/dev/null 2>&1
then
find "$target" -type f -exec shred -u -z -n 1 {} + 2>/dev/null ||
true
fi
rm -rf -- "$target" 2>/dev/null ||
true
fi
}
cleanup() {
GITHUB_TOKEN=""
secure_wipe_dir "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
LOCAL_DIR_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/github-manager/current-directory"
SESSION_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/github-manager/session"
has_control_chars() {
case "$1" in
*[[:cntrl:]]*) return 0 ;;
*) return 1 ;;
esac
}
is_safe_path_component() {
local comp="$1"
[ -n "$comp" ] ||
return 1
has_control_chars "$comp" &&
return 1
case "$comp" in
"."|".."|*/*|*\\*) return 1 ;;
*) return 0 ;;
esac
}
gui_read() {
local __gr_var="${1:-value}" __gr_val=""
IFS= read -r __gr_val ||
__gr_val=""
if has_control_chars "$__gr_val"
then
__gr_val=""
fi
printf -v "$__gr_var" '%s' "$__gr_val"
}
get_local_base_dir() {
local saved_dir=""
if [ -L "$LOCAL_DIR_CONFIG" ]
then
printf 'Erro: arquivo de configuração é um link simbólico.\n' >&2
return 1
fi
if [[ -r "$LOCAL_DIR_CONFIG" && -f "$LOCAL_DIR_CONFIG" ]]
then
IFS= read -r saved_dir < "$LOCAL_DIR_CONFIG" ||
true
fi
if [[ -n "$saved_dir" && -d "$saved_dir" && ! -L "$saved_dir" ]]
then
(cd -- "$saved_dir" 2>/dev/null && pwd -P) ||
pwd -P
else
pwd -P
fi
}
upload_selected_attachments() {
local attachments_json="${GITHUB_ATTACHMENTS_JSON:-[]}"
local count index file remote_path encoded_repo encoded_path sha http_code answer failed=0 sent=0
local repo_name branch dest_folder
ensure_login ||
return 1
command -v base64 >/dev/null 2>&1 ||
{ printf 'Erro: base64 não está disponível.\n'; return 1; }
count=$(jq 'length' <<< "$attachments_json" 2>/dev/null) ||
{ printf 'Lista de anexos inválida.\n'; return 1; }
(( count > 0 )) ||
{ printf 'Nenhum arquivo foi selecionado.\n'; return 1; }
printf '\n=== ENVIAR %s ARQUIVO(S) ANEXO(S) AO GITHUB ===\n' "$count"
printf 'Diretório local configurado: %s\n' "$(get_local_base_dir)"
printf 'Nome do repositório: '
gui_read repo_name
valid_name "$repo_name" ||
{ printf 'Nome de repositório inválido.\n'; return 1; }
if ! api GET "/repos/$GITHUB_USER/$(urlencode "$repo_name")" "" "$TMP_DIR/upload-repo.json"
then return 1
fi
DEFAULT_BRANCH=$(jq -r '.default_branch // "main"' "$TMP_DIR/upload-repo.json")
SELECTED_REPO="$repo_name"
encoded_repo=$(urlencode "$SELECTED_REPO") ||
return 1
printf 'Branch (ENTER para MAIN = %s): ' "$DEFAULT_BRANCH"
gui_read branch
[ -n "$branch" ] ||
branch="$DEFAULT_BRANCH"
if ! api GET "/repos/$GITHUB_USER/$encoded_repo/branches/$(urlencode "$branch")" "" "$TMP_DIR/upload-branch.json"
then
printf 'Branch não encontrada: %s\n' "$branch"
return 1
fi
printf 'Pasta destino (ENTER para RAIZ): '
gui_read dest_folder
dest_folder=${dest_folder#/}
dest_folder=${dest_folder%/}
if [ -n "$dest_folder" ]
then
validate_remote_folder "$dest_folder" ||
{ printf 'Pasta destino inválida.\n'; return 1; }
fi
for ((index=0; index<count; index++))
do
file=$(jq -r ".[$index] // empty" <<< "$attachments_json") ||
{ failed=$((failed+1)); continue; }
if [ -z "$file" ] ||
has_control_chars "$file" ||
[[ ! -f "$file" || -L "$file" || ! -r "$file" ]]
then
printf '[FALHA] Arquivo inexistente, inválido ou sem leitura: %s\n' "$file"
failed=$((failed+1))
continue
fi
if [ -n "$dest_folder" ]
then
remote_path="$dest_folder/$(basename -- "$file")"
else
remote_path="$(basename -- "$file")"
fi
is_safe_path_component "$remote_path" ||
{
printf '[FALHA] Nome de arquivo inválido: %s\n' "$remote_path"
failed=$((failed+1))
continue
}
encoded_path=$(urlencode_path "$remote_path") ||
{ failed=$((failed+1)); continue; }
if ! base64 < "$file" | tr -d '\r\n' > "$TMP_DIR/upload-content.b64"
then
printf '[FALHA] Não foi possível ler/codificar: %s\n' "$file"
failed=$((failed+1))
continue
fi
chmod 0600 "$TMP_DIR/upload-content.b64" 2>/dev/null ||
true
http_code=$(curl -sS -o "$TMP_DIR/content.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$encoded_repo/contents/$encoded_path?ref=$(urlencode "$branch")") ||
http_code=000
sha=""
case "$http_code" in
200) sha=$(jq -r '.sha // empty' "$TMP_DIR/content.json");;
404) ;;
*) printf '[FALHA] Consulta de %s (HTTP %s).\n' "$remote_path" "$http_code"
failed=$((failed+1))
continue;;
esac
if [[ -n "$sha" ]]
then
printf 'O arquivo remoto %s já existe. Atualizar? (s/n): ' "$remote_path"
gui_read answer
case "$answer" in s|S|sim|SIM) ;;
*) printf '[IGNORADO] %s\n' "$remote_path"
continue;;
esac
fi
if ! jq -n --arg message "Envio de $remote_path via GitHub Manager" --rawfile content "$TMP_DIR/upload-content.b64" \
--arg branch "$branch" --arg sha "$sha" \
'{message:$message,content:($content|gsub("[\\r\\n]";"")),branch:$branch} + (if $sha != "" then {sha:$sha} else {} end)' > "$TMP_DIR/upload-payload.json"
then
printf '[FALHA] Preparação do envio: %s\n' "$remote_path"
failed=$((failed+1))
continue
fi
chmod 0600 "$TMP_DIR/upload-payload.json" 2>/dev/null ||
true
http_code=$(curl -sS -o "$TMP_DIR/upload.json" -w '%{http_code}' -X PUT \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" -H 'Content-Type: application/json' \
--data-binary "@$TMP_DIR/upload-payload.json" \
"$API_URL/repos/$GITHUB_USER/$encoded_repo/contents/$encoded_path") ||
http_code=000
if [[ "$http_code" == 200 || "$http_code" == 201 ]] &&
jq -e '.content.sha and .commit.sha' "$TMP_DIR/upload.json" >/dev/null 2>&1
then
printf '[OK] Enviado: %s\n' "$file"
sent=$((sent+1))
else
printf '[FALHA] %s (HTTP %s): %s\n' "$remote_path" "$http_code" "$(jq -r '.message // "sem detalhes"' "$TMP_DIR/upload.json" 2>/dev/null)"
failed=$((failed+1))
fi
done
printf '\nRESUMO: %s enviado(s), %s com falha, %s selecionado(s).\n' "$sent" "$failed" "$count"
(( failed == 0 ))
}
move_all_files_bulk() {
local mode="$1" source_folder="${2:-}" destination_folder repo branch repo_encoded branch_encoded
local source_path base_name destination_path source_encoded destination_encoded
local source_status source_sha target_status target_sha payload status total moved failed answer i
local -a paths=() destinations=()
ensure_login ||
return 1
printf '\n=== MOVIMENTAÇÃO EM LOTE DE ARQUIVOS ===\n'
printf 'Nome do repositório: '
gui_read repo
valid_name "$repo" ||
{ printf 'Nome de repositório inválido.\n'; return 1; }
repo_encoded=$(urlencode "$repo") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded" "" "$TMP_DIR/bulk-repo.json"
then return 1
fi
printf 'Nome exato da branch (ex.: main): '
gui_read branch
[ -n "$branch" ] &&
! has_control_chars "$branch" ||
{ printf 'Branch não informada ou inválida.\n'; return 1; }
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/branches/$(urlencode "$branch")" "" "$TMP_DIR/bulk-branch.json"
then
printf 'A branch "%s" não foi encontrada ou não está acessível.\n' "$branch"
return 1
fi
DEFAULT_BRANCH=$(jq -r '.default_branch // "main"' "$TMP_DIR/bulk-repo.json")
if [ "$mode" = "main" ] &&
[ "$branch" != "$DEFAULT_BRANCH" ]
then
printf 'Esta opção exige a branch principal do repositório: %s\n' "$DEFAULT_BRANCH"
return 1
fi
if [ "$mode" = "secondary" ] &&
[ "$branch" = "$DEFAULT_BRANCH" ]
then
printf 'Esta opção exige uma branch secundária, diferente de %s.\n' "$DEFAULT_BRANCH"
return 1
fi
SELECTED_REPO="$repo"
SELECTED_BRANCH="$branch"
printf 'Diretório de ORIGEM no repositório (ENTER para RAIZ): '
gui_read source_folder
source_folder=${source_folder#/}
source_folder=${source_folder%/}
if [ -n "$source_folder" ]
then
validate_remote_folder "$source_folder" ||
{ printf 'Diretório de origem inválido.\n'; return 1; }
else
source_folder=""
printf 'Pasta de origem: RAIZ.\n'
fi
printf 'Diretório de DESTINO no repositório: '
gui_read destination_folder
destination_folder=${destination_folder#/}
destination_folder=${destination_folder%/}
if [ -n "$destination_folder" ]
then
validate_remote_folder "$destination_folder" ||
{ printf 'Diretório de destino inválido.\n'; return 1; }
fi
if [ -n "$source_folder" ] &&
{ [ "$destination_folder" = "$source_folder" ] || [[ "$destination_folder" == "$source_folder/"* ]]; }
then
printf 'Destino não pode ser a própria origem nem uma subpasta dela.\n'
return 1
fi
remote_file_paths "$SELECTED_REPO" "$SELECTED_BRANCH" "$source_folder" ||
return 1
if [ "$(jq -r '.truncated // false' "$TMP_DIR/remote-files-tree.json")" = "true" ]
then
printf 'A listagem da árvore do GitHub veio truncada. Operação cancelada para evitar mover apenas parte dos arquivos.\n'
return 1
fi
while IFS= read -r source_path
do
[ -n "$source_path" ] ||
continue
base_name=${source_path##*/}
[ -n "$destination_folder" ] &&
destination_path="$destination_folder/$base_name" ||
destination_path="$base_name"
[ "$source_path" = "$destination_path" ] &&
continue
paths+=("$source_path")
destinations+=("$destination_path")
done < "$TMP_DIR/remote-files-paths.txt"
total=${#paths[@]}
if [ "$total" -eq 0 ]
then printf 'Nenhum arquivo elegível foi encontrado.\n'
return 0
fi
local -A seen_dest=()
for destination_path in "${destinations[@]}"
do
if [[ -n "${seen_dest[$destination_path]+x}" ]]
then
printf 'Colisão: mais de um arquivo seria gravado como "%s". Nenhuma alteração foi feita.\n' "$destination_path"
return 1
fi
seen_dest[$destination_path]=1
done
for destination_path in "${destinations[@]}"
do
destination_encoded=$(urlencode_path "$destination_path") ||
return 1
target_status=$(curl -sS -o "$TMP_DIR/bulk-preflight.json" -w '%{http_code}' -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: $API_VERSION" "$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$destination_encoded?ref=$(urlencode "$SELECTED_BRANCH")") ||
target_status=000
case "$target_status" in
404) ;;
200) printf 'Destino já existe: %s. Nenhum arquivo foi alterado. Escolha outra pasta de destino.\n' "$destination_path"
return 1 ;;
*) printf 'Não foi possível validar o destino %s (HTTP %s). Nenhum arquivo foi alterado.\n' "$destination_path" "$target_status"
return 1 ;;
esac
done
printf '\nRepositório: %s\nBranch: %s\nArquivos selecionados: %s\nDestino: %s\n' "$SELECTED_REPO" "$SELECTED_BRANCH" "$total" "${destination_folder:-/}"
printf '\nPrévia da movimentação:\n'
for ((i=0; i<total; i++))
do printf '  %s  ->  %s\n' "${paths[$i]}" "${destinations[$i]}"
done
printf '\nConfirma mover TODOS os arquivos listados? (s/n): '
gui_read answer
case "$answer" in s|S|sim|SIM) ;;
*) printf 'Operação cancelada.\n'
return 0 ;;
esac
branch_encoded=$(urlencode "$SELECTED_BRANCH") ||
return 1
moved=0
failed=0
for ((i=0; i<total; i++))
do
source_path=${paths[$i]}
destination_path=${destinations[$i]}
source_encoded=$(urlencode_path "$source_path") ||
{ printf 'Falha ao codificar origem: %s\n' "$source_path"; failed=$((failed+1)); continue; }
destination_encoded=$(urlencode_path "$destination_path") ||
{ printf 'Falha ao codificar destino: %s\n' "$destination_path"; failed=$((failed+1)); continue; }
source_status=$(curl -sS -o "$TMP_DIR/bulk-source.json" -w '%{http_code}' -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: $API_VERSION" "$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$source_encoded?ref=$branch_encoded") ||
source_status=000
if [ "$source_status" != 200 ]
then printf '[FALHA] Leitura de %s (HTTP %s).\n' "$source_path" "$source_status"
failed=$((failed+1))
continue
fi
source_sha=$(jq -r '.sha // empty' "$TMP_DIR/bulk-source.json")
if [ -z "$source_sha" ] ||
! jq -e '.content and (.encoding == "base64")' "$TMP_DIR/bulk-source.json" >/dev/null 2>&1
then
printf '[FALHA] Conteúdo não disponível pela API (possível arquivo acima do limite de Contents API): %s\n' "$source_path"
failed=$((failed+1))
continue
fi
jq -r '.content' "$TMP_DIR/bulk-source.json" | tr -d '\r\n' > "$TMP_DIR/bulk-content.b64" ||
{ failed=$((failed+1)); continue; }
chmod 0600 "$TMP_DIR/bulk-content.b64" 2>/dev/null ||
true
target_status=$(curl -sS -o "$TMP_DIR/bulk-target.json" -w '%{http_code}' -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: $API_VERSION" "$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$destination_encoded?ref=$branch_encoded") ||
target_status=000
target_sha=""
case "$target_status" in
404) ;;
200) printf '[PULADO] O destino já existe: %s (nenhum arquivo será sobrescrito).\n' "$destination_path"
failed=$((failed+1))
continue ;;
*) printf '[FALHA] Verificação do destino %s (HTTP %s).\n' "$destination_path" "$target_status"
failed=$((failed+1))
continue ;;
esac
if ! jq -n --arg message "Mover $source_path para $destination_path" --rawfile content "$TMP_DIR/bulk-content.b64" --arg branch "$SELECTED_BRANCH" '{message:$message,content:$content,branch:$branch}' > "$TMP_DIR/bulk-upload.json"
then failed=$((failed+1))
continue
fi
chmod 0600 "$TMP_DIR/bulk-upload.json" 2>/dev/null ||
true
status=$(curl -sS -o "$TMP_DIR/bulk-upload-result.json" -w '%{http_code}' -X PUT -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: $API_VERSION" -H 'Content-Type: application/json' --data-binary "@$TMP_DIR/bulk-upload.json" "$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$destination_encoded") ||
status=000
case "$status" in 200|201) ;;
*) printf '[FALHA] Upload de %s (HTTP %s); origem preservada.\n' "$destination_path" "$status"
failed=$((failed+1))
continue ;;
esac
payload=$(jq -n --arg message "Remover origem após movimentação para $destination_path" --arg sha "$source_sha" --arg branch "$SELECTED_BRANCH" '{message:$message,sha:$sha,branch:$branch}') ||
{ printf '[ATENÇÃO] Destino gravado; falha ao preparar remoção de %s.\n' "$source_path"; failed=$((failed+1)); continue; }
status=$(curl -sS -o "$TMP_DIR/bulk-delete-result.json" -w '%{http_code}' -X DELETE -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: $API_VERSION" -H 'Content-Type: application/json' --data-binary "$payload" "$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$source_encoded") ||
status=000
if [ "$status" = 200 ] ||
[ "$status" = 204 ]
then printf '[OK] %s -> %s\n' "$source_path" "$destination_path"
moved=$((moved+1))
else printf '[ATENÇÃO] Destino gravado, mas origem não removida: %s (HTTP %s).\n' "$source_path" "$status"
failed=$((failed+1))
fi
done
printf '\nRESUMO: %s movido(s), %s com falha/ignorados, de %s arquivo(s).\n' "$moved" "$failed" "$total"
[ "$failed" -eq 0 ]
}
move_all_repository_folder_files() { move_all_files_bulk "folder"; }
move_all_main_branch_files() { move_all_files_bulk "main"; }
move_all_secondary_branch_files() { move_all_files_bulk "secondary"; }
expand_user_path() {
case "$1" in
'~') printf '%s' "$HOME" ;;
'~/'*) printf '%s' "$HOME/${1#\~/}" ;;
/*) printf '%s' "$1" ;;
*) printf '%s/%s' "$(get_local_base_dir)" "$1" ;;
esac
}
open_local_folder() {
local dir
dir="$(get_local_base_dir)" ||
return 1
printf '\nAbrindo pasta local: %s\n' "$dir"
if command -v xdg-open >/dev/null 2>&1
then
nohup xdg-open "$dir" >/dev/null 2>&1 &
disown 2>/dev/null ||
true
elif command -v gio >/dev/null 2>&1
then
nohup gio open "$dir" >/dev/null 2>&1 &
disown 2>/dev/null ||
true
elif command -v nautilus >/dev/null 2>&1
then
nohup nautilus "$dir" >/dev/null 2>&1 &
disown 2>/dev/null ||
true
elif command -v dolphin >/dev/null 2>&1
then
nohup dolphin "$dir" >/dev/null 2>&1 &
disown 2>/dev/null ||
true
elif command -v thunar >/dev/null 2>&1
then
nohup thunar "$dir" >/dev/null 2>&1 &
disown 2>/dev/null ||
true
else
printf 'Nenhum gerenciador de arquivos encontrado para abrir a pasta.\n'
return 1
fi
}
pick_single_file() {
local base picked
base="$(get_local_base_dir)" ||
base="$PWD"
if command -v zenity >/dev/null 2>&1
then
picked="$(zenity --file-selection --title="Escolha o arquivo para anexar (2 cliques selecionam)" --filename="$base/" 2>/dev/null)" ||
picked=""
elif command -v kdialog >/dev/null 2>&1
then
picked="$(kdialog --getopenfilename "$base" 2>/dev/null)" ||
picked=""
elif command -v yad >/dev/null 2>&1
then
picked="$(yad --file --title="Escolha o arquivo para anexar" --filename="$base/" 2>/dev/null)" ||
picked=""
else
return 1
fi
[ -n "$picked" ] ||
return 1
printf '%s' "$picked"
}
pick_multiple_files() {
local base picked
base="$(get_local_base_dir)" ||
base="$PWD"
if command -v zenity >/dev/null 2>&1
then
picked="$(zenity --file-selection --multiple --separator='
' --title="Escolha os arquivos para anexar (2 cliques selecionam)" --filename="$base/" 2>/dev/null)" ||
picked=""
elif command -v kdialog >/dev/null 2>&1
then
picked="$(kdialog --getopenfilename "$base" --multiple --separate-output 2>/dev/null)" ||
picked=""
elif command -v yad >/dev/null 2>&1
then
picked="$(yad --file --multiple --separator='
' --title="Escolha os arquivos para anexar" --filename="$base/" 2>/dev/null)" ||
picked=""
else
return 1
fi
[ -n "$picked" ] ||
return 1
printf '%s' "$picked"
}
attach_single_file() {
local file rc
ensure_login ||
return 1
printf '\nDiretório local configurado: %s\n' "$(get_local_base_dir)"
printf 'Seletor de arquivos: dê 2 cliques sobre o arquivo para anexá-lo.\n'
if file="$(pick_single_file)"
then
:
else
printf 'Arquivo a enviar (nome no diretório local ou caminho completo): '
gui_read file
[ -n "$file" ] ||
{ printf 'Nenhum arquivo informado.\n'; return 1; }
fi
file="$(expand_user_path "$file")"
GITHUB_ATTACHMENTS_JSON=$(jq -n --arg f "$file" '[$f]') ||
return 1
export GITHUB_ATTACHMENTS_JSON
upload_selected_attachments
rc=$?
unset GITHUB_ATTACHMENTS_JSON
return "$rc"
}
attach_multiple_files() {
local file rc picked
local -a files=()
ensure_login ||
return 1
printf '\nDiretório local configurado: %s\n' "$(get_local_base_dir)"
printf 'Seletor de arquivos: dê 2 cliques sobre cada arquivo para anexá-lo.\n'
if picked="$(pick_multiple_files)"
then
while IFS= read -r file
do
[ -n "$file" ] &&
files+=("$(expand_user_path "$file")")
done <<< "$picked"
else
printf 'Informe um arquivo por linha (nome no diretório local ou caminho completo).\n'
printf 'Linha vazia encerra a seleção.\n'
while :
do
printf 'Arquivo %s: ' "$(( ${#files[@]} + 1 ))"
gui_read file ||
break
[ -n "$file" ] ||
break
files+=("$(expand_user_path "$file")")
done
fi
(( ${#files[@]} > 0 )) ||
{ printf 'Nenhum arquivo selecionado.\n'; return 1; }
GITHUB_ATTACHMENTS_JSON=$(printf '%s\n' "${files[@]}" | jq -R . | jq -s .) ||
return 1
export GITHUB_ATTACHMENTS_JSON
upload_selected_attachments
rc=$?
unset GITHUB_ATTACHMENTS_JSON
return "$rc"
}
pause() {
printf '\nPressione ENTER para continuar...'
IFS= read -r _
}
open_pat_link() {
local url="https://github.com/settings/tokens/new"
local cols pad text
text="Abrindo: $url"
cols=$(tput cols 2>/dev/null || echo 120)
case "$cols" in *[!0-9]*) cols=120;; esac
pad=$(( (cols - ${#text}) / 2 ))
[ "$pad" -lt 0 ] &&
pad=0
if [ "$1" != "quiet" ]; then printf '\n%*s%s\n' "$pad" '' "$text"; fi
if command -v xdg-open >/dev/null 2>&1
then
nohup xdg-open "$url" >/dev/null 2>&1 &
disown 2>/dev/null ||
true
elif command -v gio >/dev/null 2>&1
then
nohup gio open "$url" >/dev/null 2>&1 &
disown 2>/dev/null ||
true
elif command -v open >/dev/null 2>&1
then
nohup open "$url" >/dev/null 2>&1 &
disown 2>/dev/null ||
true
else
printf 'Abra o link no navegador: %s\n' "$url"
return 1
fi
}
show_banner() {
local esc=$'\033'
local reset="${esc}[0m"
local y1="${esc}[38;5;226m"
local y2="${esc}[38;5;220m"
local y3="${esc}[38;5;214m"
local y4="${esc}[38;5;208m"
local y5="${esc}[38;5;178m"
local y6="${esc}[38;5;172m"
local ybg1="${esc}[48;5;226m"
local ybg2="${esc}[48;5;220m"
local ybg3="${esc}[48;5;214m"
local ybg4="${esc}[48;5;208m"
local ybg5="${esc}[48;5;178m"
local ybg6="${esc}[48;5;172m"
local w="${esc}[97;1m"
local dim="${esc}[90m"
local cols
local r1="██████╗ ██╗████████╗███╗   ███╗███████╗███╗   ██╗██╗   ██╗  ██████╗  ██╗     ██╗"
local r2="██╔════╝ ██║╚══██╔══╝████╗ ████║██╔════╝████╗  ██║██║   ██║  ██╔════╝ ██║     ██║"
local r3="██║  ███╗██║   ██║   ██╔████╔██║█████╗  ██╔██╗ ██║██║   ██║  ██║      ██║     ██║"
local r4="██║   ██║██║   ██║   ██║╚██╔╝██║██╔══╝  ██║╚██╗██║██║   ██║  ██║      ██║     ██║"
local r5="╚██████╔╝██║   ██║   ██║ ╚═╝ ██║███████╗██║ ╚████║╚██████╔╝  ╚██████╗ ███████╗██║"
local r6=" ╚═════╝ ╚═╝   ╚═╝   ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝   ╚═════╝  ╚══════╝╚═╝"
if [ -t 1 ] &&
[ -n "${TERM:-}" ] &&
command -v clear >/dev/null 2>&1
then
clear 2>/dev/null ||
:
fi
cols=$(tput cols 2>/dev/null || echo 120)
case "$cols" in *[!0-9]*) cols=120;;
esac
[ "$cols" -lt 60 ] &&
cols=60
print_centered() {
local color="$1"
local text="$2"
local width="${3:-}"
local pad
if [ -z "$width" ]
then width=${#text}
fi
pad=$(( (cols - width) / 2 ))
[ "$pad" -lt 0 ] &&
pad=0
printf '%s%*s%s%s%s\n' "$color" "$pad" '' "$text" "$reset"
}
printf ''
print_boxed() {
local LC_ALL=C.UTF-8
local color="$1"
local text="$2"
local width="$3"
local inner=$((cols - 2))
local real=${#text} rpad
local pad sidebg="$ybg1"
local fg="$color"
[ "$color" = "$y1" ] && sidebg="$ybg1"
[ "$color" = "$y2" ] && sidebg="$ybg2"
[ "$color" = "$y3" ] && sidebg="$ybg3"
[ "$color" = "$y4" ] && sidebg="$ybg4"
[ "$color" = "$y5" ] && sidebg="$ybg5"
[ "$color" = "$y6" ] && sidebg="$ybg6"
[ "$color" = "$w" ] && sidebg="$ybg1"
[ "$color" = "$dim" ] && sidebg="$ybg1"
pad=$(( (inner - width) / 2 ))
[ "$pad" -lt 0 ] &&
pad=0
rpad=$(( inner - real - pad ))
[ "$rpad" -lt 0 ] &&
rpad=0
printf '%s %s%s%*s%s%*s%s %s\n' "$sidebg" "$reset" "$fg" "$pad" '' "$text" "$rpad" '' "$sidebg" "$reset"
}
printf '%s' "$ybg1"
printf '%*s' "$cols" ''
printf '%s\n' "$reset"
print_boxed "$y1" "" 0
print_boxed "$y1" "" 0
print_boxed "$y1" "$r1" 80
print_boxed "$y2" "$r2" 82
print_boxed "$y3" "$r3" 82
print_boxed "$y4" "$r4" 82
print_boxed "$y5" "$r5" 82
print_boxed "$y6" "$r6" 82
print_boxed "$w" "GITMENU CLI - Gerenciador de repositorios GitHub" 47
print_boxed "$dim" "30 opcoes: repositorios, branches, pastas e arquivos (terminal)." 64
print_boxed "$dim" "Token solicitado durante a execucao e nao exibido." 49
print_boxed "$dim" "" 0
printf '%s' "$ybg6"
printf '%*s' "$cols" ''
printf '%s\n' "$reset"
printf ''
bw=72
bpad=$(( (cols - bw) / 2 ))
[ "$bpad" -lt 0 ] &&
bpad=0
tux_w=20
tux_h=20
tux_on=0
[ "$cols" -ge 116 ] &&
tux_on=1
ybg_arr=("$ybg1" "$ybg2" "$ybg3" "$ybg4" "$ybg5" "$ybg6")
tuxl=(
$'\033[0m      \033[38;5;240m▄▄▄▄▄▄\033[0m        \033[0m'
$'\033[0m    \033[38;5;240m██████████\033[0m      \033[0m'
$'\033[0m   \033[38;5;240m█████\033[38;5;240m\033[48;5;255m▀\033[38;5;255m███\033[38;5;255m\033[48;5;16m▀\033[38;5;255m██\033[38;5;255m▄\033[0m    \033[0m'
$'\033[0m  \033[38;5;240m█████\033[38;5;240m\033[48;5;255m▀\033[38;5;255m███\033[38;5;16m███\033[38;5;255m██\033[38;5;255m▄\033[0m   \033[0m'
$'\033[0m  \033[38;5;240m█████\033[38;5;255m█████\033[38;5;16m\033[48;5;255m▀\033[38;5;255m█\033[38;5;255m\033[48;5;208m▀\033[38;5;255m██\033[0m   \033[0m'
$'\033[0m  \033[38;5;240m▀\033[38;5;240m████\033[38;5;255m\033[48;5;240m▀\033[38;5;255m██████\033[38;5;208m███\033[38;5;208m▄▄\033[0m \033[0m'
$'\033[0m   \033[38;5;240m▀\033[38;5;240m████\033[38;5;255m\033[48;5;240m▀\033[38;5;255m█████\033[38;5;208m███\033[38;5;208m▀▀\033[0m \033[0m'
$'\033[0m    \033[38;5;240m▀▀\033[38;5;240m███████\033[38;5;240m▀\033[38;5;208m▀\033[0m     \033[0m'
$'\033[0m     \033[38;5;240m▄\033[38;5;240m████████\033[38;5;240m▄\033[0m     \033[0m'
$'\033[0m    \033[38;5;240m████████████\033[0m    \033[0m'
$'\033[0m \033[38;5;248m▄▄\033[38;5;240m██████\033[38;5;240m\033[48;5;255m▀\033[38;5;255m████\033[38;5;240m\033[48;5;255m▀\033[38;5;240m██\033[0m   \033[0m'
$'\033[38;5;248m▄\033[38;5;248m██\033[38;5;240m\033[48;5;248m▀\033[38;5;240m████\033[38;5;255m████████\033[38;5;240m█\033[38;5;240m\033[48;5;248m▀\033[38;5;248m▄\033[0m \033[0m'
$'\033[38;5;248m████\033[38;5;240m███\033[38;5;240m\033[48;5;255m▀\033[38;5;255m████████\033[38;5;240m\033[48;5;248m▀\033[38;5;248m██\033[38;5;248m▄\033[0m'
$'\033[38;5;248m████\033[38;5;240m███\033[38;5;255m█████████\033[38;5;248m████\033[0m'
$'\033[38;5;248m████\033[38;5;240m███\033[38;5;255m█████████\033[38;5;248m████\033[0m'
$'\033[0m \033[38;5;248m██\033[38;5;240m████\033[38;5;255m█████████\033[38;5;248m████\033[0m'
$'\033[0m   \033[38;5;240m▀\033[38;5;240m████\033[38;5;255m████████\033[38;5;240m▀\033[38;5;248m██\033[0m \033[0m'
$'\033[0m    \033[38;5;240m▀\033[38;5;240m███\033[38;5;255m\033[48;5;240m▀\033[38;5;255m██████\033[38;5;255m▀\033[0m    \033[0m'
$'\033[0m      \033[38;5;240m\033[48;5;208m▀\033[38;5;240m███\033[38;5;255m\033[48;5;240m▀▀▀\033[38;5;255m▀\033[38;5;208m▄\033[0m     \033[0m'
$'\033[0m   \033[38;5;208m███████\033[0m \033[38;5;208m███████\033[0m  \033[0m'
)
tuxr=(
$'\033[0m        \033[38;5;240m▄▄▄▄▄▄\033[0m      \033[0m'
$'\033[0m      \033[38;5;240m██████████\033[0m    \033[0m'
$'\033[0m    \033[38;5;255m▄\033[38;5;255m██\033[38;5;255m\033[48;5;16m▀\033[38;5;255m███\033[38;5;240m\033[48;5;255m▀\033[38;5;240m█████\033[0m   \033[0m'
$'\033[0m   \033[38;5;255m▄\033[38;5;255m██\033[38;5;16m███\033[38;5;255m███\033[38;5;240m\033[48;5;255m▀\033[38;5;240m█████\033[0m  \033[0m'
$'\033[0m   \033[38;5;255m██\033[38;5;255m\033[48;5;208m▀\033[38;5;255m█\033[38;5;16m\033[48;5;255m▀\033[38;5;255m█████\033[38;5;240m█████\033[0m  \033[0m'
$'\033[0m \033[38;5;208m▄▄\033[38;5;208m███\033[38;5;255m██████\033[38;5;255m\033[48;5;240m▀\033[38;5;240m████\033[38;5;240m▀\033[0m  \033[0m'
$'\033[0m \033[38;5;208m▀▀\033[38;5;208m███\033[38;5;255m█████\033[38;5;255m\033[48;5;240m▀\033[38;5;240m████\033[38;5;240m▀\033[0m   \033[0m'
$'\033[0m     \033[38;5;208m▀\033[38;5;240m▀\033[38;5;240m███████\033[38;5;240m▀▀\033[0m    \033[0m'
$'\033[0m     \033[38;5;240m▄\033[38;5;240m████████\033[38;5;240m▄\033[0m     \033[0m'
$'\033[0m    \033[38;5;240m████████████\033[0m    \033[0m'
$'\033[0m   \033[38;5;240m██\033[38;5;240m\033[48;5;255m▀\033[38;5;255m████\033[38;5;240m\033[48;5;255m▀\033[38;5;240m██████\033[38;5;248m▄▄\033[0m \033[0m'
$'\033[0m \033[38;5;248m▄\033[38;5;240m\033[48;5;248m▀\033[38;5;240m█\033[38;5;255m████████\033[38;5;240m████\033[38;5;240m\033[48;5;248m▀\033[38;5;248m██\033[38;5;248m▄\033[0m'
$'\033[38;5;248m▄\033[38;5;248m██\033[38;5;240m\033[48;5;248m▀\033[38;5;255m████████\033[38;5;240m\033[48;5;255m▀\033[38;5;240m███\033[38;5;248m████\033[0m'
$'\033[38;5;248m████\033[38;5;255m█████████\033[38;5;240m███\033[38;5;248m████\033[0m'
$'\033[38;5;248m████\033[38;5;255m█████████\033[38;5;240m███\033[38;5;248m████\033[0m'
$'\033[38;5;248m████\033[38;5;255m█████████\033[38;5;240m████\033[38;5;248m██\033[0m \033[0m'
$'\033[0m \033[38;5;248m██\033[38;5;240m▀\033[38;5;255m████████\033[38;5;240m████\033[38;5;240m▀\033[0m   \033[0m'
$'\033[0m    \033[38;5;255m▀\033[38;5;255m██████\033[38;5;255m\033[48;5;240m▀\033[38;5;240m███\033[38;5;240m▀\033[0m    \033[0m'
$'\033[0m     \033[38;5;208m▄\033[38;5;255m▀\033[38;5;255m\033[48;5;240m▀▀▀\033[38;5;240m███\033[38;5;240m\033[48;5;208m▀\033[0m      \033[0m'
$'\033[0m  \033[38;5;208m███████\033[0m \033[38;5;208m███████\033[0m   \033[0m'
)
patc=()
pat_add() {
local LC_ALL=C.UTF-8
local mode="$1" text="$2" color="$3"
local inner="" w=0 lpad=0 rpad=0
case "$mode" in
center)
w=${#text}
lpad=$(( (bw - w) / 2 ))
[ "$lpad" -lt 0 ] &&
lpad=0
rpad=$(( bw - w - lpad ))
[ "$rpad" -lt 0 ] &&
rpad=0
inner="${color}$(printf '%*s' "$lpad" '')${text}$(printf '%*s' "$rpad" '')${reset}"
;;
left)
w=${#text}
rpad=$(( bw - 1 - w ))
[ "$rpad" -lt 0 ] &&
rpad=0
inner=" ${text}$(printf '%*s' "$rpad" '')${reset}"
;;
blank) inner="$(printf '%*s' "$bw" '')" ;;
esac
patc+=("$inner")
}
pat_add center "COMO GERAR SEU TOKEN PAT NO GITHUB" "$w"
pat_add left "1. Abra o link oficial: https://github.com/settings/tokens/new" ""
pat_add left "2. Entre no GitHub, se solicitado, e dê um nome ao token." ""
pat_add left "3. Defina uma validade e selecione as permissões necessárias." ""
pat_add left "   Para repositórios privados, habilite acesso aos repositórios" ""
pat_add left "   e permissões de leitura/escrita exigidas pelas operações usadas." ""
pat_add left "4. Gere o token (Generate token) e copie-o imediatamente." ""
pat_add left "5. Cole o token no campo PAT abaixo; ele não será exibido." ""
aten_text="ATENÇÃO: nunca compartilhe seu PAT. O link pode ser aberto no navegador."
build_aten_row() {
local LC_ALL=C.UTF-8
local lpad=0 rpad=0
lpad=$(( (bw - ${#aten_text}) / 2 ))
[ "$lpad" -lt 0 ] &&
lpad=0
rpad=$(( bw - ${#aten_text} - lpad ))
[ "$rpad" -lt 0 ] &&
rpad=0
aten_row="${w}$(printf '%*s' "$lpad" '')${aten_text}$(printf '%*s' "$rpad" '')${reset}"
}
build_aten_row""
box_blank() {
local sidebg="$1"
printf '%s %s' "$sidebg" "$reset"
printf '%*s' "$(( cols - 2 ))" ''
printf '%s %s\n' "$sidebg" "$reset"
}
box_menu_row() {
local LC_ALL=C.UTF-8
local text="$1" sidebg="$2"
local inner="" rpad=0
inner="${text}"
rpad=$(( menu_w - ${#inner} ))
[ "$rpad" -lt 0 ] &&
rpad=0
inner="${inner}$(printf '%*s' "$rpad" '')"
printf '%s %s' "$sidebg" "$reset"
printf '%*s%s%*s' "$mlm" '' "$inner" "$mrm" ''
printf '%s %s\n' "$sidebg" "$reset"
}
lm2=$(( (cols - 2 - bw) / 2 ))
[ "$lm2" -lt 0 ] &&
lm2=0
rm2=$(( cols - 2 - bw - lm2 ))
[ "$rm2" -lt 0 ] &&
rm2=0
menu_w=39
mlm=$(( (cols - 2 - menu_w) / 2 ))
[ "$mlm" -lt 0 ] &&
mlm=0
mrm=$(( cols - 2 - menu_w - mlm ))
[ "$mrm" -lt 0 ] &&
mrm=0
flm=$(( (cols - menu_w) / 2 ))
[ "$flm" -lt 0 ] &&
flm=0
if [ "$cols" -ge 74 ]
then
printf '%s%*s%s\n' "$ybg1" "$cols" '' "$reset"
box_blank "$ybg1"
if [ "$tux_on" = 1 ]
then
tux_pad=$(( (cols - 114) / 2 ))
[ "$tux_pad" -lt 0 ] && tux_pad=0
tux_pad_r=$(( cols - 114 - tux_pad ))
[ "$tux_pad_r" -lt 0 ] && tux_pad_r=0
tux_gap=3
[ "$tux_pad" -lt "$tux_gap" ] && tux_gap="$tux_pad"
[ "$tux_pad_r" -lt "$tux_gap" ] && tux_gap="$tux_pad_r"
tux_pad=$(( tux_pad - tux_gap ))
tux_pad_r=$(( tux_pad_r - tux_gap ))
pat_off=$(( (tux_h - ${#patc[@]}) / 2 - 4 ))
[ "$pat_off" -lt 0 ] && pat_off=0
aten_idx=$(( pat_off + ${#patc[@]} + 1 ))
m1_idx=$(( pat_off + ${#patc[@]} + 3 ))
m0_idx=$(( pat_off + ${#patc[@]} + 4 ))
esc_idx=$(( pat_off + ${#patc[@]} + 5 ))
menu1_c="$(printf '%*s' 16 '')[1] Abrir link para gerar PAT no GitHub$(printf '%*s' 17 '')"
menu0_c="$(printf '%*s' 16 '')[0] Continuar para o login$(printf '%*s' 30 '')"
escolha_c="$(printf '%*s' 16 '')Escolha: $(printf '%*s' 47 '')"
brow=0
while [ "$brow" -lt "$tux_h" ]
do
prow=$(( brow - pat_off ))
if [ "$prow" -ge 0 ] && [ "$prow" -lt ${#patc[@]} ]
then pat="${patc[$prow]}"
elif [ "$brow" -eq "$aten_idx" ]
then pat="$aten_row"
elif [ "$brow" -eq "$m1_idx" ]
then pat="$menu1_c"
elif [ "$brow" -eq "$m0_idx" ]
then pat="$menu0_c"
elif [ "$brow" -eq "$esc_idx" ]
then pat="$escolha_c"
else pat="$(printf '%*s' "$bw" '')"
fi
printf '%s %s' "${ybg_arr[$(( brow * 6 / tux_h ))]}" "$reset"
printf '%*s' "$tux_pad" ''
printf '%s' "${tuxl[$brow]}"
printf '%*s' "$tux_gap" ''
printf '%s' "$pat"
printf '%*s' "$tux_gap" ''
printf '%s' "${tuxr[$brow]}"
printf '%*s' "$tux_pad_r" ''
printf '%s %s\n' "${ybg_arr[$(( brow * 6 / tux_h ))]}" "$reset"
brow=$(( brow + 1 ))
done
box_blank "$ybg6"
box_blank "$ybg6"
term_h=${LINES:-0}
if [ "$term_h" -le 0 ]; then term_h=$(tput lines 2>/dev/null || echo 0); fi
fill=$(( term_h - 46 ))
[ "$fill" -lt 0 ] && fill=0
fi_i=0
while [ "$fi_i" -lt "$fill" ]; do box_blank "$ybg6"; fi_i=$(( fi_i + 1 )); done
printf '%s%*s%s\n' "$ybg6" "$cols" '' "$reset"
pat_col=$(( tux_pad + tux_gap + 22 ))
pat_w=${#menu1_c}
printf '\033[%sA' "$(( fill + 8 ))"
printf '\033[%sG' "$(( mlm + 11 ))"
IFS= read -r _pat_choice ||
_pat_choice=""
while :
do
case "$_pat_choice" in
1)
printf '\033[%sG' "$pat_col"
printf '%*s' "$pat_w" ''
_acao="Abrindo: https://github.com/settings/tokens/new"
_acao_pl=$(( (pat_w - ${#_acao}) / 2 ))
[ "$_acao_pl" -lt 0 ] && _acao_pl=0
printf '\033[%sG' "$(( pat_col + _acao_pl ))"
printf '%s' "$_acao"
open_pat_link quiet ||
true
printf '\033[3A'
printf '\033[%sG' "$pat_col"
printf '%s' "$menu1_c"
printf '\033[1B'
printf '\033[%sG' "$pat_col"
printf '%s' "$menu0_c"
printf '\033[1B'
printf '\033[%sG' "$pat_col"
printf '%s' "$escolha_c"
printf '\033[%sG' "$(( mlm + 11 ))"
IFS= read -r _pat_choice ||
_pat_choice=""
;;
""|0)
printf '\033[%sB' "$(( fill + 7 ))"
break ;;
*)
printf '\033[%sG' "$pat_col"
printf '%*s' "$pat_w" ''
_acao="Opção inválida."
_acao_pl=$(( (pat_w - ${#_acao}) / 2 ))
[ "$_acao_pl" -lt 0 ] && _acao_pl=0
printf '\033[%sG' "$(( pat_col + _acao_pl ))"
printf '%s' "$_acao"
printf '\033[3A'
printf '\033[%sG' "$pat_col"
printf '%s' "$menu1_c"
printf '\033[1B'
printf '\033[%sG' "$pat_col"
printf '%s' "$menu0_c"
printf '\033[1B'
printf '\033[%sG' "$pat_col"
printf '%s' "$escolha_c"
printf '\033[%sG' "$(( mlm + 11 ))"
IFS= read -r _pat_choice ||
_pat_choice=""
;;
esac
done
else
printf '%*s%s' "$bpad" '' "$y1"
printf '%*s' "$bw" '' | tr ' ' '='
printf '%s\n' "$reset"
for pat in "${patc[@]}"
do printf '%*s%s\n' "$bpad" '' "$pat"
done
printf '%*s%s' "$bpad" '' "$y6"
printf '%*s' "$bw" '' | tr ' ' '='
printf '%s\n' "$reset"
printf '%*s%s\n' "$bpad" '' "$aten_row"
printf '\n'
while :
do
printf '%*s[1] Abrir link para gerar PAT no GitHub\n' "$flm" ''
printf '%*s[0] Continuar para o login\n' "$flm" ''
printf '%*sEscolha: ' "$flm" ''
IFS= read -r _pat_choice ||
_pat_choice=""
case "$_pat_choice" in
1) open_pat_link ||
true ;;
""|0) break ;;
*) printf '%*sOpção inválida.\n' "$flm" '' ;;
esac
done
printf '%*s%s' "$bpad" '' "$y6"
printf '%*s' "$bw" '' | tr ' ' '='
printf '%s\n' "$reset"
fi
else
printf '%*s%s' "$bpad" '' "$y1"
printf '%*s' "$bw" '' | tr ' ' '='
printf '%s\n' "$reset"
for pat in "${patc[@]}"
do printf '%*s%s\n' "$bpad" '' "$pat"
done
printf '%*s%s' "$bpad" '' "$y6"
printf '%*s' "$bw" '' | tr ' ' '='
printf '%s\n' "$reset"
printf '%*s%s\n' "$bpad" '' "$aten_row"
printf '\n'
while :
do
printf '%*s[1] Abrir link para gerar PAT no GitHub\n' "$flm" ''
printf '%*s[0] Continuar para o login\n' "$flm" ''
printf '%*sEscolha: ' "$flm" ''
IFS= read -r _pat_choice ||
_pat_choice=""
case "$_pat_choice" in
1) open_pat_link ||
true ;;
""|0) break ;;
*) printf '%*sOpção inválida.\n' "$flm" '' ;;
esac
done
printf '%*s%s' "$bpad" '' "$y6"
printf '%*s' "$bw" '' | tr ' ' '='
printf '%s\n' "$reset"
fi
printf '\n'
}
valid_name() {
case "$1" in
""|*[!a-zA-Z0-9._-]*) return 1 ;;
*) return 0 ;;
esac
}
urlencode() {
jq -nr --arg value "$1" '$value|@uri'
}
api() {
local method="$1"
local endpoint="$2"
local data="${3:-}"
local output="${4:-$TMP_DIR/response.json}"
local status curl_rc output_dir
output_dir="$(dirname "$output")"
if ! mkdir -p -m 0700 "$TMP_DIR" "$output_dir"
then
printf 'Erro: não foi possível preparar o diretório temporário.\n' >&2
return 1
fi
if [ -L "$output" ]
then
printf 'Erro: arquivo de saída é um link simbólico: %s\n' "$output" >&2
return 1
fi
: > "$output" ||
{
printf 'Erro: não foi possível criar o arquivo de resposta: %s\n' "$output" >&2
return 1
}
chmod 0600 "$output" 2>/dev/null ||
true
if [ -n "$data" ]
then
status=$(curl -sS -o "$output" -w '%{http_code}' \
-X "$method" \
-H "Accept: application/vnd.github+json" \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
-H "Content-Type: application/json" \
--data-binary "$data" \
"$API_URL$endpoint")
curl_rc=$?
else
status=$(curl -sS -o "$output" -w '%{http_code}' \
-X "$method" \
-H "Accept: application/vnd.github+json" \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL$endpoint")
curl_rc=$?
fi
if [ "$curl_rc" -ne 0 ]
then
printf 'Falha de comunicação com o GitHub (curl: %s).\n' "$curl_rc" >&2
[ -s "$output" ] &&
jq -r '.message // empty' "$output" 2>/dev/null
return 1
fi
case "$status" in
200|201|202|204) return 0 ;;
*)
printf '\nErro na API do GitHub (HTTP %s).\n' "$status"
if [ -s "$output" ]
then
jq -r '.message // .' "$output" 2>/dev/null ||
cat "$output"
fi
return 1
;;
esac
}
ensure_login() {
if [ -z "$GITHUB_USER" ] ||
[ -z "$GITHUB_TOKEN" ]
then
printf '\nFaça login no GitHub primeiro.\n'
return 1
fi
return 0
}
save_session() {
local cfg_dir tmpf expiry now
cfg_dir="$(dirname "$SESSION_FILE")"
[ -L "$cfg_dir" ] ||
[ -L "$SESSION_FILE" ] &&
return 1
mkdir -p -m 0700 "$cfg_dir" ||
return 1
now=$(date +%s 2>/dev/null) ||
return 1
expiry=$((now + 600))
tmpf="$(mktemp "$cfg_dir/.session.XXXXXX")" ||
return 1
printf 'USER=%s\nTOKEN=%s\nEXPIRY=%s\n' "$GITHUB_USER" "$GITHUB_TOKEN" "$expiry" > "$tmpf" ||
{ rm -f -- "$tmpf"; return 1; }
chmod 0600 "$tmpf" 2>/dev/null ||
true
mv -f -- "$tmpf" "$SESSION_FILE" ||
{ rm -f -- "$tmpf"; return 1; }
}
load_session() {
local su st se now cfg_dir
[ -n "$SESSION_FILE" ] &&
[ -f "$SESSION_FILE" ] &&
[ ! -L "$SESSION_FILE" ] ||
return 1
cfg_dir="$(dirname "$SESSION_FILE")"
[ -L "$cfg_dir" ] &&
return 1
su=""; st=""; se=""
while IFS='=' read -r k v
do
case "$k" in
USER) su="$v" ;;
TOKEN) st="$v" ;;
EXPIRY) se="$v" ;;
esac
done < "$SESSION_FILE"
[ -n "$su" ] &&
[ -n "$st" ] &&
[ -n "$se" ] ||
return 1
case "$se" in *[!0-9]*) return 1 ;; esac
now=$(date +%s 2>/dev/null) ||
return 1
[ "$now" -lt "$se" ] ||
{ rm -f -- "$SESSION_FILE"; return 1; }
GITHUB_USER="$su"
GITHUB_TOKEN="$st"
if ! api GET "/user" "" "$TMP_DIR/session-check.json"
then
GITHUB_USER=""
GITHUB_TOKEN=""
rm -f -- "$SESSION_FILE"
return 1
fi
local actual_login
actual_login=$(jq -r '.login // empty' "$TMP_DIR/session-check.json" 2>/dev/null) || actual_login=""
if [[ -z "$actual_login" || "${actual_login,,}" != "${GITHUB_USER,,}" ]]; then
GITHUB_USER=""
GITHUB_TOKEN=""
rm -f -- "$SESSION_FILE"
return 1
fi
GITHUB_USER="$actual_login"
printf '\nSessão restaurada: %s (válida até %s)\n' "$GITHUB_USER" "$(date -d "@$se" '+%H:%M:%S' 2>/dev/null || date -r "$se" '+%H:%M:%S' 2>/dev/null || echo "$se")"
return 0
}
login_github() {
local login token key response
printf '\n'
printf '\nLOGIN DO GITHUB: '
gui_read login
if [ -z "$login" ]
then
printf 'Login inválido.\n'
return 1
fi
printf 'PERSONAL ACCESS TOKEN (PAT): '
IFS= read -r -s token
printf '\n'
if [ -z "$token" ] ||
has_control_chars "$token"
then
printf 'Token não informado ou inválido.\n'
return 1
fi
GITHUB_USER="$login"
GITHUB_TOKEN="$token"
token=""
if ! api GET "/user" "" "$TMP_DIR/user.json"
then
GITHUB_USER=""
GITHUB_TOKEN=""
return 1
fi
response=$(jq -r '.login // empty' "$TMP_DIR/user.json")
if [ -z "$response" ]
then
printf 'Não foi possível validar o usuário.\n'
GITHUB_USER=""
GITHUB_TOKEN=""
return 1
fi
# A PAT deve pertencer exatamente ao login informado (comparação sem distinção de caixa).
if [[ "${login,,}" != "${response,,}" ]]; then
printf 'Login e PAT não correspondem: a PAT pertence a outro usuário.\n' >&2
GITHUB_USER=""
GITHUB_TOKEN=""
return 1
fi
GITHUB_USER="$response"
save_session ||
true
printf '\nLogin confirmado: %s\n' "$GITHUB_USER"
printf 'Sessão válida por 10 minutos.\n'
printf '\nCaminho da chave SSH privada (ENTER para ignorar): '
gui_read key
if [ -n "$key" ]
then
key="$(expand_user_path "$key")"
if [[ -f "$key" && ! -L "$key" ]]
then
SSH_KEY="$key"
if command -v ssh-add >/dev/null 2>&1
then
ssh-add "$SSH_KEY" 2>/dev/null ||
printf 'Aviso: não foi possível adicionar a chave ao ssh-agent.\n'
fi
else
printf 'Arquivo de chave SSH não encontrado ou inválido. Chave não configurada.\n'
fi
fi
return 0
}
logout_github() {
GITHUB_USER=""
GITHUB_TOKEN=""
SSH_KEY=""
rm -f -- "$SESSION_FILE" 2>/dev/null ||
true
printf '\nSessão encerrada.\n'
}
list_repositories() {
local page count repo default_branch private path depth indent
ensure_login ||
return 1
page=1
while :
do
if ! api GET \
"/user/repos?affiliation=owner&per_page=100&page=$page&sort=full_name" \
"" "$TMP_DIR/repos.json"
then
return 1
fi
count=$(jq 'length' "$TMP_DIR/repos.json" 2>/dev/null)
[ -n "$count" ] ||
return 1
[ "$count" -gt 0 ] ||
break
while IFS="$(printf '\t')" read -r repo default_branch private
do
[ -n "$repo" ] ||
continue
printf '\n============================================================\n'
printf 'REPOSITÓRIO      : %s\n' "$repo"
printf 'BRANCH PRINCIPAL : %s\n' "$default_branch"
printf 'PRIVADO          : %s\n' "$private"
printf '%s\n' 'DIRETÓRIOS E SUBPASTAS:'
if api GET \
"/repos/$GITHUB_USER/$(urlencode "$repo")/git/trees/$(urlencode "$default_branch")?recursive=1" \
"" "$TMP_DIR/tree.json"
then
if [ "$(jq -r '.truncated // false' "$TMP_DIR/tree.json" 2>/dev/null)" = "true" ]
then
printf '  AVISO: a API informou que a árvore foi truncada.\n'
fi
jq -r '.tree[]? | select(.type == "tree") | .path' \
"$TMP_DIR/tree.json" |
while IFS= read -r path
do
[ -n "$path" ] ||
continue
depth=$(printf '%s\n' "$path" | awk -F '/' '{print NF-1}')
indent="  "
while [ "$depth" -gt 0 ]
do
indent="${indent}  "
depth=$((depth - 1))
done
printf '%s📁 %s\n' "$indent" "$path"
done
if ! jq -e '.tree[]? | select(.type == "tree")' \
"$TMP_DIR/tree.json" >/dev/null 2>&1
then
printf '  (Nenhuma pasta encontrada.)\n'
fi
else
printf '  Não foi possível consultar os diretórios desta branch.\n'
fi
done < <(
jq -r '.[] | [.name,.default_branch,(.private|tostring)] | @tsv' \
"$TMP_DIR/repos.json"
)
[ "$count" -lt 100 ] &&
break
page=$((page + 1))
done
}
create_repository_main() {
local name description visibility payload
ensure_login ||
return 1
printf '\nNome do novo repositório: '
gui_read name
valid_name "$name" ||
{
printf 'Nome inválido.\n'
return 1
}
printf 'Descrição (opcional): '
gui_read description
printf 'Repositório privado? (s/n): '
gui_read visibility
case "$visibility" in
s|S|sim|SIM) visibility=true ;;
*) visibility=false ;;
esac
payload=$(jq -n \
--arg name "$name" \
--arg description "$description" \
--argjson private "$visibility" \
'{name:$name,description:$description,private:$private,auto_init:true}')
if api POST "/user/repos" "$payload"
then
printf '\nRepositório criado: %s/%s\n' "$GITHUB_USER" "$name"
fi
}
select_repository() {
local name
ensure_login ||
return 1
printf '\nNome do repositório: '
gui_read name
valid_name "$name" ||
{
printf 'Nome inválido.\n'
return 1
}
if ! api GET "/repos/$GITHUB_USER/$(urlencode "$name")" \
"" "$TMP_DIR/repo.json"
then
return 1
fi
if [ ! -s "$TMP_DIR/repo.json" ] ||
! jq -e 'type == "object" and (.default_branch | type == "string" and length > 0)' "$TMP_DIR/repo.json" >/dev/null 2>&1
then
printf 'Erro: a resposta do GitHub está vazia ou inválida; o repositório não foi selecionado.\n'
return 1
fi
SELECTED_REPO="$name"
DEFAULT_BRANCH=$(jq -r '.default_branch' "$TMP_DIR/repo.json") ||
{
SELECTED_REPO=""
DEFAULT_BRANCH=""
printf 'Erro: não foi possível identificar a branch principal.\n'
return 1
}
return 0
}
upload_file() {
local local_folder file_name dest_repo dest_branch dest_folder
local local_path remote_path repo_encoded path_encoded
local http_code sha status answer fsize resolved_dir
ensure_login ||
return 1
command -v base64 >/dev/null 2>&1 ||
{ printf 'Erro: base64 não está disponível.\n'; return 1; }
printf '\n=== ENVIAR ARQUIVO LOCAL AO GITHUB ===\n'
printf 'Pasta local de ORIGEM (ENTER = diretório configurado): '
gui_read local_folder
if [ -z "$local_folder" ]
then
resolved_dir="$(get_local_base_dir)" ||
return 1
else
local_folder="$(expand_user_path "$local_folder")"
[[ -d "$local_folder" && ! -L "$local_folder" ]] ||
{ printf 'Pasta local não encontrada ou inválida: %s\n' "$local_folder"; return 1; }
resolved_dir="$(cd -- "$local_folder" 2>/dev/null && pwd -P)" ||
{
printf 'Não foi possível acessar a pasta local.\n'
return 1
}
fi
printf 'Pasta local: %s\n' "$resolved_dir"
printf 'Arquivos locais:\n'
find "$resolved_dir" -maxdepth 1 -type f -printf '  %f\n' 2>/dev/null | sort ||
true
printf 'Nome do arquivo local (com extensão, sem caminho): '
gui_read file_name
is_safe_path_component "$file_name" ||
{ printf 'Informe somente o nome do arquivo, sem caminhos.\n'; return 1; }
local_path="$resolved_dir/$file_name"
[[ -f "$local_path" && ! -L "$local_path" ]] ||
{ printf 'Arquivo não encontrado: %s\n' "$local_path"; return 1; }
[ -r "$local_path" ] ||
{ printf 'Sem permissão de leitura: %s\n' "$local_path"; return 1; }
fsize=$(wc -c < "$local_path" 2>/dev/null || echo 0)
if [ "$fsize" -gt 104857600 ]
then
printf 'Erro: arquivo acima de 100 MB. Use git commit/push ou Git LFS.\n'
return 1
fi
printf 'Repositório de DESTINO: '
gui_read dest_repo
valid_name "$dest_repo" ||
{ printf 'Nome de repositório inválido.\n'; return 1; }
repo_encoded=$(urlencode "$dest_repo") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded" "" "$TMP_DIR/up-local-repo.json"
then return 1
fi
DEFAULT_BRANCH=$(jq -r '.default_branch // "main"' "$TMP_DIR/up-local-repo.json")
printf 'Branch de DESTINO (ENTER = MAIN = %s): ' "$DEFAULT_BRANCH"
gui_read dest_branch
[ -n "$dest_branch" ] ||
dest_branch="$DEFAULT_BRANCH"
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/branches/$(urlencode "$dest_branch")" "" "$TMP_DIR/up-local-branch.json"
then
printf 'Branch de destino não encontrada: %s\n' "$dest_branch"
return 1
fi
printf 'Pasta de DESTINO no GitHub (ENTER para RAIZ): '
gui_read dest_folder
dest_folder=${dest_folder#/}
dest_folder=${dest_folder%/}
if [ -n "$dest_folder" ]
then
validate_remote_folder "$dest_folder" ||
{ printf 'Pasta de destino inválida.\n'; return 1; }
remote_path="$dest_folder/$file_name"
else
remote_path="$file_name"
fi
printf '\nLocal   : %s\n' "$local_path"
printf 'Destino : %s / %s / %s\n' "$dest_repo" "$dest_branch" "$remote_path"
printf 'Confirma o envio? (s/n): '
gui_read answer
case "$answer" in s|S|sim|SIM) ;;
*) printf 'Operação cancelada.\n'
return 0 ;;
esac
if ! base64 < "$local_path" | tr -d '\r\n' > "$TMP_DIR/upload-content.b64"
then
printf 'Erro ao codificar o arquivo.\n'
return 1
fi
chmod 0600 "$TMP_DIR/upload-content.b64" 2>/dev/null ||
true
path_encoded=$(urlencode_path "$remote_path") ||
return 1
http_code=$(curl -sS -o "$TMP_DIR/content.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$path_encoded?ref=$(urlencode "$dest_branch")") ||
http_code=000
sha=""
case "$http_code" in
200)
sha=$(jq -r '.sha // empty' "$TMP_DIR/content.json")
printf 'O arquivo remoto já existe. Atualizar? (s/n): '
gui_read answer
case "$answer" in s|S|sim|SIM) ;;
*) printf 'Remoto mantido. Envio cancelado.\n'
return 0 ;;
esac
[ -n "$sha" ] ||
{ printf 'SHA remoto indisponível.\n'; return 1; }
;;
404) ;;
*) printf 'Erro ao consultar remoto (HTTP %s).\n' "$http_code"
return 1 ;;
esac
if ! jq -n --arg message "Envio de $remote_path via GitHub Manager" \
--rawfile content "$TMP_DIR/upload-content.b64" --arg branch "$dest_branch" --arg sha "$sha" \
'{message:$message,content:($content|gsub("[\\r\\n]";"")),branch:$branch} + (if $sha != "" then {sha:$sha} else {} end)' \
> "$TMP_DIR/upload-payload.json"
then
printf 'Erro ao preparar o envio.\n'
return 1
fi
chmod 0600 "$TMP_DIR/upload-payload.json" 2>/dev/null ||
true
status=$(curl -sS -o "$TMP_DIR/upload.json" -w '%{http_code}' -X PUT \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" -H 'Content-Type: application/json' \
--data-binary "@$TMP_DIR/upload-payload.json" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$path_encoded") ||
status=000
case "$status" in
200|201)
if jq -e '.content.sha and .commit.sha' "$TMP_DIR/upload.json" >/dev/null 2>&1
then
printf 'Arquivo enviado: %s -> %s/%s/%s\n' "$file_name" "$dest_repo" "$dest_branch" "$remote_path"
else
printf 'A API não confirmou o envio.\n'
return 1
fi
;;
*) printf 'Falha no envio (HTTP %s).\n' "$status"
jq -r '.message // empty' "$TMP_DIR/upload.json" 2>/dev/null
return 1 ;;
esac
}
# CORREÇÃO CONTRATO: filtra lista para somente arquivos DIRETOS da pasta informada.
# RAIZ = somente caminhos sem "/". Pasta = somente caminhos "pasta/arquivo", sem subpasta.
filter_direct_files() {
local folder="$1" infile="$2"
local tmpf
tmpf="$TMP_DIR/direct-files.tmp"
if [ -n "$folder" ]
then
awk -v prefix="$folder/" 'index($0, prefix) == 1 && index(substr($0, length(prefix)+1), "/") == 0' "$infile" > "$tmpf"
else
awk 'index($0, "/") == 0' "$infile" > "$tmpf"
fi
cat "$tmpf" > "$infile"
}
delete_remote_file() {
local repo branch folder file_name path message sha payload answer tree_sha returned_path
local repo_encoded encoded_path candidate matched_path expected_path
ensure_login ||
return 1
printf '\n=== EXCLUIR ARQUIVO REMOTO ===\n'
printf 'Nome do repositório: '
gui_read repo
valid_name "$repo" ||
{ printf 'Nome de repositório inválido.\n'; return 1; }
repo_encoded=$(urlencode "$repo") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded" "" "$TMP_DIR/del-file-repo.json"
then return 1
fi
DEFAULT_BRANCH=$(jq -r '.default_branch // "main"' "$TMP_DIR/del-file-repo.json")
SELECTED_REPO="$repo"
printf 'Branch (ENTER para MAIN = %s): ' "$DEFAULT_BRANCH"
gui_read branch
[ -n "$branch" ] ||
branch="$DEFAULT_BRANCH"
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/branches/$(urlencode "$branch")" "" "$TMP_DIR/del-file-branch.json"
then
printf 'Branch não encontrada: %s\n' "$branch"
return 1
fi
printf 'Pasta (ENTER para RAIZ): '
gui_read folder
folder=${folder#/}
folder=${folder%/}
if [ -n "$folder" ]
then
validate_remote_folder "$folder" ||
{ printf 'Caminho de pasta inválido.\n'; return 1; }
fi
remote_file_paths "$repo" "$branch" "$folder" ||
return 1
filter_direct_files "$folder" "$TMP_DIR/remote-files-paths.txt"
if [ ! -s "$TMP_DIR/remote-files-paths.txt" ]
then
printf 'Nenhum arquivo encontrado nessa pasta/branch.\n'
return 1
fi
printf '\nArquivos na pasta "%s" (branch %s):\n' "${folder:-/}" "$branch"
cat "$TMP_DIR/remote-files-paths.txt"
printf '\nNome do arquivo a excluir (com extensão, sem caminho): '
gui_read file_name
is_safe_path_component "$file_name" ||
{ printf 'Informe somente o nome do arquivo, sem caminhos.\n'; return 1; }
if [ -n "$folder" ]
then
expected_path="$folder/$file_name"
else
expected_path="$file_name"
fi
matched_path=""
while IFS= read -r candidate
do
[ -n "$candidate" ] ||
continue
if [ "$candidate" = "$expected_path" ]
then matched_path="$candidate"
break
fi
done < "$TMP_DIR/remote-files-paths.txt"
if [ -z "$matched_path" ]
then
printf 'Arquivo "%s" não encontrado na pasta "%s".\n' "$file_name" "${folder:-/}"
return 1
fi
path="$matched_path"
encoded_path=$(urlencode_path "$path") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/contents/$encoded_path?ref=$(urlencode "$branch")" "" "$TMP_DIR/content.json"
then
return 1
fi
tree_sha=$(jq -r --arg p "$path" '.tree[]? | select(.type == "blob" and .path == $p) | .sha' "$TMP_DIR/remote-files-tree.json" 2>/dev/null)
[ -n "$tree_sha" ] ||
{ printf 'Não foi possível confirmar o arquivo "%s" na pasta escolhida.\n' "$path"; return 1; }
returned_path=$(jq -r '.path // empty' "$TMP_DIR/content.json")
[ "$returned_path" = "$path" ] ||
{ printf 'O caminho retornado (%s) não confere com o escolhido (%s). Exclusão cancelada.\n' "$returned_path" "$path"; return 1; }
sha="$tree_sha"
printf 'Mensagem do commit de exclusão: '
gui_read message
[ -n "$message" ] ||
message="Exclusão de $path via GitHub Manager"
printf '\nRepositório : %s\nBranch      : %s\nArquivo     : %s\n' "$repo" "$branch" "$path"
printf 'Confirma a exclusão? (s/n): '
gui_read answer
case "$answer" in s|S|sim|SIM) ;;
*) printf 'Operação cancelada.\n'
return 0 ;;
esac
payload=$(jq -n --arg message "$message" --arg sha "$sha" --arg branch "$branch" '{message:$message,sha:$sha,branch:$branch}')
if api DELETE "/repos/$GITHUB_USER/$repo_encoded/contents/$encoded_path" "$payload"
then
printf 'Arquivo excluído: %s\n' "$path"
fi
}
download_file() {
local repo branch folder file_name path
local repo_encoded encoded_path candidate matched_path expected_path
local local_dir local_path http_code answer
ensure_login ||
return 1
printf '\n=== BAIXAR ARQUIVO REMOTO ===\n'
printf 'Nome do repositório: '
gui_read repo
valid_name "$repo" ||
{ printf 'Nome de repositório inválido.\n'; return 1; }
repo_encoded=$(urlencode "$repo") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded" "" "$TMP_DIR/dl-repo.json"
then return 1
fi
DEFAULT_BRANCH=$(jq -r '.default_branch // "main"' "$TMP_DIR/dl-repo.json")
SELECTED_REPO="$repo"
printf 'Branch (ENTER para MAIN = %s): ' "$DEFAULT_BRANCH"
gui_read branch
[ -n "$branch" ] ||
branch="$DEFAULT_BRANCH"
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/branches/$(urlencode "$branch")" "" "$TMP_DIR/dl-branch.json"
then
printf 'Branch não encontrada: %s\n' "$branch"
return 1
fi
printf 'Pasta (ENTER para RAIZ): '
gui_read folder
folder=${folder#/}
folder=${folder%/}
if [ -n "$folder" ]
then
validate_remote_folder "$folder" ||
{ printf 'Caminho de pasta inválido.\n'; return 1; }
fi
remote_file_paths "$repo" "$branch" "$folder" ||
return 1
filter_direct_files "$folder" "$TMP_DIR/remote-files-paths.txt"
if [ ! -s "$TMP_DIR/remote-files-paths.txt" ]
then
printf 'Nenhum arquivo encontrado nessa pasta/branch.\n'
return 1
fi
printf '\nArquivos na pasta "%s" (branch %s):\n' "${folder:-/}" "$branch"
cat "$TMP_DIR/remote-files-paths.txt"
printf '\nNome do arquivo a baixar (com extensão, sem caminho): '
gui_read file_name
is_safe_path_component "$file_name" ||
{ printf 'Informe somente o nome do arquivo, sem caminhos.\n'; return 1; }
if [ -n "$folder" ]
then expected_path="$folder/$file_name"
else expected_path="$file_name"
fi
matched_path=""
while IFS= read -r candidate
do
[ -n "$candidate" ] ||
continue
if [ "$candidate" = "$expected_path" ]
then matched_path="$candidate"
break
fi
done < "$TMP_DIR/remote-files-paths.txt"
if [ -z "$matched_path" ]
then
printf 'Arquivo "%s" não encontrado na pasta "%s".\n' "$file_name" "${folder:-/}"
return 1
fi
path="$matched_path"
encoded_path=$(urlencode_path "$path") ||
return 1
local_dir="$(get_local_base_dir)" ||
return 1
local_path="$local_dir/$file_name"
if [ -e "$local_path" ]
then
printf 'Arquivo local já existe: %s. Sobrescrever? (s/n): ' "$local_path"
gui_read answer
case "$answer" in s|S|sim|SIM) ;;
*) printf 'Operação cancelada.\n'
return 0 ;;
esac
fi
http_code=$(curl -sS -o "$TMP_DIR/dl-content.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$encoded_path?ref=$(urlencode "$branch")") ||
http_code=000
if [ "$http_code" != 200 ]
then printf 'Falha ao baixar (HTTP %s).\n' "$http_code"
return 1
fi
if ! jq -r '.content // empty' "$TMP_DIR/dl-content.json" | tr -d '\r\n' | base64 -d > "$local_path"
then
printf 'Não foi possível decodificar o conteúdo remoto.\n'
return 1
fi
chmod 0600 "$local_path" 2>/dev/null ||
true
printf 'Arquivo baixado: %s -> %s\n' "$path" "$local_path"
}
urlencode_path() {
local remaining component encoded separator
remaining="$1"
encoded=""
separator=""
while :
do
case "$remaining" in
*/*) component="${remaining%%/*}"
remaining="${remaining#*/}" ;;
*) component="$remaining"
remaining="" ;;
esac
encoded="${encoded}${separator}$(urlencode "$component")" ||
return 1
separator="/"
[ -n "$remaining" ] ||
break
done
printf '%s' "$encoded"
}
validate_remote_folder() {
local folder remaining component
folder="$1"
[ -n "$folder" ] ||
return 1
has_control_chars "$folder" &&
return 1
case "$folder" in /*|*/|*//*|*\\*) return 1 ;;
esac
remaining="$folder"
while :
do
case "$remaining" in
*/*) component="${remaining%%/*}"
remaining="${remaining#*/}" ;;
*) component="$remaining"
remaining="" ;;
esac
case "$component" in ""|"."|"..") return 1 ;;
esac
[ -n "$remaining" ] ||
break
done
return 0
}
create_folder_main() {
local folder repo_encoded path_encoded content payload status existing_status
ensure_login ||
return 1
select_repository ||
return 1
PICK_REPO="$SELECTED_REPO"
PICK_BRANCH="$DEFAULT_BRANCH"
load_remote_tree ||
return 1
if [ "$(jq -r '.truncated // false' "$TMP_DIR/pick-tree.json")" = true ]; then
    printf 'Árvore truncada: operação cancelada por segurança.\n'; return 1
fi
printf '\n  Navegue até a pasta pai, use [N] para digitar o nome da nova pasta e [S] para confirmar.\n'
pick_remote_folder "CRIAR PASTA NA MAIN" 1 ||
{ printf 'Operação cancelada.\n'; return 0; }
folder="$PICK_REMOTE_DIR"
# Git não armazena diretórios vazios: verificar todo o prefixo, não só .gitkeep.
if jq -e --arg dir "$folder" --arg prefix "$folder/" '.tree[]? | select(.path == $dir or (.path | startswith($prefix)))' "$TMP_DIR/pick-tree.json" >/dev/null 2>&1; then
    printf 'A pasta já existe no repositório. Nenhuma alteração realizada.\n'
    return 0
fi
validate_remote_folder "$folder" ||
{
printf 'Caminho de pasta inválido. Exemplo: docs/guias\n'
return 1
}
repo_encoded=$(urlencode "$SELECTED_REPO") ||
return 1
path_encoded=$(urlencode_path "$folder/.gitkeep") ||
return 1
existing_status=$(curl -sS -o "$TMP_DIR/folder-main-existing.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$path_encoded?ref=$(urlencode "$DEFAULT_BRANCH")") ||
{
printf 'Falha de comunicação ao verificar a pasta.\n'
return 1
}
case "$existing_status" in
200)
printf 'A pasta %s já existe na MAIN PRINCIPAL. Nenhuma alteração realizada.\n' "$folder"
return 0
;;
404) ;;
*)
printf 'Falha ao verificar a pasta (HTTP %s).\n' "$existing_status"
jq -r '.message // empty' "$TMP_DIR/folder-main-existing.json" 2>/dev/null
return 1
;;
esac
commit_message_prompt "criação da pasta" || return 1
content=$(printf '%s' 'Pasta criada pelo GitHub Manager.' | base64 | tr -d '\r\n') ||
return 1
payload=$(jq -n \
--arg message "$GITMENU_COMMIT_MESSAGE" \
--arg content "$content" \
--arg branch "$DEFAULT_BRANCH" \
'{message:$message,content:$content,branch:$branch}') ||
return 1
status=$(curl -sS -o "$TMP_DIR/create-folder-main.json" -w '%{http_code}' \
-X PUT \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
-H 'Content-Type: application/json' \
--data-binary "$payload" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$path_encoded") ||
{
printf 'Falha de comunicação ao criar a pasta.\n'
return 1
}
case "$status" in
200|201)
printf 'Pasta criada na MAIN PRINCIPAL: %s (branch %s)\n' "$folder" "$DEFAULT_BRANCH"
;;
*)
printf 'Falha ao criar pasta (HTTP %s).\n' "$status"
jq -r '.message // empty' "$TMP_DIR/create-folder-main.json" 2>/dev/null
return 1
;;
esac
}
delete_folder_main() {
local folder repo_encoded tree_status path encoded_path content_sha payload status confirm
ensure_login ||
return 1
select_repository ||
return 1
printf 'Caminho da pasta a deletar na MAIN PRINCIPAL: '
gui_read folder
folder=${folder#/}
folder=${folder%/}
validate_remote_folder "$folder" ||
{
printf 'Caminho de pasta inválido. Exemplo: docs/guias\n'
return 1
}
repo_encoded=$(urlencode "$SELECTED_REPO") ||
return 1
tree_status=$(curl -sS -o "$TMP_DIR/delete-folder-tree.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/git/trees/$(urlencode "$DEFAULT_BRANCH")?recursive=1") ||
{
printf 'Falha ao consultar a árvore do repositório.\n'
return 1
}
[ "$tree_status" = 200 ] ||
{
printf 'Falha ao consultar a árvore (HTTP %s).\n' "$tree_status"
jq -r '.message // empty' "$TMP_DIR/delete-folder-tree.json" 2>/dev/null
return 1
}
jq -r --arg prefix "$folder/" '.tree[]? | select(.type == "blob" and (.path | startswith($prefix)) and ((.path | ltrimstr($prefix)) | test("^[^/]+$"))) | .path' \
"$TMP_DIR/delete-folder-tree.json" > "$TMP_DIR/delete-folder-files.txt"
if [ ! -s "$TMP_DIR/delete-folder-files.txt" ]
then
printf 'Nenhum arquivo encontrado na pasta "%s" na MAIN PRINCIPAL.\n' "$folder"
return 1
fi
printf '\nArquivos que serão excluídos da pasta "%s":\n' "$folder"
cat "$TMP_DIR/delete-folder-files.txt"
printf '\nDigite DELETAR para confirmar a exclusão de todos esses arquivos: '
gui_read confirm
[ "$confirm" = DELETAR ] ||
{
printf 'Operação cancelada.\n'
return 0
}
while IFS= read -r path
do
[ -n "$path" ] ||
continue
encoded_path=$(urlencode_path "$path") ||
return 1
status=$(curl -sS -o "$TMP_DIR/delete-folder-content.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$encoded_path?ref=$(urlencode "$DEFAULT_BRANCH")") ||
{
printf 'Falha de comunicação ao consultar: %s\n' "$path"
return 1
}
[ "$status" = 200 ] ||
{
printf 'Falha ao consultar "%s" (HTTP %s). Interrompendo.\n' "$path" "$status"
jq -r '.message // empty' "$TMP_DIR/delete-folder-content.json" 2>/dev/null
return 1
}
content_sha=$(jq -r '.sha // empty' "$TMP_DIR/delete-folder-content.json")
[ -n "$content_sha" ] ||
{
printf 'Não foi possível obter o SHA de: %s\n' "$path"
return 1
}
payload=$(jq -n --arg message "Excluir $path da MAIN via GitHub Manager" --arg sha "$content_sha" --arg branch "$DEFAULT_BRANCH" '{message:$message,sha:$sha,branch:$branch}') ||
return 1
status=$(curl -sS -o "$TMP_DIR/delete-folder-result.json" -w '%{http_code}' \
-X DELETE \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
-H 'Content-Type: application/json' \
--data-binary "$payload" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$encoded_path") ||
{
printf 'Falha de comunicação ao excluir: %s\n' "$path"
return 1
}
case "$status" in
200) printf 'Excluído: %s\n' "$path" ;;
*)
printf 'Falha ao excluir "%s" (HTTP %s). Interrompendo.\n' "$path" "$status"
jq -r '.message // empty' "$TMP_DIR/delete-folder-result.json" 2>/dev/null
return 1
;;
esac
done < "$TMP_DIR/delete-folder-files.txt"
printf '\nConteúdo da pasta "%s" excluído da MAIN PRINCIPAL.\n' "$folder"
printf 'Observação: o GitHub não armazena diretórios vazios; a pasta deixa de aparecer\n'
printf 'quando todos os arquivos são removidos.\n'
}
create_secondary_branch() {
local branch_name repo_encoded payload check_status empty_tree_sha new_commit_sha
ensure_login || return 1
select_repository || return 1
printf '\nNome da nova BRANCH secundária: '
gui_read branch_name
[ -n "$branch_name" ] && [ "$branch_name" != "$DEFAULT_BRANCH" ] || { printf 'Nome de branch inválido.\n'; return 1; }
if command -v git >/dev/null 2>&1; then
    git check-ref-format "refs/heads/$branch_name" >/dev/null 2>&1 || { printf 'Nome de branch inválido.\n'; return 1; }
else
    case "$branch_name" in ''|.|..|*' '*|*'..'*|*'~'*|*'^'*|*':'*|*'?'*|*'['*|*'\'*|*'@{'*|/*|*/|*//*) printf 'Nome de branch inválido.\n'; return 1 ;; esac
fi
repo_encoded=$(urlencode "$SELECTED_REPO") || return 1
check_status=$(curl -sS -o "$TMP_DIR/branch-new-check.json" -w '%{http_code}' \
  -H 'Accept: application/vnd.github+json' \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: $API_VERSION" \
  "$API_URL/repos/$GITHUB_USER/$repo_encoded/git/ref/heads/$(urlencode_path "$branch_name")") || {
    printf 'Falha de comunicação ao verificar a nova branch.\n'; return 1;
}
case "$check_status" in
  404) ;;
  200) printf 'A branch já existe; nenhuma alteração realizada.\n'; return 1 ;;
  *) printf 'Falha ao consultar a branch (HTTP %s).\n' "$check_status"; return 1 ;;
esac
ui_heading 'CONFERÊNCIA — CRIAR BRANCH SECUNDÁRIA'
draw_block 'NOVA BRANCH' "Repositório|$SELECTED_REPO" "Principal preservada|$DEFAULT_BRANCH" "Nova branch|$branch_name" 'Conteúdo|Branch independente, sem arquivos da principal' 'Histórico|Novo commit raiz, sem pais'
ask_yes_no 'Confirma a criação?' || { cancelled; return 0; }
# Uma branch no GitHub exige um commit inicial. Criar árvore vazia e commit raiz
# sem pais evita herdar arquivos e histórico da branch principal.
payload='{"tree":[]}'
api POST "/repos/$GITHUB_USER/$repo_encoded/git/trees" "$payload" "$TMP_DIR/branch-empty-tree.json" || return 1
empty_tree_sha=$(jq -r '.sha // empty' "$TMP_DIR/branch-empty-tree.json")
[[ "$empty_tree_sha" =~ ^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$ ]] || { printf 'SHA da árvore vazia inválido.\n'; return 1; }
payload=$(jq -n --arg message "Criar branch secundária vazia: $branch_name" --arg tree "$empty_tree_sha" '{message:$message,tree:$tree,parents:[]}') || return 1
api POST "/repos/$GITHUB_USER/$repo_encoded/git/commits" "$payload" "$TMP_DIR/branch-root-commit.json" || return 1
new_commit_sha=$(jq -r '.sha // empty' "$TMP_DIR/branch-root-commit.json")
[[ "$new_commit_sha" =~ ^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$ ]] || { printf 'SHA do commit inicial inválido.\n'; return 1; }
payload=$(jq -n --arg ref "refs/heads/$branch_name" --arg sha "$new_commit_sha" '{ref:$ref,sha:$sha}') || return 1
api POST "/repos/$GITHUB_USER/$repo_encoded/git/refs" "$payload" "$TMP_DIR/new-branch.json" || { printf 'Falha ao publicar a branch secundária. Nenhuma referência nova foi confirmada.\n'; return 1; }
draw_block 'BRANCH SECUNDÁRIA CRIADA' "Repositório|$SELECTED_REPO" "Branch|$branch_name" "Commit inicial|$new_commit_sha" 'Conteúdo|Vazio; MAIN preservada'
}

delete_secondary_branch() {
local branch_name repo_encoded branch_encoded confirm status
ensure_login ||
return 1
select_repository secondary ||
return 1
printf '\nBRANCH PRINCIPAL protegida: %s\n' "$DEFAULT_BRANCH"
pick_branch secondary ||
{ printf 'Operação cancelada.\n'; return 0; }
branch_name="$PICK_BRANCH"
if [ "$branch_name" = "$DEFAULT_BRANCH" ]
then
printf 'Operação bloqueada: não é permitido deletar a BRANCH PRINCIPAL.\n'
return 1
fi
repo_encoded=$(urlencode "$SELECTED_REPO") ||
return 1
branch_encoded=$(urlencode "$branch_name") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/branches/$branch_encoded" "" "$TMP_DIR/branch-to-delete.json"
then
printf 'A branch informada não foi localizada ou não pode ser consultada.\n'
return 1
fi
printf '\nRepositório : %s\n' "$SELECTED_REPO"
printf 'Branch      : %s\n' "$branch_name"
printf 'Digite DELETAR para confirmar: '
gui_read confirm
[ "$confirm" = DELETAR ] ||
{
printf 'Operação cancelada.\n'
return 0
}
status=$(curl -sS -o "$TMP_DIR/delete-secondary-branch.json" -w '%{http_code}' \
-X DELETE \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/git/refs/heads/$branch_encoded") ||
{
printf 'Falha de comunicação ao deletar a branch.\n'
return 1
}
case "$status" in
204) printf 'BRANCH secundária "%s" deletada com sucesso.\n' "$branch_name" ;;
*)
printf 'Falha ao deletar a branch (HTTP %s).\n' "$status"
jq -r '.message // empty' "$TMP_DIR/delete-secondary-branch.json" 2>/dev/null
return 1
;;
esac
}
rename_secondary_branch() {
local old_branch new_branch repo_encoded old_ref_encoded new_ref_encoded sha payload confirm status
ensure_login ||
return 1
select_repository secondary ||
return 1
printf '\nBRANCH PRINCIPAL protegida: %s\n' "$DEFAULT_BRANCH"
pick_branch secondary ||
{ printf 'Operação cancelada.\n'; return 0; }
old_branch="$PICK_BRANCH"
if [ "$old_branch" = "$DEFAULT_BRANCH" ]
then
printf 'Operação bloqueada: não é permitido renomear a BRANCH PRINCIPAL.\n'
return 1
fi
printf 'Novo nome da BRANCH secundária: '
gui_read new_branch
[ -n "$new_branch" ] ||
{
printf 'Novo nome de branch inválido.\n'
return 1
}
[ "$old_branch" != "$new_branch" ] ||
{
printf 'O nome novo é igual ao nome atual. Nenhuma alteração realizada.\n'
return 1
}
if [ "$new_branch" = "$DEFAULT_BRANCH" ]
then
printf 'O novo nome não pode ser o da BRANCH PRINCIPAL.\n'
return 1
fi
if command -v git >/dev/null 2>&1 &&
! git check-ref-format "refs/heads/$new_branch" >/dev/null 2>&1
then
printf 'Novo nome de branch inválido segundo as regras do Git.\n'
return 1
fi
repo_encoded=$(urlencode "$SELECTED_REPO") ||
return 1
old_ref_encoded=$(urlencode_path "$old_branch") ||
return 1
new_ref_encoded=$(urlencode_path "$new_branch") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/git/ref/heads/$old_ref_encoded" "" "$TMP_DIR/rename-branch-old-ref.json"
then
printf 'A BRANCH atual não foi localizada.\n'
return 1
fi
sha=$(jq -r '.object.sha // empty' "$TMP_DIR/rename-branch-old-ref.json")
[ -n "$sha" ] ||
{
printf 'Não foi possível obter o commit da BRANCH atual.\n'
return 1
}
status=$(curl -sS -o "$TMP_DIR/rename-branch-new-check.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/git/ref/heads/$new_ref_encoded") ||
{
printf 'Falha ao verificar o novo nome da BRANCH.\n'
return 1
}
case "$status" in
200)
printf 'Já existe uma BRANCH chamada "%s".\n' "$new_branch"
return 1
;;
404) ;;
*)
printf 'Falha ao verificar o novo nome (HTTP %s).\n' "$status"
jq -r '.message // empty' "$TMP_DIR/rename-branch-new-check.json" 2>/dev/null
return 1
;;
esac
printf '\nRepositório : %s\n' "$SELECTED_REPO"
printf 'BRANCH atual: %s\n' "$old_branch"
printf 'Novo nome   : %s\n' "$new_branch"
printf 'A renomeação usará a API oficial de renomeação de branches.\n'
printf 'Digite RENOMEAR para confirmar: '
gui_read confirm
[ "$confirm" = RENOMEAR ] || { printf 'Operação cancelada.\n'; return 0; }
payload=$(jq -n --arg new_name "$new_branch" '{new_name:$new_name}') || return 1
status=$(curl -sS -o "$TMP_DIR/rename-branch-result.json" -w '%{http_code}' \
  -X POST -H 'Accept: application/vnd.github+json' \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: $API_VERSION" \
  -H 'Content-Type: application/json' --data-binary "$payload" \
  "$API_URL/repos/$GITHUB_USER/$repo_encoded/branches/$old_ref_encoded/rename") || {
  printf 'Falha de comunicação ao renomear a branch; consulte o GitHub antes de repetir.\n'; return 1;
}
case "$status" in
  201) printf 'BRANCH renomeada: %s -> %s\n' "$old_branch" "$new_branch" ;;
  *) printf 'Renomeação não confirmada (HTTP %s).\n' "$status"
     jq -r '.message // empty' "$TMP_DIR/rename-branch-result.json" 2>/dev/null
     return 1 ;;
esac
}
create_folder_secondary_branch() {
local branch_name folder repo_encoded path_encoded content payload status existing_status
ensure_login ||
return 1
select_repository secondary ||
return 1
pick_branch secondary ||
{ printf 'Operação cancelada.\n'; return 0; }
branch_name="$PICK_BRANCH"
if [ "$branch_name" = "$DEFAULT_BRANCH" ]
then
printf 'Informe uma branch secundária, não a MAIN PRINCIPAL.\n'
return 1
fi
repo_encoded=$(urlencode "$SELECTED_REPO") ||
return 1
if ! api GET \
"/repos/$GITHUB_USER/$repo_encoded/branches/$(urlencode "$branch_name")" \
"" "$TMP_DIR/secondary-branch.json"
then
return 1
fi
PICK_REPO="$SELECTED_REPO"
PICK_BRANCH="$branch_name"
load_remote_tree ||
return 1
if [ "$(jq -r '.truncated // false' "$TMP_DIR/pick-tree.json")" = true ]; then
    printf 'Árvore truncada: operação cancelada por segurança.\n'; return 1
fi
printf '\n  Navegue até a pasta pai, use [N] para digitar o nome da nova pasta e [S] para confirmar.\n'
pick_remote_folder "CRIAR PASTA NA BRANCH" 1 ||
{ printf 'Operação cancelada.\n'; return 0; }
folder="$PICK_REMOTE_DIR"
# Git não armazena diretórios vazios: verificar todo o prefixo, não só .gitkeep.
if jq -e --arg dir "$folder" --arg prefix "$folder/" '.tree[]? | select(.path == $dir or (.path | startswith($prefix)))' "$TMP_DIR/pick-tree.json" >/dev/null 2>&1; then
    printf 'A pasta já existe no repositório. Nenhuma alteração realizada.\n'
    return 0
fi
validate_remote_folder "$folder" ||
{
printf 'Caminho de pasta inválido. Exemplo: docs/guias\n'
return 1
}
path_encoded=$(urlencode_path "$folder/.gitkeep") ||
return 1
existing_status=$(curl -sS -o "$TMP_DIR/folder-branch-existing.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$path_encoded?ref=$(urlencode "$branch_name")") ||
{
printf 'Falha de comunicação ao verificar a pasta.\n'
return 1
}
case "$existing_status" in
200)
printf 'A pasta %s já existe na BRANCH %s. Nenhuma alteração realizada.\n' "$folder" "$branch_name"
return 0
;;
404) ;;
*)
printf 'Falha ao verificar a pasta (HTTP %s).\n' "$existing_status"
jq -r '.message // empty' "$TMP_DIR/folder-branch-existing.json" 2>/dev/null
return 1
;;
esac
commit_message_prompt "criação da pasta" || return 1
content=$(printf '%s' 'Pasta criada pelo GitHub Manager.' | base64 | tr -d '\r\n') ||
return 1
payload=$(jq -n \
--arg message "$GITMENU_COMMIT_MESSAGE" \
--arg content "$content" \
--arg branch "$branch_name" \
'{message:$message,content:$content,branch:$branch}') ||
return 1
status=$(curl -sS -o "$TMP_DIR/create-folder-branch.json" -w '%{http_code}' \
-X PUT \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
-H 'Content-Type: application/json' \
--data-binary "$payload" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$path_encoded") ||
{
printf 'Falha de comunicação ao criar a pasta.\n'
return 1
}
case "$status" in
200|201)
printf 'Pasta criada na BRANCH secundária: %s (branch %s)\n' "$folder" "$branch_name"
;;
*)
printf 'Falha ao criar pasta (HTTP %s).\n' "$status"
jq -r '.message // empty' "$TMP_DIR/create-folder-branch.json" 2>/dev/null
return 1
;;
esac
}
delete_folder_secondary_branch() {
local branch_name folder repo_encoded tree_status path encoded_path content_sha payload status confirm
ensure_login ||
return 1
select_repository secondary ||
return 1
pick_branch secondary ||
{ printf 'Operação cancelada.\n'; return 0; }
branch_name="$PICK_BRANCH"
if [ "$branch_name" = "$DEFAULT_BRANCH" ]
then
printf 'Operação bloqueada: informe uma BRANCH secundária, não a MAIN PRINCIPAL.\n'
return 1
fi
repo_encoded=$(urlencode "$SELECTED_REPO") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/branches/$(urlencode "$branch_name")" "" "$TMP_DIR/secondary-branch-to-delete-folder.json"
then
printf 'A BRANCH secundária informada não foi localizada ou não pode ser consultada.\n'
return 1
fi
printf 'Caminho da pasta a deletar na BRANCH secundária: '
gui_read folder
folder=${folder#/}
folder=${folder%/}
validate_remote_folder "$folder" ||
{
printf 'Caminho de pasta inválido. Exemplo: docs/guias\n'
return 1
}
tree_status=$(curl -sS -o "$TMP_DIR/delete-folder-branch-tree.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/git/trees/$(urlencode "$branch_name")?recursive=1") ||
{
printf 'Falha ao consultar a árvore da BRANCH secundária.\n'
return 1
}
[ "$tree_status" = 200 ] ||
{
printf 'Falha ao consultar a árvore da BRANCH (HTTP %s).\n' "$tree_status"
jq -r '.message // empty' "$TMP_DIR/delete-folder-branch-tree.json" 2>/dev/null
return 1
}
jq -r --arg prefix "$folder/" '.tree[]? | select(.type == "blob" and (.path | startswith($prefix)) and ((.path | ltrimstr($prefix)) | test("^[^/]+$"))) | .path' \
"$TMP_DIR/delete-folder-branch-tree.json" > "$TMP_DIR/delete-folder-branch-files.txt"
if [ ! -s "$TMP_DIR/delete-folder-branch-files.txt" ]
then
printf 'Nenhum arquivo encontrado na pasta "%s" na BRANCH "%s".\n' "$folder" "$branch_name"
return 1
fi
printf '\nRepositório     : %s\n' "$SELECTED_REPO"
printf 'Branch           : %s\n' "$branch_name"
printf 'Arquivos que serão excluídos da pasta "%s":\n' "$folder"
cat "$TMP_DIR/delete-folder-branch-files.txt"
printf '\nDigite DELETAR para confirmar a exclusão de todos esses arquivos: '
gui_read confirm
[ "$confirm" = DELETAR ] ||
{
printf 'Operação cancelada.\n'
return 0
}
while IFS= read -r path
do
[ -n "$path" ] ||
continue
encoded_path=$(urlencode_path "$path") ||
return 1
status=$(curl -sS -o "$TMP_DIR/delete-folder-branch-content.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$encoded_path?ref=$(urlencode "$branch_name")") ||
{
printf 'Falha de comunicação ao consultar: %s\n' "$path"
return 1
}
[ "$status" = 200 ] ||
{
printf 'Falha ao consultar "%s" (HTTP %s). Interrompendo.\n' "$path" "$status"
jq -r '.message // empty' "$TMP_DIR/delete-folder-branch-content.json" 2>/dev/null
return 1
}
content_sha=$(jq -r '.sha // empty' "$TMP_DIR/delete-folder-branch-content.json")
[ -n "$content_sha" ] ||
{
printf 'Não foi possível obter o SHA de: %s\n' "$path"
return 1
}
payload=$(jq -n --arg message "Excluir $path da BRANCH $branch_name via GitHub Manager" --arg sha "$content_sha" --arg branch "$branch_name" '{message:$message,sha:$sha,branch:$branch}') ||
return 1
status=$(curl -sS -o "$TMP_DIR/delete-folder-branch-result.json" -w '%{http_code}' \
-X DELETE \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
-H 'Content-Type: application/json' \
--data-binary "$payload" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$encoded_path") ||
{
printf 'Falha de comunicação ao excluir: %s\n' "$path"
return 1
}
case "$status" in
200) printf 'Excluído: %s\n' "$path" ;;
*)
printf 'Falha ao excluir "%s" (HTTP %s). Interrompendo.\n' "$path" "$status"
jq -r '.message // empty' "$TMP_DIR/delete-folder-branch-result.json" 2>/dev/null
return 1
;;
esac
done < "$TMP_DIR/delete-folder-branch-files.txt"
printf '\nConteúdo da pasta "%s" excluído da BRANCH "%s".\n' "$folder" "$branch_name"
printf 'Observação: o GitHub não armazena diretórios vazios; a pasta deixa de aparecer\n'
printf 'quando todos os arquivos são removidos.\n'
}
rename_folder_secondary_branch() {
local branch_name old_folder new_folder repo_encoded branch_ref_encoded branch_sha commit_tree_sha tree_status
local old_prefix new_prefix confirm payload new_tree_sha new_commit_sha update_status
local repo
ensure_login ||
return 1
printf '\n=== RENOMEAR PASTA ===\n'
printf 'Nome do repositório: '
gui_read repo
valid_name "$repo" ||
{ printf 'Nome de repositório inválido.\n'; return 1; }
repo_encoded=$(urlencode "$repo") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded" "" "$TMP_DIR/rename-folder-repo.json"
then return 1
fi
DEFAULT_BRANCH=$(jq -r '.default_branch // "main"' "$TMP_DIR/rename-folder-repo.json")
SELECTED_REPO="$repo"
printf 'Branch (ENTER para MAIN = %s): ' "$DEFAULT_BRANCH"
gui_read branch_name
[ -n "$branch_name" ] ||
branch_name="$DEFAULT_BRANCH"
branch_ref_encoded=$(urlencode_path "$branch_name") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/git/ref/heads/$branch_ref_encoded" "" "$TMP_DIR/rename-folder-branch-ref.json"
then
printf 'A branch não foi localizada: %s\n' "$branch_name"
return 1
fi
branch_sha=$(jq -r '.object.sha // empty' "$TMP_DIR/rename-folder-branch-ref.json")
[ -n "$branch_sha" ] ||
{
printf 'Não foi possível obter o commit da BRANCH.\n'
return 1
}
printf 'Caminho atual da pasta: '
gui_read old_folder
old_folder=${old_folder#/}
old_folder=${old_folder%/}
validate_remote_folder "$old_folder" ||
{
printf 'Caminho atual inválido. Exemplo: docs/guias\n'
return 1
}
printf 'Novo caminho da pasta: '
gui_read new_folder
new_folder=${new_folder#/}
new_folder=${new_folder%/}
validate_remote_folder "$new_folder" ||
{
printf 'Novo caminho inválido. Exemplo: docs/manuais\n'
return 1
}
[ "$old_folder" != "$new_folder" ] ||
{
printf 'O caminho novo é igual ao atual. Nenhuma alteração realizada.\n'
return 1
}
old_prefix="$old_folder/"
new_prefix="$new_folder/"
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/git/commits/$branch_sha" "" "$TMP_DIR/rename-folder-commit.json"
then
return 1
fi
commit_tree_sha=$(jq -r '.tree.sha // empty' "$TMP_DIR/rename-folder-commit.json")
[ -n "$commit_tree_sha" ] ||
{
printf 'Não foi possível obter a árvore da BRANCH.\n'
return 1
}
tree_status=$(curl -sS -o "$TMP_DIR/rename-folder-tree.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/git/trees/$commit_tree_sha?recursive=1") ||
{
printf 'Falha ao consultar a árvore da BRANCH.\n'
return 1
}
[ "$tree_status" = 200 ] ||
{
printf 'Falha ao consultar a árvore (HTTP %s).\n' "$tree_status"
jq -r '.message // empty' "$TMP_DIR/rename-folder-tree.json" 2>/dev/null
return 1
}
if [ "$(jq -r '.truncated // false' "$TMP_DIR/rename-folder-tree.json")" = true ]
then
printf 'A árvore do repositório foi truncada pela API. Renomeação cancelada para evitar\n'
printf 'alterações incompletas.\n'
return 1
fi
if ! jq -e --arg prefix "$old_prefix" '.tree[]? | select(.type == "blob" and (.path | startswith($prefix)))' \
"$TMP_DIR/rename-folder-tree.json" >/dev/null 2>&1
then
printf 'A pasta atual não contém arquivos ou não foi encontrada: %s\n' "$old_folder"
return 1
fi
if jq -e --arg prefix "$new_prefix" --arg exact "$new_folder" \
'.tree[]? | select(.path == $exact or (.path | startswith($prefix)))' \
"$TMP_DIR/rename-folder-tree.json" >/dev/null 2>&1
then
printf 'O destino já existe: %s. Renomeação cancelada para evitar sobrescrita.\n' "$new_folder"
return 1
fi
printf '\nRepositório     : %s\n' "$SELECTED_REPO"
printf 'BRANCH secundária: %s\n' "$branch_name"
printf 'Pasta atual     : %s\n' "$old_folder"
printf 'Novo caminho    : %s\n' "$new_folder"
printf 'Arquivos que serão movidos:\n'
jq -r --arg prefix "$old_prefix" '.tree[]? | select(.type == "blob" and (.path | startswith($prefix))) | .path' \
"$TMP_DIR/rename-folder-tree.json"
printf '\nDigite RENOMEAR para confirmar: '
gui_read confirm
[ "$confirm" = RENOMEAR ] ||
{
printf 'Operação cancelada.\n'
return 0
}
payload=$(jq -c --arg old_prefix "$old_prefix" --arg new_prefix "$new_prefix" --arg base_tree "$commit_tree_sha" '
{base_tree:$base_tree,tree:[
(.tree[]? | select(.type == "blob" and (.path | startswith($old_prefix))) |
{path:( $new_prefix + (.path | ltrimstr($old_prefix))),mode:.mode,type:"blob",sha:.sha}),
(.tree[]? | select(.type == "blob" and (.path | startswith($old_prefix))) |
{path:.path,mode:.mode,type:"blob",sha:null})
]}
' "$TMP_DIR/rename-folder-tree.json") || {
printf 'Não foi possível preparar a árvore da renomeação.\n'
return 1
}
if ! api POST "/repos/$GITHUB_USER/$repo_encoded/git/trees" "$payload" "$TMP_DIR/rename-folder-new-tree.json"
then
printf 'Não foi possível criar a nova árvore. A BRANCH não foi alterada.\n'
return 1
fi
# A árvore criada deve conter exatamente o número de arquivos movidos.
# Nenhuma referência da branch é atualizada antes da confirmação final.
new_tree_sha=$(jq -r '.sha // empty' "$TMP_DIR/rename-folder-new-tree.json")
[ -n "$new_tree_sha" ] ||
{
printf 'A API não retornou o SHA da nova árvore.\n'
return 1
}
payload=$(jq -n \
--arg message "Renomear pasta $old_folder para $new_folder" \
--arg tree "$new_tree_sha" \
--arg parent "$branch_sha" \
'{message:$message,tree:$tree,parents:[$parent]}') ||
return 1
if ! api POST "/repos/$GITHUB_USER/$repo_encoded/git/commits" "$payload" "$TMP_DIR/rename-folder-new-commit.json"
then
printf 'Não foi possível criar o commit. A BRANCH não foi alterada.\n'
return 1
fi
new_commit_sha=$(jq -r '.sha // empty' "$TMP_DIR/rename-folder-new-commit.json")
[ -n "$new_commit_sha" ] ||
{
printf 'A API não retornou o SHA do novo commit.\n'
return 1
}
payload=$(jq -n --arg sha "$new_commit_sha" '{sha:$sha,force:false}') ||
return 1
update_status=$(curl -sS -o "$TMP_DIR/rename-folder-update-ref.json" -w '%{http_code}' \
-X PATCH \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
-H 'Content-Type: application/json' \
--data-binary "$payload" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/git/refs/heads/$branch_ref_encoded") ||
{
printf 'Falha de comunicação ao atualizar a BRANCH.\n'
return 1
}
case "$update_status" in
200)
printf 'Pasta renomeada com sucesso: %s -> %s (BRANCH: %s)\n' "$old_folder" "$new_folder" "$branch_name"
printf 'Os arquivos e subpastas foram preservados no novo caminho.\n'
;;
*)
printf 'Falha ao atualizar a BRANCH (HTTP %s). A árvore e o commit foram preparados,\n' "$update_status"
printf 'mas a BRANCH não foi atualizada.\n'
jq -r '.message // empty' "$TMP_DIR/rename-folder-update-ref.json" 2>/dev/null
return 1
;;
esac
}
print_centered_report() {
local LC_ALL=C.UTF-8
local report_file="$TMP_DIR/compare-report.txt" cols max_w pad line
[ -s "$report_file" ] ||
return 0
cols=$(tput cols 2>/dev/null || echo 120)
[[ "$cols" =~ ^[0-9]+$ ]] ||
cols=120
max_w=0
while IFS= read -r line ||
[ -n "$line" ]
do
[ "${#line}" -gt "$max_w" ] &&
max_w=${#line}
done < "$report_file"
pad=$(( (cols - max_w) / 2 ))
[ "$pad" -lt 0 ] &&
pad=0
while IFS= read -r line ||
[ -n "$line" ]
do
if [ -z "$line" ]
then
printf '\n'
else
printf '%*s%s\n' "$pad" '' "$line"
fi
done < "$report_file"
}
compare_local_remote_file() {
local file local_path local_date page count repo default_branch branch path
local match_count selected_repo selected_branch selected_path encoded_repo encoded_path
local remote_date remote_sha http_code temp_remote local_dir diff_status
ensure_login ||
return 1
local_dir="$(get_local_base_dir)" ||
return 1
printf '\n=== COMPARAR ARQUIVO LOCAL COM REMOTO NO GITHUB ===\n'
printf 'Diretório local configurado: %s\n' "$local_dir"
printf 'Nome do arquivo local: '
gui_read file
is_safe_path_component "$file" ||
{
printf 'Erro: informe somente o nome do arquivo, sem caminhos.\n'
return 1
}
local_path="$local_dir/$file"
if [[ ! -f "$local_path" || -L "$local_path" || ! -r "$local_path" ]]
then
printf 'Erro: arquivo local inexistente, inválido ou sem permissão de leitura: %s\n' "$local_path"
return 1
fi
if ! command -v diff >/dev/null 2>&1 ||
! command -v cmp >/dev/null 2>&1
then
printf 'Erro: os comandos diff e cmp são necessários.\n'
return 1
fi
local_date=$(stat -c '%y' "$local_path" 2>/dev/null || stat -f '%Sm' "$local_path" 2>/dev/null || printf 'indisponível')
: > "$TMP_DIR/compare-report.txt"
: > "$TMP_DIR/compare-matches.tsv"
page=1
while :
do
if ! api GET "/user/repos?affiliation=owner&per_page=100&page=$page&sort=full_name" "" "$TMP_DIR/compare-repos.json"
then
return 1
fi
count=$(jq 'length' "$TMP_DIR/compare-repos.json" 2>/dev/null)
case "$count" in ''|*[!0-9]*) printf 'Resposta inválida da API ao listar repositórios.\n'
return 1 ;;
esac
[ "$count" -gt 0 ] ||
break
while IFS="$(printf '\t')" read -r repo default_branch
do
[ -n "$repo" ] ||
continue
if ! api GET "/repos/$GITHUB_USER/$(urlencode "$repo")/branches?per_page=100" "" "$TMP_DIR/compare-branches.json"
then
continue
fi
while IFS= read -r branch
do
[ -n "$branch" ] ||
continue
if ! api GET "/repos/$GITHUB_USER/$(urlencode "$repo")/git/trees/$(urlencode "$branch")?recursive=1" "" "$TMP_DIR/compare-tree.json"
then
continue
fi
jq -r --arg file "$file" --arg repo "$repo" --arg branch "$branch" '
.tree[]? | select(.type == "blob") | select((.path | split("/") | last) == $file) | [$repo,$branch,.path] | @tsv
' "$TMP_DIR/compare-tree.json" >> "$TMP_DIR/compare-matches.tsv"
done < <(jq -r '.[].name' "$TMP_DIR/compare-branches.json" 2>/dev/null)
done < <(jq -r '.[] | [.name,.default_branch] | @tsv' "$TMP_DIR/compare-repos.json")
[ "$count" -lt 100 ] &&
break
page=$((page + 1))
done
match_count=$(wc -l < "$TMP_DIR/compare-matches.tsv" | tr -d ' ')
if [ "$match_count" -eq 0 ]
then
printf '\nArquivo remoto não encontrado no GitHub: %s\n' "$file"
return 1
fi
IFS="$(printf '\t')" read -r selected_repo selected_branch selected_path < "$TMP_DIR/compare-matches.tsv"
if [ "$match_count" -gt 1 ]
then
printf '\nAVISO: foram encontrados %s arquivos remotos com esse nome.\n' "$match_count" >> "$TMP_DIR/compare-report.txt"
printf 'Será comparada a primeira correspondência abaixo; resultados encontrados:\n' >> "$TMP_DIR/compare-report.txt"
while IFS="$(printf '\t')" read -r repo branch path
do
printf '  %s | branch: %s | caminho: %s\n' "$repo" "$branch" "$path" >> "$TMP_DIR/compare-report.txt"
done < "$TMP_DIR/compare-matches.tsv"
fi
encoded_repo=$(urlencode "$selected_repo") ||
return 1
encoded_path=$(urlencode_path "$selected_path") ||
return 1
http_code=$(curl -sS -o "$TMP_DIR/compare-content.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' \
-H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$encoded_repo/contents/$encoded_path?ref=$(urlencode "$selected_branch")") ||
return 1
if [ "$http_code" != 200 ]
then
printf 'Erro ao baixar arquivo remoto (HTTP %s).\n' "$http_code"
jq -r '.message // empty' "$TMP_DIR/compare-content.json" 2>/dev/null
return 1
fi
if [ "$(jq -r '.type // empty' "$TMP_DIR/compare-content.json")" != "file" ]
then
printf 'O resultado remoto não é um arquivo.\n'
return 1
fi
temp_remote="$TMP_DIR/remote-file"
if ! jq -r '.content // empty' "$TMP_DIR/compare-content.json" | tr -d '\n' | base64 -d > "$temp_remote"
then
printf 'Não foi possível decodificar o conteúdo remoto.\n'
return 1
fi
chmod 0600 "$temp_remote" 2>/dev/null ||
true
remote_date=$(api GET "/repos/$GITHUB_USER/$encoded_repo/commits?path=$encoded_path&sha=$(urlencode "$selected_branch")&per_page=1" "" "$TMP_DIR/compare-commits.json" && jq -r '.[0].commit.committer.date // .[0].commit.author.date // "indisponível"' "$TMP_DIR/compare-commits.json" 2>/dev/null)
[ -n "$remote_date" ] ||
remote_date='indisponível'
printf '\n============================================================\n' >> "$TMP_DIR/compare-report.txt"
printf 'ARQUIVO LOCAL  : %s\n' "$local_path" >> "$TMP_DIR/compare-report.txt"
printf 'DATA LOCAL     : %s\n' "$local_date" >> "$TMP_DIR/compare-report.txt"
printf 'ARQUIVO REMOTO : %s/%s\n' "$GITHUB_USER" "$selected_repo" >> "$TMP_DIR/compare-report.txt"
printf 'BRANCH REMOTA  : %s\n' "$selected_branch" >> "$TMP_DIR/compare-report.txt"
printf 'CAMINHO REMOTO : %s\n' "$selected_path" >> "$TMP_DIR/compare-report.txt"
printf 'DATA REMOTA    : %s (último commit)\n' "$remote_date" >> "$TMP_DIR/compare-report.txt"
printf '============================================================\n' >> "$TMP_DIR/compare-report.txt"
if cmp -s "$local_path" "$temp_remote"
then
printf '\n╔══════════════════════════════════════════╗\n' >> "$TMP_DIR/compare-report.txt"
printf '║             ARQUIVOS IGUAIS!             ║\n' >> "$TMP_DIR/compare-report.txt"
printf '╚══════════════════════════════════════════╝\n' >> "$TMP_DIR/compare-report.txt"
print_centered_report
return 0
fi
printf '\nDIFERENÇAS ENCONTRADAS (LOCAL = - ; REMOTO = +):\n\n' >> "$TMP_DIR/compare-report.txt"
if diff -u --label "LOCAL: $file" --label "REMOTO: $selected_repo/$selected_path ($selected_branch)" "$local_path" "$temp_remote" >> "$TMP_DIR/compare-report.txt"
then
:
else
diff_status=$?
if [ "$diff_status" -gt 1 ]
then
printf 'Não foi possível gerar a comparação textual; o arquivo pode ser binário.\n' >> "$TMP_DIR/compare-report.txt"
print_centered_report
return 1
fi
fi
print_centered_report
return 0
}
list_local_files() {
local local_dir
local_dir="$(get_local_base_dir)" ||
return 1
printf '\nDiretório local configurado: %s\n' "$local_dir"
if ! find "$local_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
then
printf 'Não foi possível listar os arquivos de: %s\n' "$local_dir"
return 1
fi
}
change_current_directory() {
local requested_dir resolved_dir config_dir temp_config
local current_dir
current_dir="$(get_local_base_dir)" ||
current_dir="$PWD"
printf 'Diretório atual configurado: %s\nNovo diretório: ' "$current_dir"
gui_read requested_dir
[ -n "$requested_dir" ] ||
{ printf 'Diretório não informado.\n'; return 1; }
requested_dir="$(expand_user_path "$requested_dir")"
[[ -d "$requested_dir" && ! -L "$requested_dir" ]] ||
{ printf 'Diretório não encontrado ou inválido: %s\n' "$requested_dir"; return 1; }
resolved_dir="$(cd -- "$requested_dir" 2>/dev/null && pwd -P)" ||
{
printf 'Não foi possível acessar o diretório informado.\n'
return 1
}
config_dir="$(dirname "$LOCAL_DIR_CONFIG")"
if [ -L "$config_dir" ] ||
[ -L "$LOCAL_DIR_CONFIG" ]
then
printf 'Erro: caminho de configuração contém link simbólico.\n'
return 1
fi
mkdir -p -m 0700 "$config_dir" ||
{ printf 'Não foi possível criar a configuração local.\n'; return 1; }
temp_config="$(mktemp "$config_dir/.current-directory.XXXXXX")" ||
return 1
if ! printf '%s\n' "$resolved_dir" > "$temp_config" ||
! chmod 0600 "$temp_config" ||
! mv -f -- "$temp_config" "$LOCAL_DIR_CONFIG"
then
rm -f -- "$temp_config"
printf 'Falha ao salvar o diretório local. A configuração anterior foi preservada.\n'
return 1
fi
printf 'Diretório local alterado e salvo: %s\n' "$resolved_dir"
printf 'As tarefas que usam arquivos locais (comparar, enviar, baixar, listar e anexos)\n'
printf 'utilizarão este caminho mesmo após fechar e reabrir o aplicativo.\n'
}
search_file() {
local page count repo default_branch branch path search_term
ensure_login ||
return 1
printf 'Nome ou trecho do nome do arquivo: '
gui_read search_term
[ -n "$search_term" ] ||
{
printf 'Termo de pesquisa inválido.\n'
return 1
}
page=1
while :
do
if ! api GET \
"/user/repos?affiliation=owner&per_page=100&page=$page&sort=full_name" \
"" "$TMP_DIR/repos.json"
then
return 1
fi
count=$(jq 'length' "$TMP_DIR/repos.json")
[ "$count" -gt 0 ] ||
break
while IFS="$(printf '\t')" read -r repo default_branch
do
[ -n "$repo" ] ||
continue
if ! api GET \
"/repos/$GITHUB_USER/$(urlencode "$repo")/branches?per_page=100" \
"" "$TMP_DIR/branches.json"
then
continue
fi
while IFS= read -r branch
do
[ -n "$branch" ] ||
continue
if ! api GET \
"/repos/$GITHUB_USER/$(urlencode "$repo")/git/trees/$(urlencode "$branch")?recursive=1" \
"" "$TMP_DIR/tree.json"
then
continue
fi
jq -r --arg term "$search_term" '
.tree[]?
| select(.type == "blob")
| select(.path | ascii_downcase | contains($term | ascii_downcase))
| .path
' "$TMP_DIR/tree.json" |
while IFS= read -r path
do
printf 'Repositório: %s | Branch: %s | Caminho: %s\n' \
"$repo" "$branch" "$path"
done
done < <(jq -r '.[].name' "$TMP_DIR/branches.json")
done < <(
jq -r '.[] | [.name,.default_branch] | @tsv' "$TMP_DIR/repos.json"
)
[ "$count" -lt 100 ] &&
break
page=$((page + 1))
done
}
clone_third_party_repository() {
local url destination destination_parent
command -v git >/dev/null 2>&1 ||
{
printf 'Git não está instalado.\n'
return 1
}
printf 'URL HTTPS ou SSH do repositório: '
gui_read url
[ -n "$url" ] ||
{
printf 'URL inválida.\n'
return 1
}
case "$url" in
https://*|ssh://*|git@*:* ) ;;
*) printf 'Origem bloqueada: use somente URL HTTPS ou SSH. Caminhos locais e protocolos auxiliares não são aceitos.\n'
return 1 ;;
esac
printf 'Diretório de destino (ENTER para usar o padrão): '
gui_read destination
if [ -n "$destination" ]
then
destination="$(expand_user_path "$destination")"
destination_parent="$(dirname -- "$destination")"
[[ -d "$destination_parent" && ! -L "$destination_parent" ]] ||
{ printf 'Pasta pai do destino inexistente ou simbólica.\n'; return 1; }
[[ ! -e "$destination" && ! -L "$destination" ]] ||
{ printf 'O destino já existe. Clone cancelado para evitar sobrescrita.\n'; return 1; }
git clone -- "$url" "$destination"
else
git clone -- "$url"
fi
}
delete_repository() {
local name answer
ensure_login ||
return 1
printf 'Nome do repositório a excluir: '
gui_read name
valid_name "$name" ||
{
printf 'Nome inválido.\n'
return 1
}
printf 'ATENÇÃO: excluir permanentemente %s/%s? (s/n): ' "$GITHUB_USER" "$name"
gui_read answer
case "$answer" in
s|S|sim|SIM) ;;
*) printf 'Operação cancelada.\n'
return 0 ;;
esac
if api DELETE "/repos/$GITHUB_USER/$(urlencode "$name")"
then
printf 'Repositório excluído.\n'
fi
}
rename_repository() {
local old_name new_name payload
ensure_login ||
return 1
printf 'Nome atual do repositório: '
gui_read old_name
valid_name "$old_name" ||
{
printf 'Nome inválido.\n'
return 1
}
printf 'Novo nome do repositório: '
gui_read new_name
valid_name "$new_name" ||
{
printf 'Novo nome inválido.\n'
return 1
}
payload=$(jq -n --arg name "$new_name" '{name:$name}')
if api PATCH "/repos/$GITHUB_USER/$(urlencode "$old_name")" "$payload"
then
printf 'Repositório renomeado para: %s\n' "$new_name"
fi
}
remote_file_paths() {
local repo="$1" branch="$2" folder="$3" repo_encoded branch_encoded prefix
repo_encoded=$(urlencode "$repo") ||
return 1
branch_encoded=$(urlencode "$branch") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/git/trees/$branch_encoded?recursive=1" "" "$TMP_DIR/remote-files-tree.json"
then return 1
fi
if [ "$(jq -r '.truncated // false' "$TMP_DIR/remote-files-tree.json")" = "true" ]
then
printf 'AVISO: a árvore retornada pelo GitHub está truncada; a lista pode estar incompleta.\n'
fi
if [ -n "$folder" ]
then
prefix="$folder/"
jq -r --arg prefix "$prefix" '.tree[]? | select(.type == "blob") | select(.path | startswith($prefix)) | .path' "$TMP_DIR/remote-files-tree.json" > "$TMP_DIR/remote-files-paths.txt"
else
jq -r '.tree[]? | select(.type == "blob") | .path' "$TMP_DIR/remote-files-tree.json" > "$TMP_DIR/remote-files-paths.txt"
fi
}
choose_repository_branch() {
local mode="$1" repo repo_encoded branch
printf 'Nome do repositório: '
gui_read repo
valid_name "$repo" ||
{ printf 'Nome de repositório inválido.\n'; return 1; }
repo_encoded=$(urlencode "$repo") ||
return 1
if ! api GET "/repos/$GITHUB_USER/$repo_encoded" "" "$TMP_DIR/move-repo.json"
then return 1
fi
DEFAULT_BRANCH=$(jq -r '.default_branch // "main"' "$TMP_DIR/move-repo.json")
if [ "$mode" = "main" ]
then
branch="$DEFAULT_BRANCH"
printf 'Usando MAIN: %s\n' "$branch"
else
printf 'Nome da BRANCH secundária: '
gui_read branch
[ -n "$branch" ] ||
{ printf 'Informe uma BRANCH secundária.\n'; return 1; }
[ "$branch" != "$DEFAULT_BRANCH" ] ||
{ printf 'A branch informada é a MAIN, não uma branch secundária.\n'; return 1; }
if ! api GET "/repos/$GITHUB_USER/$repo_encoded/branches/$(urlencode "$branch")" "" "$TMP_DIR/move-branch.json"
then return 1
fi
fi
SELECTED_REPO="$repo"
SELECTED_BRANCH="$branch"
}
list_remote_folder_files() {
local mode="$1" folder total
ensure_login ||
return 1
if [ "$mode" = "main" ]
then printf '\n=== ARQUIVOS DA MAIN ===\n'
else printf '\n=== ARQUIVOS DA BRANCH SECUNDÁRIA ===\n'
fi
choose_repository_branch "$mode" ||
return 1
printf 'Caminho da pasta (ENTER para RAIZ): '
gui_read folder
folder=${folder#/}
folder=${folder%/}
if [ -n "$folder" ]
then validate_remote_folder "$folder" ||
{ printf 'Caminho de pasta inválido.\n'; return 1; }
fi
remote_file_paths "$SELECTED_REPO" "$SELECTED_BRANCH" "$folder" ||
return 1
filter_direct_files "$folder" "$TMP_DIR/remote-files-paths.txt"
total=$(wc -l < "$TMP_DIR/remote-files-paths.txt" | tr -d ' ')
if [ "$total" -eq 0 ]
then printf 'Nenhum arquivo encontrado.\n'
return 0
fi
printf '\nRepositório : %s\n' "$SELECTED_REPO"
printf 'Branch      : %s\n' "$SELECTED_BRANCH"
printf 'Pasta       : %s\n' "${folder:-/}"
printf 'Arquivos encontrados: %s\n' "$total"
cat "$TMP_DIR/remote-files-paths.txt"
}
move_remote_files() {
local mode="$1" source_folder destination_folder repo_encoded branch_encoded
local source_path relative_path destination_path source_encoded destination_encoded
local source_sha target_status target_sha answer payload status
local requested_file matched_path candidate
ensure_login ||
return 1
if [ "$mode" = "main" ]
then printf '\n=== MOVER ARQUIVO NA MAIN ===\n'
else printf '\n=== MOVER ARQUIVO NA BRANCH SECUNDÁRIA ===\n'
fi
choose_repository_branch "$mode" ||
return 1
printf 'Caminho da pasta de ORIGEM (ENTER para RAIZ): '
gui_read source_folder
source_folder=${source_folder#/}
source_folder=${source_folder%/}
if [ -n "$source_folder" ]
then validate_remote_folder "$source_folder" ||
{ printf 'Caminho de origem inválido.\n'; return 1; }
fi
remote_file_paths "$SELECTED_REPO" "$SELECTED_BRANCH" "$source_folder" ||
return 1
filter_direct_files "$source_folder" "$TMP_DIR/remote-files-paths.txt"
if [ ! -s "$TMP_DIR/remote-files-paths.txt" ]
then printf 'Nenhum arquivo encontrado na origem.\n'
return 0
fi
printf '\nArquivos disponíveis na origem:\n'
cat "$TMP_DIR/remote-files-paths.txt"
printf '\nInforme o NOME do arquivo a mover (com extensão, sem caminho): '
gui_read requested_file
is_safe_path_component "$requested_file" ||
{ printf 'Informe somente o nome do arquivo, sem caminhos.\n'; return 1; }
matched_path=""
while IFS= read -r candidate
do
[ -n "$candidate" ] ||
continue
if [ "${candidate##*/}" = "$requested_file" ]
then
matched_path="$candidate"
break
fi
done < "$TMP_DIR/remote-files-paths.txt"
if [ -z "$matched_path" ]
then
printf 'Arquivo "%s" não encontrado na pasta de origem.\n' "$requested_file"
return 1
fi
source_path="$matched_path"
printf '\nArquivo selecionado: %s\n' "$source_path"
printf 'Caminho da pasta de DESTINO (ENTER para RAIZ): '
gui_read destination_folder
destination_folder=${destination_folder#/}
destination_folder=${destination_folder%/}
if [ -n "$destination_folder" ]
then validate_remote_folder "$destination_folder" ||
{ printf 'Caminho de destino inválido.\n'; return 1; }
fi
if [ -n "$source_folder" ]
then relative_path=${source_path#"$source_folder"/}
else relative_path="$source_path"
fi
if [ -n "$destination_folder" ]
then destination_path="$destination_folder/$relative_path"
else destination_path="$relative_path"
fi
if [ "$source_path" = "$destination_path" ]
then printf 'Origem e destino são iguais; nada a mover.\n'
return 0
fi
printf '\nOrigem  : %s\n' "$source_path"
printf 'Destino : %s\n' "$destination_path"
printf 'Confirma mover este arquivo? (s/n): '
gui_read answer
case "$answer" in s|S|sim|SIM) ;;
*) printf 'Operação cancelada.\n'
return 0 ;;
esac
repo_encoded=$(urlencode "$SELECTED_REPO") ||
return 1
branch_encoded=$(urlencode "$SELECTED_BRANCH") ||
return 1
source_encoded=$(urlencode_path "$source_path") ||
{ printf 'Falha ao codificar origem.\n'; return 1; }
destination_encoded=$(urlencode_path "$destination_path") ||
{ printf 'Falha ao codificar destino.\n'; return 1; }
status=$(curl -sS -o "$TMP_DIR/move-source.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$source_encoded?ref=$branch_encoded") ||
status=000
if [ "$status" != 200 ]
then printf 'Falha ao ler origem: %s (HTTP %s)\n' "$source_path" "$status"
return 1
fi
source_sha=$(jq -r '.sha // empty' "$TMP_DIR/move-source.json")
if [ -z "$source_sha" ] ||
! jq -e '.content and (.encoding == "base64")' "$TMP_DIR/move-source.json" >/dev/null 2>&1
then
printf 'Não foi possível obter conteúdo/SHA de %s.\n' "$source_path"
return 1
fi
jq -r '.content' "$TMP_DIR/move-source.json" | tr -d '\r\n' > "$TMP_DIR/move-content.b64" ||
{ printf 'Falha ao preparar conteúdo.\n'; return 1; }
chmod 0600 "$TMP_DIR/move-content.b64" 2>/dev/null ||
true
target_status=$(curl -sS -o "$TMP_DIR/move-target.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$destination_encoded?ref=$branch_encoded") ||
target_status=000
target_sha=""
case "$target_status" in
200)
target_sha=$(jq -r '.sha // empty' "$TMP_DIR/move-target.json")
printf '\nDestino já existe: %s\n' "$destination_path"
printf 'Digite A para ATUALIZAR o destino ou M para MANTER o destino e cancelar: '
gui_read answer
case "$answer" in A|a|ATUALIZA|atualiza) ;;
*) printf 'Destino mantido; origem preservada: %s\n' "$source_path"
return 0 ;;
esac
[ -n "$target_sha" ] ||
{ printf 'SHA do destino indisponível.\n'; return 1; }
;;
404) ;;
*) printf 'Falha ao verificar destino %s (HTTP %s).\n' "$destination_path" "$target_status"
return 1 ;;
esac
if ! jq -n --arg message "Mover $source_path para $destination_path via GitHub Manager" \
--rawfile content "$TMP_DIR/move-content.b64" --arg branch "$SELECTED_BRANCH" --arg sha "$target_sha" \
'{message:$message,content:$content,branch:$branch} + (if $sha != "" then {sha:$sha} else {} end)' \
> "$TMP_DIR/move-upload-payload.json"
then
printf 'Falha ao preparar destino: %s\n' "$destination_path"
return 1
fi
chmod 0600 "$TMP_DIR/move-upload-payload.json" 2>/dev/null ||
true
status=$(curl -sS -o "$TMP_DIR/move-upload.json" -w '%{http_code}' -X PUT \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" -H 'Content-Type: application/json' \
--data-binary "@$TMP_DIR/move-upload-payload.json" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$destination_encoded") ||
status=000
case "$status" in 200|201) ;;
*) printf 'Falha ao gravar destino %s (HTTP %s); origem preservada.\n' "$destination_path" "$status"
return 1 ;;
esac
payload=$(jq -n --arg message "Remover origem após mover para $destination_path" --arg sha "$source_sha" --arg branch "$SELECTED_BRANCH" '{message:$message,sha:$sha,branch:$branch}') ||
{ printf 'Destino gravado, mas não foi possível preparar a remoção da origem.\n'; return 1; }
status=$(curl -sS -o "$TMP_DIR/move-delete.json" -w '%{http_code}' -X DELETE \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" -H 'Content-Type: application/json' \
--data-binary "$payload" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$source_encoded") ||
status=000
if [ "$status" = 200 ] ||
[ "$status" = 204 ]
then
printf '\nMovido com sucesso: %s -> %s\n' "$source_path" "$destination_path"
else
printf 'Destino gravado, mas falhou a remoção da origem %s (HTTP %s).\n' "$source_path" "$status"
printf 'Verifique antes de repetir.\n'
return 1
fi
}
list_main_repository_files() { list_remote_folder_files "main"; }
list_secondary_branch_files() { list_remote_folder_files "secondary"; }
move_main_repository_files() { move_remote_files "main"; }
move_secondary_branch_files() { move_remote_files "secondary"; }
show_menu() {
export LC_ALL=C.UTF-8
local reset='' bold=''
local c0='' c1='' c2='' c3='' c4='' c5='' c6='' cw='' cnum='' cnumbg='' ctxt=''
local cols gap col_w total_w left_pad i r nlines NUM_W remainder
local -a titles colors
local -a items0 items1 items2 items3 items4 items5 items6
local -a lines0 lines1 lines2 lines3 lines4 lines5 lines6
local -a COLW=()
local -a flags0 flags1 flags2 flags3 flags4 flags5 flags6
if [ -t 1 ] &&
[ -n "${TERM:-}" ] &&
[ "${TERM:-}" != dumb ]
then
local esc=$'\033'
reset="${esc}[0m"
bold="${esc}[1m"
cw="${esc}[97m"
cnum="${esc}[30;1m"
cnumbg="${esc}[48;5;226m"
ctxt="${esc}[97m"
c0="${esc}[97m"
c1="${esc}[97m"
c2="${esc}[97m"
y1="${esc}[38;5;226m"
y2="${esc}[38;5;220m"
y3="${esc}[38;5;214m"
y4="${esc}[38;5;208m"
y5="${esc}[38;5;178m"
y6="${esc}[38;5;172m"
c3="${esc}[97m"
c4="${esc}[97m"
c5="${esc}[97m"
c6="${esc}[97m"
ybg1="${esc}[48;5;226m"
ybg2="${esc}[48;5;220m"
ybg3="${esc}[48;5;214m"
ybg4="${esc}[48;5;208m"
ybg5="${esc}[48;5;178m"
ybg6="${esc}[48;5;172m"
sepbg=("${esc}[48;5;226m" "${esc}[48;5;220m" "${esc}[48;5;214m" "${esc}[48;5;208m" "${esc}[48;5;178m" "${esc}[48;5;172m")
colbg=("${esc}[48;5;226m" "${esc}[48;5;220m" "${esc}[48;5;214m" "${esc}[48;5;208m" "${esc}[48;5;178m" "${esc}[48;5;172m" "${esc}[48;5;226m")
hbg=("${esc}[48;5;235m" "${esc}[48;5;235m" "${esc}[48;5;235m" "${esc}[48;5;235m" "${esc}[48;5;235m" "${esc}[48;5;235m" "${esc}[48;5;235m")
hfg="${esc}[38;5;226;1m"
fi
if [ -t 1 ] &&
[ -n "${TERM:-}" ] &&
command -v clear >/dev/null 2>&1
then
clear 2>/dev/null ||
:
fi
cols=$(tput cols 2>/dev/null || echo 120)
[[ "$cols" =~ ^[0-9]+$ ]] ||
cols=120
[ "$cols" -lt 60 ] &&
cols=60
[ "$cols" -gt 200 ] &&
cols=200
gap=3
col_w=$(( (cols - 6 * gap) / 7 ))
[ "$col_w" -lt 8 ] &&
col_w=8
total_w=$(( col_w * 7 + 6 * gap + 2 ))
while [ "$total_w" -gt "$cols" ] &&
[ "$col_w" -gt 8 ]
do
col_w=$((col_w - 1))
total_w=$(( col_w * 7 + 6 * gap + 2 ))
done
left_pad=$(( (cols - total_w) / 2 ))
[ "$left_pad" -lt 0 ] &&
left_pad=0
remainder=$(( cols - total_w ))
COLW=()
for ((i=0; i<7; i++))
do
COLW+=("$col_w")
done
[ "$remainder" -gt 0 ] &&
COLW[6]=$(( col_w + remainder ))
total_w=$cols
left_pad=0
NUM_W=4
dlen() {
printf '%s' "$1" | wc -m
}
pad_exact() {
local s="$1" w="$2" t pad
t=$(printf '%s' "$s" | cut -c1-"$w")
pad=$(( w - $(dlen "$t") ))
[ "$pad" -lt 0 ] &&
pad=0
printf '%s%*s' "$t" "$pad" ''
}
wrap_into_arr() {
local text="$1" w="$2" target_id="$3"
local rest chunk line
local -a out=()
rest="$text"
while [ -n "$rest" ]
do
if [ "${#rest}" -le "$w" ]
then
out+=("$rest")
break
fi
chunk="${rest:0:w}"
if [[ "$chunk" == *' '* ]]
then
line="${chunk% *}"
if [ -z "$line" ]
then
line="$chunk"
rest="${rest:${#line}}"
else
rest="${rest:$((${#line}+1))}"
fi
else
line="$chunk"
rest="${rest:w}"
fi
rest="${rest#"${rest%%[![:space:]]*}"}"
out+=("$line")
done
case "$target_id" in
w0) _w0=("${out[@]}") ;;
w1) _w1=("${out[@]}") ;;
w2) _w2=("${out[@]}") ;;
w3) _w3=("${out[@]}") ;;
w4) _w4=("${out[@]}") ;;
w5) _w5=("${out[@]}") ;;
w6) _w6=("${out[@]}") ;;
esac
}
titles=(
"COMPARAR / MOVER"
"CONSULTAR"
"EXCLUIR"
"ENVIAR ARQUIVOS"
"CRIAR"
"RENOMEAR"
"MUDAR / LOGOFF"
)
colors=("$c0" "$c1" "$c2" "$c3" "$c4" "$c5" "$c6")
# hbg/hfg definidos no bloco de cor (com esc valido)
items0=(
"01 Comparar arquivo local/remoto"
"02 Mover arquivo da MAIN"
"03 Mover arquivo na BRANCH"
"04 MOVER TODOS arquivos de pasta (qualquer branch)"
"05 MOVER TODOS arquivos na BRANCH principal para pasta"
"06 MOVER TODOS arquivos na BRANCH secundária para pasta"
)
items1=(
"07 Listar repositórios e pastas"
"08 Pesquisar arquivo / caminho"
"09 Listar arquivos locais"
"10 Listar arquivos da MAIN"
"11 Listar arquivos na BRANCH"
)
items2=(
"12 Excluir REPOSITÓRIO"
"13 Excluir BRANCH secundária"
"14 Excluir pasta do REPOSITÓRIO"
"15 Excluir pasta na BRANCH secundária"
"16 Excluir arquivo remoto"
)
items3=(
"17 Baixar arquivo remoto"
"18 Enviar arquivo ao GitHub"
"19 Clonar repositório de terceiros"
"20 Enviar arquivo em anexo"
"21 Enviar diversos anexos"
)
items4=(
"22 Criar REPOSITÓRIO"
"23 Criar BRANCH secundária"
"24 Criar PASTA no REPOSITÓRIO"
"25 Criar pasta na BRANCH"
)
items5=(
"26 Renomear repositório"
"27 Renomear BRANCH secundária"
"28 Renomear pasta na BRANCH"
)
items6=(
"29 Mudar diretório local"
"30 Trocar usuário GitHub"
)
build_col() {
local col_idx="$1"
local it num body wbody cont k
local -a src=() out_l=() out_f=() _w0=() _w1=() _w2=() _w3=() _w4=() _w5=() _w6=()
case "$col_idx" in
0) src=("${items0[@]}") ;;
1) src=("${items1[@]}") ;;
2) src=("${items2[@]}") ;;
3) src=("${items3[@]}") ;;
4) src=("${items4[@]}") ;;
5) src=("${items5[@]}") ;;
6) src=("${items6[@]}") ;;
esac
for it in "${src[@]}"
do
num="${it%% *}"
# Exibicao sem zero a esquerda; valor da escolha permanece inalterado.
case "$num" in 0[1-9]) num="${num#0}" ;; esac
body="${it#* }"
wbody=$(( col_w - NUM_W - 1 ))
[ "$wbody" -lt 6 ] &&
wbody=6
wrap_into_arr "$body" "$wbody" "w$col_idx"
local -a cur=()
case "$col_idx" in
0) cur=("${_w0[@]}") ;;
1) cur=("${_w1[@]}") ;;
2) cur=("${_w2[@]}") ;;
3) cur=("${_w3[@]}") ;;
4) cur=("${_w4[@]}") ;;
5) cur=("${_w5[@]}") ;;
6) cur=("${_w6[@]}") ;;
esac
if [ "${#cur[@]}" -eq 0 ]
then
out_l+=("$num|")
out_f+=(1)
else
out_l+=("${num}|${cur[0]}")
out_f+=(1)
for ((k=1; k<${#cur[@]}; k++))
do
cont=$(printf '%*s%s' $((NUM_W + 1)) '' "${cur[$k]}")
out_l+=("|$cont")
out_f+=(0)
done
fi
out_l+=("|")
out_f+=(0)
done
if [ "${#out_l[@]}" -gt 0 ]
then
unset "out_l[-1]"
unset "out_f[-1]"
fi
case "$col_idx" in
0) lines0=("${out_l[@]}")
flags0=("${out_f[@]}") ;;
1) lines1=("${out_l[@]}")
flags1=("${out_f[@]}") ;;
2) lines2=("${out_l[@]}")
flags2=("${out_f[@]}") ;;
3) lines3=("${out_l[@]}")
flags3=("${out_f[@]}") ;;
4) lines4=("${out_l[@]}")
flags4=("${out_f[@]}") ;;
5) lines5=("${out_l[@]}")
flags5=("${out_f[@]}") ;;
6) lines6=("${out_l[@]}")
flags6=("${out_f[@]}") ;;
esac
}
build_col 0
build_col 1
build_col 2
build_col 3
build_col 4
build_col 5
build_col 6
nlines=${#lines0[@]}
[ ${#lines1[@]} -gt "$nlines" ] &&
nlines=${#lines1[@]}
[ ${#lines2[@]} -gt "$nlines" ] &&
nlines=${#lines2[@]}
[ ${#lines3[@]} -gt "$nlines" ] &&
nlines=${#lines3[@]}
[ ${#lines4[@]} -gt "$nlines" ] &&
nlines=${#lines4[@]}
[ ${#lines5[@]} -gt "$nlines" ] &&
nlines=${#lines5[@]}
[ ${#lines6[@]} -gt "$nlines" ] &&
nlines=${#lines6[@]}
print_cell() {
local bi="$1" ri="$2"
local raw="" flag=0 num="" rest="" badge cellw
cellw="${COLW[$bi]:-$col_w}"
case "$bi" in
0) [ "$ri" -lt "${#lines0[@]}" ] &&
{ raw="${lines0[$ri]}"; flag="${flags0[$ri]:-0}"; } ;;
1) [ "$ri" -lt "${#lines1[@]}" ] &&
{ raw="${lines1[$ri]}"; flag="${flags1[$ri]:-0}"; } ;;
2) [ "$ri" -lt "${#lines2[@]}" ] &&
{ raw="${lines2[$ri]}"; flag="${flags2[$ri]:-0}"; } ;;
3) [ "$ri" -lt "${#lines3[@]}" ] &&
{ raw="${lines3[$ri]}"; flag="${flags3[$ri]:-0}"; } ;;
4) [ "$ri" -lt "${#lines4[@]}" ] &&
{ raw="${lines4[$ri]}"; flag="${flags4[$ri]:-0}"; } ;;
5) [ "$ri" -lt "${#lines5[@]}" ] &&
{ raw="${lines5[$ri]}"; flag="${flags5[$ri]:-0}"; } ;;
6) [ "$ri" -lt "${#lines6[@]}" ] &&
{ raw="${lines6[$ri]}"; flag="${flags6[$ri]:-0}"; } ;;
esac
if [ "$flag" = 1 ]
then
num="${raw%%|*}"
rest="${raw#*|}"
badge=$(printf '%2s' "$num")
badge=$(printf '%-4s' " $badge")
badge="${badge:0:4}"
rest=$(pad_exact " $rest" $((cellw - NUM_W)))
printf '%b%s%b%b%s%b' "${cnumbg}${cnum}" "$badge" "$reset" "${cw}${ctxt}" "$rest" "$reset"
else
rest="${raw#*|}"
printf '%b%s%b' "${cw}${ctxt}" "$(pad_exact "$rest" "$cellw")" "$reset"
fi
}
rule_sep() {
printf '%*s' "$left_pad" ''
printf '%b %b' "$ybg1" "$reset"
local idx
for idx in 0 1 2 3 4 5 6
do
printf '%b%*s%b' "${colbg[$idx]}" "${COLW[$idx]}" '' "$reset"
[ "$idx" -lt 6 ] &&
printf '%b%*s%b' "${sepbg[$idx]}" "$gap" '' "$reset"
done
printf '%b %b' "$ybg6" "$reset"
printf '\n'
}
line_fill() {
local ch="${1:-#}" n="$2"
n=$((n+0))
[ "$n" -lt 0 ] &&
n=0
[ "$n" -gt 300 ] &&
n=300
printf '%*s' "$n" '' | tr ' ' "$ch"
}
clip() { printf '%s' "$1" | cut -c1-"$2"; }
pad_left() {
local s="$1" w="$2" t p
t=$(clip "$s" "$w")
p=$(( w - ${#t} ))
[ "$p" -lt 0 ] &&
p=0
printf '%s%*s' "$t" "$p" ''
}
center() {
local s="$1" w="$2" t pl pr dl
t=$(clip "$s" "$w")
dl=$(dlen "$t")
pl=$(( (w - dl) / 2 ))
[ "$pl" -lt 0 ] &&
pl=0
pr=$(( w - dl - pl ))
[ "$pr" -lt 0 ] &&
pr=0
printf '%*s%s%*s' "$pl" '' "$t" "$pr" ''
}
printf '%b' "$ybg1"
printf '%*s' "$cols" ''
printf '%b\n' "$reset"
printf '%b %b%*s%b %b\n' "$ybg2" "$reset" $((cols - 2)) '' "$ybg2" "$reset"
# Cabeçalho centralizado; azul intenso no título e sem informação de versão.
local header_bg='' header_blue='' header_sub='' 
if [ -t 1 ] && [ "${TERM:-}" != dumb ]; then
    header_bg=$'\033[48;5;235m'
    header_blue=$'\033[1;38;5;39m'
    header_sub=$'\033[38;5;117m'
fi
printf '%b %b%s%b %b\n' "$header_bg" "$header_blue" "$(center 'GITMENU CLI | CENTRO DE COMANDOS GIT' $((cols - 2)))" "$reset" "$header_bg"
printf '%b %b%s%b %b\n' "$header_bg" "$header_sub" "$(center 'Repositórios / Branches / Pastas / Arquivos (CLI)' $((cols - 2)))" "$reset" "$header_bg"
printf '%b %b%s%b %b\n' "$header_bg" "$header_sub" "$(center 'Autor: Everaldo Costa Silva' $((cols - 2)))" "$reset" "$header_bg"
printf '%b %b%s%b %b\n' "$header_bg" "$header_sub" "$(center 'Licença: MIT' $((cols - 2)))" "$reset" "$header_bg"
printf '%b %b%*s%b %b\n' "$ybg4" "$reset" $((cols - 2)) '' "$ybg4" "$reset"
printf '%b' "$ybg6"
printf '%*s' "$cols" ''
printf '%b\n' "$reset"
printf '%*s' "$left_pad" ''
rule_sep
head=("COMPARAR" "CONSULTAR" "EXCLUIR" "ENVIAR" "CRIAR" "RENOMEAR" "MUDAR / LOGOFF")
printf '%*s' "$left_pad" ''
printf '%b %b' "$ybg1" "$reset"
for i in 0 1 2 3 4 5 6
do
txt="${head[$i]}"
txt=$(clip "$txt" "${COLW[$i]}")
dl=$(dlen "$txt")
pl=$(( (COLW[$i] - dl) / 2 ))
[ "$pl" -lt 0 ] &&
pl=0
pr=$(( COLW[$i] - dl - pl ))
[ "$pr" -lt 0 ] &&
pr=0
printf '%*s' "$pl" ''
printf '%b%b%s%b' "${hbg[$i]}" "$hfg" "$txt" "$reset"
printf '%*s' "$pr" ''
[ "$i" -lt 6 ] &&
printf '%b%*s%b' "${sepbg[$i]}" "$gap" '' "$reset"
done
printf '%b %b' "$ybg6" "$reset"
printf '\n'
rule_sep
for ((r=0; r<nlines; r++))
do
printf '%*s' "$left_pad" ''
printf '%b %b' "$ybg1" "$reset"
for i in 0 1 2 3 4 5 6
do
print_cell "$i" "$r"
[ "$i" -lt 6 ] &&
printf '%b%*s%b' "${sepbg[$i]}" "$gap" '' "$reset"
done
printf '%b %b' "$ybg6" "$reset"
printf '\n'
done
rule_sep
printf '\n'
printf '%*s' "$left_pad" ''
printf '%b 0 %b Sair   %bEscolha (0-30):%b ' "${cnumbg}${cnum}" "$reset" "${cw}${bold}" "$reset"
}
# Títulos das operações legadas que ainda não usam o cabeçalho compartilhado.
ui_legacy_menu_heading() {
    case "$1" in
        8) ui_operation_title '08 - PESQUISAR ARQUIVO / CAMINHO' ;;
        13) ui_operation_title '13 - EXCLUIR BRANCH SECUNDÁRIA' ;;
        23) ui_operation_title '23 - CRIAR BRANCH SECUNDÁRIA' ;;
        24) ui_operation_title '24 - CRIAR PASTA NO REPOSITÓRIO' ;;
        25) ui_operation_title '25 - CRIAR PASTA NA BRANCH' ;;
        27) ui_operation_title '27 - RENOMEAR BRANCH SECUNDÁRIA' ;;
        30) ui_operation_title '30 - TROCAR USUÁRIO GITHUB' ;;
    esac
}
main() {
local option
while :
do
show_menu
if ! IFS= read -r option
then
printf '\nEntrada encerrada; saindo do menu.\n'
break
fi
ui_legacy_menu_heading "$option"
case "$option" in
1) compare_local_remote_file
pause ;;
2) move_main_repository_files
pause ;;
3) move_secondary_branch_files
pause ;;
4) move_all_repository_folder_files
pause ;;
5) move_all_main_branch_files
pause ;;
6) move_all_secondary_branch_files
pause ;;
7) list_repositories
pause ;;
8) search_file
pause ;;
9) list_local_files
pause ;;
10) list_main_repository_files
pause ;;
11) list_secondary_branch_files
pause ;;
12) delete_repository
pause ;;
13) delete_secondary_branch
pause ;;
14) delete_folder_main
pause ;;
15) delete_folder_secondary_branch
pause ;;
16) delete_remote_file
pause ;;
17) download_file
pause ;;
18) upload_file
pause ;;
19) clone_third_party_repository
pause ;;
20) attach_single_file
pause ;;
21) attach_multiple_files
pause ;;
22) create_repository_main
pause ;;
23) create_secondary_branch
pause ;;
24) create_folder_main
pause ;;
25) create_folder_secondary_branch
pause ;;
26) rename_repository
pause ;;
27) rename_secondary_branch
pause ;;
28) rename_folder_secondary_branch
pause ;;
29) change_current_directory
pause ;;
30) logout_github
login_github
pause ;;
0) logout_github
exit 0 ;;
*) printf '\nOpção inválida. Informe um número de 0 a 30.\n'
pause ;;
esac
done
}
# ======================================================================
# PATCH GITMENU: escolhas numéricas + resumo em blocos (degradê amarelo)
# Redefine: upload_file, upload_selected_attachments, attach_single_file,
#           attach_multiple_files, download_file
# Deve ficar DEPOIS das definições originais (as últimas prevalecem) e
# ANTES da linha final:  command -v curl >/dev/null 2>&1 ||
# ======================================================================

SUM_GRAD=(226 220 214 208 178 172)

# Interface pós-menu: apenas cores de TEXTO, sem fundo nos blocos.
ui_color_enabled() { [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; }
ui_cols() {
    local n
    n=$(tput cols 2>/dev/null) || n=100
    [[ "$n" =~ ^[0-9]+$ ]] || n=100
    (( n < 40 )) && n=40
    (( n > 40 )) && n=$((n-1))
    printf '%s' "$n"
}
ui_repeat() {
    local char="$1" count="$2" i
    for ((i=0;i<count;i++)); do printf '%s' "$char"; done
}
# Largura visual dos caracteres (acentos, símbolos e emojis).
ui_width() {
    local LC_ALL=C.UTF-8 value="$1" char i width=0
    for ((i=0;i<${#value};i++)); do
        char="${value:i:1}"
        case "$char" in
            [[:cntrl:]]) ;;
            *) width=$((width+1)) ;;
        esac
    done
    printf '%s' "$width"
}
ui_fit() {
    local LC_ALL=C.UTF-8 value="$1" max="$2" width
    (( max < 1 )) && return 0
    width=$(ui_width "$value")
    while (( width > max )); do
        value="${value:0:${#value}-1}"
        width=$(ui_width "$value")
    done
    printf '%s%*s' "$value" "$((max-width))" ''
}
ui_side() {
    if ui_color_enabled; then printf '\033[1;38;5;220m┃\033[0m'; else printf '┃'; fi
}
ui_frame_line() {
    local left="$1" right="$2" width
    width=$(ui_cols)
    if ui_color_enabled; then printf '\033[1;38;5;220m'; fi
    printf '%s' "$left"
    ui_repeat '━' "$((width-2))"
    printf '%s' "$right"
    if ui_color_enabled; then printf '\033[0m'; fi
    printf '\n'
}
ui_content_row() {
    local text="$1" width
    width=$(ui_cols)
    ui_side
    printf '%s' "$(ui_fit "  $text" "$((width-2))")"
    ui_side
    printf '\n'
}
ui_blank() { ui_content_row ''; }
ui_title_row() {
    local title="$1" width
    width=$(ui_cols)
    ui_side
    if ui_color_enabled; then printf '\033[1;38;5;226m'; fi
    printf '%s' "$(ui_fit "  $title" "$((width-2))")"
    if ui_color_enabled; then printf '\033[0m'; fi
    ui_side
    printf '\n'
}
# Um único cabeçalho para cada seletor, antes dos dados.
ui_picker_start() {
    local title="$1"
    ui_frame_line '┏' '┓'
    ui_title_row "$title"
    ui_frame_line '┣' '┫'
}
ui_operation_title() {
    local title="$1" width
    width=$(ui_cols)
    printf '\n'
    if ui_color_enabled; then printf '\033[48;5;220m\033[30;1m'; fi
    printf '%s' "$(ui_fit "  $title" "$width")"
    if ui_color_enabled; then printf '\033[0m'; fi
    printf '\n'
}
ui_list_title() {
    ui_frame_line '┣' '┫'
    ui_title_row "$1"
    ui_frame_line '┣' '┫'
}
# Cabeçalhos de resumo e conferência continuam separados dos quadros de dados.
ui_heading() {
    local title="$1"
    printf '\n'
    ui_frame_line '┏' '┓'
    ui_title_row "$title"
    ui_frame_line '┗' '┛'
}
# Todas as linhas de dados começam na coluna 3, inclusive Pasta atual.
# A largura é calculada a partir de uma única área útil entre as bordas.
ui_info_row() {
    local label="$1" value="$2" width prefix text
    width=$(ui_cols)
    prefix="  ${label}: "
    text="${prefix}${value}"
    ui_side
    printf '%s' "$(ui_fit "$text" "$((width-2))")"
    ui_side
    printf '\n'
}
ui_option_row() {
    local number="$1" desc="$2" width prefix value
    width=$(ui_cols)
    if [ "$number" = 0 ]; then number='0'; else printf -v number '%02d' "$number"; fi
    prefix="  ${number} - "
    value="$(ui_fit "${prefix}${desc}" "$((width-2))")"
    ui_side
    if ui_color_enabled; then
        printf '\033[1;38;5;226m%s\033[0m%s' "${prefix}" "$(ui_fit "$desc" "$((width-2-${#prefix}))")"
    else
        printf '%s' "$value"
    fi
    ui_side
    printf '\n'
}

ui_actions() {
    local item
    for item in "$@"; do ui_content_row "$item"; done
}
ui_prompt() {
    local width
    width=$(ui_cols)
    ui_blank
    ui_side
    if ui_color_enabled; then printf '\033[1;38;5;226m'; fi
    printf '  Escolha: '
    if ui_color_enabled; then printf '\033[0m'; fi
    # Cursor na mesma linha do prompt; o fechamento ocorre após a leitura.
}
ui_section_end() {
    printf '\n'
    ui_blank
    ui_frame_line '┗' '┛'
    printf '\n'
}
folder_label() {
if [ -n "$1" ]
then printf '/%s' "$1"
else printf '/ (raiz)'
fi
}
now_str() { date '+%d/%m/%Y %H:%M:%S'; }
is_pos_int() {
case "$1" in
''|*[!0-9]*) return 1 ;;
*) return 0 ;;
esac
}
in_range() {
is_pos_int "$1" &&
[ "$1" -ge 1 ] &&
[ "$1" -le "$2" ]
}
human_size() {
local b="${1:-0}"
if [ "$b" -ge 1048576 ]
then printf '%s MB' "$(( b / 1048576 ))"
elif [ "$b" -ge 1024 ]
then printf '%s KB' "$(( b / 1024 ))"
else printf '%s B' "$b"
fi
}
ask_yes_no() {
    local question="$1" answer
    ui_picker_start 'CONFIRMAR OPERAÇÃO'
    ui_content_row "$question"
    ui_option_row 1 'SIM'
    ui_option_row 2 'NÃO'
    ui_blank
    ui_option_row 0 'CANCELAR'
    ui_prompt
    gui_read answer
    ui_section_end
    [ "$answer" = 1 ]
}
# Entrada simples com moldura, sem alterar o valor capturado.
ui_text_input() {
    local title="$1" label="$2" target="$3" response
    ui_picker_start "$title"
    ui_content_row "$label"
    ui_blank
    ui_side
    printf '  Entrada: '
    gui_read response
    ui_section_end
    printf -v "$target" '%s' "$response"
}

# Bloco desenhado: barras em degradê amarelo, cabeçalho em destaque e
# rótulo de cada linha preenchido (fundo amarelo) antes do valor.
# Uso: draw_block "TÍTULO" "Rótulo|valor" "Rótulo|valor" ...
draw_block() {
    local title="$1" pair label value
    shift
    printf '\n'
    ui_frame_line '┏' '┓'
    ui_title_row "$title"
    ui_frame_line '┣' '┫'
    for pair in "$@"; do
        label="${pair%%|*}"
        value="${pair#*|}"
        ui_info_row "$label" "$value"
    done
    ui_frame_line '┗' '┛'
    printf '\n'
}
# ------------------------- seletores numéricos ------------------------
# Intervalos: "1,3,5-7" -> uma posição por linha
parse_selection() {
local sel="${1// /}" max="$2" part a b n
local -a parts=()
[ -n "$sel" ] ||
return 1
IFS=',' read -ra parts <<< "$sel"
for part in "${parts[@]}"
do
case "$part" in
*-*)
a="${part%-*}"
b="${part#*-}"
is_pos_int "$a" &&
is_pos_int "$b" ||
return 1
a=$((10#$a))
b=$((10#$b))
[ "$a" -ge 1 ] &&
[ "$b" -ge "$a" ] &&
[ "$b" -le "$max" ] ||
return 1
for ((n=a; n<=b; n++))
do printf '%s\n' "$n"
done
;;
*)
in_range "$part" "$max" ||
return 1
printf '%s\n' "$((10#$part))"
;;
esac
done
}

# Navegador de pastas locais -> PICK_LOCAL_DIR
pick_local_folder() {
local title="${1:-PASTA LOCAL}" cur choice i n target entered
local -a subs=()
cur="$(get_local_base_dir)" || cur="$PWD"
while :; do
mapfile -t subs < <(find "$cur" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' 2>/dev/null | sort)
n=${#subs[@]}
ui_picker_start "$title"
ui_info_row 'Pasta atual' "$cur"
ui_list_title 'PASTAS LOCAIS'
for ((i=0; i<n; i++)); do
    ui_option_row "$((i+1))" "${subs[$i]}"
done
[ "$n" -eq 0 ] && ui_info_row 'Conteúdo' '(sem subpastas)'
ui_option_row "$((n+1))" 'Selecionar pasta atual'
ui_option_row "$((n+2))" 'Informar caminho (ENTER = pasta pessoal)'
ui_blank
ui_option_row 0 'CANCELAR'
ui_prompt
gui_read choice
ui_section_end
case "$choice" in
0|00) return 1 ;;
"$((n+1))")
    PICK_LOCAL_DIR="$cur"
    return 0
    ;;
''|"$((n+2))")
    printf '\n  Caminho da pasta [ENTER = %s]: ' "$HOME"
    gui_read entered
    [ -n "$entered" ] || entered="$HOME"
    case "$entered" in
        '~') entered="$HOME" ;;
        '~/'*) entered="$HOME/${entered#~/}" ;;
    esac
    if [ -d "$entered" ] && [ ! -L "$entered" ]; then
        target="$(cd -- "$entered" 2>/dev/null && pwd -P)" || { printf '  Caminho inacessível.\n'; continue; }
        PICK_LOCAL_DIR="$target"
        return 0
    fi
    printf '  Pasta inexistente ou caminho inválido.\n'
    ;;
*)
    if in_range "$choice" "$n"; then
        target="$cur/${subs[$((10#$choice - 1))]}"
        if [ -d "$target" ] && [ ! -L "$target" ]; then
            cur="$(cd -- "$target" 2>/dev/null && pwd -P)" || cur="$target"
        fi
    else
        printf '  Opção inválida.\n'
    fi
    ;;
esac
done
}

# Arquivos locais -> array PICK_LOCAL_FILES (caminhos completos)
# modo: single | multi
pick_local_files() {
local mode="$1" dir="$2" i n sel idx fsize nm
local -a names=() raw=() chosen=()
PICK_LOCAL_FILES=()
mapfile -t raw < <(find "$dir" -maxdepth 1 -type f ! -name '.*' -printf '%f\n' 2>/dev/null | sort)
for nm in "${raw[@]}"
do
has_control_chars "$nm" ||
names+=("$nm")
done
n=${#names[@]}
if [ "$n" -eq 0 ]
then
printf '\n  Nenhum arquivo nesta pasta.\n'
return 1
fi
while :
do
ui_picker_start "ARQUIVOS EM: $dir"
if [ "$mode" = multi ]; then
    ui_content_row 'Selecione números (ex.: 1,3,5-7)'
    ui_content_row "Para selecionar todos, informe: 1-$n"
else
    ui_content_row 'Digite o número do arquivo em Escolha:'
fi
for ((i=0; i<n; i++))
do
fsize=$(wc -c < "$dir/${names[$i]}" 2>/dev/null | tr -d ' ')
ui_option_row "$((i+1))" "${names[$i]}  |  $(human_size "${fsize:-0}")"
done
ui_blank
ui_option_row 0 'CANCELAR'
ui_prompt
gui_read sel
ui_section_end
[ "$sel" = 0 ] && sel=C
case "$sel" in
c|C) return 1 ;;
esac
if [ "$mode" = multi ]
then
if [ "$sel" = t ] ||
[ "$sel" = T ]
then
chosen=()
for ((i=1; i<=n; i++))
do chosen+=("$i")
done
else
mapfile -t chosen < <(parse_selection "$sel" "$n" | awk '!s[$0]++')
fi
else
chosen=()
in_range "$sel" "$n" &&
chosen=("$((10#$sel))")
fi
if [ "${#chosen[@]}" -eq 0 ]
then
printf '  Seleção inválida.\n'
continue
fi
for idx in "${chosen[@]}"
do PICK_LOCAL_FILES+=("$dir/${names[$((idx-1))]}")
done
return 0
done
}

# Repositórios do usuário -> PICK_REPO, PICK_REPO_PRIV, DEFAULT_BRANCH
pick_repository() {
local page=1 count i n choice a b c filter_mode="${1:-any}" branch_page branch_count branch_name has_secondary
local -a filtered_rn=() filtered_rd=() filtered_rp=()
local -a rn=() rd=() rp=()
ensure_login ||
return 1
while :
do
api GET "/user/repos?affiliation=owner&per_page=100&page=$page&sort=full_name" "" "$TMP_DIR/pick-repos.json" ||
return 1
count=$(jq 'length' "$TMP_DIR/pick-repos.json" 2>/dev/null)
is_pos_int "$count" ||
{ printf 'Resposta inválida da API ao listar repositórios.\n'; return 1; }
[ "$count" -gt 0 ] ||
break
while IFS=$'\t' read -r a b c
do
rn+=("$a")
rd+=("$b")
rp+=("$c")
done < <(jq -r '.[] | [.name,.default_branch,(.private|tostring)] | @tsv' "$TMP_DIR/pick-repos.json")
[ "$count" -lt 100 ] &&
break
page=$((page + 1))
done
if [ "$filter_mode" = secondary ]; then
    for ((i=0; i<${#rn[@]}; i++)); do
        has_secondary=0
        branch_page=1
        while :; do
            if ! api GET "/repos/$GITHUB_USER/$(urlencode "${rn[$i]}")/branches?per_page=100&page=$branch_page" "" "$TMP_DIR/pick-filter-branches.json"; then
                printf 'Falha ao verificar branches de %s; seleção interrompida para evitar lista incompleta.\n' "${rn[$i]}" >&2
                return 1
            fi
            branch_count=$(jq -r 'if type == "array" then length else -1 end' "$TMP_DIR/pick-filter-branches.json" 2>/dev/null) || return 1
            [ "$branch_count" -ge 0 ] || return 1
            if jq -e --arg default "${rd[$i]}" 'any(.[]; .name != $default)' "$TMP_DIR/pick-filter-branches.json" >/dev/null 2>&1; then
                has_secondary=1
                break
            fi
            [ "$branch_count" -lt 100 ] && break
            branch_page=$((branch_page + 1))
        done
        if [ "$has_secondary" -eq 1 ]; then
            filtered_rn+=("${rn[$i]}")
            filtered_rd+=("${rd[$i]}")
            filtered_rp+=("${rp[$i]}")
        fi
    done
    rn=("${filtered_rn[@]}")
    rd=("${filtered_rd[@]}")
    rp=("${filtered_rp[@]}")
fi
n=${#rn[@]}
if [ "$n" -eq 0 ]
then
printf '\n  Nenhum repositório elegível encontrado para esta operação.\n'
return 1
fi
while :
do
ui_picker_start "ESCOLHA O REPOSITÓRIO"
for ((i=0; i<n; i++))
do
if [ "${rp[$i]}" = true ]
then c="privado"
else c="público"
fi
ui_option_row "$((i+1))" "${rn[$i]}  |  $c"
done
ui_blank
ui_option_row 0 'CANCELAR'
ui_prompt
gui_read choice
ui_section_end
[ "$choice" = 0 ] && choice=C
case "$choice" in
c|C) return 1 ;;
esac
if in_range "$choice" "$n"
then
i=$((10#$choice - 1))
PICK_REPO="${rn[$i]}"
DEFAULT_BRANCH="${rd[$i]:-main}"
if [ "${rp[$i]}" = true ]
then PICK_REPO_PRIV="privado"
else PICK_REPO_PRIV="público"
fi
SELECTED_REPO="$PICK_REPO"
return 0
fi
printf '  Opção inválida.\n'
done
}


# Árvore remota recursiva da branch escolhida
load_remote_tree() {
api GET "/repos/$GITHUB_USER/$(urlencode "$PICK_REPO")/git/trees/$(urlencode "$PICK_BRANCH")?recursive=1" "" "$TMP_DIR/pick-tree.json" ||
return 1
if [ "$(jq -r '.truncated // false' "$TMP_DIR/pick-tree.json" 2>/dev/null)" = true ]
then printf '  AVISO: árvore truncada pela API; a lista pode estar incompleta.\n'
fi
return 0
}

# Filhos diretos de uma pasta: tipo (tree|blob) e caminho ("" = raiz)
remote_children() {
jq -r --arg t "$1" --arg p "$2" '
.tree[]? | select(.type == $t) | .path
| select(if $p == "" then (contains("/") | not)
else (startswith($p + "/") and ((.[($p | length) + 1:]) | contains("/") | not)) end)
' "$TMP_DIR/pick-tree.json" | sort
}

# Navegador de pastas remotas -> PICK_REMOTE_DIR ("" = raiz)
# $1 título   $2 permitir criar nova pasta (1/0)
pick_remote_folder() {
local title="${1:-PASTA REMOTA}" allow_new="${2:-0}" cur="" choice i n newname candidate
local -a subs=()
while :; do
mapfile -t subs < <(remote_children tree "$cur")
n=${#subs[@]}
ui_picker_start "$title  (repositório: $PICK_REPO | branch: $PICK_BRANCH)"
ui_info_row 'Pasta atual' "/${cur}"
ui_list_title 'PASTAS REMOTAS'
for ((i=0; i<n; i++)); do
    ui_option_row "$((i+1))" "${subs[$i]##*/}"
done
[ "$n" -eq 0 ] && ui_info_row 'Conteúdo' '(sem subpastas)'
if [ "$allow_new" = 1 ]; then
    ui_option_row "$((n+1))" 'Selecionar pasta atual'
    ui_option_row "$((n+2))" 'Informar nova subpasta (ENTER = pasta atual)'
else
    ui_option_row "$((n+1))" 'Selecionar pasta atual'
fi
ui_blank
ui_option_row 0 'CANCELAR'
ui_prompt
gui_read choice
ui_section_end
case "$choice" in
0|00) return 1 ;;
 '') PICK_REMOTE_DIR="$cur"; return 0 ;;
 "$((n+1))") PICK_REMOTE_DIR="$cur"; return 0 ;;
 "$((n+2))")
    if [ "$allow_new" = 1 ]; then
        printf '\n  Nova subpasta (ENTER = usar pasta atual): '
        gui_read newname
        if [ -n "$newname" ]; then
            candidate="${cur:+$cur/}$newname"
            if valid_name "$newname" && validate_remote_folder "$candidate"; then
                PICK_REMOTE_DIR="$candidate"
                return 0
            fi
            printf '  Nome de subpasta inválido.\n'
            continue
        fi
    fi
    PICK_REMOTE_DIR="$cur"
    return 0
    ;;
*)
    if in_range "$choice" "$n"; then
        cur="${subs[$((10#$choice - 1))]}"
    else
        printf '  Opção inválida.\n'
    fi
    ;;
esac
done
}

# Arquivos diretos de uma pasta remota -> PICK_REMOTE_FILE (caminho completo)
pick_remote_file() {
local folder="$1" i n choice
local -a files=()
mapfile -t files < <(remote_children blob "$folder")
n=${#files[@]}
if [ "$n" -eq 0 ]
then
printf '\n  Nenhum arquivo em /%s.\n' "$folder"
return 1
fi
while :
do
ui_picker_start "ESCOLHA O ARQUIVO  (pasta: /$folder)"
for ((i=0; i<n; i++))
do ui_option_row "$((i+1))" "${files[$i]##*/}"
done
ui_blank
ui_option_row 0 'CANCELAR'
ui_prompt
gui_read choice
ui_section_end
[ "$choice" = 0 ] && choice=C
case "$choice" in
c|C) return 1 ;;
esac
if in_range "$choice" "$n"
then
PICK_REMOTE_FILE="${files[$((10#$choice - 1))]}"
return 0
fi
printf '  Opção inválida.\n'
done
}

# ------------------------------ ENVIO ---------------------------------
upload_files_core() {
local -a files=("$@") good=() rows_src=() rows_dst=() rows_res=()
local f fname fsize total_size=0 src_dir repo branch dest_folder encoded_repo
local remote_path encoded_path http_code sha sent=0 failed=0 skipped=0 k shown commit_message
command -v base64 >/dev/null 2>&1 ||
{ printf 'Erro: base64 não está disponível.\n'; return 1; }
for f in "${files[@]}"
do
if [ -z "$f" ] ||
has_control_chars "$f" ||
[[ ! -f "$f" || -L "$f" || ! -r "$f" ]]
then
rows_res+=("FALHA|${f##*/} (inexistente ou sem leitura)")
failed=$((failed + 1))
continue
fi
fsize=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
fsize=${fsize:-0}
if [ "$fsize" -gt 104857600 ]
then
rows_res+=("FALHA|${f##*/} (acima de 100 MB; use git/LFS)")
failed=$((failed + 1))
continue
fi
good+=("$f")
total_size=$((total_size + fsize))
done
if [ "${#good[@]}" -eq 0 ]
then
printf '\nNenhum arquivo válido para enviar.\n'
draw_block "ARQUIVOS REJEITADOS" "${rows_res[@]}"
return 1
fi
pick_repository ||
{ printf 'Operação cancelada.\n'; return 0; }
pick_branch ||
{ printf 'Operação cancelada.\n'; return 0; }
load_remote_tree ||
return 1
pick_remote_folder "PASTA DE DESTINO NO GITHUB" 1 ||
{ printf 'Operação cancelada.\n'; return 0; }
repo="$PICK_REPO"
branch="$PICK_BRANCH"
dest_folder="$PICK_REMOTE_DIR"
encoded_repo=$(urlencode "$repo") ||
return 1
src_dir="$(dirname -- "${good[0]}")"
rows_src=("Pasta local|$src_dir" "Arquivos selecionados|${#good[@]}" "Tamanho total|$(human_size "$total_size")")
shown=0
for f in "${good[@]}"
do
shown=$((shown + 1))
[ "$shown" -le 12 ] ||
break
rows_src+=("Arquivo $shown|${f##*/}")
done
[ "${#good[@]}" -gt 12 ] &&
rows_src+=("...|e mais $(( ${#good[@]} - 12 )) arquivo(s)")
rows_dst=("Usuário|$GITHUB_USER" "Repositório|$repo ($PICK_REPO_PRIV)" "Branch|$branch" "Pasta destino|$(folder_label "$dest_folder")")
ui_heading "CONFERÊNCIA ANTES DO ENVIO"
draw_block "ORIGEM LOCAL" "${rows_src[@]}"
draw_block "DESTINO NO GITHUB" "${rows_dst[@]}"
commit_message_prompt "envio dos arquivos" || return 1
commit_message="$GITMENU_COMMIT_MESSAGE"
ask_yes_no "Confirma o envio?" ||
{ printf 'Operação cancelada.\n'; return 0; }
for f in "${good[@]}"
do
fname="$(basename -- "$f")"
if ! is_safe_path_component "$fname"
then
rows_res+=("FALHA|$fname (nome inválido)")
failed=$((failed + 1))
continue
fi
if [ -n "$dest_folder" ]
then remote_path="$dest_folder/$fname"
else remote_path="$fname"
fi
encoded_path=$(urlencode_path "$remote_path") ||
{ rows_res+=("FALHA|$fname (codificação)"); failed=$((failed + 1)); continue; }
http_code=$(curl -sS -o "$TMP_DIR/content.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$encoded_repo/contents/$encoded_path?ref=$(urlencode "$branch")") ||
http_code=000
sha=""
case "$http_code" in
200) sha=$(jq -r '.sha // empty' "$TMP_DIR/content.json") ;;
404) ;;
*) rows_res+=("FALHA|$fname (consulta HTTP $http_code)")
failed=$((failed + 1))
continue ;;
esac
if [ -n "$sha" ]
then
if ! ask_yes_no "O arquivo remoto /$remote_path já existe. Atualizar?"
then
rows_res+=("IGNORADO|$fname (já existe; mantido)")
skipped=$((skipped + 1))
continue
fi
fi
if ! base64 < "$f" | tr -d '\r\n' > "$TMP_DIR/upload-content.b64"
then
rows_res+=("FALHA|$fname (codificação base64)")
failed=$((failed + 1))
continue
fi
chmod 0600 "$TMP_DIR/upload-content.b64" 2>/dev/null ||
true
if ! jq -n --arg message "$commit_message" --rawfile content "$TMP_DIR/upload-content.b64" \
--arg branch "$branch" --arg sha "$sha" \
'{message:$message,content:($content|gsub("[\\r\\n]";"")),branch:$branch} + (if $sha != "" then {sha:$sha} else {} end)' > "$TMP_DIR/upload-payload.json"
then
rows_res+=("FALHA|$fname (preparação do envio)")
failed=$((failed + 1))
continue
fi
chmod 0600 "$TMP_DIR/upload-payload.json" 2>/dev/null ||
true
http_code=$(curl -sS -o "$TMP_DIR/upload.json" -w '%{http_code}' -X PUT \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" -H 'Content-Type: application/json' \
--data-binary "@$TMP_DIR/upload-payload.json" \
"$API_URL/repos/$GITHUB_USER/$encoded_repo/contents/$encoded_path") ||
http_code=000
if [[ "$http_code" == 200 || "$http_code" == 201 ]] &&
jq -e '.content.sha and .commit.sha' "$TMP_DIR/upload.json" >/dev/null 2>&1
then
k=$(jq -r '.commit.sha[0:7]' "$TMP_DIR/upload.json" 2>/dev/null)
rows_res+=("OK|$fname -> /$remote_path (commit $k)")
sent=$((sent + 1))
else
rows_res+=("FALHA|$fname (HTTP $http_code: $(jq -r '.message // "sem detalhes"' "$TMP_DIR/upload.json" 2>/dev/null))")
failed=$((failed + 1))
fi
done
ui_heading "RESUMO DA OPERAÇÃO — ENVIO"
draw_block "ORIGEM LOCAL" "${rows_src[@]}"
draw_block "DESTINO NO GITHUB" "${rows_dst[@]}"
draw_block "RESULTADO POR ARQUIVO" "${rows_res[@]}"
draw_block "TOTAIS" "Enviados|$sent" "Ignorados|$skipped" "Com falha|$failed" "Concluído em|$(now_str)"
[ "$failed" -eq 0 ]
}

upload_file() {
ensure_login ||
return 1
ui_operation_title 'ENVIAR ARQUIVO LOCAL AO GITHUB'
pick_local_folder "PASTA LOCAL DE ORIGEM" ||
{ printf 'Operação cancelada.\n'; return 0; }
pick_local_files single "$PICK_LOCAL_DIR" ||
{ printf 'Operação cancelada.\n'; return 0; }
upload_files_core "${PICK_LOCAL_FILES[@]}"
}

attach_single_file() {
upload_file
}

attach_multiple_files() {
ensure_login ||
return 1
ui_operation_title 'ENVIAR VÁRIOS ARQUIVOS AO GITHUB'
pick_local_folder "PASTA LOCAL DE ORIGEM" ||
{ printf 'Operação cancelada.\n'; return 0; }
pick_local_files multi "$PICK_LOCAL_DIR" ||
{ printf 'Operação cancelada.\n'; return 0; }
upload_files_core "${PICK_LOCAL_FILES[@]}"
}

# Mantida por compatibilidade: recebe lista JSON em GITHUB_ATTACHMENTS_JSON
upload_selected_attachments() {
local -a files=()
ensure_login ||
return 1
mapfile -t files < <(jq -r '.[]' <<< "${GITHUB_ATTACHMENTS_JSON:-[]}" 2>/dev/null)
[ "${#files[@]}" -gt 0 ] ||
{ printf 'Nenhum arquivo foi selecionado.\n'; return 1; }
upload_files_core "${files[@]}"
}

# ----------------------------- DOWNLOAD -------------------------------
download_file() {
local repo branch folder remote_path file_name encoded_path repo_encoded
local local_dir local_path http_code existed="Não" status="OK" detail fsize=0
local -a rows_src=() rows_dst=() rows_res=()
ensure_login ||
return 1
ui_operation_title 'BAIXAR ARQUIVO REMOTO'
pick_repository ||
{ printf 'Operação cancelada.\n'; return 0; }
# Seleção explícita do tipo de branch na opção 17.
local branch_mode
while :; do
    ui_picker_start "TIPO DE BRANCH  (repositório: $PICK_REPO)"
    ui_option_row 1 "Branch principal ($DEFAULT_BRANCH)"
    ui_option_row 2 'Branch secundária (selecionar)'
    ui_blank
    ui_option_row 0 'CANCELAR'
    ui_prompt
    gui_read branch_mode
    ui_section_end
    case "$branch_mode" in
        1|01) PICK_BRANCH="$DEFAULT_BRANCH"; break ;;
        2|02)
            pick_branch secondary || { printf 'Nenhuma branch secundária selecionada.\n'; return 0; }
            break ;;
        0|00) printf 'Operação cancelada.\n'; return 0 ;;
        *) printf 'Opção inválida.\n' ;;
    esac
done
load_remote_tree ||
return 1
pick_remote_folder "PASTA DE ORIGEM NO GITHUB" 0 ||
{ printf 'Operação cancelada.\n'; return 0; }
folder="$PICK_REMOTE_DIR"
pick_remote_file "$folder" ||
{ printf 'Operação cancelada.\n'; return 0; }
remote_path="$PICK_REMOTE_FILE"
file_name="${remote_path##*/}"
is_safe_path_component "$file_name" ||
{ printf 'Nome de arquivo remoto inválido.\n'; return 1; }
repo="$PICK_REPO"
branch="$PICK_BRANCH"
pick_local_folder "PASTA LOCAL DE DESTINO" ||
{ printf 'Operação cancelada.\n'; return 0; }
local_dir="$PICK_LOCAL_DIR"
local_path="$local_dir/$file_name"
if [ -L "$local_path" ]
then
printf 'O destino local é um link simbólico. Operação cancelada.\n'
return 1
fi
if [ -e "$local_path" ]
then
existed="Sim (será sobrescrito)"
fi
rows_src=("Usuário|$GITHUB_USER" "Repositório|$repo ($PICK_REPO_PRIV)" "Branch|$branch" "Pasta|$(folder_label "$folder")" "Arquivo|$file_name" "Caminho completo|/$remote_path")
rows_dst=("Pasta local|$local_dir" "Arquivo|$file_name" "Já existia?|$existed")
ui_heading "CONFERÊNCIA ANTES DO DOWNLOAD"
draw_block "ORIGEM NO GITHUB" "${rows_src[@]}"
draw_block "DESTINO LOCAL" "${rows_dst[@]}"
if [ -e "$local_path" ]
then
ask_yes_no "O arquivo local já existe. Sobrescrever?" ||
{ printf 'Operação cancelada.\n'; return 0; }
else
ask_yes_no "Confirma o download?" ||
{ printf 'Operação cancelada.\n'; return 0; }
fi
repo_encoded=$(urlencode "$repo") ||
return 1
encoded_path=$(urlencode_path "$remote_path") ||
return 1
http_code=$(curl -sS -L -o "$TMP_DIR/dl-raw.bin" -w '%{http_code}' \
-H 'Accept: application/vnd.github.raw+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$encoded_path?ref=$(urlencode "$branch")") ||
http_code=000
if [ "$http_code" != 200 ]
then
status="FALHA"
detail="HTTP $http_code ao baixar"
elif [ -L "$local_path" ]
then
status="FALHA"
detail="destino virou link simbólico"
else
local staging
staging=$(mktemp "$local_dir/.github-manager-download.XXXXXXXX") || return 1
if ! cp -- "$TMP_DIR/dl-raw.bin" "$staging" || ! chmod 0600 "$staging" || ! mv -f -- "$staging" "$local_path"; then
    rm -f -- "$staging"
    status="FALHA"
    detail="não foi possível gravar o arquivo local"
else
chmod 0600 "$local_path" 2>/dev/null ||
true
fsize=$(wc -c < "$local_path" 2>/dev/null | tr -d ' ')
detail="arquivo gravado"
fi
fi
rows_res=("Status|$status" "Detalhe|$detail" "Tamanho|$(human_size "${fsize:-0}")" "Concluído em|$(now_str)")
ui_heading "RESUMO DA OPERAÇÃO — DOWNLOAD"
draw_block "ORIGEM NO GITHUB" "${rows_src[@]}"
draw_block "DESTINO LOCAL" "${rows_dst[@]}"
draw_block "RESULTADO" "${rows_res[@]}"
[ "$status" = OK ]
}

# ======================================================================
# PARTE 2: demais menus com escolha numérica
# ======================================================================

# Branch do repositório escolhido -> PICK_BRANCH
# $1 = secondary: lista só branches secundárias (exclui a principal)
pick_branch() {
local only="${1:-}" page=1 count i n choice b
local -a bn=() fb=()
while :
do
api GET "/repos/$GITHUB_USER/$(urlencode "$PICK_REPO")/branches?per_page=100&page=$page" "" "$TMP_DIR/pick-branches.json" ||
return 1
count=$(jq 'length' "$TMP_DIR/pick-branches.json" 2>/dev/null)
is_pos_int "$count" ||
{ printf 'Resposta inválida da API ao listar branches.\n'; return 1; }
[ "$count" -gt 0 ] ||
break
mapfile -t -O "${#bn[@]}" bn < <(jq -r '.[].name' "$TMP_DIR/pick-branches.json")
[ "$count" -lt 100 ] &&
break
page=$((page + 1))
done
if [ "$only" = secondary ]
then
for b in "${bn[@]}"
do
[ "$b" = "$DEFAULT_BRANCH" ] ||
fb+=("$b")
done
bn=("${fb[@]}")
fi
n=${#bn[@]}
if [ "$n" -eq 0 ]
then
if [ "$only" = secondary ]
then printf '\n  Este repositório não possui branch secundária (só a principal: %s).\n' "$DEFAULT_BRANCH"
else printf '\n  Nenhuma branch encontrada.\n'
fi
return 1
fi
while :
do
if [ "$only" = secondary ]
then ui_picker_start "ESCOLHA A BRANCH SECUNDÁRIA  (repositório: $PICK_REPO)"
else ui_picker_start "ESCOLHA A BRANCH  (repositório: $PICK_REPO)"
fi
for ((i=0; i<n; i++))
do
if [ "${bn[$i]}" = "$DEFAULT_BRANCH" ]
then ui_option_row "$((i+1))" "${bn[$i]}  |  principal"
else ui_option_row "$((i+1))" "${bn[$i]}"
fi
done
ui_blank
ui_option_row 0 'CANCELAR'
ui_prompt
gui_read choice
ui_section_end
[ "$choice" = 0 ] && choice=C
case "$choice" in
c|C) return 1 ;;
"")
if [ "$only" != secondary ]
then
PICK_BRANCH="$DEFAULT_BRANCH"
return 0
fi
;;
esac
if in_range "$choice" "$n"
then
PICK_BRANCH="${bn[$((10#$choice - 1))]}"
return 0
fi
printf '  Opção inválida.\n'
done
}

# Todos os menus que pediam repositório digitado passam a usar a lista
select_repository() {
pick_repository "${1:-any}" ||
{ printf 'Operação cancelada.\n'; return 1; }
return 0
}

# Repositório + branch por número. modo: any | main | secondary
pick_repo_branch() {
local mode="${1:-any}"
if [ "$mode" = secondary ]; then
    pick_repository secondary || return 1
else
    pick_repository || return 1
fi
case "$mode" in
main)
PICK_BRANCH="$DEFAULT_BRANCH"
printf '\n  Branch principal selecionada: %s\n' "$PICK_BRANCH"
;;
secondary)
pick_branch secondary ||
return 1
;;
*)
pick_branch ||
return 1
;;
esac
SELECTED_REPO="$PICK_REPO"
SELECTED_BRANCH="$PICK_BRANCH"
return 0
}

commit_message_prompt() {
    local label="${1:-Atualização}" msg
    printf '\nMensagem do commit para %s (obrigatória): ' "$label"
    gui_read msg
    if [ -z "$msg" ] || has_control_chars "$msg" || [ "${#msg}" -gt 250 ]; then
        printf 'Mensagem inválida: informe de 1 a 250 caracteres sem controles.\n'
        return 1
    fi
    GITMENU_COMMIT_MESSAGE="$msg"
}
cancelled() { printf '\nOperação cancelada.\n'; }

# Baixa o conteúdo bruto (até 100 MB) -> imprime o código HTTP
fetch_remote_raw() {
local enc_repo enc_path code
enc_repo=$(urlencode "$1") ||
return 1
enc_path=$(urlencode_path "$3") ||
return 1
code=$(curl -sS -L -o "$4" -w '%{http_code}' \
-H 'Accept: application/vnd.github.raw+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$enc_repo/contents/$enc_path?ref=$(urlencode "$2")") ||
code=000
printf '%s' "$code"
}

# Código HTTP de um caminho em PICK_REPO/PICK_BRANCH (JSON em path-status.json)
remote_path_status() {
local enc_repo enc_path code
enc_repo=$(urlencode "$PICK_REPO") ||
return 1
enc_path=$(urlencode_path "$1") ||
return 1
code=$(curl -sS -o "$TMP_DIR/path-status.json" -w '%{http_code}' \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" \
"$API_URL/repos/$GITHUB_USER/$enc_repo/contents/$enc_path?ref=$(urlencode "$PICK_BRANCH")") ||
code=000
printf '%s' "$code"
}

# Move um arquivo remoto (grava no destino e remove a origem)
# retorno: 0 movido | 1 falha | 2 ignorado ; mensagem em MOVE_MSG
move_one_remote_file() {
local source_path="$1" destination_path="$2" conflict="$3"
local repo_encoded source_encoded destination_encoded source_sha target_sha="" status target_status payload code
MOVE_MSG=""
repo_encoded=$(urlencode "$PICK_REPO") ||
{ MOVE_MSG="codificação do repositório"; return 1; }
source_encoded=$(urlencode_path "$source_path") ||
{ MOVE_MSG="codificação da origem"; return 1; }
destination_encoded=$(urlencode_path "$destination_path") ||
{ MOVE_MSG="codificação do destino"; return 1; }
status=$(remote_path_status "$source_path")
if [ "$status" != 200 ]
then
MOVE_MSG="leitura da origem (HTTP $status)"
return 1
fi
source_sha=$(jq -r '.sha // empty' "$TMP_DIR/path-status.json" 2>/dev/null)
[ -n "$source_sha" ] ||
{ MOVE_MSG="SHA da origem indisponível"; return 1; }
code=$(fetch_remote_raw "$PICK_REPO" "$PICK_BRANCH" "$source_path" "$TMP_DIR/move-raw.bin")
[ "$code" = 200 ] ||
{ MOVE_MSG="download da origem (HTTP $code)"; return 1; }
if ! base64 < "$TMP_DIR/move-raw.bin" | tr -d '\r\n' > "$TMP_DIR/move-content.b64"
then
MOVE_MSG="codificação do conteúdo"
return 1
fi
chmod 0600 "$TMP_DIR/move-content.b64" 2>/dev/null ||
true
target_status=$(remote_path_status "$destination_path")
case "$target_status" in
404) ;;
200)
if [ "$conflict" = ask ]
then
if ask_yes_no "O destino /$destination_path já existe. Atualizar?"
then target_sha=$(jq -r '.sha // empty' "$TMP_DIR/path-status.json" 2>/dev/null)
else
MOVE_MSG="destino já existe; origem preservada"
return 2
fi
else
MOVE_MSG="destino já existe (não sobrescrito)"
return 2
fi
;;
*)
MOVE_MSG="verificação do destino (HTTP $target_status)"
return 1
;;
esac
if ! jq -n --arg message "$GITMENU_COMMIT_MESSAGE" \
--rawfile content "$TMP_DIR/move-content.b64" --arg branch "$PICK_BRANCH" --arg sha "$target_sha" \
'{message:$message,content:$content,branch:$branch} + (if $sha != "" then {sha:$sha} else {} end)' \
> "$TMP_DIR/move-upload-payload.json"
then
MOVE_MSG="preparação da gravação"
return 1
fi
chmod 0600 "$TMP_DIR/move-upload-payload.json" 2>/dev/null ||
true
status=$(curl -sS -o "$TMP_DIR/move-upload.json" -w '%{http_code}' -X PUT \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" -H 'Content-Type: application/json' \
--data-binary "@$TMP_DIR/move-upload-payload.json" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$destination_encoded") ||
status=000
case "$status" in
200|201) ;;
*) MOVE_MSG="gravação do destino (HTTP $status); origem preservada"
return 1 ;;
esac
payload=$(jq -n --arg message "$GITMENU_COMMIT_MESSAGE" --arg sha "$source_sha" --arg branch "$PICK_BRANCH" '{message:$message,sha:$sha,branch:$branch}') ||
{ MOVE_MSG="destino gravado; falha ao preparar remoção da origem"; return 1; }
status=$(curl -sS -o "$TMP_DIR/move-delete.json" -w '%{http_code}' -X DELETE \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" -H 'Content-Type: application/json' \
--data-binary "$payload" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/contents/$source_encoded") ||
status=000
if [ "$status" = 200 ] ||
[ "$status" = 204 ]
then
MOVE_MSG="movido com sucesso"
return 0
fi
MOVE_MSG="destino gravado, mas a origem NÃO foi removida (HTTP $status)"
return 1
}

# ---------------------- 02 / 03  mover um arquivo ---------------------
move_remote_files() {
local mode="$1" src_folder dst_folder file_name source_path destination_path rc st
local -a rows=()
ensure_login ||
return 1
if [ "$mode" = main ]
then ui_operation_title 'MOVER ARQUIVO NA MAIN'
else ui_operation_title 'MOVER ARQUIVO NA BRANCH SECUNDÁRIA'
fi
pick_repo_branch "$mode" ||
{ cancelled; return 0; }
load_remote_tree ||
return 1
pick_remote_folder "PASTA DE ORIGEM" 0 ||
{ cancelled; return 0; }
src_folder="$PICK_REMOTE_DIR"
pick_remote_file "$src_folder" ||
{ cancelled; return 0; }
source_path="$PICK_REMOTE_FILE"
file_name="${source_path##*/}"
pick_remote_folder "PASTA DE DESTINO" 1 ||
{ cancelled; return 0; }
dst_folder="$PICK_REMOTE_DIR"
if [ -n "$dst_folder" ]
then destination_path="$dst_folder/$file_name"
else destination_path="$file_name"
fi
if [ "$source_path" = "$destination_path" ]
then
printf '\nOrigem e destino são iguais; nada a mover.\n'
return 0
fi
rows=("Repositório|$PICK_REPO ($PICK_REPO_PRIV)" "Branch|$PICK_BRANCH" "Origem|/$source_path" "Destino|/$destination_path")
ui_heading "CONFERÊNCIA ANTES DE MOVER"
draw_block "MOVIMENTAÇÃO" "${rows[@]}"
ask_yes_no "Confirma mover este arquivo?" ||
{ cancelled; return 0; }
commit_message_prompt "movimentação do arquivo" || return 1
move_one_remote_file "$source_path" "$destination_path" ask
rc=$?
case "$rc" in
0) st="OK" ;;
2) st="IGNORADO" ;;
*) st="FALHA" ;;
esac
ui_heading "RESUMO DA OPERAÇÃO — MOVER ARQUIVO"
draw_block "MOVIMENTAÇÃO" "${rows[@]}"
draw_block "RESULTADO" "Status|$st" "Detalhe|$MOVE_MSG" "Concluído em|$(now_str)"
[ "$rc" -eq 0 ]
}

# ------------------- 04 / 05 / 06  mover todos ------------------------
# modo: main | secondary | any   (alinhado aos textos do menu)
move_all_files_bulk() {
local mode="$1" src_folder dst_folder prefix p base dest st i total d
local moved=0 failed=0 skipped=0 rc shown=0 pmode
local -a paths=() dests=() rows=() rows_res=()
local -A seen=()
ensure_login ||
return 1
ui_operation_title 'MOVIMENTAÇÃO EM LOTE DE ARQUIVOS'
pmode="$mode"
[ "$mode" = folder ] &&
pmode=any
pick_repo_branch "$pmode" ||
{ cancelled; return 0; }
load_remote_tree ||
return 1
if [ "$(jq -r '.truncated // false' "$TMP_DIR/pick-tree.json")" = true ]
then
printf 'A árvore do GitHub veio truncada. Operação cancelada para não mover só parte dos arquivos.\n'
return 1
fi
pick_remote_folder "PASTA DE ORIGEM (todos os arquivos dela serão movidos)" 0 ||
{ cancelled; return 0; }
src_folder="$PICK_REMOTE_DIR"
pick_remote_folder "PASTA DE DESTINO" 1 ||
{ cancelled; return 0; }
dst_folder="$PICK_REMOTE_DIR"
if [ -n "$src_folder" ] &&
{ [ "$dst_folder" = "$src_folder" ] || [[ "$dst_folder" == "$src_folder/"* ]]; }
then
printf '\nDestino não pode ser a própria origem nem uma subpasta dela.\n'
return 1
fi
if [ -n "$src_folder" ]
then prefix="$src_folder/"
else prefix=""
fi
while IFS= read -r p
do
[ -n "$p" ] ||
continue
base="${p#"$prefix"}"
if [ -n "$dst_folder" ]
then dest="$dst_folder/$base"
else dest="$base"
fi
[ "$p" = "$dest" ] &&
continue
paths+=("$p")
dests+=("$dest")
done < <(jq -r --arg prefix "$prefix" '.tree[]? | select(.type == "blob") | .path | select($prefix == "" or startswith($prefix))' "$TMP_DIR/pick-tree.json")
total=${#paths[@]}
if [ "$total" -eq 0 ]
then
printf '\nNenhum arquivo elegível foi encontrado.\n'
return 0
fi
for d in "${dests[@]}"
do
if [[ -n "${seen[$d]+x}" ]]
then
printf '\nColisão: mais de um arquivo seria gravado como "%s". Nada foi alterado.\n' "$d"
return 1
fi
seen[$d]=1
done
for d in "${dests[@]}"
do
st=$(remote_path_status "$d")
case "$st" in
404) ;;
200) printf '\nDestino já existe: %s. Nada foi alterado. Escolha outra pasta de destino.\n' "$d"
return 1 ;;
*) printf '\nNão foi possível validar o destino %s (HTTP %s). Nada foi alterado.\n' "$d" "$st"
return 1 ;;
esac
done
rows=("Repositório|$PICK_REPO ($PICK_REPO_PRIV)" "Branch|$PICK_BRANCH" "Pasta de origem|$(folder_label "$src_folder")" "Pasta de destino|$(folder_label "$dst_folder")" "Arquivos a mover|$total")
for ((i=0; i<total && i<15; i++))
do rows+=("Mover $((i+1))|/${paths[$i]} -> /${dests[$i]}")
done
[ "$total" -gt 15 ] &&
rows+=("...|e mais $((total - 15)) arquivo(s)")
commit_message_prompt "movimentação em lote" || return 1
ui_heading "CONFERÊNCIA ANTES DE MOVER"
draw_block "MOVIMENTAÇÃO EM LOTE" "${rows[@]}"
ask_yes_no "Confirma mover TODOS os arquivos listados?" ||
{ cancelled; return 0; }
# Uma única transação Git: todas as mudanças no mesmo commit.
local repo_encoded branch_ref_encoded branch_sha base_tree_sha new_tree_sha new_commit_sha payload
repo_encoded=$(urlencode "$PICK_REPO") || return 1
branch_ref_encoded=$(urlencode_path "$PICK_BRANCH") || return 1
api GET "/repos/$GITHUB_USER/$repo_encoded/git/ref/heads/$branch_ref_encoded" "" "$TMP_DIR/bulk-ref.json" || return 1
branch_sha=$(jq -r '.object.sha // empty' "$TMP_DIR/bulk-ref.json")
[ -n "$branch_sha" ] || return 1
api GET "/repos/$GITHUB_USER/$repo_encoded/git/commits/$branch_sha" "" "$TMP_DIR/bulk-base.json" || return 1
base_tree_sha=$(jq -r '.tree.sha // empty' "$TMP_DIR/bulk-base.json")
[ -n "$base_tree_sha" ] || return 1
api GET "/repos/$GITHUB_USER/$repo_encoded/git/trees/$base_tree_sha?recursive=1" "" "$TMP_DIR/bulk-current-tree.json" || return 1
[ "$(jq -r '.truncated // false' "$TMP_DIR/bulk-current-tree.json")" != true ] || {
    printf 'Árvore truncada; movimentação cancelada.\n'; return 1;
}
# Confirmar que cada origem ainda existe e cada destino continua livre.
for ((i=0; i<total; i++)); do
    if ! jq -e --arg p "${paths[$i]}" '.tree[]? | select(.path == $p and .type == "blob")' "$TMP_DIR/bulk-current-tree.json" >/dev/null; then
        printf 'Origem alterada: %s. Nenhuma movimentação efetuada.\n' "${paths[$i]}"
        return 1
    fi
    if jq -e --arg p "${dests[$i]}" '.tree[]? | select(.path == $p)' "$TMP_DIR/bulk-current-tree.json" >/dev/null; then
        printf 'Destino ocupado: %s. Nenhuma movimentação efetuada.\n' "${dests[$i]}"
        return 1
    fi
done
# Criar entradas de árvore preservando SHA, modo e conteúdo dos arquivos.
: > "$TMP_DIR/bulk-entries.jsonl"
for ((i=0; i<total; i++)); do
    jq -cn --arg source "${paths[$i]}" --arg target "${dests[$i]}" --slurpfile data "$TMP_DIR/bulk-current-tree.json" '
        ($data[0].tree[] | select(.path == $source and .type == "blob")) as $f |
        {path:$target,mode:$f.mode,type:"blob",sha:$f.sha},
        {path:$source,mode:$f.mode,type:"blob",sha:null}
    ' >> "$TMP_DIR/bulk-entries.jsonl" || return 1
done
payload=$(jq -sc --arg base "$base_tree_sha" '{base_tree:$base,tree:.}' "$TMP_DIR/bulk-entries.jsonl") || return 1
api POST "/repos/$GITHUB_USER/$repo_encoded/git/trees" "$payload" "$TMP_DIR/bulk-new-tree.json" || return 1
new_tree_sha=$(jq -r '.sha // empty' "$TMP_DIR/bulk-new-tree.json")
[ -n "$new_tree_sha" ] || return 1
payload=$(jq -nc --arg msg "$GITMENU_COMMIT_MESSAGE" --arg tree "$new_tree_sha" --arg parent "$branch_sha" '{message:$msg,tree:$tree,parents:[$parent]}') || return 1
api POST "/repos/$GITHUB_USER/$repo_encoded/git/commits" "$payload" "$TMP_DIR/bulk-new-commit.json" || return 1
new_commit_sha=$(jq -r '.sha // empty' "$TMP_DIR/bulk-new-commit.json")
[ -n "$new_commit_sha" ] || return 1
# Atualização não forçada: se houver conflito, preservar branch existente.
payload=$(jq -nc --arg sha "$new_commit_sha" '{sha:$sha,force:false}') || return 1
api PATCH "/repos/$GITHUB_USER/$repo_encoded/git/refs/heads/$branch_ref_encoded" "$payload" "$TMP_DIR/bulk-update-ref.json" || {
    printf 'Não foi possível atualizar a branch; arquivos originais preservados.\n'
    return 1
}
moved=$total
for ((i=0; i<total && i<15; i++)); do
    rows_res+=("OK|/${paths[$i]} -> /${dests[$i]}")
done
[ "$total" -gt 15 ] && rows_res+=("...|e mais $((total-15)) arquivo(s)")
ui_heading "RESUMO DA OPERAÇÃO — MOVER EM LOTE"
draw_block "MOVIMENTAÇÃO EM LOTE" "${rows[@]:0:5}"
draw_block "RESULTADO POR ARQUIVO" "${rows_res[@]}"
draw_block "TOTAIS" "Movidos|$moved" "Ignorados|$skipped" "Com falha|$failed" "Concluído em|$(now_str)"
[ "$failed" -eq 0 ]
}
# Mapeamento ORIGINAL do menu preservado (04 = folder, 05 = main, 06 = secondary)
move_all_repository_folder_files() { move_all_files_bulk folder; }
move_all_main_branch_files() { move_all_files_bulk main; }
move_all_secondary_branch_files() { move_all_files_bulk secondary; }

# -------------------------- 09  arquivos locais -----------------------
list_local_files() {
local dir i n fsize
local -a names=() rows=()
pick_local_folder "PASTA LOCAL A LISTAR" ||
{ cancelled; return 0; }
dir="$PICK_LOCAL_DIR"
mapfile -t names < <(find "$dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort)
n=${#names[@]}
rows=("Pasta|$dir" "Total de arquivos|$n")
for ((i=0; i<n && i<60; i++))
do
fsize=$(wc -c < "$dir/${names[$i]}" 2>/dev/null | tr -d ' ')
rows+=("Arquivo $((i+1))|${names[$i]}  ($(human_size "${fsize:-0}"))")
done
[ "$n" -gt 60 ] &&
rows+=("...|e mais $((n - 60)) arquivo(s)")
ui_heading "ARQUIVOS LOCAIS"
draw_block "PASTA LOCAL" "${rows[@]}"
}

# ------------------------ 10 / 11  arquivos remotos -------------------
list_remote_folder_files() {
local mode="$1" folder i n
local -a files=() rows=()
ensure_login ||
return 1
if [ "$mode" = main ]
then ui_operation_title 'ARQUIVOS DA MAIN'
else ui_operation_title 'ARQUIVOS DA BRANCH SECUNDÁRIA'
fi
pick_repo_branch "$mode" ||
{ cancelled; return 0; }
load_remote_tree ||
return 1
pick_remote_folder "PASTA A LISTAR" 0 ||
{ cancelled; return 0; }
folder="$PICK_REMOTE_DIR"
mapfile -t files < <(remote_children blob "$folder")
n=${#files[@]}
rows=("Repositório|$PICK_REPO ($PICK_REPO_PRIV)" "Branch|$PICK_BRANCH" "Pasta|$(folder_label "$folder")" "Arquivos encontrados|$n")
for ((i=0; i<n && i<60; i++))
do rows+=("Arquivo $((i+1))|${files[$i]##*/}")
done
[ "$n" -gt 60 ] &&
rows+=("...|e mais $((n - 60)) arquivo(s)")
ui_heading "ARQUIVOS REMOTOS"
draw_block "PASTA NO GITHUB" "${rows[@]}"
}

# ------------------------ 01  comparar local x remoto -----------------
compare_local_remote_file() {
local lpath rpath code remote_tmp rdate ldate lsize rsize result enc_repo enc_path
local -a rows_l=() rows_r=()
ensure_login ||
return 1
ui_operation_title 'COMPARAR ARQUIVO LOCAL COM REMOTO NO GITHUB'
if ! command -v diff >/dev/null 2>&1 ||
! command -v cmp >/dev/null 2>&1
then
printf 'Erro: os comandos diff e cmp são necessários.\n'
return 1
fi
pick_local_folder "PASTA LOCAL DO ARQUIVO" ||
{ cancelled; return 0; }
pick_local_files single "$PICK_LOCAL_DIR" ||
{ cancelled; return 0; }
lpath="${PICK_LOCAL_FILES[0]}"
pick_repo_branch any ||
{ cancelled; return 0; }
load_remote_tree ||
return 1
pick_remote_folder "PASTA REMOTA DO ARQUIVO" 0 ||
{ cancelled; return 0; }
pick_remote_file "$PICK_REMOTE_DIR" ||
{ cancelled; return 0; }
rpath="$PICK_REMOTE_FILE"
remote_tmp="$TMP_DIR/remote-file"
code=$(fetch_remote_raw "$PICK_REPO" "$PICK_BRANCH" "$rpath" "$remote_tmp")
if [ "$code" != 200 ]
then
printf '\nErro ao baixar o arquivo remoto (HTTP %s).\n' "$code"
return 1
fi
chmod 0600 "$remote_tmp" 2>/dev/null ||
true
enc_repo=$(urlencode "$PICK_REPO") ||
return 1
enc_path=$(urlencode_path "$rpath") ||
return 1
rdate="indisponível"
if api GET "/repos/$GITHUB_USER/$enc_repo/commits?path=$enc_path&sha=$(urlencode "$PICK_BRANCH")&per_page=1" "" "$TMP_DIR/compare-commits.json"
then rdate=$(jq -r '.[0].commit.committer.date // .[0].commit.author.date // "indisponível"' "$TMP_DIR/compare-commits.json" 2>/dev/null)
fi
ldate=$(stat -c '%y' "$lpath" 2>/dev/null || stat -f '%Sm' "$lpath" 2>/dev/null || printf 'indisponível')
lsize=$(wc -c < "$lpath" 2>/dev/null | tr -d ' ')
rsize=$(wc -c < "$remote_tmp" 2>/dev/null | tr -d ' ')
rows_l=("Caminho|$lpath" "Modificado em|$ldate" "Tamanho|$(human_size "${lsize:-0}")")
rows_r=("Usuário|$GITHUB_USER" "Repositório|$PICK_REPO ($PICK_REPO_PRIV)" "Branch|$PICK_BRANCH" "Caminho|/$rpath" "Último commit|$rdate" "Tamanho|$(human_size "${rsize:-0}")")
if cmp -s "$lpath" "$remote_tmp"
then result="ARQUIVOS IGUAIS"
else result="ARQUIVOS DIFERENTES"
fi
ui_heading "RESUMO DA OPERAÇÃO — COMPARAÇÃO"
draw_block "ARQUIVO LOCAL" "${rows_l[@]}"
draw_block "ARQUIVO REMOTO NO GITHUB" "${rows_r[@]}"
draw_block "RESULTADO" "Situação|$result" "Concluído em|$(now_str)"
if [ "$result" = "ARQUIVOS DIFERENTES" ]
then
printf '  DIFERENÇAS (LOCAL = - ; REMOTO = +), até 200 linhas:\n\n'
diff -u --label "LOCAL: ${lpath##*/}" --label "REMOTO: $PICK_REPO/$rpath ($PICK_BRANCH)" "$lpath" "$remote_tmp" | sed -n '1,200p'
fi
return 0
}

# ---------------------------- 12  excluir repositório -----------------
delete_repository() {
ensure_login ||
return 1
pick_repository ||
{ cancelled; return 0; }
ui_heading "CONFERÊNCIA ANTES DE EXCLUIR"
draw_block "REPOSITÓRIO A EXCLUIR" "Usuário|$GITHUB_USER" "Repositório|$PICK_REPO" "Visibilidade|$PICK_REPO_PRIV" "Aviso|exclusão PERMANENTE"
ask_yes_no "ATENÇÃO: excluir permanentemente $GITHUB_USER/$PICK_REPO?" ||
{ cancelled; return 0; }
if api DELETE "/repos/$GITHUB_USER/$(urlencode "$PICK_REPO")"
then
ui_heading "RESUMO DA OPERAÇÃO — EXCLUSÃO"
draw_block "RESULTADO" "Status|OK" "Repositório|$PICK_REPO" "Concluído em|$(now_str)"
else return 1
fi
}

# ---------------------------- 16  excluir arquivo remoto --------------
delete_remote_file() {
local folder path sha message encoded_path repo_encoded payload
local -a rows=()
ensure_login ||
return 1
ui_operation_title 'EXCLUIR ARQUIVO REMOTO'
pick_repo_branch any ||
{ cancelled; return 0; }
load_remote_tree ||
return 1
pick_remote_folder "PASTA DO ARQUIVO A EXCLUIR" 0 ||
{ cancelled; return 0; }
folder="$PICK_REMOTE_DIR"
pick_remote_file "$folder" ||
{ cancelled; return 0; }
path="$PICK_REMOTE_FILE"
sha=$(jq -r --arg p "$path" '.tree[]? | select(.type == "blob" and .path == $p) | .sha' "$TMP_DIR/pick-tree.json" 2>/dev/null)
[ -n "$sha" ] ||
{ printf 'Não foi possível confirmar o arquivo "%s" na branch escolhida.\n' "$path"; return 1; }
commit_message_prompt "exclusão do arquivo" || return 1
message="$GITMENU_COMMIT_MESSAGE"
rows=("Repositório|$PICK_REPO ($PICK_REPO_PRIV)" "Branch|$PICK_BRANCH" "Arquivo|/$path" "Mensagem do commit|$message")
ui_heading "CONFERÊNCIA ANTES DE EXCLUIR"
draw_block "ARQUIVO A EXCLUIR" "${rows[@]}"
ask_yes_no "Confirma a exclusão deste arquivo?" ||
{ cancelled; return 0; }
repo_encoded=$(urlencode "$PICK_REPO") ||
return 1
encoded_path=$(urlencode_path "$path") ||
return 1
payload=$(jq -n --arg message "$message" --arg sha "$sha" --arg branch "$PICK_BRANCH" '{message:$message,sha:$sha,branch:$branch}') ||
return 1
if api DELETE "/repos/$GITHUB_USER/$repo_encoded/contents/$encoded_path" "$payload" "$TMP_DIR/del-file.json"
then
ui_heading "RESUMO DA OPERAÇÃO — EXCLUSÃO"
draw_block "ARQUIVO EXCLUÍDO" "${rows[@]}"
draw_block "RESULTADO" "Status|OK" "Concluído em|$(now_str)"
else return 1
fi
}

# ------------------- 14 / 15  excluir pasta (main / secundária) -------
# Mantém o comportamento original: exclui os arquivos DIRETOS da pasta.
delete_folder_core() {
local mode="$1" folder prefix repo_encoded branch_encoded head_sha base_tree_sha
local new_tree_sha new_commit_sha payload confirm total current_total
local -a rows=()
ensure_login || return 1
pick_repo_branch "$mode" || { cancelled; return 0; }
load_remote_tree || return 1
if [ "$(jq -r '.truncated // false' "$TMP_DIR/pick-tree.json")" = true ]; then
    printf 'Árvore incompleta: exclusão bloqueada.\n' >&2; return 1
fi
pick_remote_folder "PASTA A EXCLUIR" 0 || { cancelled; return 0; }
folder="$PICK_REMOTE_DIR"
[ -n "$folder" ] || { printf 'A raiz não pode ser excluída.\n'; return 1; }
prefix="$folder/"
total=$(jq -r --arg p "$prefix" '[.tree[]? | select(.type == "blob" and (.path | startswith($p)))] | length' "$TMP_DIR/pick-tree.json") || return 1
[ "$total" -gt 0 ] || { printf 'Pasta sem arquivos: %s\n' "$folder"; return 1; }
ui_heading 'CONFERÊNCIA ANTES DE EXCLUIR'
draw_block 'PASTA A EXCLUIR' "Repositório|$PICK_REPO" "Branch|$PICK_BRANCH" "Pasta|/$folder" "Arquivos incluindo subpastas|$total" 'Transação|Um único commit, sem exclusão parcial'
commit_message_prompt 'exclusão da pasta' || return 1
printf 'Digite DELETAR para confirmar: '
gui_read confirm
[ "$confirm" = DELETAR ] || { cancelled; return 0; }
repo_encoded=$(urlencode "$PICK_REPO") || return 1
branch_encoded=$(urlencode_path "$PICK_BRANCH") || return 1
api GET "/repos/$GITHUB_USER/$repo_encoded/git/ref/heads/$branch_encoded" '' "$TMP_DIR/del-folder-ref.json" || return 1
head_sha=$(jq -r '.object.sha // empty' "$TMP_DIR/del-folder-ref.json")
[ -n "$head_sha" ] || return 1
api GET "/repos/$GITHUB_USER/$repo_encoded/git/commits/$head_sha" '' "$TMP_DIR/del-folder-head.json" || return 1
base_tree_sha=$(jq -r '.tree.sha // empty' "$TMP_DIR/del-folder-head.json")
[ -n "$base_tree_sha" ] || return 1
api GET "/repos/$GITHUB_USER/$repo_encoded/git/trees/$base_tree_sha?recursive=1" '' "$TMP_DIR/del-folder-current.json" || return 1
[ "$(jq -r '.truncated // false' "$TMP_DIR/del-folder-current.json")" != true ] || { printf 'Árvore atual truncada; cancelado.\n'; return 1; }
current_total=$(jq -r --arg p "$prefix" '[.tree[]? | select(.type == "blob" and (.path | startswith($p)))] | length' "$TMP_DIR/del-folder-current.json") || return 1
[ "$current_total" = "$total" ] || { printf 'Conteúdo alterado durante a operação; cancelado.\n'; return 1; }
# Confere caminhos, SHA e modo dos arquivos antes de aplicar qualquer mudança.
if ! jq -e -n --slurpfile a "$TMP_DIR/pick-tree.json" --slurpfile b "$TMP_DIR/del-folder-current.json" --arg p "$prefix" '
  ([ $a[0].tree[]? | select(.type == "blob" and (.path | startswith($p))) | [.path,.sha,.mode] ] | sort) ==
  ([ $b[0].tree[]? | select(.type == "blob" and (.path | startswith($p))) | [.path,.sha,.mode] ] | sort)
' >/dev/null; then
    printf 'Arquivos da pasta foram modificados; cancelado.\n'; return 1
fi
payload=$(jq -c --arg prefix "$prefix" --arg base "$base_tree_sha" '{base_tree:$base,tree:[.tree[]? | select(.type == "blob" and (.path | startswith($prefix))) | {path:.path,mode:.mode,type:"blob",sha:null}]}' "$TMP_DIR/del-folder-current.json") || return 1
api POST "/repos/$GITHUB_USER/$repo_encoded/git/trees" "$payload" "$TMP_DIR/del-folder-tree-created.json" || return 1
new_tree_sha=$(jq -r '.sha // empty' "$TMP_DIR/del-folder-tree-created.json")
[ -n "$new_tree_sha" ] || return 1
payload=$(jq -n --arg msg "$GITMENU_COMMIT_MESSAGE" --arg tree "$new_tree_sha" --arg parent "$head_sha" '{message:$msg,tree:$tree,parents:[$parent]}') || return 1
api POST "/repos/$GITHUB_USER/$repo_encoded/git/commits" "$payload" "$TMP_DIR/del-folder-commit-created.json" || return 1
new_commit_sha=$(jq -r '.sha // empty' "$TMP_DIR/del-folder-commit-created.json")
[ -n "$new_commit_sha" ] || return 1
payload=$(jq -n --arg sha "$new_commit_sha" '{sha:$sha,force:false}') || return 1
api PATCH "/repos/$GITHUB_USER/$repo_encoded/git/refs/heads/$branch_encoded" "$payload" "$TMP_DIR/del-folder-ref-updated.json" || { printf 'Branch não atualizada; arquivos preservados.\n'; return 1; }
ui_heading 'RESUMO DA EXCLUSÃO'
draw_block 'RESULTADO' 'Status|OK' "Arquivos excluídos|$total" "Branch|$PICK_BRANCH" "Commit|$new_commit_sha"
}
delete_folder_main() { delete_folder_core main; }
delete_folder_secondary_branch() { delete_folder_core secondary; }

# ------------------------------ 19  clonar ----------------------------
clone_third_party_repository() {
local url parent base dest
command -v git >/dev/null 2>&1 ||
{ printf 'Git não está instalado.\n'; return 1; }
ui_picker_start '19 - CLONAR REPOSITÓRIO DE TERCEIROS'
ui_content_row 'Informe a URL HTTPS ou SSH do repositório.'
ui_content_row 'Origem: GitHub ou servidor Git autorizado.'
ui_frame_line '┗' '┛'
printf '  URL HTTPS ou SSH: '
gui_read url
[ -n "$url" ] ||
{ printf 'URL inválida.\n'; return 1; }
case "$url" in
https://*|ssh://*|git@*:* ) ;;
*) printf 'Origem bloqueada: use somente URL HTTPS ou SSH. Caminhos locais e protocolos auxiliares não são aceitos.\n'
return 1 ;;
esac
base="${url%/}"
base="${base##*/}"
base="${base##*:}"
base="${base%.git}"
valid_name "$base" ||
{ printf 'Não foi possível determinar o nome da pasta do repositório.\n'; return 1; }
pick_local_folder "PASTA LOCAL ONDE O REPOSITÓRIO SERÁ CLONADO" ||
{ cancelled; return 0; }
parent="$PICK_LOCAL_DIR"
dest="$parent/$base"
[[ ! -e "$dest" && ! -L "$dest" ]] ||
{ printf 'O destino já existe: %s. Clone cancelado para evitar sobrescrita.\n' "$dest"; return 1; }
ui_heading "CONFERÊNCIA ANTES DE CLONAR"
draw_block "CLONAGEM" "Origem|$url" "Destino local|$dest"
ask_yes_no "Confirma clonar?" ||
{ cancelled; return 0; }
git clone -- "$url" "$dest"
}

# --------------------------- 22  criar repositório --------------------
create_repository_main() {
local name description choice private payload
ensure_login ||
return 1
printf '\nNome do novo repositório (digitação necessária): '
gui_read name
valid_name "$name" ||
{ printf 'Nome inválido.\n'; return 1; }
printf 'Descrição (opcional): '
gui_read description
ui_picker_start 'VISIBILIDADE DO REPOSITÓRIO'
ui_option_row 1 'Privado'
ui_option_row 2 'Público'
ui_blank
ui_option_row 0 'CANCELAR'
ui_prompt
gui_read choice
ui_section_end
case "$choice" in
1) private=true ;;
2) private=false ;;
0) printf 'Operação cancelada.\n'; return 0 ;;
*) printf 'Opção inválida.\n'
return 1 ;;
esac
ui_heading 'CONFERÊNCIA — CRIAR REPOSITÓRIO'
draw_block 'NOVO REPOSITÓRIO' "Nome|$name" "Descrição|${description:-Sem descrição}" "Privado|$private" 'Inicialização|README e commit inicial do GitHub'
ask_yes_no 'Confirma a criação?' || { cancelled; return 0; }
payload=$(jq -n \
--arg name "$name" \
--arg description "$description" \
--argjson private "$private" \
'{name:$name,description:$description,private:$private,auto_init:true}')
if api POST "/user/repos" "$payload"
then printf '\nRepositório criado: %s/%s\n' "$GITHUB_USER" "$name"
fi
}

# --------------------------- 26  renomear repositório -----------------
rename_repository() {
local new_name payload
ensure_login ||
return 1
pick_repository ||
{ cancelled; return 0; }
printf '\n  Repositório escolhido: %s\n' "$PICK_REPO"
printf 'Novo nome do repositório (digitação necessária): '
gui_read new_name
valid_name "$new_name" ||
{ printf 'Novo nome inválido.\n'; return 1; }
[ "$new_name" != "$PICK_REPO" ] ||
{ printf 'O nome novo é igual ao atual.\n'; return 1; }
payload=$(jq -n --arg name "$new_name" '{name:$name}')
if api PATCH "/repos/$GITHUB_USER/$(urlencode "$PICK_REPO")" "$payload"
then printf '\nRepositório renomeado: %s -> %s\n' "$PICK_REPO" "$new_name"
fi
}

# --------------------------- 28  renomear pasta -----------------------
rename_folder_secondary_branch() {
local old_folder new_folder repo_encoded branch_ref_encoded branch_sha commit_tree_sha
local old_prefix new_prefix confirm payload new_tree_sha new_commit_sha update_status total
ensure_login ||
return 1
ui_operation_title 'RENOMEAR PASTA'
pick_repo_branch any ||
{ cancelled; return 0; }
load_remote_tree ||
return 1
if [ "$(jq -r '.truncated // false' "$TMP_DIR/pick-tree.json")" = true ]
then
printf 'A árvore do repositório foi truncada pela API. Renomeação cancelada para evitar alterações incompletas.\n'
return 1
fi
pick_remote_folder "PASTA A RENOMEAR" 0 ||
{ cancelled; return 0; }
old_folder="$PICK_REMOTE_DIR"
[ -n "$old_folder" ] ||
{ printf '\nEscolha uma pasta; a raiz não pode ser renomeada.\n'; return 1; }
printf '\n  Agora escolha o NOVO caminho: navegue até a pasta pai, use [N] para digitar o novo nome e [S] para confirmar.\n'
pick_remote_folder "NOVO CAMINHO DA PASTA" 1 ||
{ cancelled; return 0; }
new_folder="$PICK_REMOTE_DIR"
[ -n "$new_folder" ] ||
{ printf '\nO novo caminho não pode ser a raiz.\n'; return 1; }
[ "$old_folder" != "$new_folder" ] ||
{ printf '\nO caminho novo é igual ao atual. Nenhuma alteração realizada.\n'; return 1; }
if [[ "$new_folder" == "$old_folder/"* ]]
then
printf '\nO novo caminho não pode ficar dentro da própria pasta.\n'
return 1
fi
old_prefix="$old_folder/"
new_prefix="$new_folder/"
if jq -e --arg prefix "$new_prefix" --arg exact "$new_folder" \
'.tree[]? | select(.path == $exact or (.path | startswith($prefix)))' \
"$TMP_DIR/pick-tree.json" >/dev/null 2>&1
then
printf '\nO destino já existe: %s. Renomeação cancelada para evitar sobrescrita.\n' "$new_folder"
return 1
fi
total=$(jq -r --arg prefix "$old_prefix" '[.tree[]? | select(.type == "blob" and (.path | startswith($prefix)))] | length' "$TMP_DIR/pick-tree.json")
[ "${total:-0}" -gt 0 ] ||
{ printf '\nA pasta atual não contém arquivos.\n'; return 1; }
ui_heading "CONFERÊNCIA ANTES DE RENOMEAR"
draw_block "RENOMEAR PASTA" "Repositório|$PICK_REPO ($PICK_REPO_PRIV)" "Branch|$PICK_BRANCH" "Pasta atual|/$old_folder" "Novo caminho|/$new_folder" "Arquivos movidos|$total"
printf 'Digite RENOMEAR para confirmar: '
gui_read confirm
[ "$confirm" = RENOMEAR ] ||
{ cancelled; return 0; }
commit_message_prompt "renomeação da pasta" || return 1
repo_encoded=$(urlencode "$PICK_REPO") ||
return 1
branch_ref_encoded=$(urlencode_path "$PICK_BRANCH") ||
return 1
api GET "/repos/$GITHUB_USER/$repo_encoded/git/ref/heads/$branch_ref_encoded" "" "$TMP_DIR/rename-folder-branch-ref.json" ||
{ printf 'A branch não foi localizada.\n'; return 1; }
branch_sha=$(jq -r '.object.sha // empty' "$TMP_DIR/rename-folder-branch-ref.json")
[ -n "$branch_sha" ] ||
{ printf 'Não foi possível obter o commit da BRANCH.\n'; return 1; }
api GET "/repos/$GITHUB_USER/$repo_encoded/git/commits/$branch_sha" "" "$TMP_DIR/rename-folder-commit.json" ||
return 1
commit_tree_sha=$(jq -r '.tree.sha // empty' "$TMP_DIR/rename-folder-commit.json")
[ -n "$commit_tree_sha" ] ||
{ printf 'Não foi possível obter a árvore da BRANCH.\n'; return 1; }
cp -- "$TMP_DIR/pick-tree.json" "$TMP_DIR/rename-folder-original-tree.json" || return 1
# Refazer listagem com a árvore do commit atualmente apontado pela branch.
api GET "/repos/$GITHUB_USER/$repo_encoded/git/trees/$commit_tree_sha?recursive=1" "" "$TMP_DIR/pick-tree.json" || return 1
if [ "$(jq -r '.truncated // false' "$TMP_DIR/pick-tree.json")" = true ]; then
    printf 'Árvore atual truncada; nenhuma alteração realizada.\n'
    return 1
fi
# Verificar que TODOS os arquivos originais continuam idênticos (SHA, modo e caminho).
if ! jq -e -n --slurpfile a "$TMP_DIR/rename-folder-original-tree.json" --slurpfile b "$TMP_DIR/pick-tree.json" --arg p "$old_prefix" '
  ([ $a[0].tree[]? | select(.type == "blob" and (.path | startswith($p))) | [.path,.sha,.mode] ] | sort) ==
  ([ $b[0].tree[]? | select(.type == "blob" and (.path | startswith($p))) | [.path,.sha,.mode] ] | sort)
' >/dev/null; then
    printf 'A pasta foi modificada durante a renomeação; operação cancelada.\n'
    return 1
fi
# Impedir perda de dados se a origem mudou desde a seleção.
if ! jq -e --arg prefix "$old_prefix" '.tree[]? | select(.type == "blob" and (.path | startswith($prefix)))' "$TMP_DIR/pick-tree.json" >/dev/null 2>&1; then
    printf 'Pasta de origem não encontrada na versão atual da branch.\n'
    return 1
fi
# Impedir perda de dados em destinos ocupados, inclusive alterações recentes.
if jq -e --arg old "$old_prefix" --arg new "$new_prefix" '
    .tree[]? | select((.path | startswith($new)) or .path == ($new | sub("/$";"")))
' "$TMP_DIR/pick-tree.json" >/dev/null 2>&1; then
    printf 'Destino ocupado na versão atual da branch; operação cancelada.\n'
    return 1
fi
payload=$(jq -c --arg old_prefix "$old_prefix" --arg new_prefix "$new_prefix" --arg base_tree "$commit_tree_sha" '
{base_tree:$base_tree,tree:[
(.tree[]? | select(.type == "blob" and (.path | startswith($old_prefix))) |
{path:($new_prefix + (.path | ltrimstr($old_prefix))),mode:.mode,type:"blob",sha:.sha}),
(.tree[]? | select(.type == "blob" and (.path | startswith($old_prefix))) |
{path:.path,mode:.mode,type:"blob",sha:null})
]}
' "$TMP_DIR/pick-tree.json") ||
{ printf 'Não foi possível preparar a árvore da renomeação.\n'; return 1; }
api POST "/repos/$GITHUB_USER/$repo_encoded/git/trees" "$payload" "$TMP_DIR/rename-folder-new-tree.json" ||
{ printf 'Não foi possível criar a nova árvore. A BRANCH não foi alterada.\n'; return 1; }
new_tree_sha=$(jq -r '.sha // empty' "$TMP_DIR/rename-folder-new-tree.json")
[ -n "$new_tree_sha" ] ||
{ printf 'A API não retornou o SHA da nova árvore.\n'; return 1; }
payload=$(jq -n --arg message "$GITMENU_COMMIT_MESSAGE" --arg tree "$new_tree_sha" --arg parent "$branch_sha" '{message:$message,tree:$tree,parents:[$parent]}') ||
return 1
api POST "/repos/$GITHUB_USER/$repo_encoded/git/commits" "$payload" "$TMP_DIR/rename-folder-new-commit.json" ||
{ printf 'Não foi possível criar o commit. A BRANCH não foi alterada.\n'; return 1; }
new_commit_sha=$(jq -r '.sha // empty' "$TMP_DIR/rename-folder-new-commit.json")
[ -n "$new_commit_sha" ] ||
{ printf 'A API não retornou o SHA do novo commit.\n'; return 1; }
payload=$(jq -n --arg sha "$new_commit_sha" '{sha:$sha,force:false}') ||
return 1
update_status=$(curl -sS -o "$TMP_DIR/rename-folder-update-ref.json" -w '%{http_code}' -X PATCH \
-H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" \
-H "X-GitHub-Api-Version: $API_VERSION" -H 'Content-Type: application/json' \
--data-binary "$payload" \
"$API_URL/repos/$GITHUB_USER/$repo_encoded/git/refs/heads/$branch_ref_encoded") ||
{ printf 'Falha de comunicação ao atualizar a BRANCH.\n'; return 1; }
if [ "$update_status" = 200 ]
then
ui_heading "RESUMO DA OPERAÇÃO — RENOMEAR PASTA"
draw_block "RESULTADO" "Status|OK" "De|/$old_folder" "Para|/$new_folder" "Branch|$PICK_BRANCH" "Concluído em|$(now_str)"
else
printf 'Falha ao atualizar a BRANCH (HTTP %s). A BRANCH não foi alterada.\n' "$update_status"
jq -r '.message // empty' "$TMP_DIR/rename-folder-update-ref.json" 2>/dev/null
return 1
fi
}

# ------------------------ 29  mudar diretório local -------------------
change_current_directory() {
local resolved_dir config_dir temp_config
pick_local_folder "NOVO DIRETÓRIO LOCAL PADRÃO" ||
{ cancelled; return 0; }
resolved_dir="$PICK_LOCAL_DIR"
config_dir="$(dirname "$LOCAL_DIR_CONFIG")"
if [ -L "$config_dir" ] ||
[ -L "$LOCAL_DIR_CONFIG" ]
then
printf 'Erro: caminho de configuração contém link simbólico.\n'
return 1
fi
mkdir -p -m 0700 "$config_dir" ||
{ printf 'Não foi possível criar a configuração local.\n'; return 1; }
temp_config="$(mktemp "$config_dir/.current-directory.XXXXXX")" ||
return 1
if ! printf '%s\n' "$resolved_dir" > "$temp_config" ||
! chmod 0600 "$temp_config" ||
! mv -f -- "$temp_config" "$LOCAL_DIR_CONFIG"
then
rm -f -- "$temp_config"
printf 'Falha ao salvar o diretório local. A configuração anterior foi preservada.\n'
return 1
fi
ui_heading "DIRETÓRIO LOCAL ALTERADO"
draw_block "CONFIGURAÇÃO" "Diretório local|$resolved_dir" "Usado por|comparar, enviar, baixar, listar e clonar"
}

# Opção 07: usa o mesmo enquadramento dos demais menus pós-escolha.
# Mantém paginação e consultas originais, sem alterar a autenticação.
list_repositories() {
    local page=1 count repo default_branch private path total_dirs
    ensure_login || return 1
    ui_operation_title '07 - LISTAR REPOSITÓRIOS E PASTAS'
    while :; do
        if ! api GET "/user/repos?affiliation=owner&per_page=100&page=$page&sort=full_name" "" "$TMP_DIR/repos.json"; then
            return 1
        fi
        count=$(jq -r 'if type == "array" then length else -1 end' "$TMP_DIR/repos.json" 2>/dev/null) || return 1
        if [ "$count" -lt 0 ]; then
            printf 'Resposta inválida ao consultar repositórios.\n' >&2
            return 1
        fi
        [ "$count" -gt 0 ] || { [ "$page" -gt 1 ] || draw_block 'REPOSITÓRIOS' 'Resultado|Nenhum repositório encontrado'; break; }
        while IFS=$'\t' read -r repo default_branch private; do
            [ -n "$repo" ] || continue
            # Um quadro contínuo por repositório: dados e árvore na mesma moldura.
            ui_frame_line '┏' '┓'
            ui_title_row "REPOSITÓRIO $(ui_repeat '━' $(( $(ui_cols) - 16 )))"
            ui_frame_line '┣' '┫'
            ui_info_row 'Nome' "$repo"
            ui_info_row 'Branch principal' "$default_branch"
            ui_info_row 'Privado' "$private"
            ui_list_title 'PASTAS E SUBPASTAS'
            if api GET "/repos/$GITHUB_USER/$(urlencode "$repo")/git/trees/$(urlencode "$default_branch")?recursive=1" "" "$TMP_DIR/tree.json"; then
                if [ "$(jq -r '.truncated // false' "$TMP_DIR/tree.json" 2>/dev/null)" = true ]; then
                    ui_content_row 'AVISO: árvore truncada pela API; listagem incompleta.'
                fi
                total_dirs=$(jq -r '[.tree[]? | select(.type == "tree")] | length' "$TMP_DIR/tree.json" 2>/dev/null) || total_dirs=0
                if [ "$total_dirs" -eq 0 ]; then
                    ui_content_row 'Nenhuma pasta encontrada.'
                else
                    while IFS= read -r path; do
                        [ -n "$path" ] && ui_content_row "$path"
                    done < <(jq -r '.tree[]? | select(.type == "tree") | .path' "$TMP_DIR/tree.json")
                fi
            else
                ui_content_row 'Falha ao consultar as pastas desta branch.'
            fi
            ui_frame_line '┗' '┛'
        done < <(jq -r '.[] | [.name,.default_branch,(.private|tostring)] | @tsv' "$TMP_DIR/repos.json")
        [ "$count" -lt 100 ] && break
        page=$((page + 1))
    done
}

# ======================== FIM DO PATCH GITMENU ========================
# Preparação multiplataforma: executada antes do login e do menu.
# Nunca executa o programa inteiro como root; eleva somente o gerenciador de pacotes.
# Detecta o sistema por fontes independentes. Executáveis isolados não determinam a distro.
_os_field() {
    local key=$1 file line value
    for file in /etc/os-release /usr/lib/os-release; do
        [ -r "$file" ] || continue
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                "$key"=*) value=${line#*=}; value=${value#\"}; value=${value%\"}; value=${value#\'}; value=${value%\'}; printf '%s' "$value"; return 0 ;;
            esac
        done < "$file"
    done
    return 1
}

_detect_system() {
    local id like version pretty family='' manager='' c value file installed=0
    local -a evidence=() candidates=()
    id=$(_os_field ID) || id=''
    like=$(_os_field ID_LIKE) || like=''
    version=$(_os_field VERSION_ID) || version=''
    pretty=$(_os_field PRETTY_NAME) || pretty=''
    [ -z "$id" ] || evidence+=("os-release:ID=$id")
    [ -z "$version" ] || evidence+=("os-release:VERSION_ID=$version")
    [ -z "$like" ] || evidence+=("os-release:ID_LIKE=$like")
    if command -v uname >/dev/null 2>&1; then
        value=$(uname -srm 2>/dev/null) || value=''
        [ -z "$value" ] || evidence+=("uname:$value")
    fi
    if [ -r /proc/version ]; then
        IFS= read -r value < /proc/version || :
        evidence+=("proc/version:${value:0:120}")
    fi
    if command -v lsb_release >/dev/null 2>&1; then
        value=$(lsb_release -si -sr 2>/dev/null | tr '\n' ' ') || value=''
        [ -z "$value" ] || evidence+=("lsb_release:$value")
        [ -n "$id" ] || id=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')
        [ -n "$version" ] || version=$(lsb_release -sr 2>/dev/null)
    fi
    if command -v hostnamectl >/dev/null 2>&1; then
        value=$(hostnamectl status 2>/dev/null | sed -n 's/^[[:space:]]*Operating System:[[:space:]]*//p' | head -n 1) || value=''
        [ -z "$value" ] || evidence+=("hostnamectl:$value")
    fi
    for file in /etc/arch-release /etc/alpine-release /etc/void-release /etc/debian_version /etc/fedora-release /etc/redhat-release /etc/centos-release /etc/SuSE-release /etc/os-release /usr/lib/os-release; do
        [ -r "$file" ] && evidence+=("arquivo:$file")
    done
    if command -v rpm >/dev/null 2>&1; then
        value=$(rpm -q --whatprovides system-release --qf '%{NAME} %{VERSION}\n' 2>/dev/null | head -n 1) || value=''
        [ -z "$value" ] || evidence+=("rpm-system-release:$value")
    fi
    if command -v dpkg-query >/dev/null 2>&1; then
        value=$(dpkg-query -W -f='${Version}' base-files 2>/dev/null) || value=''
        [ -z "$value" ] || evidence+=("dpkg-base-files:$value")
    fi
    if command -v pacman >/dev/null 2>&1 && [ -d /var/lib/pacman/local ]; then
        value=$(pacman -Q filesystem 2>/dev/null) || value=''
        [ -z "$value" ] || evidence+=("pacman-filesystem:$value")
    fi
    [ ! -r /etc/alpine-release ] || { IFS= read -r value < /etc/alpine-release || :; evidence+=("alpine-release:$value"); }
    [ ! -r /etc/debian_version ] || { IFS= read -r value < /etc/debian_version || :; evidence+=("debian-version:$value"); }
    if command -v apk >/dev/null 2>&1; then
        value=$(apk --version 2>/dev/null | head -n 1) || value=''
        [ -z "$value" ] || evidence+=("apk:$value")
    fi
    if command -v xbps-query >/dev/null 2>&1; then
        value=$(xbps-query -p pkgver base-files 2>/dev/null) || value=''
        [ -z "$value" ] || evidence+=("xbps-base-files:$value")
    fi
    # A arquitetura do kernel não identifica a distribuição; apenas complementa o diagnóstico.
    case " $id $like " in
        *' alpine '*) family=apk ;;
        *' void '*) family=xbps ;;
        *' arch '*|*' manjaro '*|*' endeavouros '*) family=pacman ;;
        *' debian '*|*' ubuntu '*|*' linuxmint '*|*' pop '*|*' elementary '*|*' kali '*) family=apt ;;
        *' suse '*|*' opensuse '*|*' opensuse-leap '*|*' opensuse-tumbleweed '*|*' sles '*|*' sled '*) family=zypper ;;
        *' fedora '*|*' rhel '*|*' centos '*|*' rocky '*|*' almalinux '*|*' ol '*|*' amzn '*) family=rpm ;;
    esac
    [ -n "$family" ] || {
        if [ -f /etc/alpine-release ]; then family=apk
        elif [ -f /etc/void-release ]; then family=xbps
        elif [ -f /etc/arch-release ]; then family=pacman
        elif [ -f /etc/debian_version ]; then family=apt
        elif [ -f /etc/fedora-release ] || [ -f /etc/redhat-release ]; then family=rpm
        elif [ -f /etc/SuSE-release ]; then family=zypper
        fi
    }
    for c in apt pacman dnf yum zypper apk xbps; do
        case "$c" in
            apt) command -v apt-get >/dev/null 2>&1 && [ -f /var/lib/dpkg/status ] && candidates+=(apt) ;;
            pacman) command -v pacman >/dev/null 2>&1 && [ -d /var/lib/pacman/local ] && candidates+=(pacman) ;;
            dnf|yum) command -v "$c" >/dev/null 2>&1 && { [ -d /var/lib/rpm ] || [ -d /usr/lib/sysimage/rpm ]; } && candidates+=("$c") ;;
            zypper) command -v zypper >/dev/null 2>&1 && [ -d /var/lib/zypp ] && candidates+=(zypper) ;;
            apk) command -v apk >/dev/null 2>&1 && [ -f /lib/apk/db/installed ] && candidates+=(apk) ;;
            xbps) command -v xbps-install >/dev/null 2>&1 && [ -d /var/db/xbps ] && candidates+=(xbps) ;;
        esac
    done
    case "$family" in
        rpm) for c in dnf yum; do [[ " ${candidates[*]} " == *" $c "* ]] && { manager=$c; break; }; done ;;
        *) for c in "${candidates[@]}"; do [ "$c" = "$family" ] && { manager=$c; break; }; done ;;
    esac
    if [ -z "$manager" ] && [ -z "$family" ] && [ "${#candidates[@]}" -eq 1 ]; then manager=${candidates[0]}; fi
    if [ -z "$manager" ] && [ "${#candidates[@]}" -eq 2 ] && [[ " ${candidates[*]} " == *' dnf '* ]] && [[ " ${candidates[*]} " == *' yum '* ]]; then manager=dnf; fi
    DETECT_NAME=${pretty:-${id:-desconhecida}}
    DETECT_VERSION=${version:-não-identificada}
    DETECT_MANAGER=$manager
    printf '[INFO] Sistema: %s | Versão: %s | Gerenciador: %s\n' "$DETECT_NAME" "$DETECT_VERSION" "${manager:-indeterminado}"
    printf '[INFO] Evidências de identificação:\n'
    for value in "${evidence[@]}"; do printf '  - %s\n' "$value"; done
    printf '[INFO] Gerenciadores instalados: %s\n' "${candidates[*]:-nenhum}"
    if [ -z "$manager" ]; then
        printf '[ERRO] Identificação conflitante ou gerenciador não encontrado. Nenhuma instalação será executada.\n' >&2
        return 1
    fi
}

_package_for_command() {
    local mgr=$1 cmd=$2
    # Nomes explícitos por família; nenhum nome é construído por suposição.
    case "$cmd" in
        printf) return 2 ;; # builtin Bash, não depende de executável externo
        base64|sort|mktemp|timeout|uname|tr|head|tail|cut|dirname|basename|cat|date|id|mkdir|chmod|rm|cp|mv|wc|stat|readlink|realpath|sha256sum|tee|uniq|xargs|touch|install|env|whoami|sleep|stty) echo coreutils ;;
        find) echo findutils ;;
        awk) case "$mgr" in apt|pacman|dnf|yum|zypper|apk|xbps) echo gawk;; esac ;;
        diff|cmp) echo diffutils ;;
        ssh|ssh-keygen|scp|sftp|ssh-add)
            case "$mgr" in
                apt) echo openssh-client;; pacman|xbps) echo openssh;; dnf|yum|zypper) echo openssh-clients;;
                apk) case "$cmd" in ssh-add) echo openssh-keygen;; *) echo openssh-client-default;; esac;;
            esac ;;
        clear|tput) case "$mgr" in apt) echo ncurses-bin;; zypper) echo ncurses-utils;; apk) echo ncurses;; *) echo ncurses;; esac ;;
        flock) echo util-linux ;;
        python3) case "$mgr" in pacman) echo python;; *) echo python3;; esac ;;
        curl|jq|git|sed|grep|tar|gzip|unzip|zip|rsync|openssl|file|patch|perl) echo "$cmd" ;;
        *) return 1 ;;
    esac
}

# Consulta os repositorios habilitados antes de selecionar o pacote.
# Nunca instala diretamente um resultado de busca textual sem confirmar o nome.
_repo_exact_package() {
    local mgr=$1 pkg=$2
    [ -n "$pkg" ] || return 1
    case "$mgr" in
        apt) apt-cache show -- "$pkg" 2>/dev/null | grep -q '^Package: ' ;;
        pacman) pacman -Si -- "$pkg" >/dev/null 2>&1 ;;
        dnf) dnf -q repoquery --available --qf '%{name}' "$pkg" 2>/dev/null | grep -Fxq "$pkg" ;;
        yum) yum -q list available "$pkg" 2>/dev/null | awk -v p="$pkg" '$1==p || $1 ~ ("^"p"[.]") {found=1} END{exit !found}' ;;
        zypper) zypper --non-interactive info --type package "$pkg" 2>/dev/null | grep -Eq '^Name[[:space:]]*:[[:space:]]*'"$pkg"'$' ;;
        apk) apk search -x "$pkg" 2>/dev/null | grep -Eq '^'"$pkg"'-[0-9]' ;;
        xbps) xbps-query -Rs "$pkg" 2>/dev/null | awk -v p="$pkg" '$2 ~ ("^"p"-[0-9]") {found=1} END{exit !found}' ;;
        *) return 1 ;;
    esac
}

# Procura primeiro pelo nome exato; se nao existir, procura um pacote que
# forneca o executavel nos indices de arquivos, quando suportados.
_repo_find_package() {
    local mgr=$1 cmd=$2 preferred=$3 candidate='' result=''
    if _repo_exact_package "$mgr" "$preferred"; then
        printf '%s\n' "$preferred"; return 0
    fi
    printf '[INFO] Buscando fornecedor de %s nos repositorios %s...\n' "$cmd" "$mgr" >&2
    case "$mgr" in
        apt)
            if command -v apt-file >/dev/null 2>&1; then
                result=$(apt-file search -x "/(s?bin)/${cmd}$" 2>/dev/null | head -n 30)
                while IFS=: read -r candidate _; do
                    candidate=${candidate##* }
                    if _repo_exact_package "$mgr" "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
                done <<< "$result"
            fi ;;
        pacman)
            # pacman -F consulta a base de arquivos (quando ja disponivel).
            result=$(pacman -F --machinereadable "usr/bin/$cmd" 2>/dev/null | head -n 20)
            while IFS= read -r candidate; do
                candidate=${candidate#*/}; candidate=${candidate%%[[:space:]]*}
                if _repo_exact_package "$mgr" "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
            done <<< "$result" ;;
        dnf)
            result=$(dnf -q repoquery --whatprovides "*/bin/$cmd" --qf '%{name}' 2>/dev/null | sort -u)
            while IFS= read -r candidate; do
                if _repo_exact_package "$mgr" "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
            done <<< "$result" ;;
        yum)
            result=$(yum -q provides "*/bin/$cmd" 2>/dev/null | sed -nE 's/^([[:alnum:]_.+-]+)\.[[:alnum:]_]+[[:space:]]*:.*/\1/p' | head -n 20)
            while IFS= read -r candidate; do
                if _repo_exact_package "$mgr" "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
            done <<< "$result" ;;
        zypper)
            result=$(zypper --non-interactive what-provides "/usr/bin/$cmd" 2>/dev/null | awk -F'|' 'NF>=3 {gsub(/^ +| +$/, "", $2); print $2}' | head -n 20)
            while IFS= read -r candidate; do
                if _repo_exact_package "$mgr" "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
            done <<< "$result" ;;
    esac
    return 1
}

_package_installed() {
    local mgr=$1 pkg=$2
    case "$mgr" in
        apt) dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii' ;;
        pacman) pacman -Q -- "$pkg" >/dev/null 2>&1 ;;
        dnf|yum|zypper) rpm -q -- "$pkg" >/dev/null 2>&1 ;;
        apk) apk info -e "$pkg" >/dev/null 2>&1 ;;
        xbps) xbps-query -p pkgver "$pkg" >/dev/null 2>&1 ;;
    esac
}

_package_available() {
    local mgr=$1 pkg=$2
    case "$mgr" in
        apt) apt-cache show "$pkg" >/dev/null 2>&1 ;;
        pacman) pacman -Si -- "$pkg" >/dev/null 2>&1 ;;
        dnf) dnf -q list --available "$pkg" >/dev/null 2>&1 ;;
        yum) yum -q list available "$pkg" >/dev/null 2>&1 ;;
        zypper) zypper --non-interactive info "$pkg" >/dev/null 2>&1 ;;
        apk) apk search -x "$pkg" 2>/dev/null | grep -q . ;;
        xbps) xbps-query -Rs "^${pkg}-[0-9]" 2>/dev/null | grep -q . ;;
        *) return 1 ;;
    esac
}

_package_owns_command() {
    local mgr=$1 pkg=$2 cmd=$3
    case "$mgr" in
        apt) dpkg-query -L "$pkg" 2>/dev/null ;;
        pacman) pacman -Qlq -- "$pkg" 2>/dev/null ;;
        dnf|yum|zypper) rpm -ql -- "$pkg" 2>/dev/null ;;
        apk) apk info -L "$pkg" 2>/dev/null ;;
        xbps) xbps-query -f "$pkg" 2>/dev/null ;;
        *) return 1 ;;
    esac | grep -Eq "(^|/)(bin|sbin)/${cmd}$"
}

_recover_installed_command() {
    local mgr=$1 pkg=$2 cmd=$3 found='' candidate
    hash -r 2>/dev/null || :
    command -v "$cmd" >/dev/null 2>&1 && return 0
    for candidate in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
        if [ -x "$candidate/$cmd" ] && [ ! -d "$candidate/$cmd" ]; then
            case ":$PATH:" in *":$candidate:"*) ;; *) PATH="$PATH:$candidate"; export PATH;; esac
            command -v "$cmd" >/dev/null 2>&1 && return 0
        fi
    done
    # Localizar executáveis apenas entre arquivos pertencentes ao pacote.
    case "$mgr" in
        apt) command -v dpkg-query >/dev/null 2>&1 && found=$(dpkg-query -L "$pkg" 2>/dev/null | grep -E "/(s?bin)/${cmd}$" | head -n 1) ;;
        pacman) found=$(pacman -Qlq -- "$pkg" 2>/dev/null | grep -E "/(s?bin)/${cmd}$" | head -n 1) ;;
        dnf|yum|zypper) found=$(rpm -ql -- "$pkg" 2>/dev/null | grep -E "/(s?bin)/${cmd}$" | head -n 1) ;;
        apk) found=$(apk info -L "$pkg" 2>/dev/null | sed 's@^@/@' | grep -E "/(s?bin)/${cmd}$" | head -n 1) ;;
        xbps) found=$(xbps-query -f "$pkg" 2>/dev/null | grep -E "/(s?bin)/${cmd}$" | head -n 1) ;;
    esac
    if [ -n "$found" ] && [ -x "$found" ]; then
        candidate=${found%/*}
        case ":$PATH:" in *":$candidate:"*) ;; *) PATH="$PATH:$candidate"; export PATH;; esac
    fi
    hash -r 2>/dev/null || :
    command -v "$cmd" >/dev/null 2>&1
}

# Limite por execução: evita espera indefinida por rede, lock ou gerenciador.
# GNU timeout é opcional: caso ausente, tenta recuperá-lo pelo coreutils.
_bounded_pkg() {
    if command -v timeout >/dev/null 2>&1; then
        timeout --signal=TERM --kill-after=15s 300s "$@"
    else
        "$@"
    fi
}
_install_one_missing() {
    local mgr=$1 pkg=$2; shift 2
    case "$mgr" in
        apt) _bounded_pkg "$@" apt-get install -y --no-install-recommends "$pkg" ;;
        pacman) _bounded_pkg "$@" pacman -S --needed --noconfirm "$pkg" ;;
        dnf) _bounded_pkg "$@" dnf install -y "$pkg" ;;
        yum) _bounded_pkg "$@" yum install -y "$pkg" ;;
        zypper) _bounded_pkg "$@" zypper --non-interactive install --no-recommends "$pkg" ;;
        apk) _bounded_pkg "$@" apk add "$pkg" ;;
        xbps) _bounded_pkg "$@" xbps-install -y "$pkg" ;;
        *) return 1 ;;
    esac
}

_repair_installed_package() {
    local mgr=$1 pkg=$2; shift 2
    case "$mgr" in
        apt) _bounded_pkg "$@" apt-get install -y --reinstall --no-install-recommends "$pkg" ;;
        pacman) _bounded_pkg "$@" pacman -S --noconfirm "$pkg" ;;
        dnf) _bounded_pkg "$@" dnf reinstall -y "$pkg" ;;
        yum) _bounded_pkg "$@" yum reinstall -y "$pkg" ;;
        zypper) _bounded_pkg "$@" zypper --non-interactive install --force "$pkg" ;;
        apk) _bounded_pkg "$@" apk fix "$pkg" ;;
        xbps) _bounded_pkg "$@" xbps-install -fy "$pkg" ;;
        *) return 1 ;;
    esac
}

prepare_environment() {
    local manager cmd pkg attempt progress=0 refresh_ok=1 failures=0
    local -a required=(uname curl jq git base64 find awk sed grep sort diff cmp mktemp tput ssh-add timeout tr head tail cut dirname basename cat date id mkdir chmod rm cp mv wc stat readlink realpath sha256sum tee uniq xargs touch install env whoami sleep tar gzip unzip zip rsync openssl file patch ssh ssh-keygen scp sftp stty clear flock)
    local -a missing=() privilege=() unresolved=()
    local -A attempted_packages=()
    DETECT_MANAGER=''; DETECT_NAME=''; DETECT_VERSION=''
    if ! _detect_system; then
        printf '[ERRO] Não foi possível identificar com segurança a distribuição. Nenhuma instalação arriscada será executada.\n' >&2
        return 1
    fi
    manager=$DETECT_MANAGER
    for cmd in "${required[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        printf '[OK] Dependências presentes; nenhuma instalação ou atualização necessária.\n'
        return 0
    fi
    printf '[INFO] Verificando e recuperando: %s\n' "${missing[*]}"
    # Primeiro recuperar PATH sem instalar nada.
    for cmd in "${missing[@]}"; do
        pkg=$(_package_for_command "$manager" "$cmd") || continue
        _recover_installed_command "$manager" "$pkg" "$cmd" && printf '[OK] Recuperado: %s\n' "$cmd"
    done
    missing=()
    for cmd in "${required[@]}"; do command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd"); done
    [ "${#missing[@]}" -eq 0 ] && return 0
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo -v || { printf '[ERRO] Autorização sudo necessária para reparar dependências.\n' >&2; return 1; }
            privilege=(sudo)
        elif command -v doas >/dev/null 2>&1; then
            privilege=(doas)
        else
            printf '[ERRO] Sem sudo/doas e sem privilégios root para instalar dependências.\n' >&2
            return 1
        fi
    fi
    # Atualizar catálogos somente se existem dependências ausentes.
    case "$manager" in
        apt) _bounded_pkg "${privilege[@]}" apt-get update || refresh_ok=0 ;;
        pacman)
            printf '[INFO] Arch: atualização completa necessária para instalar pacotes sem atualização parcial.\n'
            printf 'Autoriza atualização completa com pacman -Syu? [s/N] '
            IFS= read -r answer
            case "$answer" in s|S|sim|SIM) _bounded_pkg "${privilege[@]}" pacman -Syu --noconfirm || refresh_ok=0 ;; *) printf '[AVISO] Atualização não autorizada; nenhuma instalação parcial será tentada.\n' >&2; return 1;; esac ;;
        xbps) _bounded_pkg "${privilege[@]}" xbps-install -S || refresh_ok=0 ;;
        apk) _bounded_pkg "${privilege[@]}" apk update || refresh_ok=0 ;;
    esac
    [ "$refresh_ok" -eq 1 ] || printf '[AVISO] Falha na atualização dos índices; tentando pacotes com os metadados disponíveis.\n' >&2
    # Instalar um por vez: falha de um pacote não impede a tentativa dos demais.
    for cmd in "${missing[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 && continue
        pkg=$(_package_for_command "$manager" "$cmd") || {
            printf '[ERRO] Não há mapeamento confiável de pacote para %s em %s.\n' "$cmd" "$manager" >&2
            failures=$((failures+1)); continue
        }
        # Consulta primeiro os repositorios configurados. Se o pacote ja esta
        # instalado, preserva-o e tenta recuperar seu executavel sem download.
        if ! _package_installed "$manager" "$pkg"; then
            local discovered=''
            discovered=$(_repo_find_package "$manager" "$cmd" "$pkg") || discovered=''
            if [ -n "$discovered" ]; then
                pkg=$discovered
            else
                printf '[AVISO] Nenhum pacote verificado encontrado para %s. Continuando as demais dependencias.\n' "$cmd" >&2
                unresolved+=("$cmd"); failures=$((failures+1)); continue
            fi
        fi
        # Cada pacote é tratado uma única vez, mesmo que forneça vários comandos.
        if [ "${attempted_packages[$pkg]+yes}" ]; then
            _recover_installed_command "$manager" "$pkg" "$cmd" || { unresolved+=("$cmd"); failures=$((failures+1)); }
            continue
        fi
        attempted_packages[$pkg]=1
        if _package_installed "$manager" "$pkg"; then
            if _recover_installed_command "$manager" "$pkg" "$cmd"; then continue; fi
            printf '[INFO] Pacote %s instalado, mas executável %s indisponível: reparando instalação danificada.\n' "$pkg" "$cmd"
            # Reparo apenas se o pacote deveria fornecer este comando (manifesto local).
            if _package_owns_command "$manager" "$pkg" "$cmd"; then
                _repair_installed_package "$manager" "$pkg" "${privilege[@]}" || printf '[AVISO] Reparação falhou: %s\n' "$pkg" >&2
            else
                printf '[AVISO] %s não consta no manifesto de %s; não reinstalando por suposição.\n' "$cmd" "$pkg" >&2
            fi
        else
            if _package_available "$manager" "$pkg"; then
                printf '[INFO] Instalando pacote ausente: %s\n' "$pkg"
                _install_one_missing "$manager" "$pkg" "${privilege[@]}" || printf '[AVISO] Instalação inicial falhou: %s\n' "$pkg" >&2
            else
                printf '[AVISO] Pacote %s não encontrado nos repositórios configurados.\n' "$pkg" >&2
            fi
        fi
        hash -r 2>/dev/null || :
        _recover_installed_command "$manager" "$pkg" "$cmd" && continue
        # Uma única tentativa de instalação/reparação por pacote nesta execução.
        # Não repetir a mesma falha em ciclos nem reinstalar pacote íntegro.
        hash -r 2>/dev/null || :
        if ! _recover_installed_command "$manager" "$pkg" "$cmd"; then
            unresolved+=("$cmd"); failures=$((failures+1))
        fi
    done
    # Validação final de todos os comandos: pacotes agrupados podem prover múltiplos executáveis.
    unresolved=()
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            pkg=$(_package_for_command "$manager" "$cmd") || pkg=''
            if [ -n "$pkg" ]; then _recover_installed_command "$manager" "$pkg" "$cmd" || :; fi
            command -v "$cmd" >/dev/null 2>&1 || unresolved+=("$cmd")
        fi
    done
    if [ "${#unresolved[@]}" -gt 0 ]; then
        printf '[ERRO] Dependências ainda indisponíveis: %s. Não é seguro iniciar transações que dependem delas.\n' "${unresolved[*]}" >&2
        return 1
    fi
    printf '[OK] Ambiente completo: %s (%s).\n' "$DETECT_NAME" "$DETECT_VERSION"
    return 0
}

if [ ! -t 0 ]
then
printf 'Erro: este programa precisa ser executado em um terminal interativo.\n' >&2
printf 'Execute com: bash "%s"\n' "$0" >&2
exit 2
fi
if ! prepare_environment; then
    printf '[ERRO] A preparação tentou recuperar todas as dependências, mas algumas continuam indisponíveis. Corrija repositórios/permissões e execute novamente.\n' >&2
    exit 1
fi
show_banner
if ! load_session
then
if ! login_github
then
printf '\nLogin não concluído. Programa encerrado.\n'
exit 1
fi
fi
main

