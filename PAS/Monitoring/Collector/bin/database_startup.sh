#!/bin/bash
# Start the database for the PAS instance.

export DBNAME=@DBNAME@
export DBPORT=@DBPORT@
# Reserved for Enterprise RDBMS: -lruskips 500 -spin 20000
export DBOPTS="-bibufs 40 -B 64000 -L 102400 -Mm 32600 -Ma 10 -Mpb 30 -Mi 1 -Mn 30 -n 80"

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

# Check if database was started or not and take appropriate action
${DLC}/bin/_proutil ${DBDIR}/${DBNAME}.db -C holder
retcode=$? # this saves the return code
case $retcode in
0) echo "Starting database ${DBNAME} on port @DBPORT@"
${DLC}/bin/_mprosrv ${DBDIR}/${DBNAME}.db -H localhost -S ${DBPORT} -N TCP ${DBOPTS} -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@ &>/dev/null &
sleep 4
;;
14) echo "The database is in single-user mode"
exit $retcode
;;
16) echo "The database is in multi-user mode"
exit $retcode
;;
*) echo "proutil -C holder failed"
echo error code = $retcode
exit $retcode
;;
esac # case $retcode in

# Confirm if the database was started before starting other processes
${DLC}/bin/_proutil ${DBDIR}/${DBNAME}.db -C holder
retcode=$? # this saves the return code
case $retcode in
0) echo "The database could not be started"
exit $retcode
;;
14) echo "The database is in single-user mode"
exit $retcode
;;
16) echo "Starting watchdog and BIW/APW processes for ${DBNAME}"
${DLC}/bin/_mprshut ${DBDIR}/${DBNAME}.db -C watchdog -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@ &>/dev/null &
${DLC}/bin/_mprshut ${DBDIR}/${DBNAME}.db -C biw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@ &>/dev/null &
${DLC}/bin/_mprshut ${DBDIR}/${DBNAME}.db -C apw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@ &>/dev/null &
${DLC}/bin/_mprshut ${DBDIR}/${DBNAME}.db -C apw -cpinternal @CODEPAGE@ -cpstream @CODEPAGE@ &>/dev/null &
;;
*) echo "proutil -C holder failed"
echo error code = $retcode
exit $retcode
;;
esac # case $retcode in
