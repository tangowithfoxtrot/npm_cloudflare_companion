#!/usr/bin/env bash

if [[ -n "${NO_COLOR:-}" ]]; then
  tput() { :; }
fi

log_error() {
  echo -e "$(tput setaf 1)❌  $*$(tput sgr0)" >&2
}

log_bold_error() {
  echo -e "$(tput setaf 1)$(tput bold)❌  $*$(tput sgr0)" >&2
}

log_warning() {
  echo -e "$(tput setaf 3)⚠️  $*$(tput sgr0)" >&2
}

log_info() {
  echo -e "$(tput setaf 6)❕  $*$(tput sgr0)"
}

log_success() {
  echo -e "$(tput setaf 2)✅  $*$(tput sgr0)"
}

log_debug() {
  echo -e "$(tput setaf 4)$*$(tput sgr0)" >&2
}

log_breakpoint() {
  echo -e "$(tput setaf 4)🛑  $*$(tput sgr0)" >&2
  read -r -p "Press enter to continue"
}

log_verbose() {
  echo -e "$(tput setaf 5)$*$(tput sgr0)" >&2
}

# if the BREAKPOINT variable is set, override the log_debug function
if [[ -n "${BREAKPOINT:-}" ]]; then
  log_debug() {
    echo -e "$(tput setaf 4)$*$(tput sgr0)" >&2
    read -r -p "Press enter to continue"
  }
fi
