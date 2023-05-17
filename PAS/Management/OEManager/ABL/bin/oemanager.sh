#!/bin/sh
# OpenEdge - OEManager CLI Utility

PROG=`basename $0`

# Utility must be run with DLC environment variable set
if [ ! -d $DLC/ant ]
then
    echo "Progress DLC environment variable may not be set correctly."
    echo "Set DLC variable to Progress installation directory."
    echo
    exit 1
fi

# Set the java environment via java_env; requires DLC
if [ ! -f $DLC/bin/java_env ]
then
    echo "Progress $PROG Messages:"
    echo
    echo "java_env could not be found."
    echo
    echo "JAVA environment not set correctly."
    echo "Progress DLC environment variable may not be set correctly."
    echo "Set DLC variable to Progress installation directory."
    echo
    echo "Progress DLC setting: $DLC"
    echo
    exit 1
fi

# Set the JAVA environment
. $DLC/bin/java_env

# Build the Apache Ant execution script path
ANTSCRIPT=${ANTSCRIPT-$DLC/ant/bin/ant}

if [ ! -f $ANTSCRIPT ]
then
    echo "Progress $PROG Messages:"
    echo
    echo "The OpenEdge Apache Ant launch script could not be found."
    echo
    echo "Progress DLC environment variable may not be set correctly."
    echo "Set DLC variable to Progress installation directory."
    echo
    echo "Progress DLC setting: $DLC"
    echo "Script not found: $ANTSCRIPT"
    echo
    exit 1
fi

# use the oemanager.xml as task instructions to Ant, passing all other parameters
ANT_HOME=$DLC/ant ; export ANT_HOME
exec $ANTSCRIPT -f oemanager.xml $@
