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
 * Obtains table lock info and running programs against a PASOE instance.
 * Usage: getLocks.p <params>
 *  Parameter Default/Allowed
 *   Scheme   [http|https]
 *   Hostname [localhost]
 *   PAS Port [8810]
 *   UserId   [tomcat]
 *   Password [tomcat]
 *   ABL App  [oepas1]
 *
 */

block-level on error undo, throw.

using OpenEdge.Core.Json.JsonPropertyHelper.
using OpenEdge.Core.JsonDataTypeEnum.
using OpenEdge.Core.Collections.*.
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

define variable oClient     as IHttpClient     no-undo.
define variable oCreds      as Credentials     no-undo.
define variable cHttpUrl    as character       no-undo.
define variable cInstance   as character       no-undo.
define variable oJsonResp   as JsonObject      no-undo.
define variable oResult     as JsonObject      no-undo.
define variable oTemp       as JsonObject      no-undo.
define variable oAblApps    as Array           no-undo.
define variable oAppAgents  as StringStringMap no-undo.
define variable oAgentList  as Array           no-undo.
define variable oQueryURL   as StringStringMap no-undo.
define variable cDB         as character       no-undo.
define variable iLoop       as integer         no-undo.
define variable iLoop2      as integer         no-undo.
define variable iLength1    as integer         no-undo.
define variable iLength2    as integer         no-undo.
define variable iPID        as integer         no-undo.
define variable oIter       as IIterator       no-undo.
define variable oAgent      as IMapEntry       no-undo.
define variable cScheme     as character       no-undo initial "http".
define variable cHost       as character       no-undo initial "localhost".
define variable cPort       as character       no-undo initial "8810".
define variable cUserId     as character       no-undo initial "tomcat".
define variable cPassword   as character       no-undo initial "tomcat".
define variable cDebug      as character       no-undo initial "false".

define temp-table ttLock no-undo
    field UserNum      as int64
    field UserName     as character
    field DomainName   as character
    field TenantName   as character
    field DatabaseName as character
    field TableName    as character
    field LockFlags    as character
    field TransID      as int64
    field PID          as int64
    field SessionID    as int64
    .

/* Check for passed-in arguments/parameters. */
if num-entries(session:parameter) ge 6 then
    assign
        cScheme   = entry(1, session:parameter)
        cHost     = entry(2, session:parameter)
        cPort     = entry(3, session:parameter)
        cUserId   = entry(4, session:parameter)
        cPassword = entry(5, session:parameter)
        cDebug    = entry(6, session:parameter)
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
        cDebug    = dynamic-function("getParameter" in source-procedure, "Debug") when (dynamic-function("getParameter" in source-procedure, "Debug") gt "") eq true
        .

if can-do("true,yes,1", cDebug) then do:
    log-manager:logfile-name    = "getLocks.log".
    log-manager:log-entry-types = "4GLTrace".
    log-manager:logging-level   = 5.
end.

assign oClient = ClientBuilder:Build():Client.
assign oCreds = new Credentials("PASOE Manager Application", cUserId, cPassword).
assign cInstance = substitute("&1://&2:&3", cScheme, cHost, cPort).
assign oQueryURL = new StringStringMap().
assign
    oAblApps   = new Array()
    oAppAgents = new StringStringMap()
    oAgentList = new Array()
    .

oAblApps:AutoExpand = true.
oAgentList:AutoExpand = true. 

/* Register the URL's to the OEM-API endpoints as will be used in this utility. */
oQueryURL:Put("Apps", "&1/oemanager/applications").
oQueryURL:Put("Agents", "&1/oemanager/applications/&2/agents").
oQueryURL:Put("Stacks", "&1/oemanager/applications/&2/agents/&3/stacks").

function MakeRequest returns JsonObject ( input pcHttpUrl as character ) forward.
function HasAgent returns logical ( input poInt as integer ) forward.

