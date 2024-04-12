/*------------------------------------------------------------------------
    File        : PushProfilerData
    Purpose     : Default implementation for profiler data
    Description :
    Author(s)   : Dustin Grau
    Created     : Wed Jul 17 13:17:43 EDT 2019
    Notes       :
  ----------------------------------------------------------------------*/

using Progress.Lang.* from propath.
using OpenEdge.Core.Json.JsonPropertyHelper from propath.
using OpenEdge.Logging.LogLevelEnum from propath.
using OpenEdge.Net.HTTP.HttpClient from propath.
using OpenEdge.Net.HTTP.IHttpRequest from propath.
using OpenEdge.Net.HTTP.IHttpResponse from propath.
using OpenEdge.Net.HTTP.RequestBuilder from propath.
using Progress.Json.ObjectModel.JsonObject from propath.
using Progress.Json.ObjectModel.JsonDataType from propath.
using OpenEdge.ApplicationServer.Service.PushConfig from propath.

block-level on error undo, throw.

class OpenEdge.ApplicationServer.Service.PushProfilerData inherits OpenEdge.ApplicationServer.Service.PushData:

    method public override JsonObject PrepareData ( input pcABLAppName  as character,
                                                    input pcInstanceURL   as character,
                                                    input piAgentPID      as int64,
                                                    input piABLSessionID  as int64,
                                                    input pdRequestStart  as datetime,
                                                    input piRequestLength as int64,
                                                    input pcTransport     as character,
                                                    input pcAPIEntryPt    as character,
                                                    input pcSampleName    as character,
                                                    input plData          as longchar ):
        define variable oRequestJson as JsonObject no-undo.
        define variable fSize        as decimal    no-undo.

        /* Prepare a JSON payload as expected by the remote server, which must include certain values to identify the source of the data. */
        assign oRequestJson = new JsonObject().
        oRequestJson:Add("AppName", pcABLAppName).
        oRequestJson:Add("Instance", pcInstanceURL).
        oRequestJson:Add("SampleName", pcSampleName).
        oRequestJson:Add("Agent", piAgentPID).
        oRequestJson:Add("Session", piABLSessionID).
        oRequestJson:Add("RequestStart", pdRequestStart).
        oRequestJson:Add("RequestLength", piRequestLength).
        oRequestJson:Add("Transport", pcTransport).
        oRequestJson:Add("EntryPt", pcAPIEntryPt).
        oRequestJson:Add("Data", plData).

        assign fSize = length(oRequestJson:GetJsonText(), "raw") / 1024.
        oLogger:Debug(substitute("Prepared JSON payload of &1kb (Profiler, A&2, S&3).", trim(string(fSize,">>>,>>>,>>9.99")), piAgentPID, piABLSessionID)).

        return oRequestJson.

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error while preparing profiler request: &1", err:GetMessage(1))).
            return ?.
        end catch.
    end method. /* PrepareData */

    method public override logical SendData ( input piAgentPID as int64,
                                              input pcHttpUrl  as character,
                                              input poData     as JsonObject ):
        define variable oRequest  as IHttpRequest  no-undo.
        define variable oResponse as IHttpResponse no-undo.
        define variable oBody     as JsonObject    no-undo.
        define variable cDumpFile as character     no-undo.

        /* Use a metric-based filename with the agent, date, and mtime. */
        assign cDumpFile = substitute("&1/push_profiler_A&2_&3_&4.json",
                                      PushConfig:TemporaryDir,
                                      piAgentPID,
                                      substring(iso-date(now), 1, 10), /* Only use the YYYY-MM-DD portion. */
                                      mtime(now)).

        if poData eq ? then
            undo, throw new AppError("Empty payload, skipping send of data.", 0).

        if not valid-object(poData) then
            undo, throw new AppError("Invalid payload, unable to send data.", 0).

        /* If URL is blank or "file" then write the payload to disk. */
        if (pcHttpUrl gt "") ne true or pcHttpUrl eq "File" then do:
            poData:WriteFile(cDumpFile, true).
            return false. /* Return without errors. */
        end. /* URL Unavailable */

        /* If still here, dump the payload to a temporary directory for forensics as needed. */
        if oLogger:LogLevel eq LogLevelEnum:Trace then
            poData:WriteFile(cDumpFile, true).

        oLogger:Debug(substitute("A&1 sending profiler data to &2", this-object:AgentPID, pcHttpUrl)).

        /* We need a Put for consistency with PDO invoke operations on the remote server. */
        assign oRequest = RequestBuilder:Put(pcHttpUrl, poData)
                                        :ContentType("application/json")
                                        :AcceptJson()
                                        :Request.
        if valid-object(oRequest) then
            oResponse = HttpClient:Instance():Execute(oRequest).

        if not valid-object(oResponse) then
            undo, throw new AppError("Response unavailable for Profiler push.", 0).

        oLogger:Trace(substitute("Returned Status Code: &1", oResponse:StatusCode)).

        /* Check the status code from the remote collector. */
        if oResponse:StatusCode lt 200 or oResponse:StatusCode gt 202 then
            undo, throw new AppError(substitute("Response code was not 200-202: &1", string(oResponse:StatusCode)), 0).

        if valid-object(oResponse:Entity) and type-of(oResponse:Entity, JsonObject) then do:
            assign oBody = cast(oResponse:Entity, JsonObject).

            if JsonPropertyHelper:HasTypedProperty(oBody, "success", JsonDataType:Boolean) then do:
                if oBody:GetLogical("success") then do:
                    oLogger:Debug("Server returned a successful response, parsing timestamp...").
                    if JsonPropertyHelper:HasTypedProperty(oBody, "processed", JsonDataType:String) then
                        oLogger:Info(substitute("Processed profile at &1 for A&2", oBody:GetCharacter("processed"), this-object:AgentPID)).
                end. /* success */
                else
                    undo, throw new AppError("Unsuccessful response from server.", 0).
            end. /* oBody */
        end. /* oResponse */

        return false. /* Return false to indicate no errors during sending/processing. */

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error while sending profiler to remote server: &1", err:GetMessage(1))).

            /* If no output exists yet, dump the current data to disk as a backup. */
            file-info:file-name = cDumpFile.
            if file-info:full-pathname eq ? then
                poData:WriteFile(cDumpFile, true).

            return true. /* Mark as failure if any error occurs. */
        end catch.
        finally:
            delete object oBody no-error.
            delete object oRequest no-error.
            delete object oResponse no-error.
        end finally.
    end method. /* SendData */

end class.
