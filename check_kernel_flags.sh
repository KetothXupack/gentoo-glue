#!/bin/bash

# This tool is not 100% accurate beacuse if some maintainers prefer to
# use "local" declarations for CONFIG_CHECK variable and *may* lead to
# missing "declare" record in environment.bz2
#
# You can inspect output of
# find /var/db/pkg/ -name "environment.bz2" -exec bzgrep 'CONFIG_CHECK=' {} +

[[ ${BASH_VERSINFO[0]} < 4 || ${BASH_VERSINFO[1]} < 3 ]] && \
    echo "You need at least bash 4.3" >&2 && exit 1

conf_file="/usr/src/linux/.config"
conf_mem="/proc/config.gz"

declare -A all_flags
declare -A n2k_file
declare -A n2k_mem
affected_packages=()
warning_packages=()

script=$(cat <<'EOF'
    $found = 0;
    $result = " ";
    $s = " ";
    while(<>) {
        line:
        if (!$found) {
            if ($_ =~ /(local|declare).*CONFIG_CHECK=[\"\']/) {
                $_ =~ s/.*CONFIG_CHECK=[\"\'](.*)/$1/;
                $found = 1;
            }
        }

        if ($found && $_ =~ /[\"\']/) {
            my $end = $_;
            $end =~ s/([^\"\']*)[\"\'].*/$1/;
            $_ =~ s/[^\"\']*[\"\'](.*)/$1/;
            $found = 0;
            $result .= $space . $end;
            goto line;
        } elsif ($found) {
            $result .= $space . $_;
        }
    }
    print $result;
EOF
)

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

function ebuild() {
    local file="$(sed -r 's~([^/]+)/([^/]+)-([0-9\-\.]+r?[0-9]?)~/usr/portage/\1/\2/\2-\3~g' <<< $1)"
    echo "${file}.ebuild"
}

function check_flag() {
    # we'll account warnings too
    local flag=${1//\~}

    local grep_cmd=$2
    local config=$3

    local prefix="+"

    if [[ "!" == "${flag:0:1}" ]]; then
        flag="${flag:1}"
        prefix="-"
    fi

    flag="CONFIG_${flag}"
    res="$(${grep_cmd} "$flag[ =]" ${config})"

    [[ "#" == "${res:0:1}" ]] || [[ "${res}" == "" ]]
    local test_result=$?
    if [[ ${test_result} == 0 && ${prefix} == "+" ]] || \
       [[ ${test_result} == 1 && ${prefix} == "-" ]]; then
        echo "${prefix}${flag}"
        return 0
    fi
    return 1
}

echo -n "Searching violations..."
j=1
sp="/-\|"
echo -n '  '
for i in $(EIX_LIMIT=0 eix '-I*' --format '<installedversions:NAMEVERSION>'); do
    printf "\b${sp:j++%${#sp}:1}"

    f="/var/db/pkg/$i/environment.bz2"
    h="/var/db/pkg/$i/INHERITED"
    if [[ -f ${f} && -f ${h} ]]; then
        if grep -q linux-info ${h}; then
            flags=$(bzcat ${f} | perl -e "${script}")

            if ! bzgrep -q "declare -- CONFIG_CHECK=[\"']" ${f} && \
                 bzgrep -qE "local\s+CONFIG_CHECK=[\"']" ${f}; then
                warning_packages+=(${i})
            fi

            for flag in ${flags}; do
                map_add all_flags ${flag} ${i}
            done
        fi
    fi
done

for read_cmd in "file grep ${conf_file}" "mem zgrep ${conf_mem}"; do
    parts=(${read_cmd})
    [[ -f "${parts[2]}" ]] || continue
    for flag in "${!all_flags[@]}"; do
        printf "\b${sp:j++%${#sp}:1}"
        res=$(check_flag ${flag} ${parts[1]} ${parts[2]})
        if [[ $? == 0 ]]; then
            for pkg in ${all_flags[$flag]}; do
                set_add affected_packages ${pkg}
                eval "map_add n2k_${parts[0]} ${pkg} ${res}"
            done
        fi
    done
done

printf "\b \n"
for pkg in ${warning_packages[@]}; do
    echo "  WARNING: may produce inaccurate result for =$pkg"
done

if [[ ${#affected_packages[@]} == 0 ]]; then
    echo "No violations found. Hooray!"
    exit 0
fi

echo "Some violations was found during analysis..."
for conf in "file ${conf_file}" "mem ${conf_mem}"; do
    parts=(${conf})
    eval "[[ -f ${parts[1]} && \${#n2k_${parts[0]}[@]} > 0 ]]"
    if [[ $? == 0 ]]; then
        echo
        echo "Violations for ${parts[1]}:"
        eval "
            for k in \"\${!n2k_${parts[0]}[@]}\"; do
                if [[ ! \${n2k_${parts[0]}[\$k]} == \"\" ]]; then
                    echo \"  =\${k}\"
                    for v in \${n2k_${parts[0]}[\$k]}; do
                        echo \"    \$v\"
                    done
                fi
            done
        "
    fi
done

echo
echo "You may run next commands to validate result:"
for package in ${affected_packages[@]}; do
    echo "  ebuild $(ebuild ${package}) clean setup clean"
done
