/*------------------------------------------------------------------------
    File        : OpenEdge/ApplicationServer/Util/healthpush.p
    Purpose     : Push HealthScanner data to a remote server as JSON
    Description :
    Author(s)   : dugrau
    Created     : Tue May 18 14:42:25 EST 2021
    Notes       :
  ----------------------------------------------------------------------*/

block-level on error undo, throw.

using OpenEdge.Logging.ILogWriter from propath.
using OpenEdge.Logging.LoggerBuilder from propath.

define input parameter PulseID  as character no-undo.
define input parameter AgentPID as integer   no-undo.

do on error undo, throw
   on stop  undo, retry:

    if retry then
        undo, throw new Progress.Lang.AppError("Stop condition encountered.", 0).

    /* Use a custom logger for any messages from this procedure. */
    define variable oLogger as ILogWriter no-undo.
    assign oLogger = LoggerBuilder:GetLogger("PushHealth").

    /* Object for managing the communication of data to a remote server. */
    define variable oPush as OpenEdge.ApplicationServer.Service.IPushData no-undo.
    assign oPush = new OpenEdge.ApplicationServer.Service.PushHealthData().
    oPush:AgentPID = AgentPID. /* Note the current PID doing the push. */

    /**
     * Prepare and send the health data to the remote location specified.
     */
    define variable oData as Progress.Json.ObjectModel.JsonObject no-undo.
    assign oData = oPush:PrepareData(PulseID).

    define variable lHasErrors as logical   no-undo.
    define variable cRemoteURI as character no-undo.
    assign cRemoteURI = cast(oPush, OpenEdge.ApplicationServer.Service.PushHealthData):HealthReportURI.
    assign lHasErrors = oPush:SendData(AgentPID, cRemoteURI, oData).

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
