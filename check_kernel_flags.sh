#!/bin/bash

# This tool is not 100% accurate beacuse if some maintainers prefer to
# use "local" declarations for CONFIG_CHECK variable and *may* lead to
# missing "declare" record in environment.bz2
#
# You can inspect output of
# find /var/db/pkg/ -name "environment.bz2" -exec bzgrep 'CONFIG_CHECK=' {} +

[[ ${BASH_VERSINFO[0]} < 4 || ${BASH_VERSINFO[1]} < 3 ]] && \
    echo "You need at least bash 4.3" >&2 && exit 1

DIR="$(
    dirname "$(readlink -f "$0")"
)"
source ${DIR}/functions/spinner.sh
source ${DIR}/functions/colors.sh
source ${DIR}/functions/collections.sh

conf_file="/usr/src/linux/.config"
conf_mem="/proc/config.gz"

export fast_search=0
for arg in "$@"; do
    case $arg in
        "--fast"|"-f" )
           fast_search=1
           ;;
        "--help"|"-h" )
           echo "$0 [-f|--fast] [-h|--help]"
           echo " -f perform fast but less accurate analisys"
           echo " -h show this help"
           exit 0
           ;;
        *) ;;
   esac
done

[[ ${fast_search} == 1 ]] && echo "Running in fast mode" || echo "Running in strict mode"
if [[ ${fast_search} == 0 ]] && [[ $USER != "root" ]]; then
    echo "You must be a root to continue!" >&2
    sudo $0 $@
    exit $?
fi

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
            #if ($_ !=~ /$$\s*local/ || $_ !=~ /$$declare/) {
            #    break;
            #}
            if ($_ =~ /(local|declare --)\s+CONFIG_CHECK=[\"\']/) {
                $_ =~ s/.*\sCONFIG_CHECK=[\"\'](.*)/$1/;
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

function ebuild() {
    local file="$(sed -r 's~([^/]+)/([^/]+)-([0-9\-\.]+r?[0-9]?)~/usr/portage/\1/\2/\2-\3~g' <<< $1)"
    echo "${file}.ebuild"
}

function check_flag() {
    # we'll account warnings too
    local flag=$1
    local grep_cmd=$2
    local config=$3
    local pars="[]"
    local prefix="+"
    local color="${BAD}"

    if [[ ${flag:0:1} == "~" ]]; then
        flag=${flag:1}
        pars="{}"
        color="${WARN}"
    fi

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
        echo "${color}${pars:0:1}${prefix}${pars:1}${NORMAL}${HILITE}${flag}${NORMAL}"
        return 0
    fi
    return 1
}

create_spinner "Searching violations..."
if [[ ${fast_search} == 0 ]]; then
    tmpdir=/tmp/kernel-checker/$(uuidgen)
    for e in $(find /var/db/pkg/ -name environment.bz2); do
        spin

        d=$(dirname $e)
        inh=$d/INHERITED
        if [[ -f $inh ]] && grep -q linux-info $inh; then
            pn=$(source <(bzgrep '\sPN=' $e) > /dev/null;
                echo ${PN}
            )
            pf=$(cat $d/PF)
            ct=$(cat $d/CATEGORY)
            pkg=$ct/$pf

            pkgdir=/$tmpdir/$ct/$pn
            mkdir -p $pkgdir
            f=$pkgdir/$pf.ebuild

            cat $d/$pf.ebuild > $f
            echo >> $f

            # we'll trick ebuild and substitute original
            # check_extra_config function with verbose one
            cat << '            EOF' | sed -r 's/\s*\|//' >> $f
                |copy_function() {
                |    test -n "$(declare -f $1)" || return
                |    eval "${_/$1/$2}"
                |}
                |rename_function() {
                |    copy_function $@ || return
                |    unset -f $1
                |}
                |rename_function check_extra_config ___check_extra_config
                |check_extra_config() {
                |    echo __CONFIG_CHECK=${CONFIG_CHECK}
                |    ___check_extra_config $@
                |}
            EOF

            # re-run setup stage with the same USE flags
            out="$(
                sudo USE="-* $(cat $d/USE)" ebuild $f clean manifest setup clean 2>&1
            )"
            code=$?
            out="$(grep '__CONFIG_CHECK=' <<< "${out}")"
            if [[ $? == 0 ]]; then
                flags=(${out:15})
                for flag in ${flags[@]}; do
                    map_add all_flags ${flag} $pkg
                done
            elif [[ $code != 0 ]]; then
                warning_packages+=($pkg)
            fi
        fi
    done
else
    for i in $(EIX_LIMIT=0 eix '-I*' --format '<installedversions:NAMEVERSION>'); do
        spin

        f="/var/db/pkg/$i/environment.bz2"
        h="/var/db/pkg/$i/INHERITED"
        if [[ -f ${f} && -f ${h} ]]; then
            if grep -q linux-info ${h}; then
                flags=$(bzcat ${f} | perl -e "${script}")

                if ! bzgrep -qP '$declare -- CONFIG_CHECK="' ${f} && \
                    bzgrep -qE "local\s+CONFIG_CHECK=[\"']" ${f};
                then
                    warning_packages+=(${i})
                fi

                for flag in ${flags}; do
                    map_add all_flags ${flag} ${i}
                done
            fi
        fi
    done
fi

for read_cmd in "file grep ${conf_file}" "mem zgrep ${conf_mem}"; do
    parts=(${read_cmd})
    [[ -f "${parts[2]}" ]] || continue
    for flag in "${!all_flags[@]}"; do
        spin
        res="$(check_flag ${flag} ${parts[1]} ${parts[2]})"
        if [[ $? == 0 ]]; then
            for pkg in ${all_flags[$flag]}; do
                set_add affected_packages ${pkg}
                eval "map_add n2k_${parts[0]} ${pkg} \"${res}\""
            done
        fi
    done
done

stop_spinner
for pkg in ${warning_packages[@]}; do
    echo "  ${WARN}WARNING${NORMAL}: may produce inaccurate result for =$pkg"
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
        echo "Violations for ${BRACKET}${parts[1]}${NORMAL}:"
        eval "
            for k in \"\${!n2k_${parts[0]}[@]}\"; do
                if [[ ! \${n2k_${parts[0]}[\${k}]} == \"\" ]]; then
                    echo \"  ${GOOD}=\${k}\"
                    for v in \${n2k_${parts[0]}[\${k}]}; do
                        echo \"    \$v\"
                    done
                fi
            done
        "
    fi
done

if [[ ${fast_search} == 1 ]]; then
    echo
    echo "You may run next commands to validate result:"
    for package in ${affected_packages[@]}; do
        echo "  ebuild $(ebuild ${package}) clean setup clean"
    done
fi
