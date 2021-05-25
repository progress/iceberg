/*
    Copyright 2020-2021 Progress Software Corporation

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
 * Trim all Session Manager and Tomcat HTTP sessions for an ABL/Web App.
 * Usage: trimSessMgrSessions.p <params>
 *  Parameter Default/Allowed
 *   Scheme       [http|https]
 *   Hostname     [localhost]
 *   PAS Port     [8810]
 *   UserId       [tomcat]
 *   Password     [tomcat]
 *   ABL App      [oepas1]
 *   Web App      [ROOT]
 *   TerminateOpt [0|1]
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
using Progress.Lang.Object.
using Progress.Json.ObjectModel.ObjectModelParser.
using Progress.Json.ObjectModel.JsonObject.
using Progress.Json.ObjectModel.JsonArray.
using Progress.Json.ObjectModel.JsonDataType.

define variable oDelResp   as IHttpResponse   no-undo.
define variable oClient    as IHttpClient     no-undo.
define variable oCreds     as Credentials     no-undo.
define variable cHttpUrl   as character       no-undo.
define variable cInstance  as character       no-undo.
define variable oJsonResp  as JsonObject      no-undo.
define variable oSessions  as JsonArray       no-undo.
define variable oSession   as JsonObject      no-undo.
define variable oQueryURL  as StringStringMap no-undo.
define variable iLoop      as integer         no-undo.
define variable iSessions  as integer         no-undo.
define variable iLimit     as integer         no-undo.
define variable cScheme    as character       no-undo initial "http".
define variable cHost      as character       no-undo initial "localhost".
define variable cPort      as character       no-undo initial "8810".
define variable cUserId    as character       no-undo initial "tomcat".
define variable cPassword  as character       no-undo initial "tomcat".
define variable cAblApp    as character       no-undo initial "oepas1".
define variable cWebApp    as character       no-undo initial "ROOT".
define variable cWebAppUrl as character       no-undo.
define variable cSession   as character       no-undo.
define variable cTerminate as character       no-undo initial "0".
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
        cWebApp    = entry(7, session:parameter)
        cTerminate = entry(8, session:parameter)
        cDebug     = entry(9, session:parameter)
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
        cWebApp    = dynamic-function("getParameter" in source-procedure, "WebApp") when (dynamic-function("getParameter" in source-procedure, "WebApp") gt "") eq true
        cTerminate = dynamic-function("getParameter" in source-procedure, "TerminateOpt") when (dynamic-function("getParameter" in source-procedure, "TerminateOpt") gt "") eq true
        cDebug     = dynamic-function("getParameter" in source-procedure, "Debug") when (dynamic-function("getParameter" in source-procedure, "Debug") gt "") eq true
        .

if can-do("true,yes,1", cDebug) then do:
    log-manager:logfile-name    = "trimSessMgrSessions.log".
    log-manager:log-entry-types = "4GLTrace".
    log-manager:logging-level   = 5.
end.

assign oClient = ClientBuilder:Build():Client.
assign oCreds = new Credentials("PASOE Manager Application", cUserId, cPassword).
assign cInstance = substitute("&1://&2:&3", cScheme, cHost, cPort).
assign oQueryURL = new StringStringMap().

/* Register the URL's to the OEM-API endpoints as will be used in this utility. */
oQueryURL:Put("ClientSessions", "&1/oemanager/applications/&2/sessions").
oQueryURL:Put("TomcatSessions", "&1/manager/text/expire").

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

        if valid-object(oReq) then
            oResp = oClient:Execute(oReq).
        else
            undo, throw new Progress.Lang.AppError("Unable to create request object", 0).
    end.

    if valid-object(oResp) and oResp:StatusCode eq 200 then do:
        /* If we have an HTTP-200 status and a JSON object as the response payload, return that. */
        if valid-object(oResp:Entity) and type-of(oResp:Entity, JsonObject) then
            return cast(oResp:Entity, JsonObject).
        else if valid-object(oResp:Entity) and type-of(oResp:Entity, OpenEdge.Core.String) then do:
                /* If we got a response as a string, insert that in a new JSON object. */
                /* This would be expected when communicating with the Tomcat Web Mngr. */
                define variable oRespObj as JsonObject no-undo.
                assign oRespObj = new JsonObject().
                oRespObj:Add("result", string(cast(oResp:Entity, OpenEdge.Core.String):value)).
                return oRespObj.
        end.
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
        message substitute("~nError executing OEM-API request: &1 [URL: &2]", err:GetMessage(1) , pcHttpUrl).
        return new JsonObject().
    end catch.
    finally:
        delete object oReq no-error.
        delete object oResp no-error.
    end finally.
