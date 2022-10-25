/*
    Copyright 2020-2022 Progress Software Corporation

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/
/**
 * Author(s): Dustin Grau (dugrau@progress.com)
 *
 * Trim a specific ABL session for an MSAgent of an ABLApp.
 * Usage: trimABLSession.p <params>
 *  Parameter Default/Allowed
 *   Scheme       [http|https]
 *   Hostname     [localhost]
 *   PAS Port     [8810]
 *   UserId       [tomcat]
 *   Password     [tomcat]
 *   ABL App      [oepas1]
 *   TerminateOpt [0|1|2]
 *   AgentID      [#]
 *   Session      [#]
 *   Debug        [false|true]
 */

using OpenEdge.Core.Json.JsonPropertyHelper.
using OpenEdge.Core.JsonDataTypeEnum.
using OpenEdge.Core.Collections.StringStringMap.
using OpenEdge.Net.HTTP.ClientBuilder.
using OpenEdge.Net.HTTP.Credentials.
using OpenEdge.Net.HTTP.IHttpClient.
using OpenEdge.Net.HTTP.IHttpRequest.
using OpenEdge.Net.HTTP.IHttpResponse.
using OpenEdge.Net.HTTP.RequestBuilder.
using Progress.Json.ObjectModel.JsonObject.
using Progress.Json.ObjectModel.JsonArray.
using Progress.Json.ObjectModel.JsonDataType.

define variable oDelResp   as IHttpResponse   no-undo.
define variable oClient    as IHttpClient     no-undo.
define variable oCreds     as Credentials     no-undo.
define variable cHttpUrl   as character       no-undo.
define variable cInstance  as character       no-undo.
define variable oJsonResp  as JsonObject      no-undo.
define variable oAgents    as JsonArray       no-undo.
define variable oAgent     as JsonObject      no-undo.
define variable oSessions  as JsonArray       no-undo.
define variable oTemp      as JsonObject      no-undo.
define variable oQueryURL  as StringStringMap no-undo.
define variable iLoop      as integer         no-undo.
define variable iLoop2     as integer         no-undo.
define variable iTotSess   as integer         no-undo.
define variable cScheme    as character       no-undo initial "http".
define variable cHost      as character       no-undo initial "localhost".
define variable cPort      as character       no-undo initial "8810".
define variable cUserId    as character       no-undo initial "tomcat".
define variable cPassword  as character       no-undo initial "tomcat".
define variable cAblApp    as character       no-undo initial "oepas1".
define variable cProcID    as character       no-undo.
define variable cSessID    as character       no-undo.
define variable iSession   as integer         no-undo.
define variable cTerminate as character       no-undo initial "0".
define variable cTermType  as character       no-undo.
define variable cDebug     as character       no-undo initial "false".

/* Check for passed-in arguments/parameters. */
if num-entries(session:parameter) ge 9 then
    assign
        cScheme    = entry(1, session:parameter)
        cHost      = entry(2, session:parameter)
        cPort      = entry(3, session:parameter)
        cUserId    = entry(4, session:parameter)
        cPassword  = entry(5, session:parameter)
        cAblApp    = entry(6, session:parameter)
        cTerminate = entry(7, session:parameter)
        cProcID    = entry(8, session:parameter)
        cSessID    = entry(9, session:parameter)
        cDebug     = entry(10, session:parameter)
        .
else if session:parameter ne "" then /* original method */
    assign cPort = session:parameter.
else
    assign
        cScheme    = dynamic-function("getParameter" in source-procedure, "Scheme") when (dynamic-function("getParameter" in source-procedure, "Scheme") gt "") eq true
        cHost      = dynamic-function("getParameter" in source-procedure, "Host") when (dynamic-function("getParameter" in source-procedure, "Host") gt "") eq true
        cPort      = dynamic-function("getParameter" in source-procedure, "Port") when (dynamic-function("getParameter" in source-procedure, "Port") gt "") eq true
        cUserId    = dynamic-function("getParameter" in source-procedure, "UserID") when (dynamic-function("getParameter" in source-procedure, "UserID") gt "") eq true
        cPassword  = dynamic-function("getParameter" in source-procedure, "PassWD") when (dynamic-function("getParameter" in source-procedure, "PassWD") gt "") eq true
        cAblApp    = dynamic-function("getParameter" in source-procedure, "ABLApp") when (dynamic-function("getParameter" in source-procedure, "ABLApp") gt "") eq true
        cTerminate = dynamic-function("getParameter" in source-procedure, "TerminateOpt") when (dynamic-function("getParameter" in source-procedure, "TerminateOpt") gt "") eq true
        cProcID    = dynamic-function("getParameter" in source-procedure, "ProcID") when (dynamic-function("getParameter" in source-procedure, "ProcID") gt "") eq true
        cSessID    = dynamic-function("getParameter" in source-procedure, "SessionID") when (dynamic-function("getParameter" in source-procedure, "SessionID") gt "") eq true
        cDebug     = dynamic-function("getParameter" in source-procedure, "Debug") when (dynamic-function("getParameter" in source-procedure, "Debug") gt "") eq true
        .

