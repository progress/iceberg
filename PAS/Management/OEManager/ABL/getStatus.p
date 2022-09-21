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
 * Obtains status about all running MSAgents from PASOE instance and ABLApp.
 * Usage: getStatus.p <params>
 *  Parameter Default/Allowed
 *   Scheme   [http|https]
 *   Hostname [localhost]
 *   PAS Port [8810]
 *   UserId   [tomcat]
 *   Password [tomcat]
 *   ABL App  [oepas1]
 *   Debug    [false|true]
 *
 * Reference: https://knowledgebase.progress.com/articles/Article/P89737
 */

&GLOBAL-DEFINE MIN_VERSION_12_2 (integer(entry(1, proversion(1), ".")) eq 12 and integer(entry(2, proversion(1), ".")) ge 2)

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

define variable cOutFile  as character       no-undo.
define variable cOutDate  as character       no-undo.
define variable oClient   as IHttpClient     no-undo.
define variable oCreds    as Credentials     no-undo.
define variable cHttpUrl  as character       no-undo.
define variable cInstance as character       no-undo.
define variable oJsonResp as JsonObject      no-undo.
define variable oResult   as JsonObject      no-undo.
define variable oTemp     as JsonObject      no-undo.
define variable oMetrics  as JsonObject      no-undo.
define variable oClSess   as JsonArray       no-undo.
define variable oQueryURL as StringStringMap no-undo.
define variable oAgentMap as StringStringMap no-undo.
define variable iLoop     as integer         no-undo.
define variable iLoop2    as integer         no-undo.
define variable iLoop3    as integer         no-undo.
define variable iCollect  as integer         no-undo.
define variable iBaseMem  as int64           no-undo.
define variable dInstTime as datetime        no-undo.
define variable cBound    as character       no-undo.
define variable cScheme   as character       no-undo initial "http".
define variable cHost     as character       no-undo initial "localhost".
define variable cPort     as character       no-undo initial "8810".
define variable cUserId   as character       no-undo initial "tomcat".
define variable cPassword as character       no-undo initial "tomcat".
define variable cAblApp   as character       no-undo initial "oepas1".
define variable cDebug    as character       no-undo initial "false".

define temp-table ttAgent no-undo
    field agentID     as character
    field agentPID    as character
    field agentState  as character
    field startTime   as datetime-tz
    field runningTime as int64
    field maxSessions as int64
    field ablSessions as int64
    field availSess   as int64
    field openConns   as int64
    field memoryBytes as int64
    .

define temp-table ttAgentSession no-undo
    field agentID      as character
    field agentPID     as character
    field sessionID    as integer
    field sessionState as character
    field startTime    as datetime-tz
    field runningTime  as int64
    field memoryBytes  as int64
    field boundSession as character
    field boundReqID   as character
    .

define dataset dsAgentSession for ttAgent, ttAgentSession
    data-relation AgentID for ttAgent, ttAgentSession relation-fields(agentID,agentID) nested.

/* Check for passed-in arguments/parameters. */
if num-entries(session:parameter) ge 7 then
    assign
        cScheme   = entry(1, session:parameter)
        cHost     = entry(2, session:parameter)
        cPort     = entry(3, session:parameter)
        cUserId   = entry(4, session:parameter)
        cPassword = entry(5, session:parameter)
        cAblApp   = entry(6, session:parameter)
        cDebug    = entry(7, session:parameter)
        .
else if session:parameter ne "" then /* original method */
    assign cPort = session:parameter.
else
    assign
        cScheme   = dynamic-function("getParameter" in source-procedure, "Scheme") when (dynamic-function("getParameter" in source-procedure, "Scheme") gt "") eq true
        cHost     = dynamic-function("getParameter" in source-procedure, "Host") when (dynamic-function("getParameter" in source-procedure, "Host") gt "") eq true
        cPort     = dynamic-function("getParameter" in source-procedure, "Port") when (dynamic-function("getParameter" in source-procedure, "Port") gt "") eq true
        cUserId   = dynamic-function("getParameter" in source-procedure, "UserID") when (dynamic-function("getParameter" in source-procedure, "UserID") gt "") eq true
        cPassword = dynamic-function("getParameter" in source-procedure, "PassWD") when (dynamic-function("getParameter" in source-procedure, "PassWD") gt "") eq true
        cAblApp   = dynamic-function("getParameter" in source-procedure, "ABLApp") when (dynamic-function("getParameter" in source-procedure, "ABLApp") gt "") eq true
        iBaseMem  = int64(dynamic-function("getParameter" in source-procedure, "BaseMem")) when (dynamic-function("getParameter" in source-procedure, "BaseMem") gt "") eq true
        cDebug    = dynamic-function("getParameter" in source-procedure, "Debug") when (dynamic-function("getParameter" in source-procedure, "Debug") gt "") eq true
        .

if can-do("enable,true,yes,1", cDebug) then do:
    log-manager:logfile-name    = "getStatus.log".
    log-manager:log-entry-types = "4GLTrace".
    log-manager:logging-level   = 5.
end.

assign oClient = ClientBuilder:Build():Client.
assign oCreds = new Credentials("PASOE Manager Application", cUserId, cPassword).
assign cInstance = substitute("&1://&2:&3", cScheme, cHost, cPort).
assign cOutDate = replace(iso-date(now), ":", "_").
assign
    oQueryURL = new StringStringMap()
    oAgentMap = new StringStringMap()
    .

