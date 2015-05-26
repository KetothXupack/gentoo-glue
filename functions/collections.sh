function map_add() {
    local -n arr=$1
    if [[ ! "${arr[$2]}" =~ "$3" ]]; then
        arr[$2]="${arr[$2]} $3"
    fi
}

function set_add() {
    local -n arr=$1
    if [[ ! ${arr[*]} =~ $2 ]]; then
        arr+=($2)
    fi
}
