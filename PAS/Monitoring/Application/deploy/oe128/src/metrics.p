/**
 * Enable or disable the "pulse metrics" for an instance (req. 12.2+).
 * Usage: pulseMetrics.p <params>
 *  Parameter Default/Allowed
 *   CatalinaBase [C:\OpenEdge\WRK\oepas1]
 *   ABL App  [oepas1]
 */

&GLOBAL-DEFINE MIN_VERSION_12_2 (integer(entry(1, proversion(1), ".")) eq 12 and integer(entry(2, proversion(1), ".")) ge 2)

using OpenEdge.Core.Json.JsonPropertyHelper from propath.
using OpenEdge.Core.JsonDataTypeEnum from propath.
using OpenEdge.Core.Collections.StringStringMap from propath.
using OpenEdge.Net.HTTP.ClientBuilder from propath.
using OpenEdge.Net.HTTP.Credentials from propath.
using OpenEdge.Net.HTTP.IHttpClient from propath.
using OpenEdge.Net.HTTP.IHttpRequest from propath.
using OpenEdge.Net.HTTP.IHttpResponse from propath.
using OpenEdge.Net.HTTP.RequestBuilder from propath.
using Progress.Lang.Object from propath.
using Progress.Json.ObjectModel.ObjectModelParser from propath.
using Progress.Json.ObjectModel.JsonObject from propath.
using Progress.Json.ObjectModel.JsonArray from propath.
using Progress.Json.ObjectModel.JsonDataType from propath.

define variable cQueryString  as character       no-undo.
define variable cOutFileName  as character       no-undo.
define variable cMetricsURL   as character       no-undo initial "web/pdo/monitor/intake/liveMetrics".
define variable cHealthURL    as character       no-undo initial "web/pdo/monitor/intake/liveHealth".
define variable cProfileURL   as character       no-undo initial "web/pdo/monitor/intake/liveProfile".
define variable cMetricsType  as character       no-undo initial "pulse".
define variable cMetricsState as character       no-undo initial "on".
define variable cMetricsOpts  as character       no-undo initial "sessions,requests,calltrees,ablobjs". /* logmsgs,sessions,requests,calltrees,callstacks,ablobjs */
define variable cDescriptor   as character       no-undo.
define variable cHostIP       as character       no-undo initial "127.0.0.1".
define variable iPulseTime    as integer         no-undo initial 20.
define variable oJsonResp     as JsonObject      no-undo.
define variable oOptions      as JsonObject      no-undo.
define variable oQueryString  as StringStringMap no-undo.
define variable iLoop         as integer         no-undo.
define variable iLoop2        as integer         no-undo.
define variable iLoop3        as integer         no-undo.
define variable iCollect      as integer         no-undo.
define variable cBound        as character       no-undo.
define variable cOEJMXBinary  as character       no-undo.
define variable cCatalinaBase as character       no-undo.
define variable cAblApp       as character       no-undo initial "oepas1".
define variable cMonScheme    as character       no-undo initial "http".
define variable cMonHost      as character       no-undo initial "localhost".
define variable cMonPort      as character       no-undo initial "8850".

define temp-table ttAgent no-undo
    field agentID    as character
    field agentPID   as character
    field agentState as character
    .

/* Check for passed-in arguments/parameters. */
if num-entries(session:parameter) ge 6 then
    assign
        cCatalinaBase = entry(1, session:parameter)
        cAblApp       = entry(2, session:parameter)
		cHostIP       = entry(3, session:parameter)
		cMetricsType  = entry(4, session:parameter)
		cMetricsState = entry(5, session:parameter)
		cMetricsOpts  = entry(6, session:parameter)
		cMonScheme    = entry(7, session:parameter)
		cMonHost      = entry(8, session:parameter)
		cMonPort      = entry(9, session:parameter)
        .
else
    assign
        cCatalinaBase = dynamic-function("getParameter" in source-procedure, "CatalinaBase") when (dynamic-function("getParameter" in source-procedure, "CatalinaBase") gt "") eq true
        cAblApp       = dynamic-function("getParameter" in source-procedure, "ABLApp") when (dynamic-function("getParameter" in source-procedure, "ABLApp") gt "") eq true
        cHostIP       = dynamic-function("getParameter" in source-procedure, "Host") when (dynamic-function("getParameter" in source-procedure, "Host") gt "") eq true
        cMetricsType  = dynamic-function("getParameter" in source-procedure, "Type") when (dynamic-function("getParameter" in source-procedure, "Type") gt "") eq true
        cMetricsState = dynamic-function("getParameter" in source-procedure, "State") when (dynamic-function("getParameter" in source-procedure, "State") gt "") eq true
        cMetricsOpts  = dynamic-function("getParameter" in source-procedure, "Opts") when (dynamic-function("getParameter" in source-procedure, "Opts") gt "") eq true
        cMonScheme    = dynamic-function("getParameter" in source-procedure, "Scheme") when (dynamic-function("getParameter" in source-procedure, "Scheme") gt "") eq true
        cMonHost      = dynamic-function("getParameter" in source-procedure, "Monitor") when (dynamic-function("getParameter" in source-procedure, "Monitor") gt "") eq true
        cMonPort      = dynamic-function("getParameter" in source-procedure, "Port") when (dynamic-function("getParameter" in source-procedure, "Port") gt "") eq true
        .