/* Register the URL's to the OEM-API endpoints as will be used in this utility. */
oQueryURL:Put("Applications", "&1/oemanager/applications").
oQueryURL:Put("SessionManagerProperties", "&1/oemanager/applications/&2/properties").
oQueryURL:Put("AgentManagerProperties", "&1/oemanager/applications/&2/agents/properties").
oQueryURL:Put("Agents", "&1/oemanager/applications/&2/agents").
oQueryURL:Put("DynamicSessionLimit", "&1/oemanager/applications/&2/agents/&3/dynamicSessionLimit").
oQueryURL:Put("AgentThreads", "&1/oemanager/applications/&2/agents/&3/threads").
oQueryURL:Put("AgentMetrics", "&1/oemanager/applications/&2/agents/&3/metrics").
oQueryURL:Put("AgentSessions", "&1/oemanager/applications/&2/agents/&3/sessions").
oQueryURL:Put("SessionMetrics", "&1/oemanager/applications/&2/metrics").
oQueryURL:Put("ClientSessions", "&1/oemanager/applications/&2/sessions").

function MakeRequest returns JsonObject ( input pcHttpUrl as character ) forward.
function FormatDecimal returns character ( input pcValue as character ) forward.
function FormatLongNumber returns character ( input pcValue as character, input plTrim as logical ) forward.
function FormatMemory returns character ( input piValue as int64, input plTrim as logical ) forward.
function FormatMsTime returns character ( input piValue as int64 ) forward.
function FormatCharAsNumber returns character ( input pcValue as character ) forward.
function FormatIntAsNumber returns character ( input piValue as integer ) forward.

assign cOutFile = substitute("status_&1_&2.txt", cAblApp, cOutDate).
message substitute("Starting output to file: &1 ...", cOutFile).
output to value(cOutFile).

/* Start with some basic header information for this report. */
put unformatted substitute("Utility Runtime: &1", proversion(1)) skip. /* Reports the OE runtime version used by this utility.     */
put unformatted substitute("Report Executed: &1", iso-date(now)) skip. /* Produce a timestamp relative to where utility was run.   */
put unformatted substitute(" PASOE Instance: &1", cInstance) skip. /* Reports the combined scheme, hostname, and port of instance. */

/* Gather the necessary metrics. */
run GetApplications.
run GetProperties.
run GetAgents.
run GetSessions.

finally:
    output close.

    message "~n". /* Denotes we completed the output, should just be an empty line on screen. */

    define variable lcText as longchar no-undo.
    define variable iLine  as integer  no-undo.
    define variable iLines as integer  no-undo.
    copy-lob from file cOutFile to lcText no-convert no-error.
    assign iLines = num-entries(lcText, "~n").
    if iLines ge 1 then
    do iLine = 1 to iLines:
        message string(entry(iLine, lcText, "~n")).
    end.

    /* Return value expected by PCT Ant task. */
    return string(0).
end finally.

/* PROCEDURES / FUNCTIONS */

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
        put unformatted substitute("~nError executing OEM-API request: &1 [URL: &2]", err:GetMessage(1), pcHttpUrl) skip.
        return new JsonObject().
    end catch.
    finally:
        delete object oReq no-error.
        delete object oResp no-error.
    end finally.
end function. /* MakeRequest */

function FormatDecimal returns character ( input pcValue as character ):
    return trim(string(int64(pcValue) / 60000, ">>9.9")).
end function. /* FormatDecimal */

function FormatMemory returns character ( input piValue as int64, input plTrim as logical ):
    /* Should show up to 999,999,999 GB which is more than expected for any process. */
    return FormatLongNumber(string(round(piValue / 1024, 0)), plTrim).
end function. /* FormatMemory */

function FormatMsTime returns character ( input piValue as int64):
    define variable iMS  as integer no-undo.
    define variable iSec as integer no-undo.
    define variable iMin as integer no-undo.
    define variable iHr  as integer no-undo.

    assign iMS = piValue modulo 1000.
    assign piValue = (piValue - iMS) / 1000.
    assign iSec = piValue modulo 60.
    assign piValue = (piValue - iSec) / 60.
    assign iMin = piValue modulo 60.
    assign iHr = (piValue - iMin) / 60.

    return trim(string(iHr, ">99")) + ":" + string(iMin, "99") + ":" + string(iSec, "99") + "." + string(iMS, "999").
end function. /* FormatMsTime */

function FormatLongNumber returns character ( input pcValue as character, input plTrim as logical ):
    if plTrim then
        return trim(string(int64(pcValue), ">>>,>>>,>>9")).
    else
        return string(int64(pcValue), ">>>,>>>,>>9").
end function. /* FormatCharAsNumber */

function FormatCharAsNumber returns character ( input pcValue as character ):
    return string(integer(pcValue), ">>9").
end function. /* FormatCharAsNumber */

function FormatIntAsNumber returns character ( input piValue as integer ):
    return string(piValue, ">,>>9").
end function. /* FormatIntAsNumber */

