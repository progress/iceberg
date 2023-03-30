/*------------------------------------------------------------------------
    Copyright (c) 2020-2021 by Progress Software Corporation. All rights reserved.

    File        : testApsv.p
    Purpose     : Test remote APSV connections for the instance.
    Description :
    Author(s)   : Dustin Grau (dugrau@progress.com)
    Created     : Wed Mar 02 15:38:52 EST 2016
    Notes       :
  ----------------------------------------------------------------------*/

/* ***************************  Definitions  ************************** */

using Progress.Lang.*.
using Progress.Json.ObjectModel.*.

block-level on error undo, throw.

/* ***************************  Main Block  *************************** */

define variable hServer   as handle      no-undo.
define variable hProc     as handle      no-undo.
define variable cConnect  as character   no-undo.
define variable lReturn   as logical     no-undo.
define variable cScheme   as character   no-undo initial "http".
define variable cHost     as character   no-undo initial "localhost".
define variable cPort     as character   no-undo initial "8810".
define variable cWebApp   as character   no-undo initial "ROOT".
define variable iNumTests as integer     no-undo.
define variable fTestNum  as decimal     no-undo.
define variable pauseTime as decimal     no-undo.
define variable startTime as datetime-tz no-undo.
define variable timeLimit as integer     no-undo.
define variable waitAfter as integer     no-undo.
define variable lBadCode  as logical     no-undo initial false.
define variable lVerbose  as logical     no-undo initial true.
define variable cTestType as character   no-undo initial "hello". /* Can be 'data' or any other name for 'HelloProc' default. */

function WriteMessage returns logical ( input pcMessage as character ):
    /* Write a message to various locations at once, if being verbose. */
    if not lVerbose then return false.

    /* Leave if the message value is empty or unknown. */
    if (pcMessage gt "") ne true then return false.

    /* Only write to a log if a filename exists. */
    if (log-manager:logfile-name gt "") eq true then
        log-manager:write-message(pcMessage).

    /* Echo message to standard out. */
    message substitute(pcMessage).

    return true.
end function.

define temp-table ttOrder no-undo
    field OrderNum as integer
    .

startTime = now.
assign
    cScheme   = dynamic-function("getParameter" in source-procedure, "scheme") when dynamic-function("getParameter" in source-procedure, "scheme") gt ""
    cHost     = dynamic-function("getParameter" in source-procedure, "host") when dynamic-function("getParameter" in source-procedure, "host") gt ""
    cPort     = dynamic-function("getParameter" in source-procedure, "port") when dynamic-function("getParameter" in source-procedure, "port") gt ""
    cWebApp   = dynamic-function("getParameter" in source-procedure, "webapp") when dynamic-function("getParameter" in source-procedure, "webapp") gt ""
    iNumTests = integer(dynamic-function("getParameter" in source-procedure, "tests"))
    fTestNum  = decimal(dynamic-function("getParameter" in source-procedure, "test"))
    pauseTime = decimal(dynamic-function("getParameter" in source-procedure, "pause"))
    timeLimit = integer(dynamic-function("getParameter" in source-procedure, "duration"))
    waitAfter = integer(dynamic-function("getParameter" in source-procedure, "waitAfter"))
    lBadCode  = lookup(dynamic-function("getParameter" in source-procedure, "badCode"), "true,yes,1") gt 0
    lVerbose  = lookup(dynamic-function("getParameter" in source-procedure, "verbose"), "true,yes,1") gt 0
    cTestType = dynamic-function("getParameter" in source-procedure, "type") when dynamic-function("getParameter" in source-procedure, "type") gt ""
    .

/* Can't run if we don't know how many total tests or which iteration. */
if iNumTests eq ? or iNumTests le 0 then return string(1).
if fTestNum eq ? or fTestNum le 0 then return string(1).

/* Set defaults for testing parameters if none given. */
if pauseTime eq ? or pauseTime le 0 then assign pauseTime = 5.
if timeLimit eq ? or timeLimit le 0 then assign timeLimit = 60.
if pauseTime gt timeLimit then assign pauseTime = timeLimit / 2.

WriteMessage(substitute("&1 | Running '&2' test w/ pause every &3 seconds, time limit &4 seconds; Bad code mode: &5",
                        trim(string(fTestNum, ">9.9")), cTestType, pauseTime, timeLimit, lBadCode)).

create server hServer.

if cWebApp eq "ROOT" then
    assign cConnect = substitute("&1://&2:&3/apsv", cScheme, cHost, cPort).
else
    assign cConnect = substitute("&1://&2:&3/&4/apsv", cScheme, cHost, cPort, cWebApp).

if cTestType eq "looper" then
	assign cConnect = substitute("-URL &1 -sessionModel Session-free", cConnect).
else
	assign cConnect = substitute("-URL &1 -sessionModel Session-managed", cConnect).

assign lReturn = hServer:connect(cConnect) no-error.
if error-status:error then
    undo, throw new AppError(error-status:get-message(1)).

