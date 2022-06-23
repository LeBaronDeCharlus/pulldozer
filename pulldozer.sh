#!/bin/bash
# shellcheck disable=SC1090
# me@kaderovski.com

set -Eeuo pipefail
trap catch_error SIGINT SIGTERM ERR EXIT
trap stop_loader SIGINT

tput civis # Hide the terminal cursor


script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
PROJECT="$(basename "$(pwd)")"

catch_error() {
  # Catch error & alert
  trap - SIGINT SIGTERM ERR EXIT
  tput cnorm # Restore the terminal cursor
}


die() {
  local msg=$1
  local code=${2-1}
  msg "$msg"
  exit "$code"
}


setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' GREEN='\033[0;32m'
  else
    NOFORMAT='' GREEN=''
  fi
}
setup_colors


msg() {                                                                                                                                                                                                              
  if [[ ${silent} -ne 1 ]] ; then
    echo >&2 -e "${1}" 
  fi
}


usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h --help] [-d --daemon] [-D --dry-run] [-s --silent] [-x --debug]

Script description here.

Available options:

-h, --help            Print this help and exit
-b, --branch          On which branch pull
-c, --config-file     Where pulldozer.json is located, default in ./.pulldozer.json
-d, --daemon-fmt      Will clean output for daemon journalctl
-D, --dry-run         Dry-run
-m, --mention-slack   Mention a user on slack webhook, expected user_id
-r, --rule            Which post hook rule should be exec 
-s, --silent          Hide output
-S, --slack-webhook   Webhook URL to post on channel
-x, --debug           Enter in debug view

EOF
  exit 0
}


parse_params() {
  prod_branch=''
  config_file=''
  daemon=''
  dry_run=''
  mention_slack=''
  rule=''
  silent=''
  slack_webhook=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -b | --branch)
      prod_branch="${2-}"
      shift
      ;;
    -c | --config-file)
      config_file="${2-}"
      shift
      ;;
    -d | --daemon-fmt) daemon=1;;
    -D | --dry-run) dry_run=1;;
    -m | --mention-slack)
      mention_slack="${2-}"
      shift
      ;;
    -r | --rule)
      rule="${2-}"
      shift
      ;;
    -s | --silent) silent=1;;
    -S | --slack-webhook)
      slack_webhook="${2-}"
      shift
      ;;
    -x | --debug) set -x ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  return 0
}

parse_params "$@"


# Loaders
cli_loader=( 0.05 ⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷ )


play_loader() {
  if [[ ${silent} -ne 1 ]] && [[ ${daemon} -ne 1 ]]; then
    while true ; do
      for frame in "${active_loading_animation[@]}" ; do
        printf "\r%s" "${frame}"
        sleep "${loading_animation_frame_interval}"
      done
    done
  fi
}


start_loader() {
  if [[ ${silent} -ne 1 ]] && [[ ${daemon} -ne 1 ]]; then
    active_loading_animation=( "${@}" )
    loading_animation_frame_interval="${active_loading_animation[0]}"
    unset "active_loading_animation[0]"
    tput civis # Hide the terminal cursor
    play_loader &
    loading_animation_pid="${!}"
  fi
}


stop_loader() {
  if [[ ${silent} -ne 1 ]] && [[ ${daemon} -ne 1 ]]; then
    kill "${loading_animation_pid}" &>/dev/null
    tput cnorm # Restore the terminal cursor
    msg "\r\\${1} ${2}"
  else
    msg "\r\\${1} ${2}"
  fi
}


check_deps() {
  # mandatory deps                            
  deps=(                                                                                                    
      git           
      jq
      curl
  )

  start_loader "${cli_loader[@]}"
  msg "[${PROJECT}] checking dependencies"; 
  for i in "${deps[@]}"; do 
    if ! which "${i}" &>/dev/null
      then
        stop_loader "u1f4a5" "${i} not found and required, please install"
    fi
  done
  stop_loader "u2728" "OK"
}


# Constants
CURL="$(which curl)"
GIT="$(which git)"
JQ="$(which jq)"


