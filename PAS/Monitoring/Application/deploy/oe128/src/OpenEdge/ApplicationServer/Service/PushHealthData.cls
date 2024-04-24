/*------------------------------------------------------------------------
    File        : PushHealthData
    Purpose     : Experimental add-on to push HealthScanner data
    Description :
    Author(s)   : Dustin Grau
    Created     : Tue May 18 14:15:53 EDT 2021
    Notes       :
  ----------------------------------------------------------------------*/

using Progress.Lang.* from propath.
using OpenEdge.Core.Json.JsonPropertyHelper from propath.
using OpenEdge.Logging.LogLevelEnum from propath.
using OpenEdge.Net.HTTP.HttpClient from propath.
using OpenEdge.Net.HTTP.IHttpRequest from propath.
using OpenEdge.Net.HTTP.IHttpResponse from propath.
using OpenEdge.Net.HTTP.RequestBuilder from propath.
using Progress.Json.ObjectModel.JsonArray from propath.
using Progress.Json.ObjectModel.JsonObject from propath.
using Progress.Json.ObjectModel.JsonDataType from propath.
using Progress.Json.ObjectModel.ObjectModelParser from propath.
using OpenEdge.ApplicationServer.Service.PushConfig from propath.

block-level on error undo, throw.

class OpenEdge.ApplicationServer.Service.PushHealthData inherits OpenEdge.ApplicationServer.Service.PushData: 

    define public property HealthReportURI as character no-undo get. private set.

    method private logical HealthCheckEnabled ( ):
        define variable lReturn as logical no-undo initial false.

        /* When HealthCheck is enabled and URI is present, check if agent should push data. */
        if PushConfig:HealthCheckEnabled then do:
            define variable cSemaphore as character  no-undo.
            define variable oData      as JsonObject no-undo.
            
            /* Use a semaphore to prevent multiple agents from trying to send health data.*/
            assign cSemaphore = substitute("&1/HealthPulse.pid", PushConfig:TemporaryDir).

            file-info:file-name = cSemaphore.
            if file-info:full-pathname eq ? then do:
                /* File does not exist so claim ownership by this agent PID. */
                oData = new JsonObject().
                oData:Add(string(this-object:AgentPID), now).
                oData:WriteFile(cSemaphore, true).
                assign lReturn = true.
            end. /* file exists */
            else do:
                /* File exists so check if owned by agent. */
                define variable oParser as ObjectModelParser no-undo.

                /* Parse the file on disk as a JSON object. */
                assign oParser = new ObjectModelParser().
                assign oData = cast(oParser:ParseFile(file-info:full-pathname), JsonObject).

                /* Determine whether this agent should be responsible for pushing health data. */
                if valid-object(oData) then do:
                    if oData:Has(string(this-object:AgentPID)) then do:
                        /* Update timestamp for the semaphore. */
                        oData:Set(string(this-object:AgentPID), now).
                        oData:WriteFile(cSemaphore, true).

                        assign lReturn = true. /* Semaphore was set by this agent. */
                    end. /* Owned by Agent */
                    else do:
                        /* Semaphore set by another agent, check if stale. */
                        define variable cNames as character   no-undo extent.
                        define variable dLast  as datetime-tz no-undo.

                        /* Get the first (only) property by name. */
                        assign cNames = oData:GetNames().
                        dLast = oData:GetDatetimeTZ(cNames[1]).

                        /* If the last update time was more than a minute ago, take ownership. */
                        if interval(now, dLast, "seconds") gt 60 then do:
                            oData = new JsonObject().
                            oData:Add(string(this-object:AgentPID), now).
                            oData:WriteFile(cSemaphore, true).
                            assign lReturn = true.
                        end. /* > 1 minute */
                    end. /* Owned by Other Agent */
                end. /* valid-object oData */

                delete object oParser no-error.
                delete object oData no-error.
            end. /* file missing */

            oLogger:Debug(substitute("A&1 &2 configured to push health data.", this-object:AgentPID, trim(string(lReturn, "is/is not")))).
        end. /* HealthCheckEnabled */

        finally:
            return lReturn.
        end finally.
    end method.

    method private JsonArray GetHealthConfig ( ):
        define variable cRequestURI as character     no-undo.
        define variable cStatus     as character     no-undo.
        define variable iHealth     as decimal       no-undo.
        define variable oRequest    as IHttpRequest  no-undo.
        define variable oResponse   as IHttpResponse no-undo.
        define variable oBody       as JsonObject    no-undo.
        define variable oData       as JsonArray     no-undo.

        /* Obtain health config from the following URL (requests against the local server). */
        assign cRequestURI = substitute("http://127.0.0.1:&1/health?view=config", PushConfig:HealthCheckPort).

        /* Perform the request via GET. */
        oLogger:Debug(substitute("Requesting health config at &1", cRequestURI)).
        oRequest = RequestBuilder:Get(cRequestURI)
                                 :ContentType("application/json")
                                 :AcceptJson()
                                 :Request.
        if valid-object(oRequest) then
            oResponse = HttpClient:Instance():Execute(oRequest).

        oLogger:Trace(substitute("HealthConfig Status Code: &1", oResponse:StatusCode)).

        /* Check the status code from the remote collector. */
        if oResponse:StatusCode ne 200 then
            undo, throw new AppError(substitute("HealthConfig response code was not HTTP/200: &1", string(oResponse:StatusCode)), 0).

        /* Check the detailed status from the HealthScanner. */
        if valid-object(oResponse) and valid-object(oResponse:Entity) and type-of(oResponse:Entity, JsonObject) then do:
            assign oBody = cast(oResponse:Entity, JsonObject).

            /* Process the results if we have a valid body. */
            if valid-object(oBody) and JsonPropertyHelper:HasTypedProperty(oBody, "HealthConfig", JsonDataType:Array) then
                assign oData = cast(oBody:GetJsonArray("HealthConfig"):Clone(), JsonArray).
        end. /* oResponse */

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error while obtaining health config: &1", err:GetMessage(1))).
        end catch.
        finally:
            delete object oBody no-error.
            delete object oRequest no-error.
            delete object oResponse no-error.

            /* Always return a JSON array. */
            if not valid-object(oData) then
                assign oData = new JsonArray().

            return oData.
        end finally.
    end method. /* getHealthConfig */

    method private JsonArray GetHealthDataset ( ):
        define variable cRequestURI as character     no-undo.
        define variable cStatus     as character     no-undo.
        define variable iHealth     as decimal       no-undo.
        define variable oRequest    as IHttpRequest  no-undo.
        define variable oResponse   as IHttpResponse no-undo.
        define variable oBody       as JsonObject    no-undo.
        define variable oData       as JsonArray     no-undo.

        /* Obtain health config from the following URL (requests against the local server). */
        assign cRequestURI = substitute("http://127.0.0.1:&1/health?view=dataset", PushConfig:HealthCheckPort).

        /* Perform the request via GET. */
        oLogger:Debug(substitute("Requesting health data at &1", cRequestURI)).
        oRequest = RequestBuilder:Get(cRequestURI)
                                 :ContentType("application/json")
                                 :AcceptJson()
                                 :Request.
        if valid-object(oRequest) then
            oResponse = HttpClient:Instance():Execute(oRequest).

        oLogger:Trace(substitute("HealthDataset Status Code: &1", oResponse:StatusCode)).

        /* Check the status code from the remote collector. */
        if oResponse:StatusCode ne 200 then
            undo, throw new AppError(substitute("HealthDataset response code was not HTTP/200: &1", string(oResponse:StatusCode)), 0).

        /* Check the detailed status from the HealthScanner. */
        if valid-object(oResponse) and valid-object(oResponse:Entity) and type-of(oResponse:Entity, JsonObject) then do:
            assign oBody = cast(oResponse:Entity, JsonObject).

            /* Process the results if we have a valid body. */
            if valid-object(oBody) and JsonPropertyHelper:HasTypedProperty(oBody, "HealthData", JsonDataType:Array) then
                assign oData = cast(oBody:GetJsonArray("HealthData"):Clone(), JsonArray).
        end. /* oResponse */

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error while obtaining probe data: &1", err:GetMessage(1))).
        end catch.
        finally:
            delete object oBody no-error.
            delete object oRequest no-error.
            delete object oResponse no-error.

            /* Always return a JSON array. */
            if not valid-object(oData) then
                assign oData = new JsonArray().

            return oData.
        end finally.
    end method. /* getHealthDataset */

    method public override JsonObject PrepareData ( input plData as longchar ):
        define variable oRequestJson as JsonObject no-undo.
        define variable fSize        as decimal    no-undo.
        define variable cTemp        as character  no-undo.
        define variable iX           as integer    no-undo.

        assign oRequestJson = new JsonObject().
        oRequestJson:Add("HealthConfig", new JsonObject()).
        oRequestJson:Add("HealthData", new JsonObject()).

        if (plData gt "") eq true then
        do iX = 1 to num-entries(plData, "|"):
            assign cTemp = trim(entry(iX, plData, "|")).

            case true:
                when cTemp begins "app=" then do:
                    this-object:ABLAppName = trim(entry(2, cTemp, "=")).
                end. /* app */

                when cTemp begins "host=" then do:
                    if PushConfig:InstancePort[1] gt 0 then
                        this-object:InstanceURI = substitute("http://&1:&2", trim(entry(2, cTemp, "=")), PushConfig:InstancePort[1]).
                    else if PushConfig:InstancePort[2] gt 0 then
                        this-object:InstanceURI = substitute("https://&1:&2", trim(entry(2, cTemp, "=")), PushConfig:InstancePort[2]).
                end. /* host */

                when cTemp begins "health=" then do:
                    this-object:HealthReportURI = trim(entry(2, cTemp, "=")).
                end. /* name */
            end case.
        end. /* do iX */

        /* If the HealthCheck is enabled and possible for this agent, then perform collection. */
        if (plData gt "") eq true and this-object:HealthCheckEnabled() then do:
            /* Update the object with the health config/data. */
            oRequestJson:Set("HealthConfig", this-object:GetHealthConfig()).
            oRequestJson:Set("HealthData", this-object:GetHealthDataset()).
        end. /* PushHealth */

        assign fSize = length(oRequestJson:GetJsonText(), "raw") / 1024.
        oLogger:Debug(substitute("Prepared JSON payload of &1kb (Health, A&2).", trim(string(fSize,">>>,>>>,>>9.99")), this-object:AgentPID)).

        return oRequestJson.

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error while preparing health request: &1", err:GetMessage(1))).
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
        assign cDumpFile = substitute("&1/push_health_A&2_&3_&4.json",
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

        /* Prepare a payload which specifies the AppName and Instance. */
        assign oBody = new JsonObject().
        oBody:Add("AppName", this-object:ABLAppName).
        oBody:Add("Instance", this-object:InstanceURI).
        oBody:Add("HealthCheck", poData).

        /* If still here, dump the payload to a temporary directory for forensics as needed. */
        if oLogger:LogLevel eq LogLevelEnum:Trace then
            oBody:WriteFile(cDumpFile, true).

        oLogger:Debug(substitute("A&1 sending health data to &2", this-object:AgentPID, pcHttpUrl)).

        /* We need a Put for consistency with PDO invoke operations on the remote server. */
        assign oRequest = RequestBuilder:Put(pcHttpUrl, oBody)
                                        :ContentType("application/json")
                                        :AcceptJson()
                                        :Request.
        if valid-object(oRequest) then
            oResponse = HttpClient:Instance():Execute(oRequest).

        if not valid-object(oResponse) then
            undo, throw new AppError("Response unavailable for Health push.", 0).

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
                        oLogger:Info(substitute("Processed health data at &1 for A&2", oBody:GetCharacter("processed"), this-object:AgentPID)).
                end. /* success */
                else
                    undo, throw new AppError("Unsuccessful response from server.", 0).
            end. /* oBody */
        end. /* oResponse */

        return false. /* Return false to indicate no errors during sending/processing. */

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error while sending health to remote server: &1", err:GetMessage(1))).

            /* If no output exists yet, dump the current data to disk as a backup. */
            file-info:file-name = cDumpFile.
            if file-info:full-pathname eq ? then
                oBody:WriteFile(cDumpFile, true).

            return true. /* Mark as failure if any error occurs. */
        end catch.
        finally:
            delete object oBody no-error.
            delete object oRequest no-error.
            delete object oResponse no-error.
        end finally.
    end method. /* SendData */

end class.
