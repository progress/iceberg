/*------------------------------------------------------------------------
    File        : OpenEdge/ApplicationServer/Util/livediagpush.p
    Purpose     : Push live diagnostic data to a remote server as JSON
    Description :
    Author(s)   : dugrau
    Created     : Fri Dec 20 14:07:25 EST 2019
    Notes       :
  ----------------------------------------------------------------------*/

block-level on error undo, throw.

using OpenEdge.Logging.ILogWriter from propath.
using OpenEdge.Logging.LoggerBuilder from propath.

define input parameter HttpUrl  as character no-undo.
define input parameter AgentPID as integer   no-undo.
define input parameter DiagData as longchar  no-undo.

do on error undo, throw
   on stop  undo, retry:

    if retry then
        undo, throw new Progress.Lang.AppError("Stop condition encountered.", 0).

    /* Use a custom logger for any messages from this procedure. */
    define variable oLogger as ILogWriter no-undo.
    assign oLogger = LoggerBuilder:GetLogger("PushLiveDiag").

    /* Object for managing the communication of data to a remote server. */
    define variable oPush as OpenEdge.ApplicationServer.Service.IPushData no-undo.
    assign oPush = new OpenEdge.ApplicationServer.Service.PushLiveDiagData().
    oPush:AgentPID = AgentPID. /* Note the current PID doing the push. */

    /**
     * Prepare and send the diagnostic data to the remote location specified.
     */
    define variable oData as Progress.Json.ObjectModel.JsonObject no-undo.
    assign oData = oPush:PrepareData(DiagData).

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
        /* Obtain the URL for the health reporting endpoint before we delete the class which holds the value. */
        define variable cPulseID as character no-undo.
        assign cPulseID = cast(oPush, OpenEdge.ApplicationServer.Service.PushLiveDiagData):PulseID.

        delete object oData no-error.
        delete object oPush no-error.

        /* Experimental: Use the same pulse for live diagnostic data to collect and push HealthScanner data to a remote endpoint. */
        run OpenEdge/ApplicationServer/Util/healthpush.p (cPulseID, AgentPID).
    end finally.
end.