/* Get available applications and confirm the given name as valid (and for proper case). */
procedure GetApplications:
    define variable oWebApps  as JsonArray no-undo.
    define variable oWebTrans as JsonArray no-undo.

    assign cHttpUrl = substitute(oQueryURL:Get("Applications"), cInstance).
    assign oJsonResp = MakeRequest(cHttpUrl).
    if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then do:
        oResult = oJsonResp:GetJsonObject("result").

        if JsonPropertyHelper:HasTypedProperty(oResult, "Application", JsonDataType:Array) then
        do iLoop = 1 to oResult:GetJsonArray("Application"):Length:
            oTemp = oResult:GetJsonArray("Application"):GetJsonObject(iLoop).
            if oTemp:Has("name") and oTemp:GetCharacter("name") eq cAblApp then do:
                /* This should be the proper and case-sensitive name of the ABLApp, so let's make sure we use that going forward. */
                assign cAblApp = oTemp:GetCharacter("name").

                /* Reports the full ABL Application name and OpenEdge version as reported by the monitored PAS instance itself. */
                put unformatted substitute("~nABL Application Information [&1 - &2]", cAblApp, oTemp:GetCharacter("version")) skip.

                if JsonPropertyHelper:HasTypedProperty(oTemp, "webapps", JsonDataType:Array) then do:
                    assign oWebApps = oTemp:GetJsonArray("webapps").
                    do iLoop2 = 1 to oWebApps:Length:
                        if oWebApps:GetJsonObject(iLoop2):Has("name") then
                            put unformatted substitute("~tWebApp: &1",  oWebApps:GetJsonObject(iLoop2):GetCharacter("name")) skip.

                        assign oWebTrans = oWebApps:GetJsonObject(iLoop2):GetJsonArray("transports").
                        do iLoop3 = 1 to oWebTrans:Length:
                            put unformatted substitute("~t&1&2: &3",
                                                       fill(" ", 6 - length(oWebTrans:GetJsonObject(iLoop3):GetCharacter("name"), "raw")),
                                                       oWebTrans:GetJsonObject(iLoop3):GetCharacter("name"),
                                                       oWebTrans:GetJsonObject(iLoop3):GetCharacter("state")) skip.
                        end. /* transport */
                    end. /* webapp */
                end. /* has webapps */
            end. /* matching ABLApp */
        end. /* Application */
    end. /* response - Applications */
end procedure.

/* Get the configured max for ABLSessions/Connections per MSAgent, along with min/max/initial MSAgents. */
procedure GetProperties:
    assign cHttpUrl = substitute(oQueryURL:Get("SessionManagerProperties"), cInstance, cAblApp).
    assign oJsonResp = MakeRequest(cHttpUrl).
    if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then
    do on error undo, leave:
        oResult = oJsonResp:GetJsonObject("result").

        put unformatted "~nManager Properties" skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "maxAgents", JsonDataType:string) then
            put unformatted substitute("~t        Maximum Agents:~t~t&1", FormatCharAsNumber(oResult:GetCharacter("maxAgents"))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "minAgents", JsonDataType:string) then
            put unformatted substitute("~t        Minimum Agents:~t~t&1", FormatCharAsNumber(oResult:GetCharacter("minAgents"))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "numInitialAgents", JsonDataType:string) then
            put unformatted substitute("~t        Initial Agents:~t~t&1", FormatCharAsNumber(oResult:GetCharacter("numInitialAgents"))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "maxConnectionsPerAgent", JsonDataType:string) then
            put unformatted substitute("~tMax. Connections/Agent:~t~t&1", FormatCharAsNumber(oResult:GetCharacter("maxConnectionsPerAgent"))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "maxABLSessionsPerAgent", JsonDataType:string) then
            put unformatted substitute("~tMax. ABLSessions/Agent:~t~t&1", FormatCharAsNumber(oResult:GetCharacter("maxABLSessionsPerAgent"))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "idleConnectionTimeout", JsonDataType:string) then
            put unformatted substitute("~t    Idle Conn. Timeout: &1 ms (&2)",
                                       FormatLongNumber(oResult:GetCharacter("idleConnectionTimeout"), false),
                                       FormatMsTime(integer(oResult:GetCharacter("idleConnectionTimeout")))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "idleSessionTimeout", JsonDataType:string) then
            put unformatted substitute("~t  Idle Session Timeout: &1 ms (&2)",
                                       FormatLongNumber(oResult:GetCharacter("idleSessionTimeout"), false),
                                       FormatMsTime(integer(oResult:GetCharacter("idleSessionTimeout")))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "idleAgentTimeout", JsonDataType:string) then
            put unformatted substitute("~t    Idle Agent Timeout: &1 ms (&2)",
                                       FormatLongNumber(oResult:GetCharacter("idleAgentTimeout"), false),
                                       FormatMsTime(integer(oResult:GetCharacter("idleAgentTimeout")))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "idleResourceTimeout", JsonDataType:string) then
            put unformatted substitute("~t Idle Resource Timeout: &1 ms (&2)",
                                       FormatLongNumber(oResult:GetCharacter("idleResourceTimeout"), false),
                                       FormatMsTime(integer(oResult:GetCharacter("idleResourceTimeout")))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "connectionWaitTimeout", JsonDataType:string) then
            put unformatted substitute("~t    Conn. Wait Timeout: &1 ms (&2)",
                                       FormatLongNumber(oResult:GetCharacter("connectionWaitTimeout"), false),
                                       FormatMsTime(integer(oResult:GetCharacter("connectionWaitTimeout")))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "requestWaitTimeout", JsonDataType:string) then
            put unformatted substitute("~t  Request Wait Timeout: &1 ms (&2)",
                                       FormatLongNumber(oResult:GetCharacter("requestWaitTimeout"), false),
                                       FormatMsTime(integer(oResult:GetCharacter("requestWaitTimeout")))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "collectMetrics", JsonDataType:string) then
            assign iCollect = integer(oResult:GetCharacter("collectMetrics")). /* Remember for later. */
    end. /* response - SessionManagerProperties */

    /* Get the configured initial number of sessions along with the min available sessions. */
    assign cHttpUrl = substitute(oQueryURL:Get("AgentManagerProperties"), cInstance, cAblApp).
    assign oJsonResp = MakeRequest(cHttpUrl).
    if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then
    do on error undo, leave:
        oResult = oJsonResp:GetJsonObject("result").

        if JsonPropertyHelper:HasTypedProperty(oResult, "numInitialSessions", JsonDataType:string) then
            put unformatted substitute("~tInitial Sessions/Agent:~t~t&1", FormatCharAsNumber(oResult:GetCharacter("numInitialSessions"))) skip.

        if JsonPropertyHelper:HasTypedProperty(oResult, "minAvailableABLSessions", JsonDataType:string) then
            put unformatted substitute("~tMin. Avail. Sess/Agent:~t~t&1", FormatCharAsNumber(oResult:GetCharacter("minAvailableABLSessions"))) skip.
    end. /* response - AgentManagerProperties */
