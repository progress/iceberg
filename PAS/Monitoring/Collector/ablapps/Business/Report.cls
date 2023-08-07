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
    File        : Report
    Purpose     : Generate data for reporting of stats
    Syntax      :
    Description :
    Author(s)   : Dustin Grau (dugrau@progress.com)
    Created     : Tue May 15 09:56:22 EDT 2018
    Notes       :
  ----------------------------------------------------------------------*/

@program FILE(name="Report.cls", module="AppServer").
@openapi.openedge.export FILE(type="REST", executionMode="singleton", useReturnValue="false", writeDataSetBeforeImage="false").
@progress.service.resource FILE(name="report", URI="/report", schemaName="", schemaFile="").

using Progress.Lang.* from propath.
using Progress.Json.ObjectModel.* from propath.

block-level on error undo, throw.

class Business.Report use-widget-pool:

    {Common/health.i}
    {Common/report.i}

    define private temp-table ttGroup
        field timestamp   as datetime-tz
        field sampleGroup as character
        .

    method private character FormatMsTime ( input piValue as int64 ):
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
    end method. /* FormatMsTime */

    method private void CalculateRequestPercentages ( ):
        define variable iTotalAppRequests   as int64 no-undo initial 0.
        define variable iTotalAgentRequests as int64 no-undo initial 0.

        define buffer bAgentSession for agentSession.

        for each agentSession no-lock
           break by agentSession.agentSessionUUID
                 by agentSession.agentPID:
            if first-of(agentSession.agentPID) then
                assign iTotalAgentRequests = 0.

            assign
                iTotalAppRequests   = iTotalAppRequests + agentSession.requestCount
                iTotalAgentRequests = iTotalAgentRequests + agentSession.requestCount
                .

            if last-of(agentSession.agentPID) then do:
                for each bAgentSession exclusive-lock
                   where bAgentSession.agentPID eq agentSession.agentPID:
                    assign bAgentSession.totalAgentReqs = iTotalAgentRequests.
                end. /* for each bAgentSession */
            end. /* last-of */
        end. /* for each agentSession */

        for each agentSession exclusive-lock:
            assign
                agentSession.totalAppReqs   = iTotalAppRequests
                agentSession.requestPercent = ((agentSession.requestCount / iTotalAppRequests) * 100) when iTotalAppRequests gt 0
                .
        end.
    end method. /* CalculateRequestPercentages */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/servers", alias="servers", mediaType="application/json").
    method public void GetServerList ( output appServer as handle ):
        define variable iGrpCount as integer no-undo.

        assign appServer = temp-table appServer:handle.

        empty temp-table appServer.

        for each ServerInfo no-lock
              by ServerInfo.ApplicationName
              by ServerInfo.ServerName:
            create appServer.
            assign
                appServer.applicationName = ServerInfo.ApplicationName
                appServer.serverName      = ServerInfo.ServerName
                appServer.appServerUUID   = ServerInfo.ServerUUID
                .

            /* First, find all sample groups for this agent. */
            empty temp-table ttGroup.
            for each AgentSample no-lock
               where AgentSample.ServerUUID eq ServerInfo.ServerUUID
               break by AgentSample.SampleGroup:
                if first-of(AgentSample.SampleGroup) then do:
                    create ttGroup.
                    assign
                        ttGroup.sampleGroup = AgentSample.SampleGroup
                        ttGroup.timestamp   = AgentSample.Timestamp
                        .
                end.
            end. /* for each ServerInfo */

            /* Next, add only the last 10 group names in reverse chronological order. */
            assign iGrpCount = 1.
            for each ttGroup no-lock
                  by ttGroup.timestamp descending:
                if iGrpCount le 10 then
                    appServer.sampleGroup[iGrpCount] = ttGroup.SampleGroup.
                assign iGrpCount = iGrpCount + 1.
            end. /* for each ttGroup */

            release appServer no-error.
        end. /* for each ServerInfo*/
    end method. /* GetServerList */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/sessions", alias="sessions", mediaType="application/json").
    method public void GetSessionList ( input  serverUUID   as character,
                                        input  sampleGroup  as character,
                                        output agentSession as handle ):
        define variable fMemBytes   as decimal  no-undo initial 0.
        define variable fMemMax     as decimal  no-undo initial 0.
        define variable fMemMin     as decimal  no-undo initial 0.
        define variable fMemTotal   as decimal  no-undo initial 0.
        define variable iMemSample  as int64    no-undo initial 0.
        define variable iObjCount   as int64    no-undo initial 0.
        define variable iObjMax     as int64    no-undo initial 0.
        define variable iObjSample  as int64    no-undo initial 0.
        define variable iSmplCount  as int64    no-undo initial 0.
        define variable iGrpCount   as int64    no-undo initial 0.
        define variable iReqTime    as int64    no-undo initial 0.
        define variable iSort       as int64    no-undo initial 1.
        define variable dLastSample as datetime no-undo.

        assign agentSession = temp-table agentSession:handle.

        if sampleGroup eq "All" then assign sampleGroup = "". /* Normalize the option for all groups. */

        empty temp-table agentSession.

        /* Return a list of ALL agents and their sessions for the given application/server. */
        for each SessionInfo no-lock
           where SessionInfo.ServerUUID eq serverUUID
              by SessionInfo.Started
              by SessionInfo.AgentPID
              by SessionInfo.SessionID:

            /* Create record for each agent-session. */
            create agentSession.
            assign
                agentSession.sessionSort      = iSort
                agentSession.agentPID         = SessionInfo.AgentPID
                agentSession.agentDisplay     = string(SessionInfo.AgentPID)
                agentSession.sessionID        = SessionInfo.SessionID
                agentSession.startedDate      = date(SessionInfo.Started) /* Extract only the date! */
                agentSession.startedTime      = entry(2, string(SessionInfo.Started), " ") when num-entries(string(SessionInfo.Started), " ") ge 2
                agentSession.agentSessionUUID = SessionInfo.SessionUUID
                .

            assign
                fMemBytes   = 0
                fMemMax     = 0
                fMemMin     = 0
                fMemTotal   = 0
                iMemSample  = 0
                iObjCount   = 0
                iObjMax     = 0
                iObjSample  = 0
                iSmplCount  = 0
                iReqTime    = 0
                iSort       = iSort + 1
                dLastSample = ?
                .

            /* Get the timestamp of the very first request for this agent-session. */
            firstreqblk:
            for each SessionSample no-lock
               where SessionSample.SessionUUID eq SessionInfo.SessionUUID
                 and (sampleGroup eq "" or SessionSample.SampleGroup eq sampleGroup)
                  by SessionSample.Timestamp:
                for first RequestInfo no-lock
                    where RequestInfo.SampleUUID eq SessionSample.SampleUUID
                      and RequestInfo.StartTime ne ?
                       by RequestInfo.StartTime:
                    assign agentSession.requestStart = RequestInfo.StartTime.
                end. /* for first RequestInfo */

                if agentSession.requestStart ne ? then leave firstreqblk.
            end. /* for each SessionSample */

            /* Get the timestamp of the very last request for this agent-session. */
            for each SessionSample no-lock
               where SessionSample.SessionUUID eq SessionInfo.SessionUUID
                 and (sampleGroup eq "" or SessionSample.SampleGroup eq sampleGroup)
                  by SessionSample.Timestamp:
                for last RequestInfo no-lock
                   where RequestInfo.SampleUUID eq SessionSample.SampleUUID
                     and RequestInfo.EndTime ne ?
                      by RequestInfo.EndTime:
                    assign agentSession.requestLast = RequestInfo.EndTime.
                end. /* for last RequestInfo */
            end. /* for each SessionSample */

            /* If request did not have a known end time, assume last request was recieved as of now. */
            if agentSession.requestLast eq ? then
                assign agentSession.requestLast = now.

            /* Get a count of total requests for this agent-session. */
            for each RequestInfo no-lock
               where RequestInfo.ServerUUID eq SessionInfo.ServerUUID
                 and RequestInfo.SessionUUID eq SessionInfo.SessionUUID:
                assign
                    agentSession.requestCount = agentSession.requestCount + 1
                    iReqTime                  = iReqTime + RequestInfo.Elapsed
                    .
            end. /* for each agentSession */

            /* Cycle through samples for each session of agent. */
            for each SessionSample no-lock
               where SessionSample.SessionUUID eq SessionInfo.SessionUUID
                 and (sampleGroup eq "" or SessionSample.SampleGroup eq sampleGroup)
                  by SessionSample.Timestamp:
                /* Count the total samples reported for this session. */
                assign iSmplCount = iSmplCount + 1.

                /* Count objects but only for samples with a non-zero value. */
                if SessionSample.ObjectCount gt 0 then
                    assign
                        iObjCount  = iObjCount + SessionSample.ObjectCount
                        iObjMax    = max(iObjMax, SessionSample.ObjectCount)
                        iObjSample = iObjSample + 1
                        .

                /* Calculate memory metrics but only for samples with a non-zero value. */
                if SessionSample.MemoryBytes gt 0 then do:
                    assign
                        fMemBytes  = round(SessionSample.MemoryBytes / 1024, 1)
                        fMemMax    = max(fMemMax, fMemBytes)
                        fMemMin    = min(fMemMin, fMemBytes)
                        fMemTotal  = fMemTotal + fMemBytes
                        iMemSample = iMemSample + 1
                        .
                    if fMemMin eq 0 then assign fMemMin = fMemBytes.
                end. /* Non-Zero Memory */

                /* Get the last sample time when this session appears. */
                assign dLastSample = SessionSample.Timestamp.
            end. /* for each SessionInfo */

            assign /* Assign min/max/avg values for the session. */
                agentSession.memoryMin      = fMemMin
                agentSession.memoryMax      = fMemMax
                agentSession.memoryAvg      = round((fMemTotal / iMemSample), 2) when iMemSample gt 0
                agentSession.memoryDelta    = round((fMemMax - fMemMin), 2)
                agentSession.memorySamples  = iMemSample
                agentSession.objectMax      = iObjMax
                agentSession.objectTotal    = iObjCount
                agentSession.objectAvg      = round((iObjCount / iObjSample), 1) when iObjSample gt 0
                agentSession.objectSamples  = iObjSample
                agentSession.totalSamples   = iSmplCount
                agentSession.lastSample     = if dLastSample ne ? then dLastSample else now
                agentSession.requestTimeAvg = round((iReqTime / agentSession.requestCount), 1) when agentSession.requestCount gt 0
                .

            assign
                agentSession.requestDuration = interval(agentSession.requestLast, agentSession.requestStart, "seconds")
                agentSession.requestPerSec   = if agentSession.requestDuration gt 0 then (agentSession.requestCount / agentSession.requestDuration) else 0
                /* Calculate the elapsed runtime by getting the difference of a last sample time and the start of the session. */
                agentSession.elapsedRuntime  = FormatMsTime(interval(agentSession.lastSample, SessionInfo.Started, "milliseconds"))
                .

            release agentSession no-error.
        end. /* for each ServerInfo, SessionInfo */

        /* Get some totals for the entire application. */
        this-object:CalculateRequestPercentages().
    end method. /* GetSessionList */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/metrics", alias="metrics", mediaType="application/json").
    method public void GetAgentMetrics ( input  serverUUID   as character,
                                         input  agentPID     as integer,
                                         input  sessionID    as integer,
                                         input  sampleGroup  as character,
                                         output agentMetrics as handle ):
        define variable lSuccess    as logical  no-undo.
        define variable dLastSample as datetime no-undo initial ?.
        define variable fMemPeak    as decimal  no-undo initial 0. /* Tracked across all sessions for this agent. */
        define variable fMemBytes   as decimal  no-undo initial 0.
        define variable fMemMax     as decimal  no-undo initial 0.
        define variable fMemMin     as decimal  no-undo initial 0.
        define variable fMemTotal   as decimal  no-undo initial 0.
        define variable fAgentMem   as decimal  no-undo initial 0.
        define variable iMemSample  as int64    no-undo initial 0.
        define variable iObjCount   as int64    no-undo initial 0.
        define variable iObjMax     as int64    no-undo initial 0.
        define variable iObjSample  as int64    no-undo initial 0.
        define variable iSmplCount  as int64    no-undo initial 0.
        define variable iReqTime    as int64    no-undo initial 0.
        define variable iReqCount   as int64    no-undo initial 0.
        define variable iSort       as int64    no-undo initial 1.

        assign agentMetrics = dataset agentMetrics:handle.

        if sampleGroup eq "All" then assign sampleGroup = "". /* Normalize the option for all groups. */

        empty temp-table instanceAgent.
        empty temp-table agentStat.
        empty temp-table sessionActivity.
        empty temp-table agentSession.
        empty temp-table sessionStat.

        /* Get the agent stats for this server and sample group. */
        for each AgentSample no-lock
           where AgentSample.ServerUUID eq serverUUID
             and AgentSample.AgentPID eq agentPID
             and (sampleGroup eq "" or AgentSample.SampleGroup eq sampleGroup)
           break by AgentSample.AgentPID
                 by AgentSample.Timestamp:
            if first-of(AgentSample.AgentPID) then do:
                create instanceAgent.
                assign
                    instanceAgent.appServerUUID = serverUUID
                    instanceAgent.agentPID      = agentPID
                    .
                release instanceAgent no-error.
            end.

            create agentStat.
            assign
                agentStat.agentPID       = agentPID
                agentStat.agentStarted   = AgentSample.AgentStarted
                agentStat.dateSample     = AgentSample.Timestamp
                agentStat.busySessions   = AgentSample.BusySessions
                agentStat.requestCount   = 0
                .
            release agentStat no-error.

            /* Remember the current overhead memory value for this agent. */
            if AgentSample.OverheadMemory ne ? and AgentSample.OverheadMemory gt 0 then
                assign fAgentMem = round(AgentSample.OverheadMemory / 1024, 1).
        end. /* AgentSample */

        /* Return a specific agent-session's memory/object data over time for each session sample. */
        for each SessionInfo no-lock
           where SessionInfo.ServerUUID eq serverUUID
             and (agentPID eq 0 or SessionInfo.AgentPID eq agentPID)
             and (sessionID eq 0 or SessionInfo.SessionID eq sessionID)
              by SessionInfo.Started
              by SessionInfo.AgentPID
              by SessionInfo.SessionID:

            /* Create record for each agent-session. */
            create agentSession.
            assign
                agentSession.sessionSort      = iSort
                agentSession.agentPID         = SessionInfo.AgentPID
                agentSession.agentDisplay     = string(SessionInfo.AgentPID)
                agentSession.sessionID        = SessionInfo.SessionID
                agentSession.startedDate      = date(SessionInfo.Started) /* Extract only the date! */
                agentSession.startedTime      = entry(2, string(SessionInfo.Started), " ") when num-entries(string(SessionInfo.Started), " ") ge 2
                agentSession.agentSessionUUID = SessionInfo.SessionUUID
                .

            assign
                fMemBytes  = 0
                fMemMax    = 0
                fMemMin    = 0
                fMemTotal  = 0
                iMemSample = 0
                iObjCount  = 0
                iObjMax    = 0
                iObjSample = 0
                iSmplCount = 0
                iReqTime   = 0
                iReqCount  = 0
                iSort      = iSort + 1
                .

            /* Get the timestamp of the very first request for this agent-session. */
            firstreqblk:
            for each SessionSample no-lock
               where SessionSample.SessionUUID eq SessionInfo.SessionUUID
                 and (sampleGroup eq "" or SessionSample.SampleGroup eq sampleGroup)
                  by SessionSample.Timestamp:
                for first RequestInfo no-lock
                    where RequestInfo.SampleUUID eq SessionSample.SampleUUID
                      and RequestInfo.StartTime ne ?
                       by RequestInfo.StartTime:
                    assign
                        agentSession.requestStart = RequestInfo.StartTime
                        dLastSample               = RequestInfo.StartTime
                        .
                end. /* for first RequestInfo */

                if agentSession.requestStart ne ? then leave firstreqblk.
            end. /* for each SessionSample */

            /* Get the timestamp of the very last request for this agent-session. */
            for each SessionSample no-lock
               where SessionSample.SessionUUID eq SessionInfo.SessionUUID
                 and (sampleGroup eq "" or SessionSample.SampleGroup eq sampleGroup)
                  by SessionSample.Timestamp:
                for last RequestInfo no-lock
                   where RequestInfo.SampleUUID eq SessionSample.SampleUUID
                     and RequestInfo.EndTime ne ?
                      by RequestInfo.EndTime:
                    assign agentSession.requestLast = RequestInfo.EndTime.
                end. /* for last RequestInfo */
            end. /* for each SessionSample */

            /* If request did not have a known end time, assume last request was recieved as of now. */
            if agentSession.requestLast eq ? then
                assign agentSession.requestLast = now.

            /* Get stats for the session as based on the available samples. */
            for each SessionSample no-lock
               where SessionSample.SessionUUID eq SessionInfo.SessionUUID
                 and (sampleGroup eq "" or SessionSample.SampleGroup eq sampleGroup)
                  by SessionSample.Timestamp:
                /* Count the total samples reported for this session. */
                assign iSmplCount = iSmplCount + 1.

                /* Count objects but only for samples with a non-zero value. */
                if SessionSample.ObjectCount gt 0 then
                    assign
                        iObjCount  = iObjCount + SessionSample.ObjectCount
                        iObjMax    = max(iObjMax, SessionSample.ObjectCount)
                        iObjSample = iObjSample + 1
                        .

                /* Calculate memory metrics but only for samples with a non-zero value. */
                if SessionSample.MemoryBytes gt 0 then do:
                    assign
                        fMemBytes  = round(SessionSample.MemoryBytes / 1024, 1)
                        fMemMax    = max(fMemMax, fMemBytes)
                        fMemMin    = min(fMemMin, fMemBytes)
                        fMemTotal  = fMemTotal + fMemBytes
                        iMemSample = iMemSample + 1
                        .
                    if fMemMin eq 0 then assign fMemMin = fMemBytes.
                end. /* Non-Zero Memory */

                create sessionActivity.
                assign
                    sessionActivity.agentPID     = SessionInfo.AgentPID
                    sessionActivity.sessionID    = SessionInfo.SessionID
                    sessionActivity.dateSample   = SessionSample.Timestamp
                    sessionActivity.memoryBytes  = fMemBytes
                    sessionActivity.requestCount = 0
                    sessionActivity.avgElapsed   = 0
                    sessionActivity.maxElapsed   = 0
                    .

                create sessionStat.
                assign
                    sessionStat.agentSessionUUID  = SessionSample.SessionUUID
                    sessionStat.sessionSampleUUID = SessionSample.SampleUUID
                    sessionStat.dateSample        = SessionSample.Timestamp
                    sessionStat.memoryBytes       = fMemBytes
                    sessionStat.objectCount       = SessionSample.ObjectCount
                    .

                /* Keep a cumulative count of requests by agent/timestamp. */
                for first agentStat exclusive-lock
                    where agentStat.agentPID eq SessionInfo.AgentPID
                      and agentStat.dateSample eq SessionSample.Timestamp:
                    /* Keep tracking the cumulative MAXIMUM calculated memory value. */
                    assign fMemPeak = max(agentStat.memoryBytes + fMemMax, fMemPeak).

                    assign
                        agentStat.memoryBytes = agentStat.memoryBytes + fMemBytes
                        agentStat.memoryPeak  = fMemPeak
                        /* Use available value or take a percentage of the minimum memory as estimated overhead. */
                        agentStat.overheadMem = if fAgentMem gt 0 then fAgentMem else fMemMin * 0.6
                        .
                end. /* for first */

                /* If not the first sample, count the requests serviced by this session since the last sample. */
                for each RequestInfo no-lock
                   where RequestInfo.SampleUUID eq SessionSample.SampleUUID
                     and RequestInfo.StartTime ge dLastSample
                     and RequestInfo.StartTime lt SessionSample.Timestamp
                     and RequestInfo.EndTime ne ?:
                    assign
                        agentSession.requestCount    = agentSession.requestCount + 1
                        sessionActivity.requestCount = sessionActivity.requestCount + 1
                        sessionActivity.avgElapsed   = sessionActivity.avgElapsed + RequestInfo.Elapsed
                        sessionActivity.maxElapsed   = max(sessionActivity.maxElapsed, RequestInfo.Elapsed)
                        iReqTime                     = iReqTime + RequestInfo.Elapsed
                        .

                    /* Keep a cumulative count of requests by agent/timestamp. */
                    for first agentStat exclusive-lock
                        where agentStat.agentPID eq SessionInfo.AgentPID
                          and agentStat.dateSample eq SessionSample.Timestamp:
                        assign agentStat.requestCount = agentStat.requestCount + 1.
                    end. /* for first */
                end. /* For each request since last Sample. */

                /* Calculate the average for this particular sample. */
                assign sessionActivity.avgElapsed = if sessionActivity.requestCount gt 0 then round(sessionActivity.avgElapsed / sessionActivity.requestCount, 2) else 0.

                /* Mark this as sample as the last timestamp for comparison in the next round. */
                assign
                    dLastSample = SessionSample.Timestamp
                    iReqCount   = agentSession.requestCount
                    .

                release sessionActivity no-error.
                release sessionStat no-error.
            end. /* for each SessionInfo */

            assign /* Assign min/max/avg values for the session. */
                agentSession.memoryMin      = fMemMin
                agentSession.memoryMax      = fMemMax
                agentSession.memoryAvg      = round((fMemTotal / iMemSample), 2) when iMemSample gt 0
                agentSession.memoryDelta    = round((fMemMax - fMemMin), 2)
                agentSession.memorySamples  = iMemSample
                agentSession.objectMax      = iObjMax
                agentSession.objectTotal    = iObjCount
                agentSession.objectAvg      = round((iObjCount / iObjSample), 1) when iObjSample gt 0
                agentSession.objectSamples  = iObjSample
                agentSession.totalSamples   = iSmplCount
                agentSession.requestTimeAvg = round((iReqTime / iReqCount), 1) when iReqCount gt 0
                .

            assign
                agentSession.requestDuration = interval(agentSession.requestLast, agentSession.requestStart, "seconds")
                agentSession.requestPerSec   = if agentSession.requestDuration gt 0 then (agentSession.requestCount / agentSession.requestDuration) else 0
                .

            release agentSession no-error.
        end. /* for each SessionInfo */

        /* Get some totals for the entire application. */
        this-object:CalculateRequestPercentages().
    end method. /* GetSessionMetrics */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/objects", alias="objects", mediaType="application/json").
    method public void GetABLObjects ( input  objectCount  as integer,
                                       input  sampleUUID   as character,
                                       input  sampleGroup  as character,
                                       input  sampleDate   as datetime,
                                       output sampleObject as handle ):
        assign sampleObject = temp-table sampleObject:handle.

        if sampleGroup eq "All" then assign sampleGroup = "". /* Normalize the option for all groups. */

        /* Locate the first session sample with the given object count, nearest the given date. */
        find first SessionSample no-lock
             where SessionSample.SampleUUID eq sampleUUID
               and (sampleGroup eq "" or SessionSample.SampleGroup eq sampleGroup)
               and SessionSample.ObjectCount eq objectCount no-error.
        if not available(SessionSample) then
            find first SessionSample no-lock
                 where (sampleGroup eq "" or SessionSample.SampleGroup eq sampleGroup)
                   and SessionSample.ObjectCount eq objectCount
                   and SessionSample.Timestamp gt sampleDate no-error.

        empty temp-table sampleObject.

        /* Return a list of objects for a given sample interval. */
        if available(SessionSample) then
            for each ABLObject no-lock
               where ABLObject.SampleUUID eq SessionSample.SampleUUID:
                create sampleObject.
                assign
                    sampleObject.handleId  = ABLObject.HandleId
                    sampleObject.source    = ABLObject.Source
                    sampleObject.line      = ABLObject.Line
                    sampleObject.origReqId = ABLObject.RequestNum
                    sampleObject.name      = ABLObject.Name
                    sampleObject.objType   = ABLObject.ObjType
                    sampleObject.objSize   = ABLObject.Size
                    .
                release sampleObject no-error.
            end. /* for each ABLObject */
    end method. /* GetABLObjects */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/requests", alias="requests", mediaType="application/json").
    method public void GetRequests ( input  sessionUUID     as character,
                                     input  sampleGroup     as character,
                                     output ablRequestStack as handle ):
        assign ablRequestStack = dataset ablRequestStack:handle.

        empty temp-table ablRequest.
        empty temp-table requestStack.

        if sampleGroup eq "All" then assign sampleGroup = "". /* Normalize the option for all groups. */

        /* Return all requests as of the first sample for the given group (or start of sampling). */
        for each SessionSample no-lock
           where (sessionUUID eq "" or SessionSample.SessionUUID eq sessionUUID)
             and (sampleGroup eq "" or SessionSample.SampleGroup eq sampleGroup)
              by SessionSample.Timestamp:

            /* Return a list of objects for a given sample interval. */
            for each RequestInfo no-lock
               where RequestInfo.SampleUUID eq SessionSample.SampleUUID:
                create ablRequest.
                assign
                    ablRequest.agentSessionUUID = RequestInfo.SessionUUID
                    ablRequest.requestUUID      = RequestInfo.RequestUUID
                    ablRequest.requestNum       = RequestInfo.RequestNum
                    ablRequest.requestID        = substitute("&1:&2:&3", RequestInfo.WebAppName, RequestInfo.Transport, RequestInfo.RequestID)
                    ablRequest.programName      = RequestInfo.ProcName
                    ablRequest.startTime        = string(RequestInfo.StartTime)
                    ablRequest.endTime          = string(RequestInfo.EndTime)
                    ablRequest.elapsedTime      = RequestInfo.Elapsed
                    ablRequest.hasCallTree      = false
                    ablRequest.hasProfiler      = false
                    .

                for first CallTree no-lock
                    where CallTree.RequestUUID eq RequestInfo.RequestUUID:
                    assign ablRequest.hasCallTree = true.
                end. /* for first CallTree */

                for first ProfilerData no-lock
                    where ProfilerData.SessionUUID eq sessionUUID
                      and ProfilerData.Timestamp eq RequestInfo.StartTime:
                    assign
                        ablRequest.hasProfiler = true
                        ablRequest.profilerRec = string(rowid(ProfilerData))
                        .
                end. /* for first ProfilerData */

                /* Add any available CallStack entries to the appropriate table. */
                for each CallStack no-lock
                   where CallStack.RequestUUID eq RequestInfo.RequestUUID:
                    create requestStack.
                    assign
                        requestStack.requestUUID = CallStack.RequestUUID
                        requestStack.stackOrder  = CallStack.StackOrder
                        requestStack.line        = CallStack.Line
                        requestStack.routine     = CallStack.Routine
                        requestStack.source      = CallStack.Source
                        .
                    release requestStack no-error.
                end. /* for each CallStack */

                release ablRequest no-error.
            end. /* for each RequestInfo */
        end. /* for each SessionSample */
    end method. /* GetRequests */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/callTree", alias="callTree", mediaType="application/json").
    method public void GetCallTreeData ( input  requestUUID  as character,
                                         output callTreeData as longchar ):
        define variable oParser as ObjectModelParser no-undo.
        define variable oData   as JsonArray no-undo.
        define variable iLine   as integer   no-undo.
        define variable iTotal  as integer   no-undo.
        define variable lcData  as longchar  no-undo initial "".
        define variable lcTemp  as longchar  no-undo initial "".
        define variable cTemp   as character no-undo.

        find first RequestInfo no-lock
             where RequestInfo.RequestUUID eq requestUUID no-error.
        if not available(RequestInfo) then return.

        /* Use version 4 of the profiler output which includes the calltree section. */
        /* This also provides some basic but useful AVM Information for the final report. */
        assign callTreeData = substitute('4 &1 "Call-Tree for Request #&2" &3 "" ~{~}~n.',
                                         trim(string(RequestInfo.StartTime, "99/99/9999")), RequestInfo.RequestNum,
                                         trim(string(integer(truncate(mtime(RequestInfo.StartTime) / 1000, 0))), "HH:MM:SS")).

        /* Extract the stringified JSON array. */
        for first CallTree no-lock
            where CallTree.RequestUUID eq requestUUID:
            copy-lob CallTree.Data to lcData no-error.
        end.

        if lcData eq ? or lcData eq "" then return.

        /* Parse the data back to a JSON array. */
        assign oParser = new ObjectModelParser().
        assign oData = cast(oParser:Parse(lcData), JsonArray).
        assign iTotal = oData:length.

        /* Output the modules and filler data for the profiler output. */
        do iLine = 1 to iTotal:
            assign cTemp = oData:GetCharacter(iLine).
            if cTemp matches '*"' then
                assign
                    callTreeData = callTreeData + "~n" + cTemp
                    lcTemp       = lcTemp + '0 "" 0~n.~n'
                    .
        end. /* for each CallTree */

        /* Add separators and more AVM info. */
        assign callTreeData = callTreeData + "~n.~n.~n.~n.~n" + lcTemp + '.~n.~n.~n.~n0 0 ""'.

        /* Add the real calltree data at the end. */
        do iLine = 1 to iTotal:
            assign cTemp = oData:GetCharacter(iLine).
            if trim(cTemp) gt "" and not (cTemp matches '*"') then
                assign callTreeData = callTreeData + "~n" + cTemp.
        end. /* for each CallTree */

        /* Terminate the profiler output. */
        assign callTreeData = callTreeData + "~n.~n.~n".

        finally:
            assign lcData = ?.
            assign lcTemp = ?.
            delete object oParser no-error.
            delete object oData no-error.
        end finally.
    end method. /* GetCallTreeData */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/access", alias="access", mediaType="application/json").
    method public void GetAccessHistory ( input  serverUUID    as character,
                                          input  sessionUUID   as character,
                                          output accessHistory as handle ):
        define variable iCount as int64       no-undo initial 0.
        define variable iTime  as int64       no-undo.
        define variable dBegin as datetime-tz no-undo initial ?.
        define variable dLimit as datetime-tz no-undo initial ?.
        define variable dStart as datetime    no-undo.
        define variable dEnd   as datetime    no-undo.

        assign accessHistory = dataset accessHistory:handle.

        empty temp-table tomcatAccess.
        empty temp-table sessionRequest.

        /* Determine the first sample for this agent/session to limit the log results. */
        for first RequestInfo no-lock
            where RequestInfo.SessionUUID eq sessionUUID:
            assign dBegin = add-interval(datetime-tz(RequestInfo.StartTime), -1, "minutes").
        end. /* for first RequestInfo */
        if dBegin eq ? then /* No requests logged. */
            for first SessionSample no-lock
                where SessionSample.SessionUUID eq sessionUUID:
                assign dBegin = add-interval(datetime-tz(SessionSample.Timestamp), -4, "minutes").
            end. /* for first SessionSample */

        /* Determine the last sample for this agent/session to limit the log results. */
        for last RequestInfo no-lock
           where RequestInfo.SessionUUID eq sessionUUID:
            assign dLimit = add-interval(datetime-tz(RequestInfo.EndTime), 1, "minutes").
        end. /* for last RequestInfo */
        if dBegin eq ? then /* No requests logged. */
            for last SessionSample no-lock
               where SessionSample.SessionUUID eq sessionUUID:
                assign dLimit = add-interval(datetime-tz(SessionSample.Timestamp), 4, "minutes").
            end. /* for last SessionSample */

        /* Look through the access log entries, previously limited to just transport and security endpoints. */
        for each AccessLog no-lock
           where AccessLog.ServerUUID eq serverUUID
             and (AccessLog.RequestStart ge dBegin and
                  AccessLog.RequestEnd le dLimit)
              by AccessLog.RequestStart:
            assign
                iTime  = 0
                iCount = iCount + 1
                dStart = datetime(date(AccessLog.RequestStart), mtime(AccessLog.RequestStart))
                dEnd   = datetime(date(AccessLog.RequestEnd), mtime(AccessLog.RequestEnd))
                .

            create tomcatAccess.
            assign
                tomcatAccess.accessOrder  = iCount
                tomcatAccess.requestStart = string(dStart)
                tomcatAccess.requestEnd   = string(dEnd)
                tomcatAccess.threadID     = AccessLog.ThreadID
                tomcatAccess.requestVerb  = AccessLog.RequestVerb
                tomcatAccess.requestPath  = AccessLog.RequestPath
                tomcatAccess.responseCode = AccessLog.ResponseCode
                tomcatAccess.responseSize = AccessLog.ResponseSize
                tomcatAccess.responseTime = AccessLog.ResponseTime
                tomcatAccess.requestUser  = AccessLog.Username
                tomcatAccess.webAppName   = AccessLog.WebAppName
                tomcatAccess.transport    = AccessLog.Transport
                tomcatAccess.requestID    = AccessLog.RequestID
                .

            /* Locate any ABL requests that may have occurred during the elapsed time of the access. */
            for each RequestInfo no-lock
               where RequestInfo.ServerUUID eq AccessLog.ServerUUID
                 and RequestInfo.StartTime ge dStart
                 and RequestInfo.EndTime le dEnd:
                create sessionRequest.
                assign
                    sessionRequest.accessOrder  = iCount
                    sessionRequest.requestNum   = RequestInfo.RequestNum
                    sessionRequest.requestID    = substitute("&1:&2:&3", RequestInfo.WebAppName, RequestInfo.Transport, RequestInfo.RequestID)
                    sessionRequest.programName  = RequestInfo.ProcName
                    sessionRequest.startTime    = string(RequestInfo.StartTime)
                    sessionRequest.endTime      = string(RequestInfo.EndTime)
                    sessionRequest.elapsedTime  = RequestInfo.Elapsed
                    .

                /* Track total time for internal ABL requests found. */
                assign iTime = iTime + RequestInfo.Elapsed.
                release sessionRequest no-error.
            end. /* for each ABLObject */

            if iTime gt 0 then /* Show overhead for request, outside of ABL processing. */
                assign tomcatAccess.overheadTime = tomcatAccess.responseTime - iTime.

            release tomcatAccess no-error.
        end. /* for each AccessLog */
    end method. /* GetAccessHistory */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/profilerList", alias="profilerList", mediaType="application/json").
    method public void GetProfilerList ( input  sessionUUID  as character,
                                         input  requestDate  as datetime,
                                         output profilerList as handle ):
        assign profilerList = temp-table profilerList:handle.

        empty temp-table profilerList.

        if requestDate eq ? then
            for each ProfilerData no-lock
               where ProfilerData.SessionUUID eq sessionUUID:
                /* Report on all profiler data collected for this session. */
                create profilerList.
                assign
                    profilerList.agentSessionUUID = ProfilerData.SessionUUID
                    profilerList.timestamp        = ProfilerData.Timestamp
                    profilerList.profileSize      = round(ProfilerData.ProfileBytes / 1024, 1)
                    profilerList.profilerRec      = string(rowid(ProfilerData))
                    .
            end. /* for each ProfilerData */
        else
            for each ProfilerData no-lock
               where ProfilerData.SessionUUID eq sessionUUID
                 and ProfilerData.Timestamp ge add-interval(requestDate, -10, "minutes")
                 and ProfilerData.Timestamp le add-interval(requestDate, 10, "minutes"):
                /* Report on data collected within 10 minutes (before/after) the given request date. */
                create profilerList.
                assign
                    profilerList.agentSessionUUID = ProfilerData.SessionUUID
                    profilerList.timestamp        = ProfilerData.Timestamp
                    profilerList.profileSize      = round(ProfilerData.ProfileBytes / 1024, 1)
                    .
            end. /* for each ProfilerData */
    end method. /* GetProfilerList */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/profilerData", alias="profilerData", mediaType="application/json").
    method public void GetProfilerData ( input  profilerRowID as character,
                                         output profilerOut   as longchar ):
        /* Return the profiler data for the exact record. */
        for first ProfilerData no-lock
            where rowid(ProfilerData) eq to-rowid(profilerRowID):
            copy-lob from ProfilerData.CodeProfile to profilerOut no-error.
        end. /* for first ProfilerData */
    end method. /* GetProfilerData */


    method private datetime-tz iso2DateTZ ( input pcString as character ):
        define variable cDateFormat as character no-undo.

        cDateFormat = session:date-format.
        session:date-format = 'ymd'.

        return datetime-tz(pcString).

        finally:
            session:date-format = cDateFormat.
        end finally.
    end method. /* iso2DateTZ */


    method private void ParseMessages ( input pcServerUUID as character,
                                        input piAgentPID   as integer ):
        define variable iMsg       as integer           no-undo.
        define variable iTotal     as int64             no-undo.
        define variable cRawMsg    as character         no-undo.
        define variable cTemp      as character         no-undo.
        define variable cCID       as character         no-undo.
        define variable dTime      as datetime-tz       no-undo.
        define variable oParser    as ObjectModelParser no-undo.
        define variable lcMessages as longchar          no-undo.
        define variable oMessages  as JsonArray         no-undo.

        assign oParser = new ObjectModelParser().

        for each AgentLogRaw exclusive-lock
           where AgentLogRaw.ServerUUID eq pcServerUUID
             and AgentLogRaw.AgentPID eq piAgentPID
              by AgentLogRaw.MsgSequence:

            copy-lob AgentLogRaw.MessageData to lcMessages no-error.
            assign oMessages = cast(oParser:Parse(lcMessages), JsonArray).

            message substitute("Parsing Messages: A&1", piAgentPID).
            if valid-object(oMessages) and oMessages:Length gt 0 then do:
                assign iTotal = oMessages:Length.

                msgblk:
                do iMsg = 1 to iTotal:
                    /* Get the full message line. */
                    assign cRawMsg = oMessages:GetCharacter(iMsg).

                    /* Find any pre-existing log message and skip if located. */
                    find first AgentLog no-lock
                         where AgentLog.ServerUUID eq pcServerUUID
                           and AgentLog.AgentPID   eq piAgentPID
                           and AgentLog.RawMessage eq cRawMsg no-error.
                    if available(AgentLog) then next msgblk.

                    /* Create the initial record with message as-is. */
                    create AgentLog.
                    assign
                        AgentLog.ServerUUID = pcServerUUID
                        AgentLog.AgentPID   = piAgentPID
                        AgentLog.MsgNum     = AgentLogRaw.MsgSequence + iMsg
                        AgentLog.RawMessage = cRawMsg
                        .

                    /* Parse the message to get some more useful bits out of it. */
                    assign cTemp = entry(1, cRawMsg, " ").
                    if (cTemp gt "") eq true and length(cTemp) eq 28 then do:
                        /* String should be 28 characters for ISO8601: YYYY-MM-DDTHH:MM:SS.SSS+ZZZZ */
                        assign AgentLog.Timestamp = this-object:iso2DateTZ(cTemp).

                        /* Begin parsing the rest of the string. */
                        assign cTemp = trim(substring(cRawMsg, 29)).

                        /* Check if the available message has a Client ID component. */
                        assign cCID = entry(5, cTemp, " ") when num-entries(cTemp, " ") ge 5.
                        if length(cCID) gt 5 and cCID matches "*:*:*" then do:
                            assign
                                AgentLog.WebAppName  = entry(1, cCID, ":")
                                AgentLog.Transport   = caps(entry(2, cCID, ":"))
                                AgentLog.RequestID   = entry(3, cCID, ":")
                                AgentLog.MsgType     = entry(6, cTemp, " ")
                                AgentLog.MessageText = trim(substring(cTemp, index(cTemp, AgentLog.MsgType) + length(AgentLog.MsgType)))
                                .
                        end. /* Has ClientID */
                        else
                            /* Otherwise, the rest of the raw string will be treated as the actual message. */
                            assign AgentLog.MessageText = trim(substring(cRawMsg, 29)).
                    end. /* Has Leading Timestamp */

                    release AgentLog no-error.
                end. /* do iMsg */
            end. /* valid-object */

            /* Delete the original raw record once data has been parsed. */
            delete AgentLogRaw.
        end. /* for each AgentLogRaw */

        catch err as Progress.Lang.Error:
            message substitute("Error: &1", err:GetMessage(1)).
        end catch.
        finally:
            message substitute("Parsed &1 Messages.", iMsg).
            delete object oParser no-error.
            assign lcMessages = ?.
        end finally.
    end method. /* ParseMessages */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/logs", alias="logs", mediaType="application/json").
    method public void GetAgentLog ( input  serverUUID  as character,
                                     input  agentPID    as integer,
                                     input  dateRange   as datetime-tz extent 2,
                                     output logData     as handle ):
        define variable iCount as int64 no-undo initial 1.

        assign logData = temp-table logData:handle.

        this-object:ParseMessages(serverUUID, agentPID). /* Parse the raw data into distinct message lines. */

        /* Return the last 200 messages in reverse chronological order (data will be ordered by message number for output). */
        for each AgentLog no-lock
           where AgentLog.ServerUUID eq serverUUID
             and AgentLog.AgentPID eq agentPID
              by AgentLog.Timestamp:
            if iCount gt 200 then leave.

            create logData.
            assign
                logData.msgNum    = AgentLog.MsgNum
                logData.timestamp = AgentLog.Timestamp
                logData.webApp    = AgentLog.WebAppName
                logData.transport = AgentLog.Transport
                logData.requestID = AgentLog.RequestID
                logData.msgType   = AgentLog.MsgType
                logData.msgText   = AgentLog.MessageText
                iCount            = iCount + 1
                .
        end. /* for each AgentLog */
    end method. /* GetAgentLog */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/health", alias="health", mediaType="application/json").
    method public void HealthReport ( input  serverUUID  as character,
                                      input  trendPeriod as integer,
                                      output healthTrend as handle ):
        define variable dLastTime as datetime-tz no-undo.
        define variable iOSHealth as integer     no-undo.
        define variable iTomcatID as integer     no-undo.

        assign healthTrend = dataset healthTrend:handle.

        if (serverUUID gt "") ne true then undo, throw new AppError("Server UUID Missing", 0).

        empty temp-table healthProbe.
        empty temp-table probeData.

        /* If no trend period is specified, default to 1 hour. */
        if trendPeriod eq ? or trendPeriod eq 0 then
            assign trendPeriod = 1.

        /* Track the overall health probe (ID 1). */
        for first HealthCheckConfig no-lock
            where HealthCheckConfig.ServerUUID eq serverUUID
              and HealthCheckConfig.probeid eq 1:
            create healthProbe.
            assign
                healthProbe.probeID   = HealthCheckConfig.probeid
                healthProbe.parentID  = HealthCheckConfig.parentid
                healthProbe.probeName = HealthCheckConfig.config_name
                .
        end. /* for first HealthConfig */

        /* Get all of the top-level probes under the overall health probe (ID 1). */
        for each HealthCheckConfig no-lock
           where HealthCheckConfig.ServerUUID eq serverUUID
             and HealthCheckConfig.parentid eq 1
             and HealthCheckConfig.enabled:
            /* Skip if we somehow find a duplicate of this probeID. */
            if can-find(first healthProbe where healthProbe.probeID eq HealthCheckConfig.probeid no-lock) then next.

            /* Ignore the overall OS Health score for later. */
            if HealthCheckConfig.config_name eq "OS Health" then
                assign iOSHealth = HealthCheckConfig.probeid.
            else do:
                create healthProbe.
                assign
                    healthProbe.probeID   = HealthCheckConfig.probeid
                    healthProbe.parentID  = HealthCheckConfig.parentid
                    healthProbe.probeName = HealthCheckConfig.config_name
                    .

                /* Remember the probeID for the Tomcat Health. */
                if HealthCheckConfig.config_name eq "Tomcat Health" then
                    assign iTomcatID = HealthCheckConfig.probeid.
            end.
        end. /* for each HealthConfig */

        /* Add the individual OS Health probes which may be of more interest. */
        for each HealthCheckConfig no-lock
           where HealthCheckConfig.ServerUUID eq serverUUID
             and HealthCheckConfig.parentid eq iOSHealth
             and HealthCheckConfig.enabled:
            /* Skip if we somehow find a duplicate of this probeID. */
            if can-find(first healthProbe where healthProbe.probeID eq HealthCheckConfig.probeid no-lock) then next.

            create healthProbe.
            assign
                healthProbe.probeID   = HealthCheckConfig.probeid
                healthProbe.parentID  = HealthCheckConfig.parentid
                healthProbe.probeName = HealthCheckConfig.config_name
                .
        end. /* for each HealthConfig */

        /* Add the individual Tomcat Health probes which may be of more interest. */
        for each HealthCheckConfig no-lock
           where HealthCheckConfig.ServerUUID eq serverUUID
             and HealthCheckConfig.parentid eq iTomcatID
             and HealthCheckConfig.enabled:
            /* Skip if we somehow find a duplicate of this probeID. */
            if can-find(first healthProbe where healthProbe.probeID eq HealthCheckConfig.probeid no-lock) then next.

            create healthProbe.
            assign
                healthProbe.probeID   = HealthCheckConfig.probeid
                healthProbe.parentID  = HealthCheckConfig.parentid
                healthProbe.probeName = HealthCheckConfig.config_name
                .
        end. /* for each HealthConfig */

        /* Find the last (non-ignored) data point for this serverUUID. */
        for last HealthCheckData no-lock
           where HealthCheckData.ServerUUID eq serverUUID
             and not HealthCheckData.ignore
              by HealthCheckData.lastpoll:
            assign dLastTime = HealthCheckData.lastpoll.
        end.

        /* Get data for every probe found within the last-specified trend period. */
        for each healthProbe no-lock:
            for each HealthCheckData no-lock
               where HealthCheckData.ServerUUID eq serverUUID
                 and HealthCheckData.probeid eq healthProbe.probeID
                 and HealthCheckData.lastpoll ge add-interval(dLastTime, (trendPeriod * -1), "hours")
                 and not HealthCheckData.ignore:
                create probeData.
                assign
                    probeData.probeID    = HealthCheckData.probeid
                    probeData.health     = (HealthCheckData.health * 100) /* Return as a percentage out of 100. */
                    probeData.isMarginal = HealthCheckData.marginal
                    probeData.isCritical = HealthCheckData.critical
                    probeData.pollTime   = HealthCheckData.lastpoll
                    .
            end. /* for each HealthData */
        end. /* for each healthProbe */

        catch err as Progress.Lang.Error:
            message substitute("Error Preparing Health Trends: &1", err:GetMessage(1)).
        end catch.
    end method. /* ParseHealth */

end class.