if not lReturn then
    undo, throw new AppError(substitute("Failed to connect to AppServer: &1", cConnect)).

if hServer:connected() then do:
    define variable cGreeting as character no-undo.
    define variable hCPO      as handle    no-undo.

    WriteMessage(substitute("&1 | Connected: &2 | Context: &3", trim(string(fTestNum, ">9.9")), cConnect, hServer:request-info:ClientContextId)).

    create client-principal hCPO.
    hCPO:initialize("dev", "0").
    hCPO:domain-name = "spark".
    hCPO:seal("spark01").
    hServer:request-info:SetClientPrincipal(hCPO).

    /* Run a remote procedure every X seconds up to the given limit. */
    RPTBLK:
    repeat stop-after timeLimit on stop undo, retry:
        if retry then
            undo, throw new AppError(substitute("&1 | STOP condition was encountered.", trim(string(fTestNum, ">9.9"))), 0).

        if not hServer:connected() then
            undo, throw new AppError(substitute("&1 | Server is no longer connected.", trim(string(fTestNum, ">9.9"))), 0).

        case cTestType:
			when "looper" then do:
					WriteMessage(substitute("&1 | Running remote procedure...", trim(string(fTestNum, ">9.9")))).

					define variable iTime as int64 no-undo.
					run Business/Looper.p on server hServer (output iTime) no-error.
					if error-status:error then
						undo, throw new AppError(substitute("&1 (Return-Value: &2)", error-status:get-message(1), return-value), 0).

					WriteMessage(substitute("&1 | Elapsed (ms): &2", trim(string(fTestNum, ">9.9")),  iTime)).
			end.
            when "hello" then do:
                WriteMessage(substitute("&1 | Running persistent procedure...", trim(string(fTestNum, ">9.9")))).

                run Business/HelloProc.p on server hServer persistent set hProc no-error.
                if error-status:error then
                    undo, throw new AppError(substitute("&1 (Return-Value: &2)", error-status:get-message(1), return-value), 0).
                else
                    WriteMessage(substitute("&1 | Created persistent procedure handle &2", trim(string(fTestNum, ">9.9")), hProc)).

                if valid-handle(hProc) then
                    run setHelloUser in hProc ( input substitute("World (&1 of &2)", trim(string(fTestNum, ">9.9")), iNumTests) ).

                WriteMessage(substitute("&1 | Ran setHelloUser", trim(string(fTestNum, ">9.9")))).

                if valid-handle(hProc) then
                    run sayHelloStoredUser in hProc ( output cGreeting ).

                WriteMessage(substitute("&1 | Ran sayHelloStoredUser", trim(string(fTestNum, ">9.9")))).

                /* This should normally be FALSE, unless we want the persistent handle to not be deleted as expected. */
                if not lBadCode then do:
                    WriteMessage(substitute("&1 | Deleting persistent procedure handle &2", trim(string(fTestNum, ">9.9")), hProc)).
                    delete object hProc no-error.
                end.

                WriteMessage(substitute("&1 | Greeting: &2", trim(string(fTestNum, ">9.9")), cGreeting)).
            end.
			otherwise
				WriteMessage(substitute("&1 | Test type '&2' not specified or not supported!", trim(string(fTestNum, ">9.9")), cTestType)).
        end case.

        WriteMessage(substitute("&1 | Pausing test loop for &2 seconds...", trim(string(fTestNum, ">9.9")), max(0.1, pauseTime))).
        pause max(1, pauseTime) no-message.

        if interval(now, startTime, "seconds") ge timeLimit then leave RPTBLK.
    end. /* do */
end. /* connected */

WriteMessage(substitute("&1 | Test End", trim(string(fTestNum, ">9.9")))).

/* Return value expected by PCT Ant task. */
return string(0).

catch err as Progress.Lang.Error:
    WriteMessage(substitute("&1 | Error: &2", trim(string(fTestNum, ">9.9")), err:GetMessage(1))).

    /* Return an unsuccessful code for this test. */
    return string(0).
end catch.
finally:
    if valid-object(hServer) and hServer:connected() then do:
        /* Make sure we always wait if still connected, even if we previously caught an error. */
        if waitAfter ne ? and waitAfter gt 0 then do:
            /* If test ended early, add on the remaining time to the specified waiting period. */
            if interval(now, startTime, "seconds") lt timeLimit then
                assign waitAfter = waitAfter + (timeLimit - interval(now, startTime, "seconds")).

            WriteMessage(substitute("&1 | Finally; Pausing post-loop for &2 seconds...", trim(string(fTestNum, ">9.9")), waitAfter)).
            pause waitAfter no-message.
        end.

        WriteMessage(substitute("&1 | Finally; Disconnecting", trim(string(fTestNum, ">9.9")))).

        hServer:disconnect().
        delete object hServer no-error.

        WriteMessage(substitute("&1 | Finally; Disconnected", trim(string(fTestNum, ">9.9")))).
    end.
    else
        WriteMessage(substitute("&1 | Finally; No Server Available", trim(string(fTestNum, ">9.9")))).
end.
