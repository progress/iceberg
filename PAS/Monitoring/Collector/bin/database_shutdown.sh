#!/bin/sh
# Stop the database for the PAS instance.

if [ "${DLC}" = "" ] ; then
    DLC="@DLCHOME@"
    export DLC
fi

if [ "${DBDIR}" = "" ] ; then
    DBDIR="${CATALINA_BASE}/db"
    export DBDIR
fi

${DLC}/bin/_mprshut -by ${DBDIR}/@DBNAME@.db &>/dev/null &