end procedure.

/* Initial URL to obtain a list of all agents for an ABL Application. */
procedure GetAgents:
    define variable iTotAgent as integer    no-undo.
    define variable iTotSess  as integer    no-undo.
    define variable iTotThrd  as integer    no-undo.
    define variable iBusySess as integer    no-undo.
    define variable iUsedSess as integer    no-undo.
    define variable dStart    as datetime   no-undo.
    define variable oAgents   as JsonArray  no-undo.
    define variable oAgent    as JsonObject no-undo.
    define variable oSessions as JsonArray  no-undo.
    define variable oSessInfo as JsonObject no-undo.
    define variable oThreads  as JsonArray  no-undo.
    define variable iMinMem   as int64      no-undo.
    define variable iTotalMem as int64      no-undo.

    empty temp-table ttAgent.
    empty temp-table ttAgentSession.

    /* Get metrics about the session manager which comes from the collectMetrics flag. */
    assign cHttpUrl = substitute(oQueryURL:Get("SessionMetrics"), cInstance, cAblApp).
    assign oJsonResp = MakeRequest(cHttpUrl).
    if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then
    do on error undo, leave:
        oMetrics = oJsonResp:GetJsonObject("result").

        /* Get the server access time (should be a timestamp from the server's timezone). */
        define variable dTemp as datetime-tz no-undo.
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "accessTime", JsonDataType:String) then do:
            assign dTemp = oMetrics:GetDateTimeTZ("accessTime").
            assign dInstTime = datetime(date(dTemp), mtime(dTemp)).
        end.
        else
            assign dInstTime = now.
    end. /* response - SessionMetrics */

    /* Capture all available agent info to a temp-table before we proceed. */
    assign cHttpUrl = substitute(oQueryURL:Get("Agents"), cInstance, cAblApp).
    assign oJsonResp = MakeRequest(cHttpUrl).
    if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then do:
        if JsonPropertyHelper:HasTypedProperty(oJsonResp:GetJsonObject("result"), "agents", JsonDataType:Array) then
            oAgents = oJsonResp:GetJsonObject("result"):GetJsonArray("agents").
        else
            oAgents = new JsonArray().

        assign iTotAgent = oAgents:Length.

        if oAgents:Length eq 0 then
            put unformatted "~nNo MSAgents running" skip.
        else
        AGENTBLK:
        do iLoop = 1 to iTotAgent
        on error undo, next AGENTBLK:
            oAgent = oAgents:GetJsonObject(iLoop).

            create ttAgent.
            assign
                ttAgent.agentID    = oAgent:GetCharacter("agentId")
                ttAgent.agentPID   = oAgent:GetCharacter("pid")
                ttAgent.agentState = oAgent:GetCharacter("state")
                .

            /* Provides a simple means of lookup later to relate agentID to PID. */
            oAgentMap:Put(ttAgent.agentID, ttAgent.agentPID).

            release ttAgent no-error.
        end. /* iLoop - Agents */
    end. /* response - Agents */

    /* https://docs.progress.com/bundle/pas-for-openedge-management/page/About-session-and-request-states.html */
    assign cHttpUrl = substitute(oQueryURL:Get("ClientSessions"), cInstance, cAblApp).
    assign oJsonResp = MakeRequest(cHttpUrl).
    if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then do:
        if JsonPropertyHelper:HasTypedProperty(oJsonResp:GetJsonObject("result"), "OEABLSession", JsonDataType:Array) then do:
            /* This data will be related to the MSAgent-sessions to denote which ones are bound. */
            oClSess = oJsonResp:GetJsonObject("result"):GetJsonArray("OEABLSession").
        end. /* Has OEABLSession */
    end. /* Client Sessions */

    for each ttAgent exclusive-lock:
        assign
            ttAgent.maxSessions = ?
            ttAgent.ablSessions = ?
            ttAgent.availSess   = ?
            ttAgent.openConns   = ?
            ttAgent.memoryBytes = ?
            .

        /* We should only obtain additional status and metrics if the MSAgent is available. */
        if ttAgent.agentState eq "available" then do:
        &IF {&MIN_VERSION_12_2} &THEN
            /* Get the dynamic value for the available sessions of this MSAgent (available only in 12.2.0 and later). */
            assign cHttpUrl = substitute(oQueryURL:Get("DynamicSessionLimit"), cInstance, cAblApp, ttAgent.agentPID).
            assign oJsonResp = MakeRequest(cHttpUrl).
            if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then do:
                oResult = oJsonResp:GetJsonObject("result").
                if JsonPropertyHelper:HasTypedProperty(oResult, "AgentSessionInfo", JsonDataType:Array) then do:
                    oSessions = oResult:GetJsonArray("AgentSessionInfo").
                    if oSessions:Length eq 1 and JsonPropertyHelper:HasTypedProperty(oSessions:GetJsonObject(1), "ABLOutput", JsonDataType:object) then do:
                        oSessInfo = oSessions:GetJsonObject(1):GetJsonObject("ABLOutput").

                        /* Should be the current calculated maximum # of ABL Sessions which can be started/utilized. */
                        if JsonPropertyHelper:HasTypedProperty(oSessInfo, "dynmaxablsessions", JsonDataType:Number) then
                            assign ttAgent.maxSessions = oSessInfo:GetInteger("dynmaxablsessions").

                        /* This should represent the total number of ABL Sessions started, not to exceed the Dynamic Max. */
                        if JsonPropertyHelper:HasTypedProperty(oSessInfo, "numABLSessions", JsonDataType:Number) then
                            assign ttAgent.ablSessions = oSessInfo:GetInteger("numABLSessions").

                        /* This should be the number of ABL Sessions available to execute ABL code for this MSAgent. */
                        if JsonPropertyHelper:HasTypedProperty(oSessInfo, "numAvailableSessions", JsonDataType:Number) then
                            assign ttAgent.availSess = oSessInfo:GetInteger("numAvailableSessions").
                    end.
                end.
            end. /* agent manager properties */
        &ENDIF

            /* Get threads for this particular MSAgent. */
            assign dStart = ?. /* Clear before use. */
            assign cHttpUrl = substitute(oQueryURL:Get("AgentThreads"), cInstance, cAblApp, ttAgent.agentPID).
            assign oJsonResp = MakeRequest(cHttpUrl).
            if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then
            do on error undo, leave:
                if JsonPropertyHelper:HasTypedProperty(oJsonResp:GetJsonObject("result"), "AgentThread", JsonDataType:Array) and
                   oJsonResp:GetJsonObject("result"):GetJsonArray("AgentThread"):Length ge 1 then do:
                    oThreads = oJsonResp:GetJsonObject("result"):GetJsonArray("AgentThread").
                    assign
                        iTotThrd          = oThreads:Length
                        ttAgent.startTime = dInstTime
                        .

                    /* Loop through the threads to get the earliest start time; should be the agent's epoch. */
                    do iLoop2 = 1 to iTotThrd:
                        oTemp = oThreads:GetJsonObject(iLoop2).
                        if JsonPropertyHelper:HasTypedProperty(oTemp, "StartTime", JsonDataType:String) then
                            assign ttAgent.startTime = min(ttAgent.startTime, oTemp:GetDateTimeTZ("StartTime")).
                    end. /* iLoop2 - oThreads */

                    /* Attempt to calculate the time this session has been running, though we don't have a current timestamp directly from the server. */
                    assign dStart = datetime(date(ttAgent.startTime), mtime(ttAgent.startTime)) when ttAgent.startTime ne ?.
                    assign ttAgent.runningTime = interval(dInstTime, dStart, "milliseconds") when (dInstTime ne ? and dStart ne ? and dInstTime ge dStart).
                end.
            end. /* response */

            /* Get metrics about this particular MSAgent. */
            assign cHttpUrl = substitute(oQueryURL:Get("AgentMetrics"), cInstance, cAblApp, ttAgent.agentPID).
            assign oJsonResp = MakeRequest(cHttpUrl).
            if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then
            do on error undo, leave:
                if JsonPropertyHelper:HasTypedProperty(oJsonResp:GetJsonObject("result"), "AgentStatHist", JsonDataType:Array) and
                   oJsonResp:GetJsonObject("result"):GetJsonArray("AgentStatHist"):Length ge 1 then do:
                    oTemp = oJsonResp:GetJsonObject("result"):GetJsonArray("AgentStatHist"):GetJsonObject(1).

                    if JsonPropertyHelper:HasTypedProperty(oTemp, "OpenConnections", JsonDataType:Number) then
                        assign ttAgent.openConns = oTemp:GetInteger("OpenConnections").

                    if JsonPropertyHelper:HasTypedProperty(oTemp, "OverheadMemory", JsonDataType:Number) then
                        assign ttAgent.memoryBytes = oTemp:GetInt64("OverheadMemory").
                end.
            end. /* response */

            /* Get sessions and count non-idle states. */
            assign dStart = ?. /* Clear before use. */
            assign cHttpUrl = substitute(oQueryURL:Get("AgentSessions"), cInstance, cAblApp, ttAgent.agentPID).
            assign oJsonResp = MakeRequest(cHttpUrl).
            if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then
            do on error undo, leave:
                if JsonPropertyHelper:HasTypedProperty(oJsonResp:GetJsonObject("result"), "AgentSession", JsonDataType:Array) then
                    oSessions = oJsonResp:GetJsonObject("result"):GetJsonArray("AgentSession").
                else
                    oSessions = new JsonArray().

                assign iTotSess  = oSessions:Length.
                do iLoop2 = 1 to iTotSess:
                    create ttAgentSession.
                    assign
                        ttAgentSession.agentID      = ttAgent.agentID
                        ttAgentSession.agentPID     = ttAgent.agentPID
                        ttAgentSession.sessionID    = oSessions:GetJsonObject(iLoop2):GetInteger("SessionId")
                        ttAgentSession.sessionState = oSessions:GetJsonObject(iLoop2):GetCharacter("SessionState")
                        ttAgentSession.startTime    = oSessions:GetJsonObject(iLoop2):GetDatetimeTZ("StartTime")
                        ttAgentSession.memoryBytes  = oSessions:GetJsonObject(iLoop2):GetInt64("SessionMemory")
                        .

                    /* Attempt to determine the most minimal memory value for all sessions of all agents available. */
                    if iMinMem eq 0 then
                        assign iMinMem = ttAgentSession.memoryBytes.
                    else
                        assign iMinMem = min(iMinMem, ttAgentSession.memoryBytes).

                    /* Attempt to calculate the time this session has been running, though we don't have a current timestamp directly from the server. */
                    assign dStart = datetime(date(ttAgentSession.startTime), mtime(ttAgentSession.startTime)) when ttAgentSession.startTime ne ?.
                    assign ttAgentSession.runningTime = interval(dInstTime, dStart, "milliseconds") when (dInstTime ne ? and dStart ne ? and dInstTime ge dStart).

                    define variable iSessions as integer no-undo.

                    assign iSessions = 0.
                    if valid-object(oClSess) then
                        assign iSessions = oClSess:Length.

                    if iSessions gt 0 then
                    do iLoop = 1 to iSessions
                    on error undo, leave:
                        assign oTemp = oClSess:GetJsonObject(iLoop).

                        if oTemp:Has("bound") and oTemp:GetLogical("bound") and
                           oTemp:GetCharacter("agentID") eq ttAgent.agentID and
                           integer(oTemp:GetCharacter("ablSessionID")) eq oSessions:GetJsonObject(iLoop2):GetInteger("SessionId") then
                            assign
                                ttAgentSession.boundSession = oTemp:GetCharacter("sessionID")
                                ttAgentSession.boundReqID   = oTemp:GetCharacter("requestID")
                                .
                    end. /* iLoop - iSessions */

                    release ttAgentSession no-error.
                end. /* iLoop2 - oSessions */
            end. /* response - AgentSessions */
        end. /* agent state = available */
    end. /* for each ttAgent */

    for each ttAgent no-lock:
        /* Output all information for each MSAgent after displaying a basic header. */
        put unformatted substitute("~n> Agent PID &1: &2", ttAgent.agentPID, ttAgent.agentState) skip.

        if ttAgent.startTime ne ? then
            put unformatted substitute("~tEst. Agent Lifetime: &1", FormatMsTime(ttAgent.runningTime)) skip.

        if ttAgent.maxSessions ne ? then
            put unformatted substitute("~tDynMax ABL Sessions:~t    &1", FormatIntAsNumber(ttAgent.maxSessions)) skip.

        if ttAgent.ablSessions ne ? then
            put unformatted substitute("~t Total ABL Sessions:~t    &1", FormatIntAsNumber(ttAgent.ablSessions)) skip.

        if ttAgent.availSess ne ? then
            put unformatted substitute("~t Avail ABL Sessions:~t    &1", FormatIntAsNumber(ttAgent.availSess)) skip.

        if ttAgent.openConns ne ? then
            put unformatted substitute("~t   Open Connections:~t    &1", FormatIntAsNumber(ttAgent.openConns)) skip.

        if ttAgent.memoryBytes ne ? then
            put unformatted substitute("~t    Overhead Memory: &1 KB", FormatMemory(ttAgent.memoryBytes, true)) skip.

        put unformatted "~n~tSESSION ID~tSTATE~t~tSTARTED~t~t~t~tLIFETIME~tSESS. MEMORY~tBOUND/ACTIVE CLIENT SESSION" skip.

        assign iBaseMem = max(iBaseMem, iMinMem) + 1024. /* Use the higher of the BaseMem (Ant parameter) or discovered minimum memory, plus 1K. */

        assign
            iBusySess = 0
            iUsedSess = 0
            iTotSess  = 0
            iTotalMem = if ttAgent.memoryBytes ne ? then ttAgent.memoryBytes else 0
            .

        for each ttAgentSession no-lock
           where ttAgentSession.agentID eq ttAgent.agentID:
            put unformatted substitute("~t~t&1~t&2~t&3~t&4 &5 KB~t&6 &7",
                                        string(ttAgentSession.sessionID, ">>>9"),
                                        string(ttAgentSession.sessionState, "x(10)"),
                                        ttAgentSession.startTime,
                                        FormatMsTime(ttAgentSession.runningTime),
                                        FormatMemory(ttAgentSession.memoryBytes, false),
                                        (if ttAgentSession.boundSession gt "" then ttAgentSession.boundSession else ""),
                                        (if ttAgentSession.boundReqID gt "" then "[" + ttAgentSession.boundReqID + "]" else "-")) skip.

            assign
                iTotSess  = iTotSess + 1
                iTotalMem = iTotalMem + ttAgentSession.memoryBytes
                .

            /* Busy sessions are those actively serving requests (non-IDLE). */
            if ttAgentSession.sessionState ne "IDLE" then
                assign iBusySess = iBusySess + 1.

            /**
             * Since iBaseMem should be the LOWEST value across all agents, it should theoretically be the baseline value
             * for any unused (fresh) sessions. Therefore, counting any sessions higher than this should indicate that the
             * session was utilized for servicing requests.
             */
            if ttAgentSession.memoryBytes gt iBaseMem then
                assign iUsedSess = iUsedSess + 1.
        end. /* for each ttAgentSession */

        /* Output summary information about agent-sessions, such as how many are busy out of the total count. */
        put unformatted substitute("~t  Active Agent-Sessions: &1 of &2 (&3% Busy)",
                                   iBusySess, iTotSess, if iTotSess gt 0 then round((iBusySess / iTotSess) * 100, 1) else 0) skip.

        /* Establish an educated guess on how many sessions have been utilized via a baseline memory value. */
        put unformatted substitute("~tUtilized Agent-Sessions: &1 of &2 (>&3 KB)", iUsedSess, iTotSess, FormatMemory(iBaseMem, true)) skip.

        /* For 12.2+ this should include agent overhead memory + all sessions, otherwise just all sessions. */
        put unformatted substitute("~t   Approx. Agent Memory: &1 KB", FormatMemory(iTotalMem, true)) skip.
    end. /* for each ttAgent */
