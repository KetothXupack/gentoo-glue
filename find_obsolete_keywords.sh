#!/bin/bash
installed=($(
    find /var/db/pkg/ -name PF \
    | sed -r 's~/var/db/pkg/(.*)/PF~=\1~'
))

for k_file in /etc/portage/package.keywords/*; do
    pkgs=($(grep "^=" $k_file | grep "~amd64" | sed -r 's/\s+~amd64//'))
    not_installed=()
    for pkg in ${pkgs[@]}; do
        if [[ ! ${installed[*]} =~ ${pkg} ]]; then
            not_installed+=($pkg)
        fi
    done

    if [[ ${#not_installed[@]} > 0 ]]; then
        echo "${k_file}:"
        for pkg in ${not_installed}; do
            echo "  $pkg"
        done
    fi
done
