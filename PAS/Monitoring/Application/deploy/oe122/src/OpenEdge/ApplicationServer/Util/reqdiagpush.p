/*------------------------------------------------------------------------
    File        : OpenEdge/ApplicationServer/Util/reqdiagpush.p
    Purpose     : Push profiler data to a remote server as JSON
    Description :
    Author(s)   : mbanks, dugrau
    Created     : Thu Feb 22 13:14:25 EST 2018
    Notes       :
  ----------------------------------------------------------------------*/

block-level on error undo, throw.

using OpenEdge.Logging.ILogWriter from propath.
using OpenEdge.Logging.LoggerBuilder from propath.
using OpenEdge.ApplicationServer.Service.PushConfig from propath.

define input parameter HttpUrl       as character no-undo.
define input parameter AgentPID      as int64     no-undo.
define input parameter ABLSessionID  as character no-undo.
define input parameter RequestStart  as datetime  no-undo.
define input parameter RequestLength as int64     no-undo.
define input parameter Transport     as character no-undo.
define input parameter APIEntryPt    as character no-undo.
define input parameter TestRun       as character no-undo.
define input parameter DiagData      as longchar  no-undo.

do on error undo, throw
   on stop  undo, retry:

    if retry then
        undo, throw new Progress.Lang.AppError("Stop condition encountered.", 0).

    /* Use a custom logger for any messages from this procedure. */
    define variable oLogger as ILogWriter no-undo.
    assign oLogger = LoggerBuilder:GetLogger("PushProfiler").

    /* Object for managing the communication of data to a remote server. */
    define variable oPush as OpenEdge.ApplicationServer.Service.IPushData no-undo.
    assign oPush = new OpenEdge.ApplicationServer.Service.PushProfilerData().
    oPush:AgentPID = AgentPID. /* Note the current PID doing the push. */

    /* Assumes the "TestRun" value provides info in the format <app-name>|<instance-url>|<sample-group>. */
    define variable cPulseID as character no-undo.
    define variable cTemp    as character no-undo.
    define variable cName    as character no-undo.
    define variable iX       as integer   no-undo.

    if (TestRun gt "") eq true then
    do iX = 1 to num-entries(TestRun, "|"):
        assign cTemp = trim(entry(iX, TestRun, "|")).

        case true:
            when cTemp begins "app=" then do:
                oPush:ABLAppName = trim(entry(2, cTemp, "=")).
            end. /* app */

            when cTemp begins "host=" then do:
                if PushConfig:InstancePort[1] gt 0 then
                    oPush:InstanceURI = substitute("http://&1:&2", trim(entry(2, cTemp, "=")), PushConfig:InstancePort[1]).
                else if PushConfig:InstancePort[2] gt 0 then
                    oPush:InstanceURI = substitute("https://&1:&2", trim(entry(2, cTemp, "=")), PushConfig:InstancePort[2]).
            end. /* host */

            when cTemp begins "name=" then do:
                assign cName = trim(entry(2, cTemp, "=")).
            end. /* name */
        end case.
    end. /* do iX */

    /**
     * Prepare and send the diagnostic data to the remote location specified.
     * The session ID must have the "AS-" prefix stripped (isolates integer value).
     */
    define variable oData as Progress.Json.ObjectModel.JsonObject no-undo.
    assign oData = oPush:PrepareData( oPush:ABLAppName,
                                      oPush:InstanceURI,
                                      AgentPID,
                                      integer(replace(ABLSessionID, "AS-", "")),
                                      RequestStart,
                                      RequestLength,
                                      Transport,
                                      APIEntryPt,
                                      cName,
                                      DiagData ).

    define variable lHasErrors as logical no-undo.
    assign lHasErrors = oPush:SendData(AgentPID, HttpUrl, oData).

    catch err as Progress.Lang.Error:
        define variable iLoop    as integer   no-undo.
        define variable cMessage as character no-undo.

        do iLoop = 1 to err:NumMessages:
            assign cMessage = trim(substitute("&1 &2", cMessage, err:GetMessage(iLoop))).
        end. /* iLoop */

        if session:error-stack-trace then
            assign cMessage = trim(substitute(("&1~nStack Trace:~n&2"), cMessage, err:CallStack)).

        oLogger:Error(cMessage).
    end catch.
    finally:
        delete object oData no-error.
        delete object oPush no-error.
    end finally.
end.
