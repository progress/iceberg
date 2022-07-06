/*
    Copyright 2021 Progress Software Corporation

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
/*------------------------------------------------------------------------
    File        : Intake
    Purpose     : Perform operations to read generated data from PAS instances
    Syntax      :
    Description :
    Author(s)   : Dustin Grau (dugrau@progress.com)
    Created     : Fri May 11 10:24:18 EDT 2018
    Notes       :
  ----------------------------------------------------------------------*/

@program FILE(name="Intake.cls", module="AppServer").
@openapi.openedge.export FILE(type="REST", executionMode="singleton", useReturnValue="false", writeDataSetBeforeImage="false").
@progress.service.resource FILE(name="intake", URI="/intake", schemaName="", schemaFile="").

&global-define TOP_LEVEL_DIRS "ABLObjects,ProfilerData,Requests,SessionData,TrackingAgents"
&global-define MAX_TIME_LIMIT 900

using Progress.Lang.* from propath.
using Progress.Json.ObjectModel.* from propath.
using OpenEdge.Core.Json.JsonPropertyHelper from propath.
using OpenEdge.Logging.* from propath.

block-level on error undo, throw.

class Business.Intake use-widget-pool:

    {Common/health.i}

    /**
     * This class should be the primary interface for consuming data written by the monitoring
     * utilities on external PAS instances. Data should be located in a known directory based
     * on application name (for a given customer) and optionally a distinct ServerInfo. Metrics
     * should be rolled up to a session ID number, which should belong to an agent ID (PID).
     * Below each session ID can be multiple metrics tables, such that plotting data over time
     * for a given session will allow for correlation between the various tracked metrics.
     *
     * Server > Session > Sample > [Metric1|Metric2]
     */

    define private variable lHasObjects   as logical   no-undo initial false.
    define private variable lHasProfiles  as logical   no-undo initial false.
    define private variable lHasRequests  as logical   no-undo initial false.
    define private variable lHasSessions  as logical   no-undo initial false.
    define private variable cObjectsPath  as character no-undo.
    define private variable cProfilesPath as character no-undo.
    define private variable cRequestsPath as character no-undo.
    define private variable cSessionsPath as character no-undo.
    define private variable dStart        as datetime  no-undo.

    define private temp-table ttConfig no-undo serialize-name "General"
        field ApplicationName as character
        field ServerName      as character
        field LogsLocation    as character
        field MetricsLocation as character
        .

    define private dataset dsConfig serialize-name "Config" for ttConfig.

    define private temp-table AgentRequest no-undo
        field RequestProcName as character
        field SessionId       as integer
        field ConnectionId    as integer
        field StartTime       as datetime
        field EndTime         as datetime
        field RequestNum      as integer
        field BrokerSessionId as character
        field ClientId        as character
        field RequestLen      as int64
        field Transport       as character
        field RequestStatus   as integer
        index idxRequest RequestNum
        .

    define private temp-table ttFiles no-undo
        field FilePath  as character
        field Processed as logical
        .

    define protected property oLogger as ILogWriter no-undo
        get():
            /* Create single logger instance for this class. */
            if not valid-object(oLogger) then
                assign oLogger = LoggerBuilder:GetLogger(this-object:getClass()).
            return oLogger.
        end get.
        private set.

    define protected property TemporaryDir as character no-undo
        get():
            if TemporaryDir eq "" then
                assign TemporaryDir = right-trim(replace(session:temp-directory, "~\", "~/"), "~/").
            return TemporaryDir.
        end get.
        private set.


    /***** Constructor *****/

    constructor Intake ( ):
        define variable oParser as ObjectModelParser no-undo.
        define variable oConfig as JsonObject        no-undo.

        /* Create a special subdirectory for processing if it does not exist already. */
        os-create-dir value(substitute("&1/intake", this-object:TemporaryDir)).

        /* Read the config file to know what logs can be parsed. */
        file-info:filename = "config.json".
        if file-info:full-pathname ne ? then do:
            assign oParser = new ObjectModelParser().
            assign oConfig = cast(oParser:ParseFile(file-info:full-pathname), JsonObject).
            if valid-object(oConfig) then
                dataset dsConfig:read-json("JsonObject", oConfig).
            else
                oLogger:Debug("Warning: Cannot find/parse config file!").
        end. /* Config File Present */

        finally:
            delete object oParser no-error.
            delete object oConfig no-error.
        end finally.
    end constructor.


    /***** Private Methods *****/


    method private date iso2Date ( input pcString as character ):
        define variable cDateFormat as character no-undo.

        cDateFormat = session:date-format.
        session:date-format = "ymd".

        return date(pcString).

        finally:
            session:date-format = cDateFormat.
        end finally.
    end method. /* iso2Date */


    method private datetime-tz iso2DateTZ ( input pcString as character ):
        define variable cDateFormat as character no-undo.

        cDateFormat = session:date-format.
        session:date-format = "ymd".

        return datetime-tz(pcString).

        finally:
            session:date-format = cDateFormat.
        end finally.
    end method. /* iso2DateTZ */


    method private datetime NormalizeDate ( input pcDate as date,
                                            input piTime as integer ):
        define variable fTemp as decimal no-undo.

        /* Round up or down to the nearest whole second, normalizing the sample time. */
        assign fTemp = piTime / 1000.
        assign fTemp = round(fTemp, 0).

        /* Return the combined date+time value. */
        return datetime(pcDate, integer(fTemp * 1000)).
    end method. /* NormalizeDate */


    method private void UpdateConfig ( input pcApplication as character,
                                       input pcServerName  as character ):
        /* Check that the app/server exists in the config tables. */
        find first ttConfig
             where ttConfig.ApplicationName eq pcApplication
               and ttConfig.ServerName eq pcServerName no-error.
        if not available(ttConfig) then do:
            /* Add the server to the internal list. */
            create ttConfig.
            assign
                ttConfig.ApplicationName = pcApplication
                ttConfig.ServerName      = pcServerName
                .
            release ttConfig.

            /* Update the config file on disk with the latest data. */
            file-info:filename = search("config.json").
            if file-info:full-pathname ne ? then do:
                dataset dsConfig:write-json("file", file-info:full-pathname, true).
            end. /* Config File Present */
        end. /* not available */
    end method. /* UpdateConfig */


    method private character UpdateServer ( input pcApplication as character,
                                            input pcServerName  as character ):
        define variable cServerUUID as character no-undo.

        define buffer bServerInfo for ServerInfo.

        assign dStart = now. /* Mark start of timer for debugging. */

        find first bServerInfo no-lock
             where bServerInfo.ApplicationName eq pcApplication
               and bServerInfo.ServerName eq pcServerName no-error.

        if not available(bServerInfo) then do:
            create bServerInfo.
            assign
                cServerUUID                 = encode(substitute("&1.&2", pcApplication, pcServerName))
                bServerInfo.ApplicationName = pcApplication
                bServerInfo.ServerName      = pcServerName
                bServerInfo.ServerUUID      = cServerUUID
                .

            release bServerInfo no-error.
        end. /* not available */
        else
            assign cServerUUID = bServerInfo.ServerUUID.

        return cServerUUID.

        finally:
            oLogger:Trace(substitute("|-- UpdateServer: &1ms", interval(now, dStart, "milliseconds"))).
        end finally.
    end method. /* UpdateServer */


    method private character UpdateSession ( input pcServerUUID as character,
                                             input piAgentPID   as integer,
                                             input piSessionID  as integer,
                                             input pdStarted    as datetime ):
        define variable cSessoinUUID as character no-undo.

        define buffer bSessionInfo for SessionInfo.

        assign dStart = now. /* Mark start of timer for debugging. */

        find first bSessionInfo no-lock
             where bSessionInfo.ServerUUID eq pcServerUUID
               and bSessionInfo.AgentPID eq piAgentPID
               and bSessionInfo.SessionID eq piSessionID no-error.

        if not available(bSessionInfo) then do:
            create bSessionInfo.
            assign
                cSessoinUUID             = encode(substitute("&1.&2.&3", pcServerUUID, piAgentPID, piSessionID))
                bSessionInfo.ServerUUID  = pcServerUUID
                bSessionInfo.AgentPID    = piAgentPID
                bSessionInfo.SessionID   = piSessionID
                bSessionInfo.SessionUUID = cSessoinUUID
                bSessionInfo.Started     = ? /* Set the timestamp to unknown when first creating the record. */
                .
        end. /* not available */
        else do:
            assign cSessoinUUID = bSessionInfo.SessionUUID.

            /* Set the session start time when a valid timestamp is provided. */
            if pdStarted ne ? and bSessionInfo.Started eq ? then do:
                find current bSessionInfo exclusive-lock.
                assign bSessionInfo.Started = pdStarted.
            end.
        end. /* available */

        return cSessoinUUID.

        finally:
            release bSessionInfo no-error.
            oLogger:Trace(substitute("|-- UpdateSession: &1ms", interval(now, dStart, "milliseconds"))).
        end finally.
    end method. /* UpdateSession */


    method private character UpdateAgent ( input pcServerUUID  as character,
                                           input piAgentPID    as integer,
                                           input pcGroupName   as character,
                                           input pdSampleTime  as datetime,
                                           input pcSessions    as character,
                                           input pdAgentStart  as datetime,
                                           input piOverheadMem as int64 ):
        assign dStart = now. /* Mark start of timer for debugging. */
        assign pcGroupName = trim(pcGroupName).

        define buffer bAgentSample for AgentSample.

        find first bAgentSample no-lock
             where bAgentSample.ServerUUID eq pcServerUUID
               and bAgentSample.AgentPID eq piAgentPID
               and bAgentSample.SampleGroup eq pcGroupName
               and bAgentSample.Timestamp eq pdSampleTime no-error.

        if not available(bAgentSample) then do:
            create bAgentSample.
            assign
                bAgentSample.ServerUUID     = pcServerUUID
                bAgentSample.AgentPID       = piAgentPID
                bAgentSample.SampleGroup    = pcGroupName
                bAgentSample.Timestamp      = pdSampleTime
                bAgentSample.AgentStarted   = pdAgentStart
                bAgentSample.OverheadMemory = piOverheadMem
                .

            if (pcSessions gt "") eq true then
                assign
                    bAgentSample.BusySessions   = num-entries(pcSessions)
                    bAgentSample.ActiveSessions = pcSessions
                    .
        end. /* not available */
        else if available(bAgentSample) and (pcSessions gt "") eq true then do:
            find current bAgentSample exclusive-lock.
            assign
                bAgentSample.BusySessions   = num-entries(pcSessions)
                bAgentSample.ActiveSessions = pcSessions
                .
        end. /* available */

        finally:
            release bAgentSample no-error.
            oLogger:Trace(substitute("|-- UpdateAgent: &1ms", interval(now, dStart, "milliseconds"))).
        end finally.
    end method. /* UpdateAgent */


    method private character UpdateSample ( input pcSessionUUID as character,
                                            input pcGroupName   as character,
                                            input pdSampleTime  as datetime,
                                            input piMemoryBytes as int64,
                                            input piObjectCount as integer ):
        define variable cSampleUUID as character no-undo.

        define buffer bSessionSample for SessionSample.

        assign dStart = now. /* Mark start of timer for debugging. */
        assign pcGroupName = trim(pcGroupName).

        find first bSessionSample no-lock
             where bSessionSample.SessionUUID eq pcSessionUUID
               and bSessionSample.SampleGroup eq pcGroupName
               and bSessionSample.Timestamp eq pdSampleTime no-error.

        if not available(bSessionSample) then do:
            create bSessionSample.
            assign
                cSampleUUID                = encode(substitute("&1.&2", pcSessionUUID, pdSampleTime))
                bSessionSample.SessionUUID = pcSessionUUID
                bSessionSample.SampleUUID  = cSampleUUID
                bSessionSample.SampleGroup = pcGroupName
                bSessionSample.Timestamp   = pdSampleTime
                bSessionSample.MemoryBytes = piMemoryBytes when (piMemoryBytes ne ? and piMemoryBytes ge 0)
                bSessionSample.ObjectCount = piObjectCount when (piObjectCount ne ? and piObjectCount ge 0)
                .
        end. /* not available */
        else if available(bSessionSample) then do:
            assign cSampleUUID = bSessionSample.SampleUUID.

            /* Update session memory size, when provided. */
            if piMemoryBytes ne ? and piMemoryBytes ge 0 then do:
                find current bSessionSample exclusive-lock.
                assign bSessionSample.MemoryBytes = piMemoryBytes.
            end. /* piMemoryBytes */

            /* Update session object count, when provided. */
            if piObjectCount ne ? and piObjectCount ge 0 then do:
                find current bSessionSample exclusive-lock.
                assign bSessionSample.ObjectCount = piObjectCount.
            end. /* piObjectCount */
        end. /* available */

        return cSampleUUID.

        finally:
            release bSessionSample no-error.
            oLogger:Trace(substitute("|-- UpdateSample: &1ms", interval(now, dStart, "milliseconds"))).
        end finally.
    end method. /* UpdateSample */


    method private logical ProcessObjects ( input pcServerUUID as character,
                                            input pcFilePath   as character ):
        define variable cShortPath as character  no-undo.
        define variable cSessUUID  as character  no-undo.
        define variable cSampUUID  as character  no-undo.
        define variable cFilename  as character  no-undo.
        define variable oObjects   as JsonArray  no-undo.
        define variable iAgentPID  as integer    no-undo.
        define variable iSessionID as integer    no-undo.
        define variable cSessionID as character  no-undo.
        define variable cDateTime  as character  no-undo.
        define variable dDate      as date       no-undo.
        define variable iTime      as integer    no-undo.
        define variable dTimestamp as datetime   no-undo.

        /* Format: <agent>/<iso_date>.<mtime>_A<agent>_S<session>.json */
        assign cShortPath = substring(pcFilePath, length(cObjectsPath) + 1).
        oLogger:Debug(substitute("Processing Objects: &1", cShortPath)).

        /* Parse the filename and obtain contents. */
        file-info:file-name = pcFilePath.
        if file-info:full-pathname ne ? then do:
            assign
                iAgentPID = integer(entry(1, cShortPath, "/"))
                cFilename = entry(2, cShortPath, "/")
                cDateTime = entry(1, cFilename, "_")
                .

            assign dDate = this-object:iso2Date(entry(1, cDateTime, ".")).
            assign iTime = integer(entry(2, cDateTime, ".")) when num-entries(cDateTime, ".") eq 2.
            assign dTimestamp = this-object:NormalizeDate(dDate, iTime). /* Round to nearest second. */

            assign
                cSessionID = replace(entry(3, cFilename, "_"), "S", "") when num-entries(cFilename, "_") ge 3
                iSessionID = integer(entry(1, cSessionID, "."))
                .

            /* File is in JSON format, parse and store as local array. */
            do on error undo, throw:
                define variable oParser as ObjectModelParser no-undo.

                assign dStart = now.
                assign oParser = new ObjectModelParser().
                assign oObjects = cast(oParser:ParseFile(file-info:full-pathname), JsonArray).

                delete object oParser no-error.
                oLogger:Trace(substitute("Object File Parse: &1ms", interval(now, dStart, "milliseconds"))).
            end. /* Parse File */

            /* Update the current session info, sample record, and pass the object count. */
            assign cSessUUID = this-object:UpdateSession(pcServerUUID, iAgentPID, iSessionID, dTimestamp).
            assign cSampUUID = this-object:UpdateSample(cSessUUID, "", dTimestamp, ?, oObjects:Length).

            /* Call the common method for processing data from the parsed file. */
            return this-object:ProcessObjects(cSampUUID, oObjects).
        end. /* file exists */

        return false. /* Unable to process file. */

        finally:
            delete object oObjects no-error.
        end finally.
    end method. /* ProcessObjects */


    method private logical ProcessObjects ( input pcSampleUUID as character,
                                            input poObjects    as JsonArray ):
        define variable iObjects  as integer    no-undo.
        define variable iCount    as integer    no-undo.
        define variable oObject   as JsonObject no-undo.
        define variable iHandleID as integer    no-undo.
        define variable cSource   as character  no-undo.
        define variable iLine     as integer    no-undo.

        define buffer bABLObject for ABLObject.

        assign iObjects = poObjects:length.
        if iObjects eq 0 then return false. /* Nothing to parse. */

        /* Create timestamped records for each object found at this time for this session. */
        oLogger:Trace(substitute("|- Processing &1 object(s) for sample '&2'.", iObjects, pcSampleUUID)).
        if iObjects gt 0 then
        do iCount = 1 to iObjects:
            assign oObject = poObjects:GetJsonObject(iCount). /* Grab the next object in the array. */

            /* We cannot continue if any of these values are missing. */
            if not (oObject:Has("HandleId") and oObject:Has("Source") and oObject:Has("Line")) then do:
                delete object oObject no-error.
                next.
            end.

            assign
                iHandleID = oObject:GetInteger("HandleId")
                cSource   = oObject:GetCharacter("Source")
                iLine     = oObject:GetInteger("Line")
                .

            /* Should be a unique match using these 4 fields (per the pukMain index). */
            find first bABLObject no-lock
                 where bABLObject.SampleUUID eq pcSampleUUID
                   and bABLObject.HandleId eq iHandleID
                   and bABLObject.Source eq cSource
                   and bABLObject.Line eq iLine no-error.
            if not available(bABLObject) then do:
                create bABLObject.
                assign
                    bABLObject.SampleUUID = pcSampleUUID
                    bABLObject.HandleId   = iHandleID
                    bABLObject.RequestNum = if JsonPropertyHelper:HasTypedProperty(oObject, "origRqId", JsonDataType:Number) then oObject:GetInteger("origRqId") else 0
                    bABLObject.Source     = cSource
                    bABLObject.Line       = iLine
                    bABLObject.Name       = if JsonPropertyHelper:HasTypedProperty(oObject, "Name", JsonDataType:String) then oObject:GetCharacter("Name") else "UNKNOWN"
                    bABLObject.ObjType    = if JsonPropertyHelper:HasTypedProperty(oObject, "ObjType", JsonDataType:String) then oObject:GetCharacter("ObjType") else "UNKNOWN"
                    bABLObject.Size       = if JsonPropertyHelper:HasTypedProperty( oObject, "Size", JsonDataType:Number) then oObject:GetInt64("Size") else 0
                    .
                release bABLObject no-error.
            end. /* not available */

            delete object oObject no-error.
        end. /* do iCount */

        return true. /* Return after parsing through all objects. */

        finally:
            delete object oObject no-error.
        end finally.
    end method. /* ProcessObjects */


    method private logical ProcessProfile ( input pcServerUUID as character,
                                            input pcFilePath   as character ):
        define variable cShortPath as character no-undo.
        define variable cFilename  as character no-undo.
        define variable lcProfile  as longchar  no-undo.
        define variable iAgentPID  as integer   no-undo.
        define variable iSessionID as integer   no-undo.
        define variable cSessionID as character no-undo.
        define variable cDateTime  as character no-undo.
        define variable cSessUUID  as character no-undo.
        define variable dDate      as date      no-undo.
        define variable iTime      as integer   no-undo.
        define variable dTimestamp as datetime  no-undo.

        /* Format: <agent>/<iso_date>.<mtime>_R<req>_A<agent>_S<session>.prof */
        assign cShortPath = substring(pcFilePath, length(cProfilesPath) + 1).
        oLogger:Debug(substitute("Processing Profile: &1", cShortPath)).

        /* Parse the filename and obtain contents. */
        file-info:file-name = pcFilePath.
        if file-info:full-pathname ne ? then do:
            assign
                iAgentPID = integer(entry(1, cShortPath, "/"))
                cFilename = entry(2, cShortPath, "/")
                cDateTime = entry(1, cFilename, "_")
                .

            assign dDate = this-object:iso2Date(entry(1, cDateTime, ".")).
            assign iTime = integer(entry(2, cDateTime, ".")) when num-entries(cDateTime, ".") eq 2.
            assign dTimestamp = datetime(dDate, iTime). /* Don't normalize this particular date. */

            assign /* An exact session number may not be present if profiler output generated for entire session. */
                cSessionID = replace(entry(4, cFilename, "_"), "S", "") when num-entries(cFilename, "_") ge 4
                iSessionID = integer(entry(1, cSessionID, "."))
                .

            /* Update the current session info. */
            assign cSessUUID = this-object:UpdateSession(pcServerUUID, iAgentPID, iSessionID, dTimestamp).

            /* Only read the file if profiler data does not exist for this session/time. */
            if not can-find(first ProfilerData no-lock
                            where ProfilerData.SessionUUID eq cSessUUID
                              and ProfilerData.Timestamp eq dTimestamp) then do:
                /* File is a flat file, parse and store as longchar value. */
                copy-lob from file file-info:full-pathname to lcProfile no-error.

                /* Create a timestamped record for this profiler output. */
                return this-object:SaveProfilerData(cSessUUID, dTimestamp, lcProfile).
            end. /* not available */
        end. /* file exists */

        return false. /* Unable to process file. */

        finally:
            assign lcProfile = ?.
        end finally.
    end method. /* ProcessProfile */


    method private logical ProcessRequests ( input pcServerUUID as character,
                                             input pcFilePath   as character ):
        define variable cShortPath  as character  no-undo.
        define variable cSessUUID   as character  no-undo.
        define variable cSampUUID   as character  no-undo.
        define variable cFilename   as character  no-undo.
        define variable oRequests   as JsonArray  no-undo.
        define variable iAgentPID   as integer    no-undo.
        define variable iSessionID  as integer    no-undo.
        define variable cDateTime   as character  no-undo.
        define variable dDate       as date       no-undo.
        define variable iTime       as integer    no-undo.
        define variable dTimestamp  as datetime   no-undo.

        /* Format: <agent>/<iso_date>.<mtime>_A<agent>.json */
        assign cShortPath = substring(pcFilePath, length(cRequestsPath) + 1).
        oLogger:Debug(substitute("Processing Requests: &1", cShortPath)).

        /* Parse the filename and obtain contents. */
        file-info:file-name = pcFilePath.
        if file-info:full-pathname ne ? then do:
            assign
                iAgentPID = integer(entry(1, cShortPath, "/"))
                cFilename = entry(2, cShortPath, "/")
                cDateTime = entry(1, cFilename, "_")
                .

            assign dDate = this-object:iso2Date(entry(1, cDateTime, ".")).
            assign iTime = integer(entry(2, cDateTime, ".")) when num-entries(cDateTime, ".") eq 2.
            assign dTimestamp = this-object:NormalizeDate(dDate, iTime). /* Round to nearest second. */

            /* File is in JSON format, parse and store as local array. */
            do on error undo, throw:
                define variable oParser as ObjectModelParser no-undo.

                assign dStart = now.
                assign oParser = new ObjectModelParser().
                assign oRequests = cast(oParser:ParseFile(file-info:full-pathname), JsonArray).

                oLogger:Trace(substitute("Request File Parse: &1ms", interval(now, dStart, "milliseconds"))).

                finally:
                    delete object oParser no-error.
                end finally.
            end. /* Parse File */

            /* Create the necessary support records for the session and current sample. */
            if oRequests:Length gt 0 and oRequests:GetJsonObject(1):Has("SessionId") then
                assign iSessionID = oRequests:GetJsonObject(1):GetInteger("SessionId").
            assign cSessUUID = this-object:UpdateSession(pcServerUUID, iAgentPID, iSessionID, dTimestamp).
            assign cSampUUID = this-object:UpdateSample(cSessUUID, "", dTimestamp, ?, ?).

            /* Call the common method for processing data from the parsed file. */
            return this-object:ProcessRequests(cSampUUID, dTimestamp, oRequests).
        end. /* file exists */

        return false. /* Unable to process file. */

        finally:
            delete object oRequests no-error.
        end finally.
    end method. /* ProcessRequests */


    method private logical ProcessRequests ( input pcSampleUUID as character,
                                             input pdStartEpoch as datetime,
                                             input poRequests   as JsonArray ):
        define variable oRequest     as JsonObject no-undo.
        define variable cRequestUUID as character  no-undo.
        define variable cSessionUUID as character  no-undo.
        define variable dTimestamp   as datetime   no-undo.
        define variable iRequests    as integer    no-undo.
        define variable iCount       as integer    no-undo.
        define variable iRequestNum  as integer    no-undo.
        define variable lHasEndTime  as logical    no-undo.

        define buffer bRequestInfo for RequestInfo.
        define buffer bSessionInfo for SessionInfo.
        define buffer bSessionSample for SessionSample.

        assign iRequests = poRequests:length.
        if iRequests eq 0 then return false. /* Nothing to parse. */

        oLogger:Trace(substitute("|- Processing &1 request(s) for sample '&2'.", iRequests, pcSampleUUID)).

        find first bSessionSample no-lock
             where bSessionSample.SampleUUID eq pcSampleUUID no-wait no-error.
        if not available(bSessionSample) then return false.
        assign
            cSessionUUID = bSessionSample.SessionUUID
            dTimestamp   = bSessionSample.Timestamp
            .

        find first bSessionInfo no-lock
             where bSessionInfo.SessionUUID eq cSessionUUID no-wait no-error.
        if not available(bSessionInfo) then return false.

        /* Inspect each session for start time and current memory size. */
        if iRequests gt 0 then
        do iCount = 1 to iRequests:
            assign oRequest = poRequests:GetJsonObject(iCount).

            /* Obtain the unique request number, which may be rqId or RequestNum depending on the API which provided the data. */
            if JsonPropertyHelper:HasTypedProperty(oRequest, "rqId", JsonDataType:Number) then
                assign iRequestNum = oRequest:GetInteger("rqId").
            else if JsonPropertyHelper:HasTypedProperty(oRequest, "RequestNum", JsonDataType:Number) then
                assign iRequestNum = oRequest:GetInteger("RequestNum").

            assign
                lHasEndTime  = false
                cRequestUUID = ""
                .

            /* Check if a request record exists for this server/agent/session with a given request ID. */
            find first bRequestInfo exclusive-lock
                 where bRequestInfo.ServerUUID  eq bSessionInfo.ServerUUID
                   and bRequestInfo.SessionUUID eq bSessionInfo.SessionUUID
                   and bRequestInfo.RequestNum  eq iRequestNum no-error.
            if not available(bRequestInfo) then do:
                create bRequestInfo.
                assign
                    bRequestInfo.ServerUUID  = bSessionInfo.ServerUUID
                    bRequestInfo.SessionUUID = bSessionInfo.SessionUUID
                    bRequestInfo.SampleUUID  = pcSampleUUID
                    bRequestInfo.RequestNum  = iRequestNum
                    bRequestInfo.RequestUUID = encode(substitute("&1.&2", bSessionInfo.SessionUUID, iRequestNum)) /* Per-request key for callstack data. */
                    .
            end. /* not available */

            /* Add basic data to the request record, or update specific items as necessary. */
            if available(bRequestInfo) then do:
                assign
                    /**
                     * The "Client Request ID" was added in OE11.7.4 and OE12.x, so check appropriately if it exists before attempting to utilize.
                     * This property name is different between data payloads depending on the source API, and even changed between 12.1 and 12.2.
                     */
                    bRequestInfo.ClientID     = if JsonPropertyHelper:HasTypedProperty(oRequest, "cRqstId", JsonDataType:String) then oRequest:GetCharacter("cRqstId")
                                                else if JsonPropertyHelper:HasTypedProperty(oRequest, "requestID", JsonDataType:String) then oRequest:GetCharacter("requestID")
                                                else if JsonPropertyHelper:HasTypedProperty(oRequest, "ClientId", JsonDataType:String) then oRequest:GetCharacter("ClientId")
                                                else "-"
                    bRequestInfo.ConnectionID = if JsonPropertyHelper:HasTypedProperty(oRequest, "ConnectionId", JsonDataType:Number)
                                                then oRequest:GetInteger("ConnectionId")
                                                else 0
                    bRequestInfo.ProcName     = if oRequest:Has("entryPoint") then oRequest:GetCharacter("entryPoint")
                                                else if oRequest:Has("RequestProcName") then oRequest:GetCharacter("RequestProcName")
                                                else ""
                    bRequestInfo.StartTime    = if JsonPropertyHelper:HasTypedProperty(oRequest, "start", JsonDataType:Number)
                                                then add-interval(pdStartEpoch, oRequest:GetInteger("start"), "milliseconds")
                                                else if JsonPropertyHelper:HasTypedProperty(oRequest, "StartTime", JsonDataType:String) then oRequest:GetDatetime("StartTime")
                                                else dTimestamp
                    bRequestInfo.EndTime      = if JsonPropertyHelper:HasTypedProperty(oRequest, "EndTime", JsonDataType:String) then oRequest:GetDatetime("EndTime") else ?
                    bRequestInfo.Elapsed      = 0
                    .

                /* Add some context about this request, so we can find it in the intake log later if necessary. */
                oLogger:Debug(substitute("|-- Added request #&1 with ID '&2'.", bRequestInfo.RequestNum, bRequestInfo.ClientID)).

                /* If a request has been marked as finished then update the end time and duration values. */
                if oRequest:Has("finished") and oRequest:GetCharacter("finished") eq "true" then do:
                    /* Ignore any given end time, and just log the elapsed time (request time so far). */
                    if JsonPropertyHelper:HasTypedProperty(oRequest, "duration", JsonDataType:Number) then do:
                        assign bRequestInfo.Elapsed = oRequest:GetInteger("duration").
                        assign bRequestInfo.EndTime = add-interval(bRequestInfo.StartTime, bRequestInfo.Elapsed, "milliseconds").
                    end.
                end. /* finished */

                /* Calculate the elapsed time if there is none present but an end time does exist. */
                if bRequestInfo.Elapsed eq 0 and bRequestInfo.EndTime ne ? then
                    assign bRequestInfo.Elapsed = interval(bRequestInfo.EndTime, bRequestInfo.StartTime, "milliseconds").

                /* Parse the Client Request ID when present and matching the expected format. */
                if (bRequestInfo.ClientID gt "") eq true and num-entries(bRequestInfo.ClientID, ":") ge 3 then do:
                    assign
                        bRequestInfo.WebAppName = entry(1, bRequestInfo.ClientID, ":")
                        bRequestInfo.Transport  = caps(entry(2, bRequestInfo.ClientID, ":"))
                        bRequestInfo.RequestID  = entry(3, bRequestInfo.ClientID, ":")
                        .
                end. /* ClientID is WebApp:Transport:Request */
                else if (bRequestInfo.ClientID gt "") eq true then do:
                    assign
                        bRequestInfo.WebAppName = if JsonPropertyHelper:HasTypedProperty(oRequest, "WebApp", JsonDataType:String) then oRequest:GetCharacter("WebApp")
                                                  else "-"
                            bRequestInfo.Transport  = if JsonPropertyHelper:HasTypedProperty(oRequest, "Transport", JsonDataType:String) then oRequest:GetCharacter("Transport")
                                                  else "-"
                        bRequestInfo.RequestID  = bRequestInfo.ClientID
                        .
                end. /* ClientID is simply non-blank */

                /* Mark some items for use in the next steps. */
                assign
                    lHasEndTime  = bRequestInfo.EndTime ne ?
                    cRequestUUID = bRequestInfo.RequestUUID
                    .

                release bRequestInfo no-error.
            end. /* available, not locked */

            /* If the completed request has any Objects, parse accordingly (typical for the LiveDiag metrics). */
            if lHasEndTime and JsonPropertyHelper:HasTypedProperty(oRequest, "Objects", JsonDataType:Array) then do:
                /* Log the current ABLObjects for this agent-session as of this moment. */
                oLogger:Debug(substitute("|- Processing ABLObjects: A&1 S&2", bSessionInfo.AgentPID, bSessionInfo.SessionID)).
                find current bSessionSample exclusive-lock.
                assign bSessionSample.ObjectCount = bSessionSample.ObjectCount + oRequest:GetJsonArray("Objects"):length.
                this-object:ProcessObjects(pcSampleUUID, oRequest:GetJsonArray("Objects")).
            end. /* Objects */

            if (cRequestUUID gt "") eq true then do:
                /* If the request data has a CallStack, parse accordingly (typical for the LiveDiag metrics). */
                if JsonPropertyHelper:HasTypedProperty(oRequest, "Callstack", JsonDataType:Array) then do:
                    /* Only attempt to create new CallStack records if none exists for this request. */
                    find first CallStack no-lock where CallStack.RequestUUID eq cRequestUUID no-error.
                    if not available(CallStack) then
                        this-object:ProcessCallStack(cRequestUUID, oRequest:GetJsonArray("Callstack")).
                end. /* CallStack */

                /* If the request data has a CallTree, parse accordingly (typical for the LiveDiag metrics). */
                if JsonPropertyHelper:HasTypedProperty(oRequest, "calltree", JsonDataType:Array) then do:
                    /* Only attempt to create new CallTree records if none exists for this request. */
                    find first CallTree no-lock where CallTree.RequestUUID eq cRequestUUID no-error.
                    if not available(CallTree) then
                        this-object:ProcessCallTree(cRequestUUID, oRequest:GetJsonArray("calltree")).
                end. /* CallTree */
            end. /* cRequestUUID */

            delete object oRequest no-error.
        end. /* do iCount */

        return true.

        catch err as Progress.Lang.Error:
            /* Log an error but keep going. */
            oLogger:Error(substitute("Error while processing requests: &1", err:GetMessage(1))).
            return false.
        end catch.
        finally:
            release bSessionSample no-error.
            delete object oRequest no-error.
        end finally.
    end method. /* ProcessRequests */


    method private logical ProcessCallStack ( input pcRequestUUID as character,
                                              input poData        as JsonArray ):
        define variable iCount as integer    no-undo.
        define variable oObj   as JsonObject no-undo.

        do iCount = 1 to poData:Length:
            assign oObj = poData:GetJsonObject(iCount).

            create CallStack.
            assign
                CallStack.RequestUUID = pcRequestUUID
                CallStack.StackOrder  = iCount
                CallStack.Line        = oObj:GetInteger("Line")
                CallStack.Routine     = oObj:GetCharacter("Routine")
                CallStack.Source      = oObj:GetCharacter("Source")
                .
            release CallStack no-error.

            delete object oObj no-error.
        end. /* do iCount */

        return true.

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("|- Error while processing CallStack: &1 [&2].", err:GetMessage(1), pcRequestUUID)).
            return false.
        end catch.
        finally:
            delete object oObj no-error.
            oLogger:Trace(substitute("|- Saved &1 CallStack items for request '&2'.",
                                     trim(string(iCount, ">>>,>>>,>>9")), pcRequestUUID)).
        end finally.
    end method. /* ProcessCallStack */


    method private logical ProcessCallTree ( input pcRequestUUID as character,
                                             input poData        as JsonArray ):
        create CallTree.
        assign
            CallTree.RequestUUID = pcRequestUUID
            CallTree.Data        = poData:GetJsonText()
            .

        return true.

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("|- Error while processing CallTree: &1 [&2].", err:GetMessage(1), pcRequestUUID)).
            return false.
        end catch.
        finally:
            oLogger:Trace(substitute("|- Saved &1 CallTree items (&2kb) for request '&3'.",
                                     trim(string(poData:Length, ">>>,>>>,>>9")),
                                     trim(string(length(CallTree.Data, "raw") / 1024, ">>>,>>>,>>9.999")),
                                     pcRequestUUID)).
            release CallTree no-error.
        end finally.
    end method. /* ProcessCallTree */


    method private logical ProcessSessions ( input pcServerUUID as character,
                                             input pcFilePath   as character ):
        define variable cShortPath as character  no-undo.
        define variable cFilename  as character  no-undo.
        define variable oSessions  as JsonArray  no-undo.
        define variable iAgentPID  as integer    no-undo.
        define variable cDateTime  as character  no-undo.
        define variable dDate      as date       no-undo.
        define variable iTime      as integer    no-undo.
        define variable dTimestamp as datetime   no-undo.

        /* Format: <agent>/<iso_date>.<mtime>_A<agent>.json */
        assign cShortPath = substring(pcFilePath, length(cSessionsPath) + 1).
        oLogger:Debug(substitute("|- Processing Sessions: &1", cShortPath)).

        /* Parse the filename and obtain contents. */
        file-info:file-name = pcFilePath.
        if file-info:full-pathname ne ? then do:
            assign
                iAgentPID = integer(entry(1, cShortPath, "/"))
                cFilename = entry(2, cShortPath, "/")
                cDateTime = entry(1, cFilename, "_")
                .

            assign dDate = this-object:iso2Date(entry(1, cDateTime, ".")).
            assign iTime = integer(entry(2, cDateTime, ".")) when num-entries(cDateTime, ".") eq 2.
            assign dTimestamp = this-object:NormalizeDate(dDate, iTime). /* Round to nearest second. */

            /* File is in JSON format, parse and store as local array. */
            do on error undo, throw:
                define variable oParser as ObjectModelParser no-undo.

                assign dStart = now.
                assign oParser = new ObjectModelParser().
                assign oSessions = cast(oParser:ParseFile(file-info:full-pathname), JsonArray).

                delete object oParser no-error.
                oLogger:Trace(substitute("Session File Parse: &1ms", interval(now, dStart, "milliseconds"))).
            end. /* Parse File */

            /* Call the common method for processing data from the parsed file. */
            return this-object:ProcessSessions(pcServerUUID, dTimestamp, iAgentPID, "", oSessions).
        end. /* file exists */

        return false. /* Unable to process file. */

        finally:
            delete object oSessions no-error.
        end finally.
    end method. /* ProcessSessions */


    method private logical ProcessSessions ( input pcServerUUID as character,
                                             input pdTimestamp  as datetime,
                                             input piAgentPID   as integer,
                                             input pcGroupName  as character,
                                             input poSessions   as JsonArray ):
        define variable oSession   as JsonObject no-undo.
        define variable iCount     as integer    no-undo.
        define variable iSessionID as integer    no-undo.
        define variable cSessUUID  as character  no-undo.
        define variable cSampUUID  as character  no-undo.

        if poSessions:Length eq 0 then return false. /* Nothing to parse. */

        /* Inspect each session for start time and current memory size. */
        do iCount = 1 to poSessions:length:
            assign oSession = poSessions:GetJsonObject(iCount).

            /* Continue if session was not assigned to a thread. */
            if oSession:GetInteger("ThreadId") lt 0 then next.

            assign iSessionID = oSession:GetInteger("SessionId").

            /* Update the current session info, recording the start time. */
            assign cSessUUID = this-object:UpdateSession(pcServerUUID,
                                                         piAgentPID,
                                                         iSessionID,
                                                         oSession:GetDatetime("StartTime")).

            /* Record the current session memory size for this sample. */
            assign cSampUUID = this-object:UpdateSample(cSessUUID, pcGroupName, pdTimestamp, oSession:GetInt64("SessionMemory"), ?).

            delete object oSession no-error.
        end. /* do iCount */

        return true.

        catch err as Progress.Lang.Error:
            /* Log an error but keep going. */
            oLogger:Error(substitute("|- Error while processing sessions: &1", err:GetMessage(1))).
            return false.
        end catch.
        finally:
            delete object oSession no-error.
        end finally.
    end method. /* ProcessSessions */


    method private logical ProcessAgentLog ( input pcServerUUID as character,
                                             input piAgentPID   as integer,
                                             input piMsgSeqNum  as int64,
                                             input piMsgCount   as int64,
                                             input pdTimestamp  as datetime-tz,
                                             input plcMessages  as longchar ):
        create AgentLogRaw.
        assign
            AgentLogRaw.ServerUUID  = pcServerUUID
            AgentLogRaw.AgentPID    = piAgentPID
            AgentLogRaw.Timestamp   = pdTimestamp
            AgentLogRaw.MsgSequence = piMsgSeqNum
            AgentLogRaw.MsgCount    = piMsgCount
            .

        /* Copy the longchar value to the target CLOB field. */
        copy-lob from plcMessages to AgentLogRaw.MessageData no-error.

        return true.

        catch err as Progress.Lang.Error:
            /* Log an error but keep going. */
            oLogger:Error(substitute("Error while processing agent log: &1", err:GetMessage(1))).
            return false.
        end catch.
        finally:
            release AgentLogRaw no-error.
            oLogger:Trace(substitute("Saved &1kb of log messages for agent '&2'", trim(string(length(plcMessages, "raw") / 1024, ">>>,>>>,>>9.999")), piAgentPID)).
        end finally.
    end method. /* ProcessAgentLog */


    method private void ProcessAccessLog ( input pcServerUUID as character,
                                           input plcAccessLog as longchar ):
        define variable iCount    as integer     no-undo.
        define variable iLines    as integer     no-undo.
        define variable iLine     as integer     no-undo.
        define variable iLoop     as integer     no-undo.
        define variable iCode     as integer     no-undo.
        define variable iBytes    as integer     no-undo.
        define variable iTime     as integer     no-undo.
        define variable cLine     as character   no-undo.
        define variable cLogMsg   as character   no-undo.
        define variable cRequest  as character   no-undo.
        define variable cResponse as character   no-undo.
        define variable cEntry    as character   no-undo.
        define variable cAccess   as character   no-undo.
        define variable cVerb     as character   no-undo.
        define variable cPath     as character   no-undo.
        define variable cReqID    as character   no-undo.
        define variable cThread   as character   no-undo.
        define variable cUser     as character   no-undo.
        define variable dStart    as datetime-tz no-undo.
        define variable dEnd      as datetime-tz no-undo.

        assign iLines = num-entries(plcAccessLog, "~n").
        oLogger:Info(substitute("Parsing access log with &1 lines...", iLines)).

        if iLines ge 1 then logblk:
        do iLine = 1 to iLines:
            /**
             * Import the log line, expecting the following formats:
             *  %h %u [%{yyyy-MM-dd'T'HH:mm:ss.SSSZ}t] "%r" %s %b %D %I %S
             *  %h %{OEReq.userId}r [%{yyyy-MM-dd'T'HH:mm:ss.SSSZ}t] “%r” %s %b %D %{OEReq.requestId}r
             *  %h %l %reqAttribute{OEReq.userId} [%date{"yyyy-MM-dd'T'HH:mm:ss.SSSXXX"}] "%r" %s %b %D %reqAttribute{OEReq.requestId} %n
             *  %h %l %reqAttribute{OEReq.userId} [%date{"yyyy-MM-dd'T'HH:mm:ss.SSSXXX"}] "%r" %s %b %reqAttribute{OEReq.requestId} %D %n
             *
             * Set format as psc.as.accesslog.pattern in conf/catalina.properties for OE11
             * or as psc.as.logging.access.pattern in conf/logging-tomcat.properties for OE12
             */
            assign cLine = entry(iLine, plcAccessLog, "~n").
            assign cLine = replace(cLine, chr(10), "").
            assign cLine = replace(cLine, chr(13), "").
            if (trim(cLine) gt "") ne true then next logblk.

            /* Extract a username from one of the first 2 values preceeding the date. */
            assign cUser = trim(entry(2, cLine, " ")). /* %l or %{OEReq.userId}r or %reqAttribute{OEReq.userId} */
            if cUser eq "-" and not entry(3, cLine, " ") begins "[" then
                assign cUser = trim(entry(3, cLine, " ")). /* %{OEReq.userId}r or %reqAttribute{OEReq.userId} */

            /**
             * Extract date, which should be in ISO8601 format:
             *  YYYY-MM-DDTHH:MM:SS.SSS+HH:MM
             *
             * In some cases the date may or may not include a colon in the timezone, eg. -0400 vs. -04:00
             * This affects the string length as either 28 or 29, so we must be aware during extraction.
             *
             * And for ease of parsing, anything after the date should be processed as a new string.
             */
            assign
                cAccess = trim(substring(cLine, index(cLine, "[") + 1, 29)) /* ISO-8601 Access Time */
                cLogMsg = trim(substring(cLine, index(cLine, "]") + 1)) /* Everything Else */
                .

            /* Massage the data for the date string and attempt to convert to a Datetime-TZ value. */
            assign cAccess = trim(replace(cAccess, "]", "")). /* Make sure any end bracket is removed. */
            if index(substring(cAccess, 27, 28), ":") gt 0 then
                assign cAccess = substring(cAccess, 1, 29). /* Timezone component already has a colon in the value. */
            else
                assign cAccess = substring(cAccess, 1, 26) + ":" + substring(cAccess, 27, 28). /* Must add a colon. */
            assign dEnd = this-object:iso2DateTZ(cAccess) no-error.
            if error-status:error then next logblk. /* Could not parse date, just skip to next entry. */

            /**
             * In addition to the request timestamp, notable tokens may include:
             *  %l - Remote logical username from identd (always returns '-')
             *  %{OEReq.userId}r or %reqAttribute{OEReq.userId} - username@domain
             *  %r - First line of the request
             *  %s - HTTP status code of the response
             *  %b - Bytes sent, excluding HTTP headers, or '-' if no bytes were sent
             *  %D - Time taken to process the request, in millis
             *  %I - Thread in Tomcat which served the request
             *  %S - Session ID
             *  %{OEReq.requestId}r or %reqAttribute{OEReq.requestId} - Unique request identifier (webapp:transport:value)
             *  %n - Inserts a newline
             */
            assign cRequest = trim(entry(2, cLogMsg, '"')).
            assign cResponse = trim(entry(3, cLogMsg, '"')).

            assign /* Process the request portion into verb and path. */
                cVerb = entry(1, cRequest, " ") /* %r */
                cPath = entry(2, cRequest, " ") /* %r */
                .

            do iLoop = 1 to num-entries(cResponse, " "):
                assign cEntry = trim(entry(iLoop, cResponse, " ")).

                case iLoop:
                    when 1 then /* Assumed %s */
                        assign iCode = integer(cEntry).
                    when 2 then /* Assumed %b */
                        assign iBytes = integer(cEntry).
                    when 3 then do:
                        /* Assumed %D, but could be requestId */
                        if cEntry eq "-" or cEntry matches "*:*:*" then
                            assign iTime = 0. /* Not the elapsed time value. */
                        else
                            assign iTime = integer(cEntry).
                    end.
                    when 4 then do: /* Assumed %D */
                        assign iTime = integer(cEntry).
                    end.
                end case.

                /* %I value should begin with a "thd-" prefix. */
                if cEntry begins "thd-" then
                    assign cThread = replace(cEntry, "thd-", "").

                /* %{OEReq.requestId}r or %reqAttribute{OEReq.requestId} */
                if cEntry eq "-" or cEntry matches "*:*:*" then
                    assign cReqID = cEntry.
            end. /* do iLoop */

            if iTime gt 0 then /* Calculate start time using end timestamp and elapsed time. */
                assign dStart  = add-interval(dEnd, (iTime * -1), "milliseconds").

            if cReqID eq "-" then assign cReqID = "". /* Treat "-" value as blank string. */

            find first AccessLog exclusive-lock
                 where AccessLog.ServerUUID eq pcServerUUID
                   and AccessLog.RequestStart eq dStart no-error.
            if not available(AccessLog) then do:
                create AccessLog.
                assign
                    AccessLog.ServerUUID   = pcServerUUID
                    AccessLog.RequestStart = dStart
                    AccessLog.RequestEnd   = dEnd
                    AccessLog.RequestVerb  = cVerb
                    AccessLog.RequestPath  = cPath
                    AccessLog.ResponseCode = iCode
                    AccessLog.ResponseSize = iBytes
                    AccessLog.ResponseTime = iTime
                    AccessLog.Username     = cUser
                    AccessLog.WebAppName   = entry(1, cReqID, ":") when (cReqID gt "") eq true
                    AccessLog.Transport    = caps(entry(2, cReqID, ":")) when (cReqID gt "") eq true
                    AccessLog.RequestID    = entry(3, cReqID, ":") when (cReqID gt "") eq true
                    .

                if AccessLog.WebAppName eq "" then
                    assign AccessLog.WebAppName = entry(1, cPath, "/").

                if AccessLog.Transport eq "" then
                case entry(3, cPath, "/"):
                    when "static" then
                        assign AccessLog.Transport = "F".
                    when "apsv" then
                        assign AccessLog.Transport = "A".
                    when "rest" then
                        assign AccessLog.Transport = "R".
                    when "soap" then
                        assign AccessLog.Transport = "S".
                    when "web" then
                        assign AccessLog.Transport = "W".
                end case.

                if (cThread gt "") eq true then
                    assign AccessLog.ThreadID = if cThread eq "null" then ? else integer(cThread).
            end. /* not available */

            /* After processing, only keep log entries which utilize certain transports/paths. */
            if AccessLog.RequestPath matches "*/static/auth/*" or
               AccessLog.RequestPath matches "*/apsv*" or
               AccessLog.RequestPath matches "*/rest/*" or
               AccessLog.RequestPath matches "*/soap/*" or
               AccessLog.RequestPath matches "*/web/*" then
                release AccessLog no-error.
            else
                delete AccessLog.

            assign iCount = iCount + 1.
        end. /* do iLine */

        oLogger:Info(substitute("Processed &1 lines successfully.", iCount)).
    end method. /* ProcessAccessLog */


    method private logical SaveProfilerData ( input pcSessionUUID as character,
                                              input pdTimestamp   as datetime,
                                              input plcProfile    as longchar ):
        create ProfilerData.
        assign
            ProfilerData.SessionUUID  = pcSessionUUID
            ProfilerData.Timestamp    = pdTimestamp
            ProfilerData.ProfileBytes = length(plcProfile, "raw")
            .

        /* Copy the longchar value to the target CLOB field. */
        copy-lob from plcProfile to ProfilerData.CodeProfile no-error.

        return true.

        finally:
            release ProfilerData no-error.
        end finally.
    end method. /* SaveProfilerData */


    method private void doProfilerCleanup ( input pcSessionUUID as character ):
        define variable iRecord as integer no-undo.
        define variable iBatch  as integer no-undo initial 10000.

        define buffer bProfilerData for ProfilerData.

        assign dStart = now.

        outer:
        do while true transaction:
            for each bProfilerData exclusive-lock
               where bProfilerData.SessionUUID eq pcSessionUUID:
                assign iRecord = iRecord + 1.
                delete bProfilerData.

                /* Commit the current transaction(iteration) and proceed with the next.
                 * This will restart the FOR EACH block with the new first record.
                 */
                if (iRecord modulo iBatch) eq 0 then oLogger:Debug(substitute("Completed batch of &1 profiler data deletions", iBatch)).
                if (iRecord modulo iBatch) eq 0 then next outer.
            end. /* for each ProfilerData */
            leave.
        end. /* do while */

        oLogger:Debug(substitute("Purged profiler data in &1ms", trim(string(interval(now, dStart, "milliseconds"), ">>>,>>>,>>9")))).
    end method. /* doProfilerCleanup */


    method private void doObjectCleanup ( input pcSessionUUID as character ):
        define variable iRecord as integer no-undo.
        define variable iBatch  as integer no-undo initial 10000.

        define buffer bSessionSample for SessionSample.
        define buffer bABLObject for ABLObject.

        assign dStart = now.

        for each bSessionSample no-lock
           where bSessionSample.SessionUUID eq pcSessionUUID:
            outer:
            do while true transaction:
                for each bABLObject exclusive-lock
                   where bABLObject.SampleUUID eq bSessionSample.SampleUUID:
                    assign iRecord = iRecord + 1.
                    delete bABLObject.

                    /* Commit the current transaction(iteration) and proceed with the next.
                     * This will restart the FOR EACH block with the new first record.
                     */
                    if (iRecord modulo iBatch) eq 0 then oLogger:Debug(substitute("Completed batch of &1 object deletions", iBatch)).
                    if (iRecord modulo iBatch) eq 0 then next outer.
                end. /* for each ABLObject */
                leave.
            end. /* do while */
        end. /* for each bSessionSample */

        oLogger:Debug(substitute("Purged objects in &1ms", trim(string(interval(now, dStart, "milliseconds"), ">>>,>>>,>>9")))).
    end method. /* doObjectCleanup */


    method private void doRequestCleanup ( input pcSessionUUID as character ):
        define variable iRecord as integer no-undo.
        define variable iBatch  as integer no-undo initial 10000.

        define buffer bRequestInfo for RequestInfo.

        assign dStart = now.

        outer:
        do while true transaction:
            for each bRequestInfo exclusive-lock
               where bRequestInfo.SessionUUID eq pcSessionUUID:
                assign iRecord = iRecord + 1.
                delete bRequestInfo.

                /* Commit the current transaction(iteration) and proceed with the next.
                 * This will restart the FOR EACH block with the new first record.
                 */
                if (iRecord modulo iBatch) eq 0 then oLogger:Debug(substitute("Completed batch of &1 request deletions", iBatch)).
                if (iRecord modulo iBatch) eq 0 then next outer.
            end. /* for each RequestInfo */
            leave.
        end. /* do while */

        oLogger:Debug(substitute("Purged requests in &1ms", trim(string(interval(now, dStart, "milliseconds"), ">>>,>>>,>>9")))).
    end method. /* doRequestCleanup */


    method private void doAgentCleanup ( input pcServerUUID as character,
                                         input pdPurgeDate   as datetime ):
        define variable iRecord as integer no-undo.
        define variable iBatch  as integer no-undo initial 10000.

        define buffer bAgentSample for AgentSample.

        assign dStart = now.

        outer:
        do while true transaction:
            for each bAgentSample exclusive-lock
               where bAgentSample.ServerUUID eq pcServerUUID
                 and bAgentSample.Timestamp lt pdPurgeDate:
                assign iRecord = iRecord + 1.
                delete bAgentSample.

                /* Commit the current transaction(iteration) and proceed with the next.
                 * This will restart the FOR EACH block with the new first record.
                 */
                if (iRecord modulo iBatch) eq 0 then oLogger:Debug(substitute("Completed batch of &1 agent sample deletions", iBatch)).
                if (iRecord modulo iBatch) eq 0 then next outer.
            end.
            leave.
        end. /* do while */

        oLogger:Debug(substitute("Purged agent samples in &1ms", trim(string(interval(now, dStart, "milliseconds"), ">>>,>>>,>>9")))).
    end method. /* doAgentCleanup */


    method private void doSampleCleanup ( input pcSessionUUID as character ):
        define variable iRecord as integer no-undo.
        define variable iBatch  as integer no-undo initial 10000.

        define buffer bSessionSample for SessionSample.

        assign dStart = now.

        outer:
        do while true transaction:
            for each bSessionSample exclusive-lock
               where bSessionSample.SessionUUID eq pcSessionUUID:
                assign iRecord = iRecord + 1.
                delete bSessionSample.

                /* Commit the current transaction(iteration) and proceed with the next.
                 * This will restart the FOR EACH block with the new first record.
                 */
                if (iRecord modulo iBatch) eq 0 then oLogger:Debug(substitute("Completed batch of &1 session sample deletions", iBatch)).
                if (iRecord modulo iBatch) eq 0 then next outer.
            end.
            leave.
        end. /* do while */

        oLogger:Debug(substitute("Purged session samples in &1ms", trim(string(interval(now, dStart, "milliseconds"), ">>>,>>>,>>9")))).
    end method. /* doSampleCleanup */


    method private void dumpRequests ( input piAgentPID as integer ):
        define buffer bSessionInfo for SessionInfo.
        define buffer bRequestInfo for RequestInfo.

        empty temp-table AgentRequest.

        /* Dump the RequestInfo by agent PID, matching the RequestMetrics output format. */
        for each bSessionInfo no-lock
           where bSessionInfo.AgentPID eq piAgentPID,
            each bRequestInfo no-lock
           where bRequestInfo.SessionUUID eq bSessionInfo.SessionUUID:
            create AgentRequest.
            assign
                AgentRequest.RequestProcName = bRequestInfo.ProcName
                AgentRequest.SessionId       = bSessionInfo.SessionID
                AgentRequest.ConnectionId    = bRequestInfo.ConnectionID
                AgentRequest.StartTime       = bRequestInfo.StartTime
                AgentRequest.EndTime         = bRequestInfo.EndTime
                AgentRequest.RequestNum      = bRequestInfo.RequestNum
                AgentRequest.BrokerSessionId = bRequestInfo.RequestUUID
                AgentRequest.ClientId        = bRequestInfo.ClientID
                AgentRequest.RequestLen      = bRequestInfo.Elapsed
                AgentRequest.Transport       = bRequestInfo.Transport
                AgentRequest.RequestStatus   = 0
                .
        end. /* each SessionInfo, each RequestInfo */

        /* Overwrite the last dumped file for this agent on each run. */
        temp-table AgentRequest:write-json("file", substitute("&1/AgentRequest_&2.json", this-object:TemporaryDir, piAgentPID), true).

        catch err as Progress.Lang.Error:
            /* Log an error but keep going. */
            oLogger:Error(substitute("Error while dumping requests: &1", err:GetMessage(1))).
        end catch.
    end method. /* dumpRequests */


    /***** Public Methods *****/


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/applications", alias="applications", mediaType="application/json").
    method public void ListApplications ( output applicationNames as JsonArray ):
        assign applicationNames = new JsonArray().

        for each ServerInfo:
            applicationNames:Add(ServerInfo.ServerName + "/" + ServerInfo.ApplicationName).
        end.
    end method. /* ListApplications */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/accessLogs", alias="accessLogs", mediaType="application/json").
    method public void ParseAccessLogs ( input  applicationName as character,
                                         input  serverName      as character,
                                         output success         as logical,
                                         output processed       as datetime ):
        /* Make sure an application name is provided by the request. */
        if (applicationName gt "") ne true then undo, throw new AppError("Application Name Missing", 0).

        /* Ensure this app/server combo exists in the config. */
        this-object:UpdateConfig(applicationName, serverName).

        /* Obtain a unique ID for this application/server combination, creating any records as necessary. */
        define variable cServerUUID as character no-undo. /* UUID to pass in lieu of application/server. */
        assign cServerUUID = this-object:UpdateServer(applicationName, serverName).

        /**
         * Get a recursive list of files from the specified directory.
         */
        define variable oDirs as JsonArray no-undo.
        define variable cRoot as character no-undo.
        if ttConfig.LogsLocation begins "C:" then
            assign cRoot = ttConfig.LogsLocation.
        else
            assign cRoot = substitute("&1/intake/&2", this-object:TemporaryDir, ttConfig.LogsLocation).
        oLogger:Debug(substitute("Reading Access Logs from Location: &1", cRoot)).
        file-info:file-name = cRoot.
        if file-info:full-pathname ne ? then
            assign oDirs = Common.OSTools:recurseDir(file-info:full-pathname, true).
        else
            assign oDirs = new JsonArray().

        define variable iCount    as integer    no-undo.
        define variable oItem     as JsonObject no-undo.
        define variable cFilename as character  no-undo.
        define variable cFilePath as character  no-undo.
        define variable lcAccess  as longchar   no-undo.

        /* Parse through the list of files looking for access log files. */
        oLogger:Debug(substitute("Found &1 potential directory items(s) to parse.", oDirs:length)).
        do iCount = 1 to oDirs:length:
            /* Parse through all the directories and files, looking for certain items. */
            assign oItem = oDirs:GetJsonObject(iCount).
            if oItem:Has("FileName") then do:
                assign
                    cFilename = oItem:GetCharacter("FileName")
                    cFilePath = oItem:GetCharacter("FullPath")
                    .

                if cFilename matches "localhost_access_log*" then do:
                    oLogger:Debug(substitute("|- Processing Access Log: &1", cFilename)).

                    copy-lob from file cFilePath to lcAccess no-error.
                    this-object:ProcessAccessLog(cServerUUID, lcAccess).
                end. /* Localhost Access */
            end. /* Valid Item */
        end. /* do ix */

        assign
            success   = true
            processed = now
            .

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error: &1", err:GetMessage(1))).
            assign
                success   = false
                processed = now
                .
        end catch.
        finally:
            release ttConfig no-error.
            delete object oDirs no-error.
            delete object oItem no-error.
        end finally.
    end method. /* ParseAccessLogs */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/ablMetrics", alias="ablMetrics", mediaType="application/json").
    method public void ReadMetrics ( input  applicationName as character,
                                     input  serverName      as character,
                                     input  processObjects  as logical,
                                     input  processProfiles as logical,
                                     input  processRequests as logical,
                                     input  processSessions as logical,
                                     output success         as logical,
                                     output processed       as datetime ):
        /* Make sure an application name is provided by the request. */
        if (applicationName gt "") ne true then undo, throw new AppError("Application Name Missing", 0).

        /* Ensure this app/server combo exists in the config. */
        this-object:UpdateConfig(applicationName, serverName).

        /* Obtain a unique ID for this application/server combination, creating any records as necessary. */
        define variable cServerUUID as character no-undo. /* UUID to pass in lieu of application/server. */
        assign cServerUUID = this-object:UpdateServer(applicationName, serverName).

        empty temp-table ttFiles.

        /**
         * Get a recursive list of files from the specified directory. Note that this
         * will return ALL directories and files, so the list could be quite extensive
         * if the monitoring solution has been running for some time. We need to be
         * cautious in the next steps how we parse through the data.
         */
        define variable oDirs as JsonArray no-undo.
        define variable cRoot as character no-undo.
        if ttConfig.MetricsLocation begins "C:" then
            assign cRoot = ttConfig.MetricsLocation.
        else
            assign cRoot = substitute("&1/intake/&2", this-object:TemporaryDir, ttConfig.MetricsLocation).
        oLogger:Debug(substitute("Reading Metrics Files from Location: &1", cRoot)).
        file-info:file-name = cRoot.
        if file-info:full-pathname ne ? then
            assign oDirs = Common.OSTools:recurseDir(file-info:full-pathname, false).
        else
            assign oDirs = new JsonArray().

        define variable oItem      as JsonObject no-undo.
        define variable iCount     as integer    no-undo.
        define variable iObjTotal  as integer    no-undo.
        define variable iObjCount  as integer    no-undo.
        define variable iProfTotal as integer    no-undo.
        define variable iProfCount as integer    no-undo.
        define variable iReqTotal  as integer    no-undo.
        define variable iReqCount  as integer    no-undo.
        define variable iSessTotal as integer    no-undo.
        define variable iSessCount as integer    no-undo.
        define variable lSuccess   as logical    no-undo.
        define variable cFilename  as character  no-undo.
        define variable cFilePath  as character  no-undo.
        define variable dProcLimit as datetime   no-undo.
        define variable dProcStart as datetime   no-undo.

        assign
            lHasObjects   = false
            lHasProfiles  = false
            lHasRequests  = false
            lHasSessions  = false
            cObjectsPath  = ""
            cProfilesPath = ""
            cRequestsPath = ""
            cSessionsPath = ""
            .

        /* Parse through the list of directories, searching for specific folders.  */
        /* This should build up the initial list of files for each type of metric. */
        oLogger:Debug(substitute("Found &1 potential directory item(s) to parse.", oDirs:length)).
        do iCount = 1 to oDirs:length:
            /* Parse through all the directories and files, looking for certain items. */
            assign oItem = oDirs:GetJsonObject(iCount).

            if valid-object(oItem) and oItem:Has("FileName") and oItem:Has("FullPath") and
               JsonPropertyHelper:HasTypedProperty(oItem, "isDir", JsonDataType:Boolean) then do:
                assign
                    cFilename = oItem:GetCharacter("FileName")
                    cFilePath = oItem:GetCharacter("FullPath")
                    .

                /* We should come across certain top-level directories first, so check which ones exist. */
                if oItem:GetLogical("isDir") and can-do({&TOP_LEVEL_DIRS}, cFilename) then do:
                    oLogger:Debug(substitute("Found Top-Level Directory: &1", cFilename)).

                    /* Should be a top-level directory we care about. */
                    case cFilename:
                        when "ABLObjects" then
                            assign
                                lHasObjects  = true
                                cObjectsPath = cFilePath
                                .
                        when "ProfilerData" then
                            assign
                                lHasProfiles  = true
                                cProfilesPath = cFilePath
                                .
                        when "Requests" then
                            assign
                                lHasRequests  = true
                                cRequestsPath = cFilePath
                                .
                        when "SessionData" then
                            assign
                                lHasSessions  = true
                                cSessionsPath = cFilePath
                                .
                        otherwise
                            . /* Do nothing for other top-level directories. */
                    end case. /* FileName */
                end. /* is a top-level folder */
                else if not oItem:GetLogical("isDir") then do:
                    assign lSuccess  = false. /* Reset flag. */

                    /* Check for files of the available top-level folders. */
                    case true:
                        when lHasObjects and processObjects and cFilePath begins cObjectsPath and
                             cFilename matches "*.json" then do:
                            create ttFiles.
                            assign
                                ttFiles.FilePath  = cFilePath
                                ttFiles.Processed = false
                                iObjTotal = iObjTotal + 1
                                .
                            release ttFiles no-error.
                        end. /* objects */

                        when lHasProfiles and processProfiles and cFilePath begins cProfilesPath and
                             cFilename matches "*.prof" then do:
                            create ttFiles.
                            assign
                                ttFiles.FilePath  = cFilePath
                                ttFiles.Processed = false
                                iProfTotal = iProfTotal + 1
                                .
                            release ttFiles no-error.
                        end. /* profiles */

                        when lHasRequests and processRequests and cFilePath begins cRequestsPath and
                             cFilename matches "*.json" then do:
                            create ttFiles.
                            assign
                                ttFiles.FilePath  = cFilePath
                                ttFiles.Processed = false
                                iReqTotal = iReqTotal + 1
                                .
                            release ttFiles no-error.
                        end. /* requests */

                        when lHasSessions and processSessions and cFilePath begins cSessionsPath and
                             cFilename matches "*.json" then do:
                            create ttFiles.
                            assign
                                ttFiles.FilePath  = cFilePath
                                ttFiles.Processed = false
                                iSessTotal = iSessTotal + 1
                                .
                            release ttFiles no-error.
                        end. /* sessions */
                    end case. /* not a directory */
                end. /* not a top-level folder */

            end. /* Valid Item */
        end. /* do ix */

        /* Set a limit on maximum execution time for processing (eg. time to die). */
        assign dProcLimit = add-interval(now, {&MAX_TIME_LIMIT}, "seconds").

        /* Finally, do the processing for a specific directory. */
        PROCESSBLK:
        do iCount = 1 to oDirs:length:
            /* Parse through all the directories and files, looking for certain items. */
            assign oItem = oDirs:GetJsonObject(iCount).

            if valid-object(oItem) and oItem:Has("FileName") and oItem:Has("FullPath") and
               JsonPropertyHelper:HasTypedProperty(oItem, "isDir", JsonDataType:Boolean) then do:
                assign
                    cFilename = oItem:GetCharacter("FileName")
                    cFilePath = oItem:GetCharacter("FullPath")
                    .

                /* We should come across certain top-level directories first, so check which ones exist. */
                if oItem:GetLogical("isDir") and can-do({&TOP_LEVEL_DIRS}, cFilename) then do:
                    oLogger:Info(substitute("Processing Top-Level Directory: &1", cFilename)).
                end. /* is a top-level folder */
                else if not oItem:GetLogical("isDir") then do:
                    assign lSuccess  = false. /* Reset flag. */
                    assign dProcStart = now. /* Reset timer. */

                    /* Check for files of the available top-level folders. */
                    case true:
                        when lHasObjects and processObjects and cFilePath begins cObjectsPath and
                             cFilename matches "*.json" then do:
                            assign lSuccess = this-object:ProcessObjects(cServerUUID, cFilePath).

                            for first ttFiles exclusive-lock
                                where ttFiles.FilePath eq cFilePath:
                                /* Mark as processed (or not). */
                                assign ttFiles.Processed = lSuccess.
                            end.

                            assign iObjCount = iObjCount + 1.
                            oLogger:Info(substitute("Processing Objects File: &1 of &2", iObjCount, iObjTotal)).
                            oLogger:Debug(substitute("Processed &1 in &2ms", cFilePath, interval(now, dProcStart, "milliseconds"))).
                        end. /* objects */

                        when lHasProfiles and processProfiles and cFilePath begins cProfilesPath and
                             cFilename matches "*.prof" then do:
                            assign lSuccess = this-object:ProcessProfile(cServerUUID, cFilePath).

                            for first ttFiles exclusive-lock
                                where ttFiles.FilePath eq cFilePath:
                                /* Mark as processed (or not). */
                                assign ttFiles.Processed = lSuccess.
                            end.

                            assign iProfCount = iProfCount + 1.
                            oLogger:Info(substitute("Processing Profiler File: &1 of &2", iProfCount, iProfTotal)).
                            oLogger:Debug(substitute("Processed &1 in &2ms", cFilePath, interval(now, dProcStart, "milliseconds"))).
                        end. /* profiles */

                        when lHasRequests and processRequests and cFilePath begins cRequestsPath and
                             cFilename matches "*.json" then do:
                            assign lSuccess = this-object:ProcessRequests(cServerUUID, cFilePath).

                            for first ttFiles exclusive-lock
                                where ttFiles.FilePath eq cFilePath:
                                /* Mark as processed (or not). */
                                assign ttFiles.Processed = lSuccess.
                            end.

                            assign iReqCount = iReqCount + 1.
                            oLogger:Info(substitute("Processing Requests File: &1 of &2", iReqCount, iReqTotal)).
                            oLogger:Debug(substitute("Processed &1 in &2ms", cFilePath, interval(now, dProcStart, "milliseconds"))).
                        end. /* requests */

                        when lHasSessions and processSessions and cFilePath begins cSessionsPath and
                             cFilename matches "*.json" then do:
                            assign lSuccess = this-object:ProcessSessions(cServerUUID, cFilePath).

                            for first ttFiles exclusive-lock
                                where ttFiles.FilePath eq cFilePath:
                                /* Mark as processed (or not). */
                                assign ttFiles.Processed = lSuccess.
                            end.

                            assign iSessCount = iSessCount + 1.
                            oLogger:Info(substitute("Processing Sessions File: &1 of &2", iSessCount, iSessTotal)).
                            oLogger:Debug(substitute("Processed &1 in &2ms", cFilePath, interval(now, dProcStart, "milliseconds"))).
                        end. /* sessions */
                    end case. /* not a directory */
                end. /* not a top-level folder */
            end. /* Valid Item */

            if now gt dProcLimit then do:
                oLogger:Error("Processing of files exceeded allowed time.").
                leave PROCESSBLK. /* Leave this block to complete processing of files so far. */
            end.
        end. /* do ix */

        assign
            success   = true
            processed = now
            .

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error: &1", err:GetMessage(1))).
            assign
                success   = false
                processed = now
                .
        end catch.
        finally:
            /* Delete original files after successful processing. */
            for each ttFiles no-lock
               where ttFiles.Processed:
                os-delete value(ttFiles.FilePath).
            end. /* for each ttFiles */

            release ttConfig no-error.
            delete object oDirs no-error.
            delete object oItem no-error.
        end finally.
    end method. /* ReadMetrics */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/fixData", alias="fixData", mediaType="application/json").
    method public void FixData ( input  applicationName as character,
                                 output success         as logical,
                                 output processed       as datetime ):
        /* Correct any bad data in our recorded metrics. */
        define variable dNextSample as datetime no-undo.
        define variable lDeleteStat as logical  no-undo.

        define buffer bSessionSample for SessionSample.

        assign dStart = now.

        /* Cycle through each server for this application. */
        for each ServerInfo no-lock
           where ServerInfo.ApplicationName eq applicationName:
            /* Cycle through each Agent/Session combo, looking for samples without a valid memory reading. */
            for each SessionInfo no-lock
                  by SessionInfo.AgentPID
                  by SessionInfo.SessionID:
                /**
                 * Memory should NEVER be zero, but if there is a gap in reported data for
                 * this particular session we should at least copy over the last known value
                 * available. It's not statistically ideal, but having a null or zero value
                 * could otherwise more greatly affect the trending data.
                 */
                for each SessionSample exclusive-lock
                   where SessionSample.SessionUUID eq SessionInfo.SessionUUID
                     and SessionSample.MemoryBytes eq 0
                      by SessionSample.Timestamp:
                    for last bSessionSample no-lock
                       where bSessionSample.SessionUUID eq SessionSample.SessionUUID
                         and bSessionSample.MemoryBytes ne 0
                         and bSessionSample.Timestamp lt SessionSample.Timestamp
                          by bSessionSample.Timestamp:
                        assign SessionSample.MemoryBytes = bSessionSample.MemoryBytes.
                    end. /* for last bSessionSample */
                end. /* for each SessionSample */

                /**
                 * Need to ensure that if multiple records with zero ABL Objects occur within
                 * 90 seconds of each other, we remove any duplicates or otherwise keep any
                 * non-zero values. Otherwise, the graph can get confusing when rendering data
                 * with such granularity. This assumes a minimum reporting interval of at least
                 * 2 minutes for each session available.
                 */
                for each SessionSample exclusive-lock
                   where SessionSample.SessionUUID eq SessionInfo.SessionUUID
                     and SessionSample.ObjectCount eq 0
                      by SessionSample.Timestamp:
                    assign
                        dNextSample = add-interval(SessionSample.Timestamp, 90, "seconds")
                        lDeleteStat = false
                        .

                    /**
                     * As the current record has an object count of 0,
                     * compare to the next available session sample(s)
                     * within 90 seconds of this record.
                     */
                    for each bSessionSample exclusive-lock
                       where bSessionSample.SessionUUID eq SessionSample.SessionUUID
                         and bSessionSample.Timestamp gt SessionSample.Timestamp
                         and bSessionSample.Timestamp le dNextSample:
                        /* Delete any future samples where object count is also zero. */
                        if bSessionSample.ObjectCount eq 0 then delete bSessionSample.
                        /* Otherwise delete current record if a future sample is non-zero. */
                        else if bSessionSample.ObjectCount gt 0 then assign lDeleteStat = true.
                    end. /* for each bStat */

                    /* Wait to delete current record when done comparing. */
                    if lDeleteStat then delete SessionSample.
                end. /* for each sessionStat */
            end. /* for each SessionInfo */
        end. /* for each ServerInfo */

        /* Remove any orphaned ABLObject records, if present. */
        for each ABLObject exclusive-lock
           where not can-find(first SessionSample no-lock
                              where SessionSample.SampleUUID eq ABLObject.SampleUUID):
            delete ABLObject no-error.
        end. /* for each ABLObject */

        assign
            success   = true
            processed = now
            .

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error: &1", err:GetMessage(1))).
            assign
                success   = false
                processed = now
                .
        end catch.
        finally:
            oLogger:Debug(substitute("Fix Data: &1ms", trim(string(interval(now, dStart, "milliseconds"), ">>>,>>>,>>9")))).
        end finally.
    end method. /* FixData */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/liveMetrics", alias="liveMetrics", mediaType="application/json").
    method public void LiveMetrics ( input  AppName    as character,
                                     input  Instance   as character,
                                     input  SampleName as character,
                                     input  Data       as JsonObject,
                                     output success    as logical,
                                     output processed  as datetime ):
        define variable oMetrics    as JsonObject       no-undo.
        define variable oDataArray  as JsonArray        no-undo.
        define variable oSubObj     as JsonObject       no-undo.
        define variable dStartDebug as datetime         no-undo.
        define variable dStartTime  as datetime         no-undo.
        define variable dAgentStart as datetime         no-undo.
        define variable dTimestamp  as datetime         no-undo.
        define variable dTemp       as datetime-tz      no-undo.
        define variable cNames      as character extent no-undo.
        define variable cTemp       as character        no-undo.
        define variable cServerName as character        no-undo.
        define variable cPortNumber as character        no-undo.
        define variable cSessUUID   as character        no-undo.
        define variable cSampUUID   as character        no-undo.
        define variable cSessions   as character        no-undo.
        define variable iX          as integer          no-undo.
        define variable iAgentPID   as integer          no-undo.
        define variable iSessionID  as integer          no-undo.
        define variable iMemoryUsed as int64            no-undo.
        define variable iAgentOvMem as int64            no-undo.
        define variable iLogMsgCnt  as int64            no-undo.
        define variable iMsgSeqNum  as int64            no-undo.
        define variable iSessions   as integer          no-undo.

        oLogger:Info(substitute("Metrics Received from '&1' @ '&2'", AppName, Instance)).

        assign
            dStartDebug = now /* Begin tracking for how long processing takes for this metric payload. */
            dTimestamp  = now /* All samples are relative to this moment in time unless updated later. */
            .

        /* Make sure an application name and instance is provided by the request. */
        if (AppName gt "") ne true then undo, throw new AppError("Application Name Missing", 0).
        if (Instance gt "") ne true then undo, throw new AppError("Instance Info Missing", 0).

        /* Obtain the hostname from the instance URI (assumes scheme://hostname:port/). */
        assign cTemp = replace(Instance, "~/", ""). /* Simplify to scheme[:hostname|IP][:port] */
        assign cServerName = entry(2, cTemp, ":") when num-entries(cTemp, ":") ge 2. /* Just get the hostname/IP, if available. */
        assign cPortNumber = entry(3, cTemp, ":") when num-entries(cTemp, ":") ge 3. /* Just get the port number, if available. */

        if (cPortNumber gt "") eq true then /* Include the port number, if present. */
            assign cServerName = substitute("&1:&2", cServerName, cPortNumber).

        /* Ensure this app/server combo exists in the config. */
        this-object:UpdateConfig(AppName, cServerName).

        /* Data may be nested inside the provided parameters, so check and use as appropriate. */
        if JsonPropertyHelper:HasTypedProperty(Data, "Data", JsonDataType:Object) then do:
            assign oMetrics = Data:GetJsonObject("Data").

            if oLogger:LogLevel eq LogLevelEnum:Debug then do:
                /* Rebuild the original format with all properties in their expected place. */
                Data:Remove("Data").
                Data:Add("AppName", AppName).
                Data:Add("Instance", Instance).
                Data:Add("SampleName", SampleName).
                Data:Add("Data", oMetrics).
            end. /* DEBUG */
        end. /* Has Data */
        else
            assign oMetrics = Data.

        /* Ouput the body of the request if trace enabled. */
        if oLogger:LogLevel eq LogLevelEnum:Trace then
            Data:WriteFile(substitute("&1/intake/Metrics_&2_&3.&4.json",
                           this-object:TemporaryDir, AppName, iso-date(today), mtime(now)), true).

        /* Obtain a unique ID for this application/server combination, creating any records as necessary. */
        define variable cServerUUID as character no-undo. /* UUID to pass in lieu of application/server. */
        assign cServerUUID = this-object:UpdateServer(AppName, cServerName).

        /* Check if there is a "sessions" array in the request (as sent via the LiveDiag tooling, 12.2+). */
        if JsonPropertyHelper:HasTypedProperty(oMetrics, "sessions", JsonDataType:Array) then do:
            /* All data should be relative to a single agent PID. */
            if JsonPropertyHelper:HasTypedProperty(oMetrics, "agentPid", JsonDataType:Number) then
                assign iAgentPID = oMetrics:GetInteger("agentPid").

            /* Get the start time when the pulse metrics began (requests will be relative to this). */
            if JsonPropertyHelper:HasTypedProperty(oMetrics, "startTime", JsonDataType:String) then do:
                /* Get the absolute time, ignoring whatever timezone was sent. */
                assign dTemp = oMetrics:GetDatetimeTZ("startTime").
                assign dStartTime = datetime(date(dTemp), mtime(dTemp)).
            end.

            /* Use the current timestamp as provided by the server. */
            if JsonPropertyHelper:HasTypedProperty(oMetrics, "curTime", JsonDataType:String) then do:
                /* Get the absolute time, ignoring whatever timezone was sent. */
                assign dTemp = oMetrics:GetDatetimeTZ("curTime").
                assign dTimestamp = datetime(date(dTemp), mtime(dTemp)).
            end.

            /* Get the log message lines and parse the contents. */
            if JsonPropertyHelper:HasTypedProperty(oMetrics, "logMsgs", JsonDataType:Array) then do:
                /* Get the log message count. */
                if JsonPropertyHelper:HasTypedProperty(oMetrics, "logMsgCnt", JsonDataType:Number) then
                    assign iLogMsgCnt = oMetrics:GetInteger("logMsgCnt").

                /* Get the log message sequence. */
                if JsonPropertyHelper:HasTypedProperty(oMetrics, "msgSeqNum", JsonDataType:Number) then
                    assign iMsgSeqNum = oMetrics:GetInteger("msgSeqNum").

                this-object:ProcessAgentLog(cServerUUID, iAgentPID, iMsgSeqNum, iLogMsgCnt, dTimestamp, oMetrics:GetJsonArray("logMsgs"):GetJsonText()).
            end. /* Has logMsgs */

            /* Get the agent's start time, when available (12.4+). */
            if JsonPropertyHelper:HasTypedProperty(oMetrics, "agentStartTime", JsonDataType:String) then do:
                /* Get the absolute time, ignoring whatever timezone was sent. */
                assign dTemp = oMetrics:GetDatetimeTZ("agentStartTime").
                assign dAgentStart = datetime(date(dTemp), mtime(dTemp)).
            end.

            /* Get the agent's overhead memory, when available (12.4+). */
            if JsonPropertyHelper:HasTypedProperty(oMetrics, "overheadMemory", JsonDataType:Number) then
                assign iAgentOvMem = oMetrics:GetInt64("overheadMemory").

            assign
                iSessions = oMetrics:GetJsonArray("sessions"):length
                cSessions = "" /* Reset the list of sessions encountered in this sample. */
                .
            oLogger:Trace(substitute("|- Processing 'sessions' array [&1] for metrics", iSessions)).

            do iX = 1 to iSessions:
                assign oSubObj = oMetrics:GetJsonArray("sessions"):GetJsonObject(iX).

                /* Should always report the current session ID, even if no metrics present. */
                if JsonPropertyHelper:HasTypedProperty(oSubObj, "sessionId", JsonDataType:Number) then
                    assign iSessionID = oSubObj:GetInteger("sessionId").
                else
                    assign iSessionID = 0.

                /* Should always report the current memory use for the session. */
                if JsonPropertyHelper:HasTypedProperty(oSubObj, "memoryUse", JsonDataType:Number) then
                    assign iMemoryUsed = oSubObj:GetInt64("memoryUse").
                else
                    assign iMemoryUsed = ?.

                if iAgentPID ne 0 and iSessionID ne 0 then do:
                    /* Update the current session info and record the current memory used at this sample point in time. */
                    oLogger:Debug(substitute("|- Updating Session: A&1 S&2 (Sample @ &3)", iAgentPID, iSessionID, dTimestamp)).
                    assign cSessUUID = this-object:UpdateSession(cServerUUID, iAgentPID, iSessionID, dTimestamp).
                    oLogger:Debug(substitute("|- Updating Memory Usage: A&1 S&2 (&3 MB)", iAgentPID, iSessionID, trim(string(iMemoryUsed / 1024, ">>>,>>>,>>9.99")))).
                    assign cSampUUID = this-object:UpdateSample(cSessUUID, SampleName, dTimestamp, iMemoryUsed, ?).

                    if JsonPropertyHelper:HasTypedProperty(oSubObj, "requests", JsonDataType:Array) then do:
                        /* Log any recorded session requests relative to the start of the pulse metrics. */
                        oLogger:Debug(substitute("|- Processing Requests: A&1 S&2", iAgentPID, iSessionID)).
                        this-object:ProcessRequests(cSampUUID, dStartTime, oSubObj:GetJsonArray("requests")).

                        if oLogger:LogLevel eq LogLevelEnum:Trace then
                            this-object:dumpRequests(iAgentPID). /* Dump all requests for the associated AgentPID when in trace mode. */
                    
                        /* If requests were present, then we should note this seession was active. */
                        if oSubObj:GetJsonArray("requests"):Length gt 0 then
                            assign cSessions = trim(substitute("&1,&2", cSessions, cSessUUID), ",").
                    end. /* Has requests */
                end. /* Has Agent/Session */
            end. /* do iX */

            /* Update metadata for this agent which will be used to report on % busy sessions and concurrent requests. */
            this-object:UpdateAgent(cServerUUID, iAgentPID, SampleName, dTimestamp, cSessions, dAgentStart, iAgentOvMem).
        end. /* Data Payload */
        else do:
            /* Loop through distinct objects for metrics data (as sent by the Spark Diagnostics). */
            assign cNames = oMetrics:GetNames().
            oLogger:Trace(substitute("|- Processing individual objects [&1] for metrics", extent(cNames))).
            do iX = 1 to extent(cNames):
                case cNames[ix]:
                    when "ABLObjects" then do:
                        if JsonPropertyHelper:HasTypedProperty(oMetrics, "ABLObjects", JsonDataType:Object) then do:
                            assign oSubObj = oMetrics:GetJsonObject("ABLObjects").

                            if JsonPropertyHelper:HasTypedProperty(oSubObj, "Agent", JsonDataType:Number) then
                                assign iAgentPID = oSubObj:GetInteger("Agent").
                            else if JsonPropertyHelper:HasTypedProperty(oSubObj, "AgentPID", JsonDataType:Number) then
                                assign iAgentPID = oSubObj:GetInteger("AgentPID").

                            if JsonPropertyHelper:HasTypedProperty(oSubObj, "Session", JsonDataType:Number) then
                                assign iSessionID = oSubObj:GetInteger("Session").
                            else if JsonPropertyHelper:HasTypedProperty(oSubObj, "ABLSessionID", JsonDataType:Number) then
                                assign iSessionID = oSubObj:GetInteger("ABLSessionID").

                            /* Create the necessary support records for the session and current sample. */
                            assign cSessUUID = this-object:UpdateSession(cServerUUID, iAgentPID, iSessionID, dTimestamp).
                            assign cSampUUID = this-object:UpdateSample(cSessUUID, SampleName, dTimestamp, ?, oSubObj:GetJsonArray("Data"):Length).

                            oLogger:Debug(substitute("|- Processing ABLObjects: A&1 S&2", iAgentPID, iSessionID)).

                            if JsonPropertyHelper:HasTypedProperty(oSubObj, "Data", JsonDataType:Array) then
                                this-object:ProcessObjects(cSampUUID, oSubObj:GetJsonArray("Data")).
                        end. /* Has Valid JSON Object */
                    end. /* ABLObjects */

                    when "Sessions" then do:
                        if JsonPropertyHelper:HasTypedProperty(oMetrics, "Sessions", JsonDataType:Object) then do:
                            assign oSubObj = oMetrics:GetJsonObject("Sessions").

                            if JsonPropertyHelper:HasTypedProperty(oSubObj, "Agent", JsonDataType:Number) then
                                assign iAgentPID = oSubObj:GetInteger("Agent").
                            else if JsonPropertyHelper:HasTypedProperty(oSubObj, "AgentPID", JsonDataType:Number) then
                                assign iAgentPID = oSubObj:GetInteger("AgentPID").

                            oLogger:Debug(substitute("|- Processing Sessions: A&1", iAgentPID)).

                            if JsonPropertyHelper:HasTypedProperty(oSubObj, "Data", JsonDataType:Array) then
                                this-object:ProcessSessions(cServerUUID, dTimestamp, iAgentPID, SampleName, oSubObj:GetJsonArray("Data")).
                        end. /* Has Valid JSON Object */
                    end. /* Sessions */

                    when "Requests" then do:
                        if JsonPropertyHelper:HasTypedProperty(oMetrics, "Requests", JsonDataType:Object) then do:
                            assign oSubObj = oMetrics:GetJsonObject("Requests").

                            if JsonPropertyHelper:HasTypedProperty(oSubObj, "Agent", JsonDataType:Number) then
                                assign iAgentPID = oSubObj:GetInteger("Agent").
                            else if JsonPropertyHelper:HasTypedProperty(oSubObj, "AgentPID", JsonDataType:Number) then
                                assign iAgentPID = oSubObj:GetInteger("AgentPID").

                            if JsonPropertyHelper:HasTypedProperty(oSubObj, "Data", JsonDataType:Array) then do:
                                /* Create the necessary support records for the session and current sample. */
                                assign oDataArray = oSubObj:GetJsonArray("Data").
                                if oDataArray:Length gt 0 and oDataArray:GetJsonObject(1):Has("SessionId") then
                                    assign iSessionID = oDataArray:GetJsonObject(1):GetInteger("SessionId").

                                assign cSessUUID = this-object:UpdateSession(cServerUUID, iAgentPID, iSessionID, dTimestamp).
                                assign cSampUUID = this-object:UpdateSample(cSessUUID, SampleName, dTimestamp, ?, ?).

                                oLogger:Debug(substitute("|- Processing Requests: A&1 S&2", iAgentPID, iSessionID)).

                                this-object:ProcessRequests(cSampUUID, dTimestamp, oDataArray).

                                /* Update metadata for this agent which will be used to report on % busy sessions and concurrent requests. */
                                this-object:UpdateAgent(cServerUUID, iAgentPID, SampleName, dTimestamp, "", ?, ?).
                            end. /* Has Data */

                            if oLogger:LogLevel eq LogLevelEnum:Trace then
                                this-object:dumpRequests(iAgentPID). /* Dump all requests for the associated AgentPID when in trace mode. */

                            delete object oDataArray no-error.
                        end. /* Has Valid JSON Object */
                    end. /* Requests */
                end case.
            end. /* do iX */
        end. /* Individual Payload */

        assign
            success   = true
            processed = now
            .

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error Parsing Metrics from &1 @ &2: &3", AppName, Instance, err:GetMessage(1))).
            assign
                success   = false
                processed = now
                .
        end catch.
        finally:
            /* Make note of when the request completed processing along with some basic stats. */
            if oLogger:LogLevel eq LogLevelEnum:Debug then
                oLogger:Debug(substitute("Metrics Received from '&1' @ '&2'; Processed &3kb in &4s.",
                                         AppName, Instance,
                                         trim(string(length(Data:GetJsonText(),  "raw") / 1024, ">>>,>>>,>>9.999")),
                                         trim(string(interval(now, dStartDebug, "milliseconds") / 1000, ">>>,>>>,>>9.999")))).

            delete object oDataArray no-error.
            delete object oSubObj no-error.
            delete object oMetrics no-error.
            delete object Data no-error.
        end finally.
    end method. /* LiveMetrics */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/liveProfile", alias="liveProfile", mediaType="application/json").
    method public void LiveProfile ( input  AppName   as character,
                                     input  Instance  as character,
                                     output success   as logical,
                                     output processed as datetime ):
        define variable oWebRequest as OpenEdge.Web.WebRequest no-undo.
        define variable oBody       as JsonObject              no-undo.
        define variable dTimestamp  as datetime                no-undo.
        define variable cTemp       as character               no-undo.
        define variable cServerName as character               no-undo.
        define variable cPortNumber as character               no-undo.
        define variable cServerUUID as character               no-undo.
        define variable cSessUUID   as character               no-undo.
        define variable cRequestID  as character               no-undo.
        define variable cWebAppName as character               no-undo.
        define variable cTransport  as character               no-undo.
        define variable iAgentPID   as integer                 no-undo.
        define variable iSessionID  as integer                 no-undo.

        /* Make note of where the latest data came from. */
        oLogger:Info(substitute("Profile data received from &1 @ &2", AppName, Instance)).

        /* Make sure an application name and instance is provided by the request. */
        if (AppName gt "") ne true then undo, throw new AppError("Application Name Missing", 0).
        if (Instance gt "") ne true then undo, throw new AppError("Instance Info Missing", 0).

        /* Obtain the hostname from the instance URI (assumes scheme://hostname:port/). */
        assign cTemp = replace(Instance, "~/", ""). /* Simplify to scheme[:hostname|IP][:port] */
        assign cServerName = entry(2, cTemp, ":") when num-entries(cTemp, ":") ge 2. /* Just get the hostname/IP, if available. */
        assign cPortNumber = entry(3, cTemp, ":") when num-entries(cTemp, ":") ge 3. /* Just get the port number, if available. */

        if (cPortNumber gt "") eq true then /* Include the port number, if present. */
            assign cServerName = substitute("&1:&2", cServerName, cPortNumber).

        /* Ensure this app/server combo exists in the config. */
        this-object:UpdateConfig(AppName, cServerName).

        /**
         * Use a direct WebRequest to access the raw data from the request.
         * We do this in lieu of named parameters so that changes to the
         * data format passed does not cause issues with older instances
         * of the collection logic.
         */
        assign oWebRequest = new OpenEdge.Web.WebRequest().

        /* Parse metrics as sent from a live server. */
        if valid-object(oWebRequest:Entity) and type-of(oWebRequest:Entity, JsonObject) then
            assign oBody = cast(oWebRequest:Entity, JsonObject).
        else
            undo, throw new AppError("Request body is not JSON.", 0).

        /* Ouput the body of the request if trace enabled. */
        if oLogger:LogLevel eq LogLevelEnum:Trace and valid-object(oBody) and type-of(oBody, JsonObject) then
            oBody:WriteFile(substitute("&1/intake/Profile_&2_&3.&4.json",
                            this-object:TemporaryDir, AppName, iso-date(today), mtime(now)), true).

        if JsonPropertyHelper:HasTypedProperty(oBody, "Agent", JsonDataType:Number) then
            assign iAgentPID = oBody:GetInteger("Agent").
        else if JsonPropertyHelper:HasTypedProperty(oBody, "AgentPID", JsonDataType:Number) then
            assign iAgentPID = oBody:GetInteger("AgentPID").

        if JsonPropertyHelper:HasTypedProperty(oBody, "Session", JsonDataType:Number) then
            assign iSessionID = oBody:GetInteger("Session").
        else if JsonPropertyHelper:HasTypedProperty(oBody, "ABLSessionID", JsonDataType:Number) then
            assign iSessionID = oBody:GetInteger("ABLSessionID").

        if JsonPropertyHelper:HasTypedProperty(oBody, "RequestID", JsonDataType:String) then
            assign cRequestID = oBody:GetCharacter("RequestID").

        assign cServerUUID = this-object:UpdateServer(AppName, cServerName).
        assign cSessUUID = this-object:UpdateSession(cServerUUID, iAgentPID, iSessionID, ?).
        assign dTimestamp = now. /* All samples are relative to this moment in time (by default). */

        if JsonPropertyHelper:HasTypedProperty(oBody, "RequestStart", JsonDataType:String) then
            assign dTimestamp = oBody:GetDatetime("RequestStart"). /* Use the request start as the timestamp. */

        /* If a RequestID has been captured as part of the data payload, then use that for context. */
        if (cRequestID gt "") eq true and num-entries(cRequestID, ":") ge 3 then do:
            assign
                cWebAppName = entry(1, cRequestID, ":")
                cTransport  = caps(entry(2, cRequestID, ":"))
                cRequestID  = entry(3, cRequestID, ":")
                .

            /* Attempt to find a matching request using this information. */
            find first RequestInfo no-lock
                 where RequestInfo.ServerUUID eq cServerUUID
                   and RequestInfo.SessionUUID eq cSessUUID
                   and RequestInfo.WebAppName eq cWebAppName
                   and RequestInfo.Transport eq cTransport
                   and RequestInfo.RequestID eq cRequestID no-error.
            if available(RequestInfo) then
                assign dTimestamp = RequestInfo.StartTime. /* Use the start time of the related request. */
        end. /* cRequestID */

        if JsonPropertyHelper:HasTypedProperty(oBody, "Data", JsonDataType:String) then
            this-object:SaveProfilerData(cSessUUID, dTimestamp, oBody:GetLongchar("Data")).

        assign
            success   = true
            processed = now
            .

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error Parsing Profiler: &1", err:GetMessage(1))).
            assign
                success   = false
                processed = now
                .
        end catch.
        finally:
            delete object oBody no-error.
            delete object oWebRequest no-error.
        end finally.
    end method. /* LiveProfile */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/liveLogs", alias="liveLogs", mediaType="application/json").
    method public void LiveLogs ( input  AppName   as character,
                                  input  Instance  as character,
                                  output success   as logical,
                                  output processed as datetime ):
        define variable oWebRequest as OpenEdge.Web.WebRequest no-undo.
        define variable oBody       as JsonObject              no-undo.
        define variable oSubArr     as JsonArray               no-undo.
        define variable cTemp       as character               no-undo.
        define variable cServerName as character               no-undo.
        define variable cPortNumber as character               no-undo.
        define variable cServerUUID as character               no-undo.
        define variable iX          as integer                 no-undo.

        /* Make note of where the latest data came from. */
        oLogger:Info(substitute("Access Log data received from &1 @ &2", AppName, Instance)).

        /* Make sure an application name and instance is provided by the request. */
        if (AppName gt "") ne true then undo, throw new AppError("Application Name Missing", 0).
        if (Instance gt "") ne true then undo, throw new AppError("Instance Info Missing", 0).

        /* Obtain the hostname from the instance URI (assumes scheme://hostname:port/). */
        assign cTemp = replace(Instance, "~/", ""). /* Simplify to scheme[:hostname|IP][:port] */
        assign cServerName = entry(2, cTemp, ":") when num-entries(cTemp, ":") ge 2. /* Just get the hostname/IP, if available. */
        assign cPortNumber = entry(3, cTemp, ":") when num-entries(cTemp, ":") ge 3. /* Just get the port number, if available. */

        if (cPortNumber gt "") eq true then /* Include the port number, if present. */
            assign cServerName = substitute("&1:&2", cServerName, cPortNumber).

        /* Ensure this app/server combo exists in the config. */
        this-object:UpdateConfig(AppName, cServerName).

        /**
         * Use a direct WebRequest to access the raw data from the request.
         * We do this in lieu of named parameters so that changes to the
         * data format passed does not cause issues with older instances
         * of the collection logic.
         */
        assign oWebRequest = new OpenEdge.Web.WebRequest().

        /* Parse metrics as sent from a live server. */
        if valid-object(oWebRequest:Entity) and type-of(oWebRequest:Entity, JsonObject) then
            assign oBody = cast(oWebRequest:Entity, JsonObject).
        else
            undo, throw new AppError("Request body is not JSON.", 0).

        /* Ouput the body of the request if trace enabled. */
        if oLogger:LogLevel eq LogLevelEnum:Trace and valid-object(oBody) and type-of(oBody, JsonObject) then
            oBody:WriteFile(substitute("&1/intake/Logs_&2_&3.&4.json",
                            this-object:TemporaryDir, AppName, iso-date(today), mtime(now)), true).

        if JsonPropertyHelper:HasTypedProperty(oBody, "Data", JsonDataType:Array) then do:
            assign cServerUUID = this-object:UpdateServer(AppName, cServerName).
            assign oSubArr = oBody:GetJsonArray("Data").

            if oSubArr:Length ge 1 then
            do iX = 1 to oSubArr:Length:
                /* Process each log file, sent as a longchar in a JSON array. */
                this-object:ProcessAccessLog(cServerUUID, oSubArr:GetLongchar(iX)).
            end.
        end. /* oBody Data */

        assign
            success   = true
            processed = now
            .

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error Parsing Logs: &1", err:GetMessage(1))).
            assign
                success   = false
                processed = now
                .
        end catch.
        finally:
            delete object oBody no-error.
            delete object oWebRequest no-error.
        end finally.
    end method. /* LiveLogs */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/liveHealth", alias="liveHealth", mediaType="application/json").
    method public void LiveHealth ( input  AppName     as character,
                                    input  Instance    as character,
                                    input  HealthCheck as JsonObject,
                                    output success     as logical,
                                    output processed   as datetime ):
        define variable cTemp       as character no-undo.
        define variable cServerName as character no-undo.
        define variable cPortNumber as character no-undo.
        
        /* Make note of where the latest data came from. */
        oLogger:Info(substitute("Health data received from &1 @ &2", AppName, Instance)).

        /* Make sure an application name and instance is provided by the request. */
        if (AppName gt "") ne true then undo, throw new AppError("Application Name Missing", 0).
        if (Instance gt "") ne true then undo, throw new AppError("Instance Info Missing", 0).

        /* Obtain the hostname from the instance URI (assumes scheme://hostname:port/). */
        assign cTemp = replace(Instance, "~/", ""). /* Simplify to scheme[:hostname|IP][:port] */
        assign cServerName = entry(2, cTemp, ":") when num-entries(cTemp, ":") ge 2. /* Just get the hostname/IP, if available. */
        assign cPortNumber = entry(3, cTemp, ":") when num-entries(cTemp, ":") ge 3. /* Just get the port number, if available. */

        if (cPortNumber gt "") eq true then /* Include the port number, if present. */
            assign cServerName = substitute("&1:&2", cServerName, cPortNumber).

        define variable cServerUUID as character no-undo. /* UUID to pass in lieu of application/server. */
        assign cServerUUID = this-object:UpdateServer(AppName, cServerName).

        /* Read the JSON data into the Dataset. */
        dataset HealthCheck:read-json("JsonObject", HealthCheck, "empty").

        if oLogger:LogLevel eq LogLevelEnum:Trace then do:
            HealthCheck:WriteFile(substitute("&1/HealthCheck_Input_&2.json", this-object:TemporaryDir, mtime), true).
            dataset HealthCheck:write-json("file", substitute("&1/HealthCheck_Dataset_&2.json", this-object:TemporaryDir, mtime), true).
        end.

        define buffer bHealthConfig for HealthCheckConfig.
        define buffer bHealthData   for HealthCheckData.

        for each HealthConfig no-lock:
            /* Config entries should be unique by server, probe ID/parent, name, and timestamp. */
            if not can-find(first bHealthConfig no-lock
                            where bHealthConfig.ServerUUID eq cServerUUID
                              and bHealthConfig.probeid eq HealthConfig.probeid
                              and bHealthConfig.parentid eq HealthConfig.parentid
                              and bHealthConfig.config_name eq HealthConfig.config_name
                              and bHealthConfig.timestamp eq HealthConfig.timestamp) then do:
                create bHealthConfig.
                assign bHealthConfig.ServerUUID = cServerUUID.
                buffer-copy HealthConfig to bHealthConfig.
            end. /* not can-find */
        end. /* for each HealthConfig */

        for each HealthData no-lock:
            /* Config entries should be unique by server, probe ID, and poll time. */
            if not can-find(first bHealthData no-lock
                            where bHealthData.ServerUUID eq cServerUUID
                              and bHealthData.probeid eq HealthData.probeid
                              and bHealthData.lastpoll eq HealthData.lastpoll) then do:
                create bHealthData.
                assign bHealthData.ServerUUID = cServerUUID.
                buffer-copy HealthData to bHealthData.
            end. /* not can-find */
        end. /* for each HealthData */

        assign
            success   = true
            processed = now
            .

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error Parsing Health Config: &1", err:GetMessage(1))).
            assign
                success   = false
                processed = now
                .
        end catch.
        finally:
        end finally.
    end method. /* LiveHealth */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/purgeMetrics", alias="purgeMetrics", mediaType="application/json").
    method public void PurgeMetrics ( input  applicationName as character,
                                      input  serverName      as character,
                                      input  purgeDate       as datetime,
                                      output success         as logical,
                                      output processed       as datetime ):
        define variable cServerUUID  as character no-undo.
        define variable cSessionUUID as character no-undo.
        define variable oSessionList as JsonArray no-undo.
        define variable dStartPurge  as datetime  no-undo.
        define variable iX           as integer   no-undo.

        define buffer bServerInfo for ServerInfo.
        define buffer bSessionInfo for SessionInfo.

        /* ***************************  Main Code  *************************** */

        /* Determine date for purge cut-off. */
        if purgeDate eq ? then
            assign purgeDate = now.

        if (applicationName gt "") ne true or
           (serverName gt "") ne true then
            undo, throw new AppError("No application or server name given.", 0).

        /* Ensure this app/server combo exists in the config. */
        this-object:UpdateConfig(applicationName, serverName).

        /* Get the UUID for this app/server. */
        for first bServerInfo no-lock
            where bServerInfo.ApplicationName eq applicationName
              and bServerInfo.ServerName eq serverName:
            assign cServerUUID = bServerInfo.ServerUUID.
        end.

        if (cServerUUID gt "") ne true then
            undo, throw new AppError("No server UUID available.", 0).

        oLogger:Debug(substitute("Expunging for &1/&2 as UUID &3", applicationName, serverName, cServerUUID)).
        oLogger:Debug(substitute("Expunging records prior to &1...", purgeDate)).

        /* Identify the session UUID's to be deleted. */
        assign oSessionList = new JsonArray().
        for each bSessionInfo no-lock
           where bSessionInfo.ServerUUID eq cServerUUID
             and (bSessionInfo.Started eq ? or
                  bSessionInfo.Started lt purgeDate):
            oLogger:Debug(substitute("Found Agent &1, Session &2 as UUID &3", bSessionInfo.AgentPID, bSessionInfo.SessionID, bSessionInfo.SessionUUID)).
            oSessionList:Add(bSessionInfo.SessionUUID). /* Create a simple JSON array of agent-session UUID's. */
        end. /* for each bSessionInfo */

        /* Delete all of the metrics records for each session. */
        do iX = 1 to oSessionList:Length on error undo, throw
                                         on stop undo, leave:
            assign
                dStartPurge  = now
                cSessionUUID = oSessionList:GetCharacter(iX)
                .

            oLogger:Debug(substitute("Reviewing UUID &1 Metrics Records...", cSessionUUID)).

            /* Break these up to avoid too deep of a transaction. */
            this-object:doProfilerCleanup(cSessionUUID).
            this-object:doObjectCleanup(cSessionUUID).
            this-object:doRequestCleanup(cSessionUUID).
            this-object:doSampleCleanup(cSessionUUID).
            this-object:doAgentCleanup(cServerUUID, purgeDate).

            oLogger:Debug(substitute("Deleted UUID &1 Metrics Records in &2ms", cSessionUUID,
                          trim(string(interval(now, dStartPurge, "milliseconds") / 1000, ">>>,>>9.999")))).

            /* Peform the delete of the session record itself. */
            find first bSessionInfo exclusive-lock
                 where bSessionInfo.ServerUUID eq cServerUUID
                   and bSessionInfo.SessionUUID eq oSessionList:GetCharacter(iX) no-wait no-error.
            if available(bSessionInfo) and not locked(bSessionInfo) then do:
                oLogger:Debug(substitute("Deleting Agent &1, Session &2", bSessionInfo.AgentPID, bSessionInfo.SessionID)).
                delete bSessionInfo.
            end. /* for first bSessionInfo */

            catch err as Progress.Lang.Error:
                /* Report any errors but leave without performing an undo operation. */
                oLogger:Error(substitute("Error Purging Data: &1", err:GetMessage(1))).
            end catch.
        end. /* do iX */

        /* Delete the raw agent log records for this server. */
        for each AgentLogRaw exclusive-lock
           where AgentLogRaw.ServerUUID eq cServerUUID
             and (AgentLogRaw.Timestamp eq ? or
                  AgentLogRaw.Timestamp lt datetime-tz(purgeDate)):
            delete AgentLogRaw.
        end. /* for each AgentLogRaw */

        /* Delete the parsed agent log records for this server. */
        for each AgentLog exclusive-lock
           where AgentLog.ServerUUID eq cServerUUID
             and (AgentLog.Timestamp eq ? or
                  AgentLog.Timestamp lt datetime-tz(purgeDate)):
            delete AgentLog.
        end. /* for each AgentLog */

        /* Delete the access log records for this server. */
        for each AccessLog exclusive-lock
           where AccessLog.ServerUUID eq cServerUUID
             and (AccessLog.RequestStart eq ? or
                  AccessLog.RequestStart lt datetime-tz(purgeDate)):
            delete AccessLog.
        end. /* for each AccessLog */

        /* Make sure any orphaned records are removed. */
        this-object:CleanOrphans(applicationName, serverName, success, processed).

        assign
            success   = true
            processed = now
            .

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error Purging Data: &1", err:GetMessage(1))).
            assign
                success   = false
                processed = now
                .
        end catch.
        finally:
            delete object oSessionList no-error.
        end finally.
    end method. /* PurgeMetrics */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/purgeHealth", alias="purgeHealth", mediaType="application/json").
    method public void PurgeHealth ( input  applicationName as character,
                                     input  serverName      as character,
                                     input  purgeDate       as datetime,
                                     output success         as logical,
                                     output processed       as datetime ):
        define variable cServerUUID  as character no-undo.
        define variable cSessionUUID as character no-undo.

        define buffer bServerInfo   for ServerInfo.
        define buffer bHealthConfig for HealthCheckConfig.
        define buffer bHealthData   for HealthCheckData.

        /* ***************************  Main Block  *************************** */

        /* Determine date for purge cut-off. */
        if purgeDate eq ? then
            assign purgeDate = now.

        if (applicationName gt "") ne true or
           (serverName gt "") ne true then
            undo, throw new AppError("No application or server name given.", 0).

        /* Get the UUID for this app/server. */
        for first bServerInfo no-lock
            where bServerInfo.ApplicationName eq applicationName
              and bServerInfo.ServerName eq serverName:
            assign cServerUUID = bServerInfo.ServerUUID.
        end.

        if (cServerUUID gt "") ne true then
            undo, throw new AppError("No server UUID available.", 0).

        oLogger:Debug(substitute("Expunging for &1/&2 as UUID &3", applicationName, serverName, cServerUUID)).
        oLogger:Debug(substitute("Expunging records prior to &1...", purgeDate)).

        /* Remove health configs for this server. */
        for each bHealthConfig exclusive-lock
           where bHealthConfig.ServerUUID eq cServerUUID
             and (bHealthConfig.timestamp eq ? or
                  bHealthConfig.timestamp lt datetime-tz(purgeDate)):
            delete bHealthConfig.
        end. /* for each bHealthConfig */

        /* Remove health data for this server. */
        for each bHealthData exclusive-lock
           where bHealthData.ServerUUID eq cServerUUID
             and (bHealthData.lastpoll eq ? or
                  bHealthData.lastpoll lt datetime-tz(purgeDate)):
            delete bHealthData.
        end. /* for each bHealthData */

        assign
            success   = true
            processed = now
            .

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error Purging Data: &1", err:GetMessage(1))).
            assign
                success   = false
                processed = now
                .
        end catch.
    end method. /* PurgeHealth */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/cleanOrphans", alias="cleanOrphans", mediaType="application/json").
    method public void CleanOrphans ( input  applicationName as character,
                                      input  serverName      as character,
                                      output success         as logical,
                                      output processed       as datetime ):
        define variable cServerUUID  as character no-undo.
        define variable cSessionUUID as character no-undo.

        define buffer bServerInfo for ServerInfo.
        define buffer bSessionInfo for SessionInfo.
        define buffer bAgentSample for AgentSample.
        define buffer bSessionSample for SessionSample.
        define buffer bABLObject for ABLObject.
        define buffer bCallStack for CallStack.
        define buffer bCallTree for CallTree.
        define buffer bProfilerData for ProfilerData.
        define buffer bRequestInfo for RequestInfo.
        define buffer bHealthConfig for HealthCheckConfig.
        define buffer bHealthData for HealthCheckData.

        /* ***************************  Main Code  *************************** */

        if (applicationName gt "") ne true or
           (serverName gt "") ne true then
            undo, throw new AppError("No application or server name given.", 0).

        /* Ensure this app/server combo exists in the config. */
        this-object:UpdateConfig(applicationName, serverName).

        /* Get the UUID for this app/server. */
        for first bServerInfo no-lock
            where bServerInfo.ApplicationName eq applicationName
              and bServerInfo.ServerName eq serverName:
            assign cServerUUID = bServerInfo.ServerUUID.
        end.

        if (cServerUUID gt "") ne true then
            undo, throw new AppError("No server UUID available.", 0).

        oLogger:Debug(substitute("Cleaning orphans for &1/&2 as UUID &3", applicationName, serverName, cServerUUID)).

        /* Delete sessions of server with no request, sample, and session data. */
        assign dStart = now.
        for each bSessionInfo exclusive-lock
           where bSessionInfo.ServerUUID eq cServerUUID
             and not can-find(first bRequestInfo no-lock
                              where bRequestInfo.ServerUUID eq cServerUUID
                                and bRequestInfo.SessionUUID eq bSessionInfo.SessionUUID)
             and not can-find(first bSessionSample no-lock
                              where bSessionSample.SessionUUID eq bSessionInfo.SessionUUID)
             and not can-find(first bProfilerData no-lock
                              where bProfilerData.SessionUUID eq bSessionInfo.SessionUUID):
            delete bSessionInfo.
        end. /* for each bSessionInfo */
        oLogger:Debug(substitute("Deleted orphaned sessions in &1ms", interval(now, dStart, "milliseconds"))).

        /* Delete requests with no sessions. */
        assign dStart = now.
        for each bRequestInfo exclusive-lock
           where bRequestInfo.ServerUUID eq cServerUUID
             and not can-find(first bSessionInfo no-lock
                              where bSessionInfo.SessionUUID eq bRequestInfo.SessionUUID):
            /* Delete all stack info for this request. */
            for each bCallStack exclusive-lock
               where bCallStack.RequestUUID eq bRequestInfo.RequestUUID:
                delete bCallStack.
            end.

            delete bRequestInfo.
        end. /* for each bRequestInfo */
        oLogger:Debug(substitute("Deleted orphaned requests in &1ms", interval(now, dStart, "milliseconds"))).

        /* Delete stack info with no request. */
        assign dStart = now.
        for each bCallStack exclusive-lock
           where not can-find(first bRequestInfo no-lock
                              where bRequestInfo.SessionUUID eq bCallStack.RequestUUID):
            delete bCallStack.
        end. /* for each bCallStack */
        oLogger:Debug(substitute("Deleted orphaned call stacks in &1ms", interval(now, dStart, "milliseconds"))).

        /* Delete calltree info with no request. */
        assign dStart = now.
        for each bCallTree exclusive-lock
           where not can-find(first bRequestInfo no-lock
                              where bRequestInfo.SessionUUID eq bCallTree.RequestUUID):
            delete bCallTree.
        end. /* for each bCallTree */
        oLogger:Debug(substitute("Deleted orphaned calltree in &1ms", interval(now, dStart, "milliseconds"))).

        /* Delete profiler data with no sessions. */
        assign dStart = now.
        for each bProfilerData exclusive-lock
           where not can-find(first bSessionInfo no-lock
                              where bSessionInfo.SessionUUID eq bProfilerData.SessionUUID):
            delete bProfilerData.
        end. /* for each bProfilerData */

        /* Delete agents with no sessions. */
        assign dStart = now.
        for each bAgentSample exclusive-lock
           where bAgentSample.ServerUUID eq cServerUUID
             and not can-find(first bSessionInfo no-lock
                              where bSessionInfo.ServerUUID eq cServerUUID
                                and bSessionInfo.AgentPID eq bAgentSample.AgentPID):
            delete bAgentSample.
        end. /* for each bAgentSample */
        oLogger:Debug(substitute("Deleted orphaned agents in &1ms", interval(now, dStart, "milliseconds"))).

        /* Delete servers with no requests, sessions, and health data. */
        assign dStart = now.
        for each bServerInfo exclusive-lock
           where bServerInfo.ServerUUID eq cServerUUID
             and not can-find(first bRequestInfo no-lock
                              where bRequestInfo.ServerUUID eq cServerUUID)
             and not can-find(first bSessionInfo no-lock
                              where bSessionInfo.ServerUUID eq cServerUUID)
             and not can-find(first bHealthConfig no-lock
                              where bHealthConfig.ServerUUID eq cServerUUID)
             and not can-find(first bHealthData no-lock
                              where bHealthData.ServerUUID eq cServerUUID):
            delete bServerInfo.
        end. /* for each bServerInfo */
        oLogger:Debug(substitute("Deleted orphaned servers in &1ms", interval(now, dStart, "milliseconds"))).

        /* Delete access log entries with no server. */
        assign dStart = now.
        for each AccessLog exclusive-lock
           where not can-find(first bServerInfo no-lock
                              where bServerInfo.ServerUUID eq AccessLog.ServerUUID):
            delete AccessLog.
        end. /* for each AccessLog */
        oLogger:Debug(substitute("Deleted orphaned access logs in &1ms", interval(now, dStart, "milliseconds"))).

        assign
            success   = true
            processed = now
            .

        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error Purging Data: &1", err:GetMessage(1))).
            assign
                success   = false
                processed = now
                .
        end catch.
    end method. /* CleanOrphans */

end class.
