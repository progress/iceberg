#!/bin/bash
# Stop the database for the PAS instance.

if [ "${DLC}" = "" ] ; then
    export DLC="@DLCHOME@"
fi

if [ "${DBDIR}" = "" ] ; then
    if [ -z "${CATALINA_BASE}" ]; then
        echo "CATALINA_BASE is not set, using static path."
        export DBDIR="@PASPATH@/db"
    else
        export DBDIR="${CATALINA_BASE}/db"
    fi
fi

echo "Shutting down @DBNAME@ database."
${DLC}/bin/_mprshut -by ${DBDIR}/@DBNAME@.db &>/dev/null &
