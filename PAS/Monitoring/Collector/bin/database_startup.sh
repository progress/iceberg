#!/bin/bash
# Start the database for the PAS instance.

export DBPORT=@DBPORT@
export DBOPTS="-bibufs 40 -B 64000 -L 102400 -lruskips 500 -Mm 32600 -Ma 10 -Mpb 30 -Mi 1 -Mn 30 -n 360 -spin 20000"

if [ "${DLC}" = "" ] ; then
    DLC="@DLCHOME@"
    export DLC
fi

if [ "${DBDIR}" = "" ] ; then
    DBDIR="${CATALINA_BASE}/db"
    export DBDIR
fi

${DLC}/bin/_proutil ${DBDIR}/@DBNAME@.db -C holder
retcode=$? # this saves the return code
case $retcode in
0) echo "Starting database pasmon on port ${DBPORT}"
${DLC}/bin/_mprosrv ${DBDIR}/@DBNAME@.db -H localhost -S ${DBPORT} -N TCP ${DBOPTS} -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@ &>/dev/null &
sleep 2
${DLC}/bin/_mprshut ${DBDIR}/@DBNAME@.db -C biw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@ &>/dev/null &
${DLC}/bin/_mprshut ${DBDIR}/@DBNAME@.db -C apw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@ &>/dev/null &
${DLC}/bin/_mprshut ${DBDIR}/@DBNAME@.db -C apw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@ &>/dev/null &
;;
14) echo "The database is in single-user mode"
exit $retcode
;;
16) echo "The database is busy in multi-user mode"
exit $retcode
;;
*) echo "proutil -C holder failed"
echo error code = $retcode
exit $retcode
;;
esac # case $retcode in
