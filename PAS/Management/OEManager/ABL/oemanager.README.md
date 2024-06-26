# OEManager CLI Tools - Usage Guide #

Execute the `oemanager.[bat|sh]` command to run the desired tasks from the command line. Default values will be inherited automatically for HTTP/S ports, server paths, the instance's name, and the default ABL Application name. Any required or optional parameters may be overridden via the command line or by editing the `oemanager.properties` file in advance, with modified values being honored in that order.

Note that each request to an OEM-API endpoint will be automatically logged to an `oemanager.log` file. No sensitive data will be included in these logged messages, only PID's and operationally-relevant information will be included in the URL or as query parameters to the API endpoint.

## Basic Usage ##

The following represents the default usage for all tasks which can be executed using the CLI tools and is the standard output when the `oemanager.[bat|sh]` command is run without a task name.

     Usage Instructions:

     TCMAN Shortcuts:

     oemanager query    - Use TCMAN to query the PAS instance

     oemanager startup  - Use TCMAN to start the PAS instance
                          [OPTIONAL] -Dtimeout=300 - Time (seconds) to wait for a proper startup

     oemanager shutdown - Use TCMAN to stop the PAS instance
                          [OPTIONAL] -Dtimeout=300 - Time (seconds) to wait for a proper shutdown


     Support Tools:

     oemanager inventory - Bundle useful PAS instance files (as .zip) for support tickets


     Status/Info:

     oemanager status - [RO] Obtain MSAgent/connection status information for an ABL App
                        [REQUIRED]  -Dablapp=oepas1 - ABL Application name, defaulting to the instance name if not changed
                        [OPTIONAL] -Dbasemem=819200 - Minimum memory threshold (bytes) to consider as 'unused' agent sessions

     oemanager stacks - [RO] Obtain stack information for all MSAgents for an ABL App
                        [REQUIRED] -Dablapp=oepas1       - ABL Application name, defaulting to the instance name if not changed
                        [OPTIONAL]    -Dpid=[AGENT_PID]  - Limit stack information to a specific MSAgent process ID
                        [OPTIONAL] -Dsessid=[SESSION_ID] - Limit stack information to a specific ABL Session ID
                                                           Requires specifying an MSAgent via -Dpid=[AGENT_PID]

     oemanager flush  - [RO] Flush the available deferred log buffer to agent log file
                         [REQUIRED] -Dablapp=oepas1 - ABL Application name, defaulting to the instance name if not changed

     oemanager locks  - [RO] Display database users and their table locks related to an MSAgent-Session
                        This utilizes a single DBConnection; edit the 'locks' task in build.xml to add more as necessary
                        Note: Only provides session data if using self-service DB connections for OE versions under 12.5
                        [REQUIRED] -Dablapp=oepas1    - ABL Application name, defaulting to the instance name if not changed
                        [REQUIRED]     -Dpf=[PF_NAME] - PF file to use for database connection(s)

     oemanager users  - [RO] Alias for 'locks' task


     Agent Management:

     oemanager add     - Add (read: start) one new MSAgent for an ABL App
                         [REQUIRED] -Dablapp=oepas1 - ABL Application name, defaulting to the instance name if not changed

     oemanager close   - Perform a 'soft restart' of an ABL App (runs: status, flush + trimhttp + stop, status)
                                          For this task the 'trimhttp' will be called with the termination option 1 (forced)
                         [REQUIRED] -Dablapp=oepas1        - ABL Application name, defaulting to the instance name if not changed
                         [REQUIRED] -Dwebapp=[WEBAPP_NAME] - WebApp for Tomcat Manager to terminate active client sessions
                                     The given WebApp is expected to be associated with the provided -Dablapp name
                         [OPTIONAL]  -Dsleep=1             - Sleep time in minutes after stop, prior to final 'status' output

     oemanager reset   - Reset an aspect of each MSAgent for an ABL App
                         [REQUIRED]    -Dablapp=oepas1 - ABL Application name, defaulting to the instance name if not changed
                         [REQUIRED] -Dresettype=stats  - Type may be one of the following [stats|logs]

     oemanager stop    - Gracefully stop one or all MSAgents (+stacks output) for an ABL App
                         [REQUIRED]     -Dablapp=oepas1 - ABL Application name, defaulting to the instance name if not changed
                         [OPTIONAL] -Dwaitfinish=120000 - How long to wait (milliseconds) if the MSAgent is busy serving a request
                         [OPTIONAL]  -Dwaitafter=60000  - Additional time to wait (milliseconds) before killing [hard stop] the MSAgent
                         [OPTIONAL]        -Dpid=[AGENT_PID] - Numeric process ID for a specific MSAgent to be stopped


     Session Management:

     Note: All trim actions listed below will write application stack information to a file.

     oemanager trimsingle - Trim a single ABL Session (via the Agent Manager) for a specific MSAgent
                            [REQUIRED]       -Dablapp=oepas1       - ABL Application name, defaulting to the instance name if not changed
                            [REQUIRED]          -Dpid=[AGENT_PID]  - Numeric process ID of the MSAgent for context
                            [REQUIRED]       -Dsessid=[SESSION_ID] - Numeric ID for the ABL Session to be stopped
                            [OPTIONAL] -Dterminateopt=0            - Termination Option: 0=graceful, 1=forced, 2=finish+stop

     oemanager trimall    - Trim all available ABL Sessions (via the Agent Manager) for each MSAgent for an ABL App
                            Note: For any busy sessions considered stuck use 'trimhttp' with a specific Session ID
                            [REQUIRED]       -Dablapp=oepas1 - ABL Application name, defaulting to the instance name if not changed
                            [OPTIONAL] -Dterminateopt=0      - Termination Option: 0=graceful, 1=forced, 2=finish+stop

     oemanager trimidle   - Trim only the IDLE ABL Sessions (via the Agent Manager) for each MSAgent for an ABL App
                            Allows for manually scaling down an MSAgent which may have many unused ABL Sessions
                            [REQUIRED]       -Dablapp=oepas1 - ABL Application name, defaulting to the instance name if not changed
                            [OPTIONAL] -Dterminateopt=0      - Termination Option: 0=graceful, 1=forced, 2=finish+stop

     oemanager trimhttp   - Trim one or all Client HTTP Sessions (via the Session Manager) for an ABLApp + WebApp
                            Terminating a client HTTP session will also terminate its associated ABL Session
                            [REQUIRED]       -Dablapp=oepas1        - ABL Application name, defaulting to the instance name if not changed
                            [REQUIRED]       -Dwebapp=[WEBAPP_NAME] - WebApp for Tomcat Manager to terminate active sessions
                                              The given WebApp is expected to be associated with the provided -Dablapp name
                            [OPTIONAL]       -Dsessid=[SESSION_ID]  - Alphanumeric Client Session ID to be stopped
                                              When no session ID provided, all available Client HTTP Sessions will be expired
                            [OPTIONAL] -Dterminateopt=0             - Termination Option: 0=graceful, 1=forced, 2=finish+stop

     oemanager refresh    - Refresh ABL Sessions for each MSAgent for an ABL App
                            Note: This will terminate all sessions using the 'finish+stop' option,
                                  which prepares the MSAgent to pick up available R-code changes.
                                  Use this only during a 'quiet period' for your application.
                            [REQUIRED] -Dablapp=oepas1 - ABL Application name, defaulting to the instance name if not changed

