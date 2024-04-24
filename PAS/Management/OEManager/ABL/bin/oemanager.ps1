<#
.NOTES
===========================================================================
Created on:       05/16/2023
Updated on:       05/16/2023
Created by:       dugrau
Organization:     Progress Software Corp. | OpenEdge
Filename:         oemanager.ps1
===========================================================================
.DESCRIPTION
This Powershell script is a called by the oemanager.bat script to execute
the Ant utility in the DLC installation directory (DLC/ant). It utilizes
the oemanager.xml file to configure all tasks and parameters available.

This provides a command line interface to the OEManager webapp installed
to a PAS instance to manage and monitor that instance.
#>

#---- Local Variables ----#
[string]$script:_antPath="$env:DLC\ant\bin\ant.bat"
[string]$script:_taskFilePath="$PSScriptRoot\oemanager.xml"
[string]$script:_taskArgs=""

# Prefix arguments with a "-D" as necessary. This allows the user to pass parameters
# without the prefix (if they forgot) and allows the task name to be anywhere within
# the list of arguments passed to this script. Note that multiple tasks may be run,
# in the order by which they are given.

foreach ($arg in $args) {
    if ($arg.Contains("=") -and $arg -notlike "-D*") {
        $thisArg = " -D$arg"
    }
    else {
        $thisArg = " $arg"
    }
    $script:_taskArgs += $thisArg
}

# Run the ant utility from DLC/ant as previously discovered
Invoke-Expression "& $script:_antPath -f $script:_taskFilePath $script:_taskArgs"