if can-do("enable,true,yes,1", cDebug) then do:
    log-manager:logfile-name    = "trimABLSessions.log".
    log-manager:log-entry-types = "4GLTrace".
    log-manager:logging-level   = 5.
end.

case cTerminate:
    when "0" then assign cTermType = "Graceful".
    when "1" then assign cTermType = "Forced".
    when "2" then assign cTermType = "Finish".
    otherwise
        assign /* Must assume graceful option. */
            cTerminate = "0"
            cTermType  = "Graceful"
            .
end case.

assign oClient = ClientBuilder:Build():Client.
assign oCreds = new Credentials("PASOE Manager Application", cUserId, cPassword).
assign cInstance = substitute("&1://&2:&3", cScheme, cHost, cPort).
assign oQueryURL = new StringStringMap().

if (cProcID gt "") ne true then
    undo, throw new Progress.Lang.AppError("No MSAgent PID provided", 0).

if (cSessID gt "") ne true then
    undo, throw new Progress.Lang.AppError("No ABL Session ID provided", 0).

/* Register the URL's to the OEM-API endpoints as will be used in this utility. */
oQueryURL:Put("Agents", "&1/oemanager/applications/&2/agents").
oQueryURL:Put("AgentSessions", "&1/oemanager/applications/&2/agents/&3/sessions").
oQueryURL:Put("AgentSession", "&1/oemanager/applications/&2/agents/&3/sessions/&4").

/* PROCEDURES / FUNCTIONS */

function LogCommand returns logical ( input pcVerb as character, input pcCommand as character ):
    output to value("commands.log") append.
    put unformatted substitute("&1 - &2 &3", iso-date(now), pcVerb, pcCommand) skip.
    output close.
end function. /* LogCommand */

function MakeRequest returns JsonObject ( input pcHttpUrl as character ):
    define variable oReq  as IHttpRequest  no-undo.
    define variable oResp as IHttpResponse no-undo.

    if not valid-object(oClient) then
        undo, throw new Progress.Lang.AppError("No HTTP client available", 0).

    if not valid-object(oCreds) then
        undo, throw new Progress.Lang.AppError("No HTTP credentials provided", 0).

    do on error undo, throw
       on stop undo, retry:
        if retry then
            undo, throw new Progress.Lang.AppError("Encountered stop condition", 0).

        if can-do("true,yes,1", cDebug) then
            message substitute("Calling URL: &1", cHttpUrl).

        oReq = RequestBuilder
                :Get(pcHttpUrl)
                :AcceptContentType("application/vnd.progress+json")
                :UsingBasicAuthentication(oCreds)
                :Request.

        if valid-object(oReq) then do:
            /* Always log the OEM-API command URL with an exact time of execution. */
            LogCommand("GET", cHttpUrl).

            oResp = oClient:Execute(oReq).
        end.
        else
            undo, throw new Progress.Lang.AppError("Unable to create request object", 0).
    end.

    if valid-object(oResp) and oResp:StatusCode eq 200 then do:
        /* If we have an HTTP-200 status and a JSON object as the response payload, return that. */
        if valid-object(oResp:Entity) and type-of(oResp:Entity, JsonObject) then
            return cast(oResp:Entity, JsonObject).
        else if valid-object(oResp:Entity) then
            /* Anything other than a JSON payload should be treated as an error condition. */
            undo, throw new Progress.Lang.AppError(substitute("Successful but non-JSON response object returned: &1",
                                                              oResp:Entity:GetClass():TypeName), 0).
        else
            /* Anything other than a JSON payload should be treated as an error condition. */
            undo, throw new Progress.Lang.AppError("Successful but non-JSON response object returned", 0).
    end. /* Valid Entity */
    else do:
        /* Check the resulting response and response entity if valid. */
        if valid-object(oResp) and valid-object(oResp:Entity) then
            case true:
                when type-of(oResp:Entity, OpenEdge.Core.Memptr) then
                    undo, throw new Progress.Lang.AppError(substitute("Response is a memptr of size &1",
                                                                      string(cast(oResp:Entity, OpenEdge.Core.Memptr):Size)), 0).

                when type-of(oResp:Entity, OpenEdge.Core.String) then
                    undo, throw new Progress.Lang.AppError(string(cast(oResp:Entity, OpenEdge.Core.String):Value), 0).

                when type-of(oResp:Entity, JsonObject) then
                    undo, throw new Progress.Lang.AppError(string(cast(oResp:Entity, JsonObject):GetJsonText()), 0).

                otherwise
                    undo, throw new Progress.Lang.AppError(substitute("Unknown type of response object: &1 [HTTP-&2]",
                                                                      oResp:Entity:GetClass():TypeName, oResp:StatusCode), 0).
            end case.
        else if valid-object(oResp) then
            /* Response is available, but entity is not. Just report the HTTP status code. */
            undo, throw new Progress.Lang.AppError(substitute("Unsuccessful status from server: HTTP-&1", oResp:StatusCode), 0).
        else
            /* Response is not even available (valid) so report that as an explicit case. */
            undo, throw new Progress.Lang.AppError("Invalid response from server, ", 0).
    end. /* failure */

    catch err as Progress.Lang.Error:
        /* Always report any errors during the API requests, and return an empty JSON object allowing remaining logic to continue. */
        message substitute("~nError executing OEM-API request: &1 [URL: &2]", err:GetMessage(1), pcHttpUrl).
        return new JsonObject().
    end catch.
    finally:
        delete object oReq no-error.
        delete object oResp no-error.
    end finally.