read_config() {
  if [[ ! "${config_file}" ]] ; then
    config_file="./.pulldozer.json"
    if [ ! -f "${config_file}" ]; then
      die "Could not find config file : ${config_file}"
    fi
  fi
  if [[ ! "${prod_branch}" ]] ; then
    prod_branch=$("${JQ}" '.prod_branch' "${config_file}" | tr -d '"'"'"'')
  fi
  if [[ ! "${rule}" ]] ; then
    rule=$("${JQ}" '.rule' "${config_file}" | tr -d '"'"'"'')
  fi
  if [[ ! "${slack_webhook}" ]] ; then
    webhook=$("${JQ}" '.slack[].webhook' "${config_file}" | tr -d '"'"'"'')
  fi
  if [[ ! "${mention_slack}" ]] ; then
    mention_slack=$("${JQ}" '.slack[].mention' "${config_file}" | tr -d '"'"'"'')
  fi
}


# Slack hook
slack_send() {
  if [[ ${webhook} ]]; then
    message="${1}"
    "${CURL}" -s -X POST -H 'Content-type: application/json' --data "{\"text\":\"${message}\"}" "${webhook}"
  fi
}


deploy() {
  msg "[${PROJECT}] Deploying application" 
  start_loader "${cli_loader[@]}"
  
  GIT_PROD_BRANCH="$1"
  GIT_CURRENT_BRANCH="$2"

  if [[ ${dry_run} -eq 1 ]] ; then
    gdiff=$("${GIT}" --no-pager diff --name-only origin/"${GIT_PROD_BRANCH}")
    stop_loader "U2728" "[Dry Run] files changed if deploying :\n${GREEN}${gdiff}${NOFORMAT}"
    return 0
  fi 

  slack_send ":information_source: [${PROJECT}] new release found, deploying latest…"
  "${GIT}" pull origin "${GIT_PROD_BRANCH}" &> /dev/null

  # Rule
  if [[ "${rule}" ]] ; then
    source "${script_dir}/rules/${rule}.sh"
    "${rule}"
  fi

  GIT_CURRENT_COMMIT=$("${GIT}" rev-parse --short HEAD)
  slack_send ":white_check_mark: [${PROJECT}] \`${GIT_CURRENT_BRANCH}\`:\`${GIT_CURRENT_COMMIT}\` deployed"
  stop_loader "U2728" "${GIT_CURRENT_BRANCH}:${GIT_CURRENT_COMMIT} deployed"
  return 0
}


pulldozer() {
  start_loader "${cli_loader[@]}"
  msg "[${PROJECT}] git checks" 
  if [ ! -d .git ]; then
    stop_loader "U1F4A5" "is not a git repository"
    return 1
  fi

  "${GIT}" fetch --all --quiet

  GIT_PROD_BRANCH="${prod_branch}"
  
  GIT_CURRENT_BRANCH=$("${GIT}" rev-parse --abbrev-ref HEAD)
  LOCAL_CHANGES=$("${GIT}" status --porcelain)
 
  read -r IS_AHEAD IS_BEHIND <<<"$("${GIT}" rev-list --left-right --count "${GIT_PROD_BRANCH}"...origin/"${GIT_PROD_BRANCH}")"
  
  if [ "${GIT_CURRENT_BRANCH}" != "${GIT_PROD_BRANCH}" ]; then
    slack_send ":warning: [${PROJECT}] Alert, branch is ${GIT_CURRENT_BRANCH} and should be ${GIT_PROD_BRANCH} $(if [[ ${mention_slack} ]]; then echo ", pinging <@${mention_slack}>";fi)"
    stop_loader "U1F4A5" "branch is ${GIT_CURRENT_BRANCH} and should be ${GIT_PROD_BRANCH}"
    return 1

  elif [ "${LOCAL_CHANGES}" != "" ]; then
    slack_send ":warning: [${PROJECT}] Alert locals modification in production $(if [[ ${mention_slack} ]]; then echo ", pinging <@${mention_slack}>";fi)"
    stop_loader "U1F4A5" "locals modification in production"
    return 1

  elif [ "${IS_AHEAD}" -ne 0 ] ; then
    slack_send ":boom: [${PROJECT}] branch is ahead from ${IS_AHEAD} commits"
    stop_loader "U1F4A5" "branch is ahead from ${IS_AHEAD} commits"
    return 1

  elif [ "${IS_BEHIND}" -ne 0 ]; then
    # Run
    stop_loader "U2728" "found updates to pull !"
    deploy "${GIT_PROD_BRANCH}" "${GIT_CURRENT_BRANCH}"

  else
    stop_loader "U2728" "everything already is up to date"
    return 1
  fi
}


main() {
  check_deps
  read_config
  pulldozer
}

main

