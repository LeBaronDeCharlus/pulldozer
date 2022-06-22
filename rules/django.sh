#!/bin/bash

check_deps() {
  # mandatory deps                            
  deps=(                                                                                                    
      gunicorn
  )

  start_loader "${cli_loader[@]}"
  msg "- checking dependencies" 
  for i in "${deps[@]}"; do 
    if ! which "${i}" &>/dev/null
      then
        stop_loader "u1f4a5" "${i} not found and required, please install"
    fi
  done
  stop_loader "u2728" "ok"
}

# const
SUDO="$(which sudo)"
SYSTEMCTL="$(which systemctl)"
GUNICORN="$(which gunicorn)"

django() {
  check_deps
  "${SUDO}" "${SYSTEMCTL}" restart "${GUNICORN}"
}
