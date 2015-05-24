#!/bin/bash
IFS=' ' read -a cpu_flags <<< "$(
    cat /proc/cpuinfo \
    | grep flags \
    | cut -d: -f2 \
    | sort -u
)"
IFS='' read -a use_flags <<< "$(
    find /usr/portage \
        -name '*.ebuild' \
        -exec grep -Po 'cpu_flags_x86_([\d\w_-]+)' {} + \
        2>/dev/null \
    | cut -d: -f2 \
    | sort -u \
    | sed 's/cpu_flags_x86_//g' \
    | tr '\n' ' '
)"

# for installed only
#    find /var/db/pkg \
#        -name IUSE \
#        -exec grep -Po 'cpu_flags_x86_([\d\w_-]+)' {} + \


result=()
for i in ${cpu_flags[@]}; do
    for j in ${use_flags[@]}; do
        if [[ "${i}" == "${j}" ]]; then
            result+=("${i}")
        fi
    done
done

echo "CPU_FLAGS_X86=\"\${CPU_FLAGS_X86} ${result[@]}\""
