#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

#
# Upgrade a single agent on CNs in this DC.
#

if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail


NAME=$(basename $0)
START=$(date +%s)


#---- support functions

function usage {
    if [[ -n "$1" ]]; then
        echo "error: $1"
        echo ""
    fi
    echo "Usage:"
    echo "  $NAME [<options>] <agent-tarball>       # install to SDC 7 CNs"
    echo "  $NAME [<options>] -6 <agent-tarball>    # ... to SDC 6.5 CNs"
    echo "  $NAME [<options>] -6 -7 <agent-tarball> # ... to both 6.5 and 7 CNs"
    echo ""
    echo "Options:"
    echo "  -6            Install to SDC 6.5 CNs."
    echo "  -7            Explicitly install to SDC 7 CNs. This is the default."
    echo "                However if '-6' is also specified, then '-7' is"
    echo "                necessary to install to SDC 7 CNs as well."
    echo ""
    echo "Examples:"
    echo "  ./upgrade-one-agent.sh amon-agent-master-20140309T052321Z-ga873a6c.tgz"
    exit 1
}

function fatal {
    echo "$(basename $0): error: $1" >&2
    exit 1
}

function errexit {
    if [[ $1 -eq 0 ]]; then
        END=$(date +%s)
        echo "$NAME: Success. Upgrade took $(($END - $START)) seconds." >&2
        exit 0
    else
        echo "$NAME: Failed. Exit status: $1"
        exit $1
    fi
}



#---- mainline

trap 'errexit $?' EXIT

DO_6=false
DO_7=
while getopts "h67" c; do
    case "$c" in
    h)
        usage
        ;;
    6)
        DO_6=true
        ;;
    7)
        DO_7=true
        ;;
    *)
        usage "illegal option -- $OPTARG"
        ;;
    esac
done
if [[ -z "$DO_7" ]]; then
    if [[ "$DO_6" == "true" ]]; then
        DO_7=false
    else
        DO_7=true
    fi
fi
shift $((OPTIND - 1))

TARBALL=$1
[[ -z ${TARBALL} ]] && usage
[[ ! -f ${TARBALL} ]] && fatal "file '${TARBALL}' not found"

# Cannot be in /tmp, else we'll overwrite it during the upgrade of this
# node.
# TODO: this guard fails if relative path given.
[[ "$(dirname $TARBALL)" == "/tmp" ]] \
    && fatal "input agent tarball cannot be in /tmp: $TARBALL"


FILENAME=$(basename ${TARBALL})
OEN_ARGS="-a -t 10 -T 600"

echo "Copy $FILENAME to /tmp on all CNs."
sdc-oneachnode $OEN_ARGS "rm -f /tmp/${FILENAME}" || true
sdc-oneachnode $OEN_ARGS -g $TARBALL -d /tmp

if [[ "$DO_6" == "true" ]]; then
    echo ""
    echo "Installing $FILENAME to SDC 6.5 CNs."
    sdc-oneachnode $OEN_ARGS "
        [ -d /opt/smartdc/agents/lib ] && exit 0;   # looks like SDC 7
        set -o errexit
        /opt/smartdc/agents/bin/agents-npm install /tmp/$FILENAME
        rm /tmp/$FILENAME"
fi

if [[ "$DO_7" == "true" ]]; then
    echo ""
    echo "Installing $FILENAME to SDC 7 CNs."
    sdc-oneachnode $OEN_ARGS "
        [ ! -d /opt/smartdc/agents/lib ] && exit 0;   # looks like SDC 6.5
        set -o errexit
        /opt/smartdc/agents/bin/apm install /tmp/$FILENAME
        rm /tmp/$FILENAME"
fi

