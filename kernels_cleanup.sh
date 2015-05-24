#!/bin/bash

#/lib/modules

[[ ${BASH_VERSINFO[0]} < 4 || ${BASH_VERSINFO[1]} < 3 ]] && \
    echo "You need at least bash 4.3" >&2 && exit 1

keep_major=${1:-2}
keep_build=${2:-1}

function set_add() {
    local -n arr=$1
    if [[ ! ${arr[*]} =~ $2 ]]; then
        arr+=($2)
    fi
}

function add_file() {
    local -n res=$1
    [[ -f $2 ]] && res+=($2)
}

function add_dir() {
    local -n res=$1
    [[ -d $2 ]] && res+=($2)
}

function sort_version() {
    local -n arr=$1
    sort -t. -k 1,1nr -k 2,2nr -k 3,3nr -k 4,4nr <<< \
        "$(tr ' ' '\n' <<< ${arr[*]})"
}

declare -A removed
declare -A kept
major_versions=()
build_versions=()
versions=()
installed=()

for kv in /var/db/pkg/sys-kernel/gentoo-sources-*; do
    ver=$(basename $kv | sed -r 's/gentoo-sources-//')
    set_add major_versions $ver
    set_add installed $ver
done


for module in /lib/modules/*; do
    version=$(basename $module)
    set_add build_versions $version
    set_add major_versions $(sed -r 's/-gentoo-.*//' <<< $version)
done

for boot_file in \
    /boot/System.map-* \
    /boot/initramfs-* \
    /boot/kernel-genkernel-*; do
    if [[ ${boot_file} =~ '*' ]]; then
        echo "make sure that /boot is mounted!"
        exit 1
    fi

    version=$(
        sed -e 's|/boot/||' \
            -e 's/System.map-genkernel-x86_64-//' \
            -e 's/initramfs-genkernel-x86_64-//' \
            -e 's/kernel-genkernel-x86_64-//' <<< $boot_file
    )
    set_add build_versions ${version}
    set_add major_versions $(sed -r 's/-gentoo-.*//' <<< $version)
done

for src in /usr/src/linux-*; do
    version=$(
        sed -r 's|/usr/src/linux-(.*)-gentoo|\1|' <<< $src
    )
    set_add major_versions $version
done

major_versions=($(sort_version major_versions))
build_versions=($(sort_version build_versions))

echo "Kernels found:"
for i in "${!major_versions[@]}"; do
    version=${major_versions[$i]}
    filtered=()
    for build in ${build_versions[@]}; do
        if [[ "${build}" =~ "${version}-gentoo" ]]; then
            filtered+=(${build})
        fi
    done

    if [[ ! $i < $keep_major ]]; then
        echo "  $version *"
        removed[$version]="${removed[${version}]} ${filtered[@]}"
        for ri in ${filtered[@]}; do
            echo "    $ri *"
        done
    else
        echo "  $version"

        r=${filtered[@]:${keep_build}}
        k=${filtered[@]:0:${keep_build}}

        for ri in ${r}; do
            echo "    $ri *"
        done
        for ki in ${k}; do
            echo "    $ki"
        done

        removed[$version]="${removed[$version]} $r"
    fi
done

echo
echo "Items to be removed:"
i=0
all_files=()
for major in ${major_versions[@]}; do
    files=()
    for build in ${removed[$major]}; do
        add_file files /boot/System.map-genkernel-x86_64-${build}
        add_file files /boot/initramfs-genkernel-x86_64-${build}
        add_file files /boot/kernel-genkernel-x86_64-${build}
        add_dir files /lib/modules/${build}
    done

    #[[ ! $i < $keep_major ]] && \
    if [[ ! ${installed[*]} =~ $major ]]; then
        add_dir files /usr/src/linux-${major}-gentoo
    fi

    if [[ ${#files[@]} > 0 ]]; then
        echo "  $major:"
        echo -n "    rm -rf"
        for f in ${files[@]}; do
            echo " \\"
            echo -n "      $f"
        done
        echo
    fi
    i=$(( i + 1 ))
    all_files+=(${files[@]})
done

size="$(bc <<< "($(
    du --max-depth=0 ${all_files[@]} \
    | awk '{print $1}' \
    | sed -e 's/M//' \
    | tr '\n' '+' \
    | sed -r -e 's~^\++~~' -e 's~\++$~~'
    ))/1024")"
echo "Running these commands will free ~${size}M"

echo
echo "Consider running following commands before this script:"
echo "  mount /boot"
echo "  emerge --depclean"
echo "and these after:"
echo "  grub2-mkconfig -o /boot/grub/grub.cfg"