end function. /* MakeRequest */

/* Get client HTTP sessions from the Session Manager. */
assign cHttpUrl = substitute(oQueryURL:Get("ClientSessions"), cInstance, cAblApp).
message substitute("Looking for SessionManager Sessions of &1...", cAblApp).
message substitute("[Using &1 Termination]", if cTerminate eq "0" then "Graceful" else "Forced").
assign oJsonResp = MakeRequest(cHttpUrl).
if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:Object) then do:
    oSessions = oJsonResp:GetJsonObject("result"):GetJsonArray("OEABLSession").

    assign iSessions = oSessions:Length.
    assign iLimit = 1000 * 60 * 60 * 24.
    message substitute("~nSession Manager Sessions: &1", iSessions).

    if iSessions gt 0 then
    SESSIONBLK:
    do iLoop = 1 to iSessions
    on error undo, next SESSIONBLK
    on stop undo, next SESSIONBLK:
        oSession = oSessions:GetJsonObject(iLoop).

        if JsonPropertyHelper:HasTypedProperty(oSession, "sessionID", JsonDataType:string) then
            assign cSession = oSession:GetCharacter("sessionID").

        if oSession:Has("sessionID") then do
        on error undo, next:
            message substitute("Found Session Manager Session: &1 [Elapsed &2 sec.]", cSession,
                               trim(string(oSession:GetInt64("elapsedTimeMs") / 1000, ">>>,>>>,>>9"))).

            do stop-after 10
            on error undo, throw
            on stop undo, retry:
                if retry then
                    undo, throw new Progress.Lang.AppError("Encountered stop condition", 0).

                assign cHttpUrl = substitute(oQueryURL:Get("ClientSessions"), cInstance, cAblApp) + "?terminateOpt=" + cTerminate + "&sessionID".
                assign cHttpUrl = substitute("&1=&2", cHttpUrl, cSession). /* Specify the SessionID */

                if can-do("true,yes,1", cDebug) then
                    message substitute("Calling URL: &1", cHttpUrl).

                oDelResp = oClient:Execute(RequestBuilder
                                           :Delete(cHttpUrl)
                                           :AcceptContentType("application/vnd.progress+json")
                                           :ContentType("application/vnd.progress+json")
                                           :UsingBasicAuthentication(oCreds)
                                           :Request).

                if valid-object(oDelResp) and valid-object(oDelResp:Entity) and type-of(oDelResp:Entity, JsonObject) then do:
                    assign oJsonResp = cast(oDelResp:Entity, JsonObject).
                    if oJsonResp:Has("operation") and oJsonResp:Has("outcome") then
                        message substitute("~t&1 (&2): &3 [&4]",
                                           oJsonResp:GetCharacter("operation"),
                                           if cTerminate eq "0" then "Graceful" else "Forced",
                                           oJsonResp:GetCharacter("outcome"),
                                           cSession).
                end.

                catch err as Progress.Lang.Error:
                    message substitute("Error Closing Session &1: &2", cSession, err:GetMessage(1)).
                    next SESSIONBLK.
                end catch.
            end. /* do stop-after */
        end. /* Has sessionID */
    end. /* iLoop - sessions */
end. /* client sessions */

/* Expire all sessions via the Tomcat Web Application Manager. */
assign cHttpUrl = substitute(oQueryURL:Get("TomcatSessions"), cInstance, cAblApp) + "?idle=0&path".
if cWebApp eq "ROOT" then
    assign cWebAppUrl = "/".
else
    assign cWebAppUrl = substitute("/&1", cWebApp).

assign cHttpUrl = substitute("&1=&2", cHttpUrl, cWebAppUrl). /* Specify the WebApp as a URL */
message substitute("~nExpiring sessions via Tomcat for &1 ...", cWebAppUrl).
assign oJsonResp = MakeRequest(cHttpUrl).

if valid-object(oJsonResp) and oJsonResp:Has("result") then
do stop-after 30
on error undo, leave
on stop undo, leave:
    define variable cTemp as character no-undo.
    assign cTemp = string(oJsonResp:GetJsonText("result")).
    assign cTemp = replace(cTemp, "~\r~\n", "~n").
    assign cTemp = replace(cTemp, "~\n", "~n").
    assign cTemp = replace(cTemp, "~\~/", "~/").
    message substitute("Tomcat Manager Response:~n&1", cTemp).
end. /* oJsonResp - Tomcat */

finally:
    /* Return value expected by PCT Ant task. */
    return string(0).
end finally.