/* Populate temp-table with table lock status. */
message "~nScanning for Table Locks from connected PASN clients...".
do iLoop = 1 to num-dbs:
    assign cDB = ldbname(iLoop).
    if cDB eq ? then next.

    /* Change to the next DB by setting the "dictdb" alias. */
    create alias dictdb for database value(cDB).

    /* Scan all locks for this DB */
    message substitute("~tGetting lock stats for &1...", cDB).
    run getLockStats.p (input-output table ttLock by-reference).
end.

/* Display table lock information to screen. */
message "~nUsr#~tUser~t~tDomain~t~tTenant~t~tDatabase~tTable~t~tFlags~t~t~tPID~tSessionID".
for each ttLock no-lock:
    message substitute("&1  &2  &3 &4 &5 &6 &7 &8~t&9",
                       string(ttLock.UserNum) + fill(" ", 8 - length(string(ttLock.UserNum))),
                       string(ttLock.UserName, "x(16)"),
                       string(ttLock.DomainName, "x(15)"),
                       string(ttLock.TenantName, "x(15)"),
                       string(ttLock.DatabaseName, "x(15)"),
                       string(ttLock.TableName, "x(15)"),
                       string(ttLock.LockFlags, "x(15)"),
                       string(ttLock.PID, ">>>>>>>>>>>>>>9"),
                       (if ttLock.SessionID eq ? then "" else string(ttLock.SessionID))).

    /****************************************************************************************************
      Lock Flags (https://knowledgebase.progress.com/articles/Article/21639):
        C   Create              The lock is in create mode.
        D   Downgrade           The lock is downgraded.
        E   Expired             The lock wait timeout has expired on this queued lock.
        H   On hold             The "onhold" flag is set.
        J   JTA                 The lock is part of a JTA transaction
        K   Keep                Keep the lock across transaction end boundary
        L   Limbo lock          The client has released the record, but the transaction has not completed.
                                (The record lock is not released until the transaction ends.)
        P   Purged lock entry   The lock is no longer held.
        Q   Queued lock req.    Represents a queued request for a lock already held by another process.
        U   Upgrade request     The user has requested a lock upgrade from SHARE to EXCLUSIVE.
    ****************************************************************************************************/

    /* Track a list of PID's which relate to locked tables (by PASN users). */
    oAgentList:Add(new OpenEdge.Core.Integer(ttLock.PID)).
end.

/* Get information on PAS instance. */
run getAblApplications.
run getAblAppAgents.

/* Iterate through the list of ABL App MSAgents, getting stacks for those with table locks. */
assign oIter = oAppAgents:EntrySet:Iterator().
do while oIter:HasNext():
    assign oAgent = cast(oIter:Next(), IMapEntry).
    assign iPID = integer(string(oAgent:key)).

    /* Obtain stacks for the agent. */
    if HasAgent(iPID) then do:
        assign cHttpUrl = substitute(oQueryURL:Get("Stacks"), cInstance, string(oAgent:value), iPID).
        assign oJsonResp = MakeRequest(cHttpUrl).
        if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:Object) then do:
            if JsonPropertyHelper:HasTypedProperty(oJsonResp:GetJsonObject("result"), "ABLStacks", JsonDataType:Array) then do:
                define variable oABLStacks as JsonArray  no-undo.
                define variable oABLStack  as JsonObject no-undo.
                define variable oCallstack as JsonArray  no-undo.

                message substitute("~n&1 MSAgent PID &2:", string(oAgent:value), iPID).

                assign oABLStacks = oJsonResp:GetJsonObject("result"):GetJsonArray("ABLStacks").

                assign iLength1 = oABLStacks:Length.
                do iLoop = 1 to iLength1:
                    assign oABLStack = oABLStacks:GetJsonObject(iLoop).

                    if oABLStack:Has("AgentSessionId") then
                        message substitute("~n~tCall Stack for Session ID #&1:", oABLStack:GetInteger("AgentSessionId")).

                    if JsonPropertyHelper:HasTypedProperty(oABLStack, "Callstack", JsonDataType:Array) then do:
                        assign oCallstack = oABLStack:GetJsonArray("Callstack").

                        assign iLength2 = oCallstack:Length.
                        do iLoop2 = 1 to iLength2:
                            if oCallstack:GetJsonObject(iLoop2):Has("Routine") then
                                message substitute("~t~t&1", oCallstack:GetJsonObject(iLoop2):GetCharacter("Routine")).
                        end. /* iLoop2 */
                    end. /* Has Callstack*/
                end. /* iLoop */
            end. /* Has ABLStacks */
        end. /* stacks */
    end. /* oAgentList:Contains(iPID) */
