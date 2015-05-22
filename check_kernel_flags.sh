#!/bin/bash

conf="/usr/src/linux/.config"

for i in $(EIX_LIMIT=0 eix '-I*' --format '<installedversions:NAMEVERSION>'); do
    f="/var/db/pkg/$i/environment.bz2"
    h="/var/db/pkg/$i/INHERITED"
    e="$(echo $i | sed -r 's~([^/]+)/([^/]+)-([0-9\-\.]+r?[0-9]?)~/usr/portage/\1/\2/\2-\3~g')"
    e="$e.ebuild"

    if [[ -f $f && -f $h ]]; then
        if grep -q linux-info $h; then
        flags=`bzcat $f | perl -e '
            $found = 0;
            $result = " ";
            $s = " ";
            while(<>) {
                line:
                if (!$found) {
                    if ($_ =~ /(local|declare).*\sCONFIG_CHECK=\"/) {
                        $_ =~ s/.*CONFIG_CHECK=\"(.*)/$1/;
                        $found = 1;
                    }
                }
                if ($found && $_ =~ /\"/) {
                    my $end = $_;
                    $end =~ s/([^\"]*)\".*/$1/;
                    $_ =~ s/[^\"]*\"(.*)/$1/;
                    $found = 0;
                    $result .= $space . $end;
                    goto line;
                } elsif ($found) {
                    $result .= $space . $_;
                }
            }
            print $result;
        '`

        for flag in $flags; do
            if [[ "~!" == "${flag:0:2}" ]]; then
                key="CONFIG_${flag:2}"
                res="$(grep "$key[ =]" $conf)"
                if [[ "#" == "${res:0:1}" ]] || [[ "${res}" == "" ]]; then
                    #echo "$key OK (not set)"
                    :;
                else
                    echo "$key FAIL (required by =$i)"
                fi
            elif [[ "~" == "${flag:0:1}" ]]; then
                key="CONFIG_${flag:1}"
                res="$(grep "$key[ =]" $conf)"
                if [[ "#" == "${res:0:1}" ]] || [[ "${res}" == "" ]]; then
                    echo "$key FAIL (required by =$i)"
                else
                    #echo "$key OK (set)"
                    :;
                fi
            fi
        done
        fi
    fi
done
