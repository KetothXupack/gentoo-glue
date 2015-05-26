_spin_count=1
_spinner="/-\|"

function create_spinner() {
    echo -n "$1  "
}

function spin() {
    printf "\b${_spinner:_spin_count++%${#_spinner}:1}"
}

function stop_spinner() {
    printf "\b \n"
}