if cMonHost eq "file" then
	assign
		cMetricsURL = cMonHost
		cHealthURL  = cMonHost
		cProfileURL = cMonHost
		.
else
	assign
		cMetricsURL = substitute("&1://&2:&3/&4", cMonScheme, cMonHost, cMonPort, cMetricsURL)
		cHealthURL  = substitute("&1://&2:&3/&4", cMonScheme, cMonHost, cMonPort, cHealthURL)
		cProfileURL = substitute("&1://&2:&3/&4", cMonScheme, cMonHost, cMonPort, cProfileURL)
		.

/* Set the name of the OEJMX binary based on operating system. */
assign cOEJMXBinary = if opsys eq "WIN32" then "oejmx.bat" else "oejmx.sh".

/* Register the queries for the OEJMX command as will be used in this utility. */
assign cDescriptor = substitute("app=&1|host=&2|name=Metrics_&3|health=&4", cAblApp, cHostIP, iso-date(now), cHealthURL).
assign oOptions = new JsonObject().
oOptions:Add("AdapterMask", "").
oOptions:Add("Coverage", true).
oOptions:Add("Statistics", true).
oOptions:Add("ProcList", "").
oOptions:Add("TestRunDescriptor", cDescriptor).
assign oQueryString = new StringStringMap().
oQueryString:Put("Agents", '~{"O":"PASOE:type=OEManager,name=AgentManager","M":["getAgents","&1"]}').
oQueryString:Put("PulseOn", '~{"O":"PASOE:type=OEManager,name=AgentManager", "M":["debugTest", "&1", "LiveDiag", "&2", &3, "&4|&5"]}').
oQueryString:Put("PulseOff", '~{"O":"PASOE:type=OEManager,name=AgentManager", "M":["debugTest", "&1", "LiveDiag", "", 0, ""]}').
oQueryString:Put("ProfilerOn", '~{"O":"PASOE:type=OEManager,name=AgentManager", "M":["pushProfilerData", "&1", "&2", "-1", "&3"]}').
oQueryString:Put("ProfilerOff", '~{"O":"PASOE:type=OEManager,name=AgentManager", "M":["pushProfilerData", "&1", "", 0, ""]}').

function InvokeJMX returns character ( input pcQueryPath as character ) forward.
function RunQuery returns JsonObject ( input pcHttpUrl as character ) forward.

/* Start with some basic header information for this report. */
message substitute("PASOE Instance: &1", cCatalinaBase).
message substitute("  Metrics Type: &1 (&2)", cMetricsType, cMetricsState).

/* Gather the list of agents for this ABL App. */
run GetAgents.

for each ttAgent no-lock
   where ttAgent.agentState eq "available":
    message substitute("~nAgent PID &1: &2", ttAgent.agentPID, ttAgent.agentState).

    assign cQueryString = "".
    case cMetricsType:
        when "pulse" or
        when "metrics" then do:
            if can-do("enable,true,yes,on,1", cMetricsState) then
                assign
                    cQueryString = substitute(oQueryString:Get("PulseOn"), ttAgent.agentPID, cMetricsURL, iPulseTime, cMetricsOpts, cDescriptor)
                    cOutFileName = substitute("pulse_on_&1", ttAgent.agentPID)
                    .
			else
                assign
                    cQueryString = substitute(oQueryString:Get("PulseOff"), ttAgent.agentPID)
                    cOutFileName = substitute("pulse_off_&1", ttAgent.agentPID)
                    .
        end.
        when "profile" or
        when "profiler" then do:
            if can-do("enable,true,yes,on,1", cMetricsState) then
                assign
                    cQueryString = substitute(oQueryString:Get("ProfilerOn"), ttAgent.agentPID, cProfileURL, replace(oOptions:GetJsonText(), '"', '\"'))
                    cOutFileName = substitute("profiler_on_&1", ttAgent.agentPID)
                    .
            else
                assign
                    cQueryString = substitute(oQueryString:Get("ProfilerOff"), ttAgent.agentPID)
                    cOutFileName = substitute("profiler_off_&1", ttAgent.agentPID)
                    .
        end.
        otherwise
            message "Unknown metric type provided, task aborted.".
    end case. /* cMetricsType */

    if (cQueryString gt "") eq true then do:
        message substitute("Query: &1", cQueryString).
        assign oJsonResp = RunQuery(cQueryString).
        if valid-object(oJsonResp) then
            message substitute("Result: &1", string(oJsonResp:GetJsonText())).
    end.