## Tailoring ##

Some tasks denote optional or required parameters, while all will use a set of common parameters either derived from the local PAS instance or specified via the command line or `oemanager.properties` file. When necessary to override any property values, simply pass as `name=value` on the command line or uncomment the property name and set a default value within the `oemanager.properties`.

The output for any generated files from available tasks will be placed in the location referred to by the `-Doutdir` value. This may be one of 2 built-in options, `BIN` or `TMP` for the deployed utils directory (`CATALINA_BASE/utils`) or temp folder (`CATALINA_BASE/temp`), respectively. Alternately, you may specify a full path to use for all output.

**Examples:**

- The `userid` and `passwd` parameters for the oemanager/manager webapps must always be specified if changed from the default of tomcat/tomcat.
- The `ablapp` (and `webapp` when necessary) should be checked and modified appropriately as it is not possible to assume which app names in the PAS instance may be intended for tasks.
- The `port` property may still be overridden by use of the `scheme` command line parameter to prefer either "http" or "https".

## Use-Cases ##

The following should cover specific cases of when and how to use the tasks listed above in the usage instructions.

### Obtaining Runtime Data ###

The following tasks are read-only and simply report data from a running PAS instance.

- **status** - This will be the most-used task for monitoring a PAS instance. It produces comprehensive output which is reminiscent of the old "ASBMAN" utility but formats and displays more relevant data meant for the PAS server architecture. In addition to statistics and metrics (when enabled) this shows the current state of all MSAgents and their ABL Sessions, and HTTP Connections to the PAS instance.
- **locks / users** - This uses one or more connected databases (specified via a .pf file) to correlate any table locks to ABL code running in the application. This utilizes information about current requests to an MSAgent, stack information, and session data to create an end-to-end picture of which user may be active in a table.
- **flush** - When deferred logging is enabled, this forces any current data in the deferred log buffer (up to the configured number of lines) to be flushed to the named log file. Please [see this following documentation](https://docs.progress.com/bundle/pas-for-openedge-management/page/Use-deferred-logging-in-PAS-for-OpenEdge.html) for instructions on configuration and enablement of the deferred logging feature.
- **stacks** - Reports the current stack information for a given ABL Application, creating a unique file for each MSAgent. This data will only be visible for MSAgents which are currently busy executing ABL code. Note that all tasks which terminate sessions or MSAgents will automatically generate this same stack information.

### Server Management Tasks ###

The following have a distinct effect on the operation of a PAS instance and should be used with caution and understanding about their intended uses.

**Instance Operations**

- **startup** - Uses the "tcman" utility using either the "pasoestart" or "oeserver" command to start the instance.
- **query** - Uses the "tcman" utility using either the "pasoestart" or "oeserver" command to query the instance.
- **shutdown** - Uses the "tcman" utility using either the "pasoestart" or "oeserver" command to stop the instance.

**ABL Application Operations**

- **add** - [Starts a new MSAgent](https://docs.progress.com/bundle/pas-for-openedge-reference/page/Add-a-multi-session-agent.html) for an ABL Application, provided the maxAgents setting has not yet been reached.
- **stop** - [Stops a running MSAgent](https://docs.progress.com/bundle/pas-for-openedge-reference/page/Stop-a-multi-session-agent.html) for an ABL Application, provided there are any MSAgents to be stopped. It is advised to use the "close" task to adequately prepare each ABL Application for termination which includes terminating any active connections and stopping all running MSAgents.
- **close** - This is a compound task which executes several existing tasks in a specific order to help safely prepare a PAS instance for shutdown. Before and after all of the following tasks are run, the "status" task is run to get a snapshot of the ABL Application. Any deferred log information is then flushed (flush), any available Client HTTP Sessions are terminated gracefully (trimhttp), and all MSAgents for the ABL Application are stopped (stop).
- **reset** - Used to either reset internal MSAgent stats or to [clear any accumulated deferred log data](https://docs.progress.com/bundle/pas-for-openedge-reference/page/Reset-deferred-log-buffer.html). In most cases these actions will not be needed unless instructed by tech support.
- **trimhttp / trimsingle / trimall / trimidle / refresh** - These tasks all affect the termination of "sessions" which requires additional context for correct operation. Please see the next section on **Trimming Sessions** for those details.

### Trimming Sessions ###

There are two primary types of "sessions" in use for PAS instances so to avoid confusion we will be using the following names to distinguish these from each other:

- **Client HTTP Session** - The session for an HTTP request from a client. Termination of an HTTP client should both cancel the active (in-flight) request as well as terminate that request's runtime context (the ABL Session).
- **ABL Session** - The runtime context in which a request executes ABL code. This is the "session" of an MSAgent where application code runs (essentially, the AVM).

We use the term "trim" as a carry-over from Classic AppServer and WebSpeed where agents could be "trimmed" to remove them from their associated broker process. Within the PAS server architecture we can effectively do the same thing, terminating an ABL Session from its associated MSAgent. However, we must be aware of any client (HTTP) connections from the Tomcat web server and gracefully end those connections in addition to terminating the ABL Session associated with that HTTP session. This can be determined by viewing the output of the **status** task. The following tasks are presented in order of suggested use.

- **trimhttp** - For active client requests to a PAS instance it is highly advisable to utilize the "trimhttp" task when termination is necessary. This will utilize both the OpenEdge Manager (oemanager.war) and Tomcat Manager (manager.war) webapps to terminate one or more Client HTTP Sessions as well as its context which is an ABL Session. So while the primary effect is to terminate the remote connection this will also reduce the total available ABL Sessions for the related MSAgent and may require the server to start a new ABL Session to handle additional client requests. This utilizes the API endpoint to [terminate a single (Client HTTP) Session](https://docs.progress.com/bundle/pas-for-openedge-reference/page/Terminate-a-session.html).
    - This task will only work against available HTTP connections. If no active sessions are present, no impact to existing ABL Sessions will be observed--in this situation one of the 3 "trim" tasks in the next section can/should be used.
- **trimsingle** / **trimall** / **trimidle** - When there are no active or bound/reserved Client HTTP Sessions the use of these may be run to reduce the number of running ABL Sessions for an MSAgent. This can be an effective means of scaling down an MSAgent which has started a large number of ABL Sessions which are no longer of use. All 3 of these tasks operate in a similar manner, first obtaining a list of current ABL Sessions for an MSAgent and iterating over those sessions using any applicable criteria. For the "trimsingle" this will only terminate an ABL Session which matches the given session ID, while "trimidle" will only terminate an ABL Session if its status is reported as "IDLE". Before each session is terminated, the current session stack information will be written to disk to identify what may have been running at the time the termination was requested. These actions utilize the API endpoint to [terminate a single ABL Session](https://docs.progress.com/bundle/pas-for-openedge-reference/page/Terminate-an-ABL-session.html) (note: link goes to the OEJMX query as we do not have a page which covers this action via the OEM REST API's).
    - It is advised to use the "**trimhttp**" task first to terminate any active or lingering Client HTTP Sessions first, then use the appropriate task above to terminate additional ABL Sessions.
- **refresh** - This task is a built-in operation which behaves similar to the "trimall" task with the Finish+Stop termination option. Whereas the "trim" tasks (just covered above) will iterate directly over each ABL Session of an MSAgent, this acts upon the MSAgent itself. In other words, refresh tells the MSAgent of an ABL Application to terminate all of its current ABL Sessions, thereby refreshing the MSAgent so that changes to the application can be picked up. The refresh API allows newly-created sessions to use the updated persistent procedures, static objects, or online schema changes, and starts running sessions against the new application code. This task was intended to be used for high-availability environments, during a "quiet period" with no user activity, where new code may be deployed but it is not desirable to shut down or restart the entire PAS instance, only to refresh the running MSAgents. More information on this operation may be found [here in the product documentation](https://docs.progress.com/bundle/pas-for-openedge-management/page/Refresh-agents-in-an-ABL-application.html).
    - **Warning:** This task is not intended to be used when a PAS instance is serving active requests, or if it may have stuck/busy sessions. You should make use of the "trim" tasks above to gracefully terminate those sessions prior to using the refresh task.
    - As an alternative to the suggested "trim" tasks, the "**close**" task will gracefully terminate any existing Client HTTP Sessions then stop all MSAgents for an ABL Application. This allows the MSAgent to return any memory back to the OS, and then use the "**add**" task to start one or more new MSAgents.
