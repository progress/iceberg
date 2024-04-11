/*------------------------------------------------------------------------
    File        : PushLiveDiagData
    Purpose     : Default implementation for live diagnostic data
    Description :
    Author(s)   : Dustin Grau
    Created     : Fri Dec 20 14:07:43 EDT 2019
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

class OpenEdge.ApplicationServer.Service.PushLiveDiagData inherits OpenEdge.ApplicationServer.Service.PushData:

    /* Special string which contains the parameters passed from the enablement command line. */
    define public property PulseID as character no-undo get. private set.

    method public override JsonObject PrepareData ( input plData as longchar ):
        define variable oRequestJson as JsonObject no-undo.
        define variable fSize        as decimal    no-undo.

        /* Prepare a JSON payload as expected by the remote server, which must include certain values to identify the source of the data. */
        assign oRequestJson = new JsonObject().
        oRequestJson:Add("AppName", "").
        oRequestJson:Add("Instance", "").
        oRequestJson:Add("SampleName", "").
        oRequestJson:Add("Data", super:PrepareData(plData)). /* Run the super method to parse the JSON string into a JSON object. */

        /* Parse out the "Pulse ID" values to be used within the payload to the monitoring instance. */
        if JsonPropertyHelper:HasTypedProperty(oRequestJson, "Data", JsonDataType:Object) then do:
            define variable cTemp as character no-undo.
            define variable iX    as integer   no-undo.

            if JsonPropertyHelper:HasTypedProperty(oRequestJson:GetJsonObject("Data"), "pulseId", JsonDataType:String) then do:
                this-object:PulseID = oRequestJson:GetJsonObject("Data"):GetCharacter("pulseId").

                if (this-object:PulseID gt "") eq true then
                do iX = 1 to num-entries(this-object:PulseID, "|"):
                    assign cTemp = trim(entry(iX, this-object:PulseID, "|")).
    
                    case true:
                        when cTemp begins "app=" then do:
                            this-object:ABLAppName = trim(entry(2, cTemp, "=")).
                            oRequestJson:Set("AppName", this-object:ABLAppName).
                        end. /* app */
    
                        when cTemp begins "host=" then do:
                            if PushConfig:InstancePort[1] gt 0 then
                                this-object:InstanceURI = substitute("http://&1:&2", trim(entry(2, cTemp, "=")), PushConfig:InstancePort[1]).
                            else if PushConfig:InstancePort[2] gt 0 then
                                this-object:InstanceURI = substitute("https://&1:&2", trim(entry(2, cTemp, "=")), PushConfig:InstancePort[2]).
                            oRequestJson:Set("Instance", this-object:InstanceURI).
                        end. /* host */
    
                        when cTemp begins "name=" then do:
                            oRequestJson:Set("SampleName", trim(entry(2, cTemp, "="))).
                        end. /* name */
                    end case.
                end. /* do iX */

                oRequestJson:GetJsonObject("Data"):Remove("pulseId"). /* Remove the property before sending. */
            end. /* has pulseId */
        end. /* valid data */

        assign fSize = length(oRequestJson:GetJsonText(), "raw") / 1024.
        oLogger:Debug(substitute("Prepared JSON payload of &1kb (LiveDiag, A&2).", trim(string(fSize,">>>,>>>,>>9.99")), this-object:AgentPID)).

        return oRequestJson.

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error while preparing metrics request: &1", err:GetMessage(1))).
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
        assign cDumpFile = substitute("&1/push_livediag_A&2_&3_&4.json",
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

        oLogger:Debug(substitute("A&1 sending metrics data to &2", this-object:AgentPID, pcHttpUrl)).

        /* We need a Put for consistency with PDO invoke operations on the remote server. */
        assign oRequest = RequestBuilder:Put(pcHttpUrl, poData)
                                        :ContentType("application/json")
                                        :AcceptJson()
                                        :Request.
        if valid-object(oRequest) then
            oResponse = HttpClient:Instance():Execute(oRequest).

        if not valid-object(oResponse) then
            undo, throw new AppError("Response unavailable for Metrics push.", 0).

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
                        oLogger:Info(substitute("Processed diagnostics at &1 for A&2", oBody:GetCharacter("processed"), this-object:AgentPID)).
                end. /* success */
                else
                    undo, throw new AppError("Unsuccessful response from server.", 0).
            end. /* oBody */
        end. /* oResponse */

        return false. /* Return false to indicate no errors during sending/processing. */

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error while sending metrics to remote server: &1", err:GetMessage(1))).

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