end. /* for each ttAgent */

finally:
    /* Return value expected by PCT Ant task. */
    return string(0).
end finally.

/* PROCEDURES / FUNCTIONS */

function InvokeJMX returns character ( input pcQueryPath as character ):
    /**
     * Make a query again the running Java process via JMX to obtain any
     * information or set flags to control monitoring/debugging options.
     *   The -R flag removes the header, leaving only the JSON body.
     *   The -Q flag specifies the name of the query to be executed.
     *   The -O flag sets a specific location for the query output.
     * Example:
     *   oejmx.[bat|sh] -R -Q <catalina_base>/temp/<name>.qry -O <catalina_base>/temp/<output>.out
     */
    define variable cBinaryPath as character no-undo.
    define variable cOutputPath as character no-undo.
    define variable cCommand    as character no-undo.
    define variable iTime       as integer   no-undo.

    if (pcQueryPath gt "") ne true then
        undo, throw new Progress.Lang.AppError("No query path provided.", 0).

    assign iTime = mtime. /* Each request should be timestamped to avoid overlap. */
    assign cBinaryPath = substitute("&1/bin/&2", cCatalinaBase, cOEJMXBinary). /* oejmx.[bat|sh] */
    assign cOutputPath = substitute("&1/bin/&2.out", cCatalinaBase, cOutFileName). /* Output File. */

    /* Construct the final command string to be executed. */
    assign cCommand = substitute("&1 -R -Q &2 -O &3", cBinaryPath, pcQueryPath, cOutputPath).

    /* Run command and report information to log file. */
    os-command no-console value(cCommand). /* Cannot use silent or no-wait here. */

    return cOutputPath. /* Return the expected location of the query output. */

    finally:
        os-delete value(pcQueryPath).
    end finally.
end function. /* InvokeJMX */

function RunQuery returns JsonObject ( input pcQueryString as character ):
    define variable cQueryPath as character         no-undo initial "temp.qry".
    define variable cOutPath   as character         no-undo.
    define variable oParser    as ObjectModelParser no-undo.
    define variable oQuery     as JsonObject        no-undo.

    do on error undo, throw
       on stop undo, retry:
        if retry then
            undo, throw new Progress.Lang.AppError("Encountered stop condition", 0).

        assign oParser = new ObjectModelParser().

        /* Output the modified string to the temporary query file. */
        assign oQuery = cast(oParser:Parse(pcQueryString), JsonObject).
        oQuery:WriteFile(cQueryPath). /* Send JSON data to disk. */

        /* Create the query for obtaining agents, and invoke the JMX command. */
        assign cOutPath = InvokeJMX(cQueryPath).

        /* Confirm output file exists, and parse the JSON payload. */
        file-info:file-name = cOutPath.
        if file-info:full-pathname ne ? then do:
            if file-info:file-size eq 0 then
                undo, throw new Progress.Lang.AppError(substitute("Encountered Empty File: &1", cOutPath), 0).

            return cast(oParser:ParseFile(cOutPath), JsonObject).
        end. /* File Exists */
    end.

    catch err as Progress.Lang.Error:
        /* Always report any errors during the API requests, and return an empty JSON object allowing remaining logic to continue. */
        message substitute("~nError executing OEM-API request: &1 [URL: &2]", err:GetMessage(1) , pcQueryString).
        return new JsonObject().
    end catch.
    finally:
        delete object oParser no-error.
    end finally.
end function. /* RunQuery */

/* Initial URL to obtain a list of all agents for an ABL Application. */
procedure GetAgents:
    define variable iTotAgent as integer    no-undo.
    define variable iTotSess  as integer    no-undo.
    define variable iBusySess as integer    no-undo.
    define variable dStart    as datetime   no-undo.
    define variable dCurrent  as datetime   no-undo.
    define variable oAgents   as JsonArray  no-undo.
    define variable oAgent    as JsonObject no-undo.
    define variable oSessions as JsonArray  no-undo.
    define variable oSessInfo as JsonObject no-undo.

    empty temp-table ttAgent.

    /* Capture all available agent info to a temp-table before we proceed. */
    assign cQueryString = substitute(oQueryString:Get("Agents"), cAblApp).
    assign oJsonResp = RunQuery(cQueryString).
    if JsonPropertyHelper:HasTypedProperty(oJsonResp, "getAgents", JsonDataType:Object) then do:
        if JsonPropertyHelper:HasTypedProperty(oJsonResp:GetJsonObject("getAgents"), "agents", JsonDataType:Array) then
            oAgents = oJsonResp:GetJsonObject("getAgents"):GetJsonArray("agents").
        else
            oAgents = new JsonArray().

        assign iTotAgent = oAgents:Length.

        if oAgents:Length eq 0 then
            message "~nNo agents running".
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

            release ttAgent no-error.
        end. /* iLoop - Agents */
    end. /* response - Agents */
end procedure.