end function. /* MakeRequest */

/* Output the name of the program being executed. */
LogCommand("RUN", this-procedure:name).

/* Initial URL to obtain a list of all MSAgents for an ABL Application. */
assign cHttpUrl = substitute(oQueryURL:Get("Agents"), cInstance, cAblApp).
message substitute("Looking for MSAgent &1 of &2...", cProcID, cAblApp).
assign cHttpUrl = substitute(oQueryURL:Get("AgentSessions"), cInstance, cAblApp, cProcID).
assign oJsonResp = MakeRequest(cHttpUrl).
if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:Object) then do:
    if oJsonResp:Has("result") then do:
        message substitute("Found MSAgent PID &1", cProcID).

        oSessions = oJsonResp:GetJsonObject("result"):GetJsonArray("AgentSession").
        assign iTotSess = oSessions:Length.

        if iTotSess gt 0 then
        SESSIONBLK:
        do iLoop2 = 1 to iTotSess
        on error undo, next SESSIONBLK
        on stop undo, next SESSIONBLK:
            if oSessions:GetType(iLoop2) eq JsonDataType:Object then
                assign oTemp = oSessions:GetJsonObject(iLoop2).
            else
                next SESSIONBLK.

            if JsonPropertyHelper:HasTypedProperty(oTemp, "SessionId", JsonDataType:number) then
                assign iSession = oTemp:GetInteger("SessionId").

            if iSession eq integer(cSessID) then
                message substitute("Terminating ABL Session: &1 [Using &2 Termination]", iSession, cTermType).
            else
                next SESSIONBLK.

            do stop-after 10
            on error undo, throw
            on stop undo, retry:
                if retry then
                    undo, throw new Progress.Lang.AppError("Encountered stop condition", 0).

                assign cHttpUrl = substitute(oQueryURL:Get("AgentSession"), cInstance, cAblApp, cProcID, iSession) + "?terminateOpt=" + cTerminate.

                if can-do("true,yes,1", cDebug) then
                    message substitute("Calling URL: &1", cHttpUrl).

                /* Always log the OEM-API command URL with an exact time of execution. */
                LogCommand("DELETE", cHttpUrl).

                oDelResp = oClient:Execute(RequestBuilder
                                           :Delete(cHttpUrl)
                                           :AcceptContentType("application/vnd.progress+json")
                                           :ContentType("application/vnd.progress+json")
                                           :UsingBasicAuthentication(oCreds)
                                           :Request).

                if valid-object(oDelResp) and valid-object(oDelResp:Entity) and type-of(oDelResp:Entity, JsonObject) then do:
                    assign oJsonResp = cast(oDelResp:Entity, JsonObject).
                    if oJsonResp:Has("operation") and oJsonResp:Has("outcome") then
                        message substitute("~t&1: &2", oJsonResp:GetCharacter("operation"), oJsonResp:GetCharacter("outcome")).
                end.

                catch err as Progress.Lang.Error:
                    message substitute("Error Terminating ABL Session &1: &2", iSession, err:GetMessage(1)).
                    next SESSIONBLK.
                end catch.
            end. /* do stop-after */
        end. /* iLoop2 - session */
    end. /* has result */
end. /* agent sessions */

finally:
    /* Return value expected by PCT Ant task. */
    return string(0).
end finally.