end. /* do while */

finally:
    delete alias dictdb.

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
        put unformatted substitute("~nError executing OEM-API request: &1 [URL: &2]", err:GetMessage(1) , pcHttpUrl) skip.
        return new JsonObject().
    end catch.
    finally:
        delete object oReq no-error.
        delete object oResp no-error.
    end finally.
end function. /* MakeRequest */

function HasAgent returns logical (input poInt as integer):
    define variable lFound as logical no-undo initial false.
    define variable iMax   as integer no-undo.
    define variable iX     as integer no-undo.

    assign iMax = oAgentList:Size.
    do iX = 1 to iMax while not lFound:
        if valid-object(oAgentList:GetValue(iX)) then
            assign lFound = oAgentList:GetValue(iX):Equals(new OpenEdge.Core.Integer(poInt)).
    end.

    return lFound.
end function.

procedure getAblApplications:
    /* Oobtain a list of all ABL Applications for a PAS instance. */
    assign cHttpUrl = substitute(oQueryURL:Get("Apps"), cInstance).
    assign oJsonResp = MakeRequest(cHttpUrl).
    if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:object) then do:
        define variable oApps as JsonArray  no-undo.
        define variable oApp  as JsonObject no-undo.

        oApps = oJsonResp:GetJsonObject("result"):GetJsonArray("Application").

        if oApps:Length gt 0 then
        APPBLK:
        do iLoop = 1 to oApps:Length
        on error undo, next APPBLK
        on stop undo, next APPBLK:
            oApp = oApps:GetJsonObject(iLoop).

            if oApp:Has("name") and oApp:Has("type") and oApp:GetCharacter("type") eq "OPENEDGE" then
                oAblApps:Add(new OpenEdge.Core.String(oApp:GetCharacter("name"))).
        end. /* iLoop - Application */
    end. /* agents */
end procedure.

procedure getAblAppAgents:
    define variable iSize as integer no-undo.

    /* Iterate through the list of ABL Applications, getting all MSAgent PID's. */
    assign iSize = oAblApps:Size.
    do iLoop = 1 to iSize:
        if valid-object(oAblApps:GetValue(iLoop)) then do:
            /* Obtain a list of all AVAILABLE agents for an ABL Application. */
            assign cHttpUrl = substitute(oQueryURL:Get("Agents"), cInstance, cast(oAblApps:GetValue(iLoop), OpenEdge.Core.String):Value).
            assign oJsonResp = MakeRequest(cHttpUrl).
            if JsonPropertyHelper:HasTypedProperty(oJsonResp, "result", JsonDataType:Object) then do:
                define variable oAgents as JsonArray  no-undo.
                define variable oAgent  as JsonObject no-undo.
        
                oAgents = oJsonResp:GetJsonObject("result"):GetJsonArray("agents").
        
                if oAgents:Length gt 0 then
                AGENTBLK:
                do iLoop2 = 1 to oAgents:Length
                on error undo, next AGENTBLK
                on stop undo, next AGENTBLK:
                    oAgent = oAgents:GetJsonObject(iLoop2).

                    if oAgent:GetCharacter("state") eq "available" then
                        oAppAgents:Put(oAgent:GetCharacter("pid"), cast(oAblApps:GetValue(iLoop), OpenEdge.Core.String):Value).
                end. /* iLoop - agents */
            end. /* agents */
        end. /* Non-Null Array Item */
    end. /* iLoop */
end procedure.
