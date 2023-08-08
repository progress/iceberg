/*------------------------------------------------------------------------
    File        : report.i
    Purpose     :
    Description :
    Author(s)   : Dustin Grau
    Created     : Tue May 15 13:07:39 EDT 2018
    Notes       :
  ----------------------------------------------------------------------*/

/* ***************************  Definitions  ************************** */

/* Standalone table to track the list of available Servers */
define temp-table appServer no-undo
    field applicationName as character
    field serverName      as character
    field appServerUUID   as character
    field sampleGroup     as character extent 10 /* This tracks the last 10 sample groups for the server/application. */
    index idxAppServer applicationName serverName
    .

/* Parent table for agentMetrics ProDataset which tracks ALL agents for a PAS instance. */
define temp-table instanceAgent no-undo
    field appServerUUID as character
    field agentPID      as int64
    index idxAgent appServerUUID agentPID
    .

/* Comprehensive list of samples captured for this agent, along with agent-level stat roll-ups. */
define temp-table agentStat no-undo
    field agentPID     as int64 serialize-hidden /* Duplicated data, doesn't need to be sent. */
    field agentStarted as datetime /* When available, denotes the true start time of the agent. */
    field dateSample   as datetime /* Should be the authority for all other sampled statistics. */
    field busySessions as int64    /* Number of concurrently-busy sessions per sampled period. */
    field requestCount as int64    /* Roll-up of requests served by all agent-sessions/sample. */
    field memoryBytes  as decimal  /* Roll-up of memory consumed by all agent-sessions/sample. */
    field memoryPeak   as decimal  /* Peak memory seen by this agent, incl. terminated sessions. */
    field overheadMem  as decimal  /* Overhead memory for this agent (management, etc.). */
    index idxAgentDate agentPID datesample
    .

/* Individual stats for each agent-session by timestamp. */
define temp-table sessionActivity no-undo
    field agentPID     as int64
    field sessionID    as int64
    field dateSample   as datetime serialize-hidden /* Duplicated data, doesn't need to be sent. */
    field memoryBytes  as decimal /* Memory for session */
    field requestCount as int64   /* Roll-up of all requests served by session since last sample. */
    field avgElapsed   as decimal /* Average request duration by session since last sample */
    field maxElapsed   as int64   /* Peak request duration by session since last sample */
    index idxAgentSessionDate agentPID sessionID datesample
    .

/* Overall session-level stats, header for sample-based stats. */
define temp-table agentSession no-undo
    field sessionSort      as int64
    field agentPID         as int64
    field agentDisplay     as character
    field sessionID        as int64
    field startedDate      as date
    field startedTime      as character
    field elapsedRuntime   as character
    field memoryAvg        as decimal
    field memoryMax        as decimal
    field memoryMin        as decimal
    field memoryDelta      as decimal
    field memorySamples    as int64
    field objectMax        as int64
    field objectTotal      as int64
    field objectAvg        as decimal
    field objectSamples    as int64
    field requestCount     as int64
    field requestStart     as datetime
    field requestLast      as datetime
    field requestDuration  as int64
    field requestPerSec    as decimal
    field requestPercent   as decimal
    field requestTimeAvg   as decimal
    field totalAppReqs     as int64
    field totalAgentReqs   as int64
    field totalSamples     as int64
    field lastSample       as datetime
    field agentSessionUUID as character /* Used to relate the sampled statistics to this session. */
    index idxSessionSort sessionSort
    .

/* Specific sample-based stats per agent-session. */
define temp-table sessionStat no-undo
    field agentSessionUUID  as character /* Used to drill-down into additional stats in UI. */
    field sessionSampleUUID as character /* Used to drill-down into additional stats in UI. */
    field dateSample        as datetime  /* Standard timestamp for metric ingestion */
    field memoryBytes       as decimal   /* Memory for session */
    field objectCount       as int64     /* DynObject count */
    index idxDate datesample
    .

/* Primary ProDataset for agent-session data, nesed to aid with parsing and data formatting/display. */
define dataset agentMetrics for instanceAgent, agentStat, sessionActivity, agentSession, sessionStat
    data-relation AgentStatDR for instanceAgent, agentStat relation-fields(agentPID,agentPID) nested
    data-relation SessionActDR for agentStat, sessionActivity relation-fields(agentPID,agentPID,dateSample,dateSample) nested
    data-relation AgentSessionDR for instanceAgent, agentSession relation-fields(agentPID,agentPID) nested
    data-relation SessionStatDR for agentSession, sessionStat relation-fields(agentSessionUUID,agentSessionUUID) nested
    .

define temp-table tomcatAccess no-undo
    field accessOrder  as int64
    field requestStart as character
    field requestEnd   as character
    field threadID     as int64
    field requestVerb  as character
    field requestPath  as character
    field responseCode as int64
    field responseSize as int64
    field responseTime as int64
    field overheadTime as int64
    field requestUser  as character
    field webAppName   as character
    field transport    as character
    field requestID    as character
    index idxAccess accessOrder
    .

/* Provides data from RequestInfo for comparison with the Tomcat Access log data. */
define temp-table sessionRequest no-undo
    field accessOrder  as int64
    field requestNum   as int64
    field requestID    as character
    field programName  as character
    field startTime    as character
    field endTime      as character
    field elapsedTime  as int64
    index idxRequest accessOrder requestNum
    .

define dataset accessHistory for tomcatAccess, sessionRequest
    data-relation AccessID for tomcatAccess, sessionRequest relation-fields(accessOrder,accessOrder) nested
    .

/* Provides data from RequestInfo for listing with CallStack data. */
define temp-table ablRequest no-undo
    field agentSessionUUID as character
    field requestUUID      as character
    field accessOrder      as int64
    field requestNum       as int64
    field requestID        as character
    field programName      as character
    field startTime        as character
    field endTime          as character
    field elapsedTime      as int64
    field hasCallTree      as logical /* Denotes that CallTree output is available. */
    field hasProfiler      as logical /* Denotes that Profiler output is available. */
    field profilerRec      as character
    index idxRequest accessOrder requestNum
    .

/* Provides data from the CallStack table. */
define temp-table requestStack no-undo
    field requestUUID as character
    field stackOrder  as int64
    field line        as int64
    field routine     as character
    field source      as character
    index idxStack requestUUID stackOrder
    .

define dataset ablRequestStack for ablRequest, requestStack
    data-relation RequestID for ablRequest, requestStack relation-fields(requestUUID,requestUUID) nested
    .

define temp-table sampleObject no-undo
    field handleId  as int64
    field source    as character
    field line      as int64
    field origReqId as int64
    field name      as character
    field objType   as character
    field objSize   as int64
    index idxHandle handleId source line
    .

define temp-table profilerList no-undo
    field agentSessionUUID as character
    field timestamp        as datetime
    field profileSize      as decimal
    field profilerRec      as character
    .

define temp-table logData no-undo
    field msgNum    as int64
    field timestamp as datetime-tz
    field webApp    as character
    field transport as character
    field requestID as character
    field msgType   as character
    field msgText   as character
    index idxLine timestamp msgNum
    .
