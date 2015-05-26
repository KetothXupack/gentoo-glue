if (command -v tput && tput colors) >/dev/null 2>&1; then
    GOOD="$(tput sgr0)$(tput bold)$(tput setaf 2)"
    WARN="$(tput sgr0)$(tput bold)$(tput setaf 3)"
    BAD="$(tput sgr0)$(tput bold)$(tput setaf 1)"
    HILITE="$(tput sgr0)$(tput bold)$(tput setaf 6)"
    HILITE="$(tput sgr0)$(tput bold)$(tput setaf 7)"
    BRACKET="$(tput sgr0)$(tput bold)$(tput setaf 4)"
    NORMAL="$(tput sgr0)"
else
    GOOD=$(printf '\033[32;01m')
    WARN=$(printf '\033[33;01m')
    BAD=$(printf '\033[31;01m')
    HILITE=$(printf '\033[36;01m')
    BRACKET=$(printf '\033[34;01m')
    NORMAL=$(printf '\033[0m')
fi