end procedure.

/* Consults the SessionManager for a count of Client HTTP Sessions, along with stats on the Client Connections and Agent Connections. */
procedure GetSessions:
    define variable iSessions as integer    no-undo.
    define variable lIsBound  as logical    no-undo.
    define variable oConnInfo as JsonObject no-undo.

    /* https://docs.progress.com/bundle/pas-for-openedge-management/page/Collect-runtime-metrics.html */
    put unformatted "~nSession Manager Metrics ".
    case iCollect:
        when 0 then put unformatted "(Not Enabled)" skip.
        when 1 then put unformatted "(Count-Based)" skip.
        when 2 then put unformatted "(Time-Based)" skip.
        when 3 then put unformatted "(Count+Time)" skip.
    end case.

    if valid-object(oMetrics) then do:
        /* Total number of requests to the session. */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "requests", JsonDataType:Number) then
            put unformatted substitute("~t       # Requests to Session:  &1",
                                        FormatLongNumber(string(oMetrics:GetInteger("requests")), false)) skip.

        /* Number of times a response was read by the session from the MSAgent. */
        /* Number of errors that occurred while reading a response from the MSAgent. */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "reads", JsonDataType:Number) and
           JsonPropertyHelper:HasTypedProperty(oMetrics, "readErrors", JsonDataType:Number) then
            put unformatted substitute("~t      # Agent Responses Read:  &1 (&2 Errors)",
                                        FormatLongNumber(string(oMetrics:GetInteger("reads")), false),
                                        trim(string(oMetrics:GetInteger("readErrors"), ">>>,>>>,>>9"))) skip.

        /* Minimum, maximum, average times to read a response from the MSAgent. */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "minAgentReadTime", JsonDataType:Number) and
           JsonPropertyHelper:HasTypedProperty(oMetrics, "maxAgentReadTime", JsonDataType:Number) and
           JsonPropertyHelper:HasTypedProperty(oMetrics, "avgAgentReadTime", JsonDataType:Number) then
            put unformatted substitute("~tAgent Read Time (Mn, Mx, Av): &1 / &2 / &3",
                                        FormatMsTime(oMetrics:GetInteger("minAgentReadTime")),
                                        FormatMsTime(oMetrics:GetInteger("maxAgentReadTime")),
                                        FormatMsTime(oMetrics:GetInteger("avgAgentReadTime"))) skip.

        /* Number of times requests were written by the session on the MSAgent. */
        /* Number of errors that occurred during writing a request to the MSAgent. */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "writes", JsonDataType:Number) and
           JsonPropertyHelper:HasTypedProperty(oMetrics, "writeErrors", JsonDataType:Number) then
            put unformatted substitute("~t    # Agent Requests Written:  &1 (&2 Errors)",
                                        FormatLongNumber(string(oMetrics:GetInteger("writes")), false),
                                        trim(string(oMetrics:GetInteger("writeErrors"), ">>>,>>>,>>9"))) skip.

        /* Number of clients connected at a particular time. */
        /* Maximum number of concurrent clients. */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "concurrentConnectedClients", JsonDataType:Number) and
           JsonPropertyHelper:HasTypedProperty(oMetrics, "maxConcurrentClients", JsonDataType:Number) then
            put unformatted substitute("~tConcurrent Connected Clients:  &1 (Max: &2)",
                                        FormatLongNumber(string(oMetrics:GetInteger("concurrentConnectedClients")), false),
                                        trim(string(oMetrics:GetInteger("maxConcurrentClients"), ">>>,>>>,>>9"))) skip.

        /* Total time that reserved ABL sessions had to wait before executing. */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "totReserveABLSessionWaitTime", JsonDataType:Number) then
            put unformatted substitute("~tTot. Reserve ABLSession Wait: &1", FormatMsTime(oMetrics:GetInteger("totReserveABLSessionWaitTime"))) skip.

        /* Number of waits that occurred while reserving a local ABL session. */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "numReserveABLSessionWaits", JsonDataType:Number) then
            put unformatted substitute("~t  # Reserve ABLSession Waits:  &1", FormatLongNumber(string(oMetrics:GetInteger("numReserveABLSessionWaits")), false)) skip.

        /* Average time that a reserved ABL session had to wait before executing. */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "avgReserveABLSessionWaitTime", JsonDataType:Number) then
            put unformatted substitute("~tAvg. Reserve ABLSession Wait: &1", FormatMsTime(oMetrics:GetInteger("avgReserveABLSessionWaitTime"))) skip.

        /* Maximum time that a reserved ABL session had to wait before executing. */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "maxReserveABLSessionWaitTime", JsonDataType:Number) then
            put unformatted substitute("~tMax. Reserve ABLSession Wait: &1", FormatMsTime(oMetrics:GetInteger("maxReserveABLSessionWaitTime"))) skip.

        /* Number of timeouts that occurred while reserving a local ABL session. */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "numReserveABLSessionTimeouts", JsonDataType:Number) then
            put unformatted substitute("~t# Reserve ABLSession Timeout:  &1", FormatLongNumber(string(oMetrics:GetInteger("numReserveABLSessionTimeouts")), false)) skip.
    end. /* valid oMetrics */

    /* Parse through and display statistics from the Client Sessions API as obtained previously. */
    if valid-object(oClSess) then do:
        assign iSessions = oClSess:Length.
        put unformatted substitute("~nClient HTTP Sessions: &1", iSessions) skip.

        if iSessions gt 0 then do:
            put unformatted "~tSTATE     SESS STATE  BOUND~tLAST ACCESS / STARTED~t~tELAPSED TIME  SESSION MODEL    ADAPTER   SESSION ID~t~t~t~t~t~t~tREQUEST ID" skip.

            SESSIONBLK:
            do iLoop = 1 to iSessions
            on error undo, throw:
                /* There should always be a session present, so output that first. */
                assign oTemp = oClSess:GetJsonObject(iLoop).

                /* If we have elements in the ClientSession array, then each should be a valid object. But just in case it's not valid, skip. */
                if not valid-object(oTemp) then next SESSIONBLK.

                assign lIsBound = false. /* Reset for each iteration. */
                if JsonPropertyHelper:HasTypedProperty(oTemp, "bound", JsonDataType:Boolean) then
                    assign lIsBound = oTemp:GetLogical("bound") eq true.

                put unformatted substitute("~n~t&1&2&3~t&4~t&5  &6 &7&8 &9",
                                           string(oTemp:GetCharacter("requestState"), "x(10)"),
                                           string(oTemp:GetCharacter("sessionState"), "x(12)"),
                                           string(lIsBound, "YES/NO"),
                                           oTemp:GetCharacter("lastAccessStr"),
                                           FormatMsTime(oTemp:GetInt64("elapsedTimeMs")),
                                           string(oTemp:GetCharacter("sessionType"), "x(16)"),
                                           string(oTemp:GetCharacter("adapterType"), "x(10)"),
                                           string(oTemp:GetCharacter("sessionID"), "x(60)"),
                                           oTemp:GetCharacter("requestID")) skip.

                assign cBound = "". /* Reset on each iteration. */

                /* For bound sessions, prepare info about the agent-session against which the connection exists. */
                if lIsBound and oTemp:Has("agentID") and oTemp:Has("ablSessionID") then do:
                    if oAgentMap:ContainsKey(oTemp:GetCharacter("agentID")) then
                        /* We have a matching agent in existence, so return its PID with the ABLSession. */
                        assign cBound = string(oAgentMap:Get(oTemp:GetCharacter("agentID"))) + " #" + oTemp:GetCharacter("ablSessionID").
                    else if (oTemp:GetCharacter("agentID") gt "") eq true then
                        /* There is no matching PID, but we're bound and have an AgentID and ABLSession. */
                        assign cBound = "[PID Unknown] #" + oTemp:GetCharacter("ablSessionID").
                end. /* bound */

                /* Client Connections should be present next, especially if session-managed model is used. */
                if JsonPropertyHelper:HasTypedProperty(oTemp, "clientConnInfo", JsonDataType:object) then do:
                    assign oConnInfo = oTemp:GetJsonObject("clientConnInfo").

                    if valid-object(oConnInfo) then
                        put unformatted substitute("~t|- ClientConn: &1~t&2~t&3  Proc: &4 &5",
                                                   if oConnInfo:Has("clientName") then oConnInfo:GetCharacter("clientName") else "UNKNOWN",
                                                   if oConnInfo:Has("reqStartTimeStr") then oConnInfo:GetCharacter("reqStartTimeStr") else "UNKNOWN",
                                                   FormatMsTime(if oConnInfo:Has("elapsedTimeMs") then oConnInfo:GetInt64("elapsedTimeMs") else 0),
                                                   string(if oConnInfo:Has("requestProcedure") then oConnInfo:GetCharacter("requestProcedure") else "", "x(40)"),
                                                   if cBound gt "" then "Agent-Session: " + cBound else "") skip.
                end. /* clientConnInfo */

                /* Agent Connection should be present if executing ABL code. */
                if JsonPropertyHelper:HasTypedProperty(oTemp, "agentConnInfo", JsonDataType:object) then do:
                    assign oConnInfo = oTemp:GetJsonObject("agentConnInfo").

                    /* We can't really continue unless there is an AgentID (string) value to display. */
                    if JsonPropertyHelper:HasTypedProperty(oConnInfo, "agentID", JsonDataType:string) then
                        put unformatted substitute("~t|-- AgentConn: &1  &2  Agent: &3  Local: &4",
                                                   if oAgentMap:ContainsKey(oConnInfo:GetCharacter("agentID"))
                                                   then "PID " + oAgentMap:Get(oConnInfo:GetCharacter("agentID"))
                                                   else "ID " + oConnInfo:GetCharacter("agentID"),
                                                   /* Omitted connID and conPoolID */
                                                   if oConnInfo:Has("state") then oConnInfo:GetCharacter("state") else "UNKNOWN",
                                                   if oConnInfo:Has("agentAddr") then oConnInfo:GetCharacter("agentAddr") else "NA",
                                                   if oConnInfo:Has("localAddr") then oConnInfo:GetCharacter("localAddr") else "NA") skip.
                end. /* agentConnInfo */

                catch err as Progress.Lang.Error:
                    message substitute("Encountered error displaying session &1 of &2: &3", iLoop, iSessions, err:GetMessage(1)).
                    if valid-object(oConnInfo) then /* Output JSON data for investigation. */
                        oClSess:WriteFile(substitute("ClientSession_&1.json", cOutDate), true).
                    next SESSIONBLK.
                end catch.
            end. /* iLoop */
        end. /* valid-object - oClSess */
    end. /* response - ClientSessions */
end procedure.
