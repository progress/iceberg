# ABL Management #

Utilizing the [RESTful API's](https://docs.progress.com/bundle/pas-for-openedge-reference/page/REST-API-Reference-for-oemanager.war.html) offered by the oemanager WebApp, the included ABL code may provide either a comprehensive view of a running instance or means to manage an ABL Application. All actions can be run via a command-line interface using ANT tasks on either Windows or Unix environments.

## Requirements ##

Use of **proant** is required to execute the **build.xml** included. This can be accessed via the `DLC/bin` directory, typically via a **PROENV** session. If necessary, ABL code may be compiled before deployment in an environment where a 4GL compiler is not available.

**Note:** Some data may only be displayed in an OpenEdge 12 environment, such as the Dynamic Session Limit which was added as part of the Agent self-management feature. Other values such as **RequestID** (where applicable) will only be displayed if the **Enhanced MDC Logging** is enabled--this is on by default in OpenEdge 12 though it must be manually enabled in OpenEdge 11.7.x (via **openedge_setenv.[bat|sh]**). And lastly, some runtime metrics such as counts and time values will only be present if **collectMetrics** has been set to 3 for the AppServer and each WebApp (via openedge.properties).

## Deployment ##

Simply run **proant** from this directory to obtain usage information as shown below. Parameters may be specified via command-line or by editing the `build.properties` file in advance. For actions which will alter a running PAS instance (read: those without the RO indicator), individual OEM-API commands will be logged to a `commands.log` file.

     [echo] Usage Instructions:
     [echo]
     [echo]  TCMAN Shortcuts:
     [echo]
     [echo]  proant query    - Use TCMAN to query the oepas1 PAS instance
     [echo]
     [echo]  proant startup  - Use TCMAN to start the oepas1 PAS instance
     [echo]                    [OPTIONAL] -Dtimeout=300 (Time to wait for a proper startup)
     [echo]
     [echo]  proant shutdown - Use TCMAN to stop the oepas1 PAS instance
     [echo]                    [OPTIONAL] -Dtimeout=300 (Time to wait for a proper shutdown)
     [echo]
     [echo]
     [echo]  Internal Tools:
     [echo]
     [echo]  proant inventory - Bundle useful PAS instance files (as .zip) for support tickets
     [echo]
     [echo]  proant compile   - Compile all utility procedures to r-code (for production use)
     [echo]
     [echo]
     [echo]  Status/Info:
     [echo]
     [echo]  proant status - [RO] Obtain MSAgent/connection status information for an ABL App
     [echo]                  [OPTIONAL] -Dbasemem=819200 (Minimum memory threshold, in bytes, of unused agent sessions)
     [echo]
     [echo]  proant stacks - [RO] Obtain stack information for all MSAgents for an ABL App
     [echo]
     [echo]  proant flush  - [RO] Flush the available deferred log buffer to agent log file
     [echo]
     [echo]  proant locks  - [RO] Display database users and their table locks related to an MSAgent-Session
     [echo]                  This utilizes a single DBConnection; edit the 'locks' task in build.xml to add more as necessary
     [echo]                  Note: Only provides session data if using self-service DB connections for OE versions under 12.5
     [echo]                  [OPTIONAL]  -Dcodepage=UTF-8 (Codepage)
     [echo]                  [OPTIONAL] -Dcollation=BASIC (Collation)
     [echo]                  [OPTIONAL]   -Ddb.name=Sports2020 (Database name to check)
     [echo]                  [OPTIONAL]   -Ddb.host=localhost (Database host to check)
     [echo]                  [OPTIONAL]   -Ddb.port=8600 (Database port to check)
     [echo]
     [echo]  proant users  - [RO] Alias for 'locks' task
     [echo]
     [echo]
     [echo]  Agent Management:
     [echo]
     [echo]  proant add     - Add (read: start) one new MSAgent for an ABL App
     [echo]
     [echo]  proant close   - Perform a 'soft restart' of an ABL App (runs: status, flush + trimhttp + stop, status)
     [echo]                   [OPTIONAL] -Dsleep=1 (Sleep time in minutes after stop)
     [echo]
     [echo]  proant clean   - Alias for 'close' task [Deprecated]
     [echo]
     [echo]  proant refresh - Refresh ABL Sessions for each MSAgent for an ABL App (OE 12 Only)
     [echo]                   Note: This will essentially terminate all sessions (gracefully),
     [echo]                         and prepare the Agent to pick up any R-code changes
     [echo]
     [echo]  proant reset   - Reset an aspect of each MSAgent for an ABL App
     [echo]                   [REQUIRED] -Dresettype=stats [stats|logs]
     [echo]
     [echo]  proant stop    - Gracefully stop one or all MSAgents (+stacks output) for an ABL App
     [echo]                   [OPTIONAL] -Dwaitfinish=120000 (How long to wait in milliseconds if the MSAgent is busy serving a request)
     [echo]                   [OPTIONAL]  -Dwaitafter=60000 (Additional time to wait in milliseconds before killing [hard stop] the MSAgent)
     [echo]                   [OPTIONAL]        -Dpid=[AGENT_PID] (Numeric process ID for a specific MSAgent to be stopped)
     [echo]
     [echo]
     [echo]  Session Management:
     [echo]
     [echo]  proant trimidle   - Trim only the IDLE ABL Sessions (via the Agent Manager) for each MSAgent for an ABL App
     [echo]                      Allows for manually scaling down an MSAgent which may have many unused ABL Sessions
     [echo]                      [OPTIONAL] -Dterminateopt=0 (Termination Option: 0=graceful, 1=forced, 2=finish/stop)
     [echo]
     [echo]  proant trimsingle - Trim a single ABL Session (via the Agent Manager) for a specific MSAgent
     [echo]                      [REQUIRED]          -Dpid=[AGENT_PID] (Numeric process ID of the MSAgent for context)
     [echo]                      [REQUIRED]       -Dsessid=[SESSION_ID] (Numeric ID for the ABL Session to be stopped)
     [echo]                      [OPTIONAL] -Dterminateopt=0 (Termination Option: 0=graceful, 1=forced, 2=finish/stop)
     [echo]
     [echo]  proant trimall    - Trim all active/idle ABL Sessions (via the Agent Manager) for each MSAgent for an ABL App
     [echo]                      Note: For any busy sessions considered stuck, use 'trimhttp' with a specific Session ID
     [echo]                      [OPTIONAL] -Dterminateopt=0 (Termination Option: 0=graceful, 1=forced, 2=finish/stop)
     [echo]
     [echo]  proant trimhttp   - Trim one or all Client Sessions (via the Session Manager) for an ABLApp/WebApp pair
     [echo]                      Note: When no session ID provided, all available Tomcat HTTP sessions will be expired
     [echo]                      [OPTIONAL]       -Dsessid=[SESSION_ID] (Unique alphanumeric Session ID to be stopped)
     [echo]                      [OPTIONAL] -Dterminateopt=0 (0 for graceful termination and 1 for forced termination)
     [echo]
     [echo]
     [echo] Available parameters with their defaults, override as necessary:
     [echo]     -Dscheme=http
     [echo]       -Dhost=localhost
     [echo]       -Dport=8810
     [echo]     -Duserid=tomcat
     [echo]     -Dpasswd=tomcat
     [echo]   -Dpas.root=C:\OpenEdge\WRK (PAS parent directory)
     [echo]   -Dinstance=oepas1 (Physical instance name)
     [echo]     -Dablapp=oepas1
     [echo]     -Dwebapp=ROOT (Used by trimhttp/close as context for the Tomcat manager webapp)
     [echo]      -Ddebug=false (When enabled, outputs OEManager REST API URL's and enables [ABL] HttpClient logging)
     [echo]
     [echo] NOTE: The name of the ABLApp is case-sensitive!
     [echo]
     [echo] CATALINA_HOME: C:\Progress\OpenEdge\servers\pasoe
     [echo] CATALINA_BASE: C:\OpenEdge\WRK\oepas1

## Security Notes ##

It is strongly recommended to [secure the oemanager and manager WebApps](https://docs.progress.com/bundle/openedge-security-and-auditing/page/Secure-the-Tomcat-Manager-and-OpenEdge-Manager-web-applications.html) when deployed in a production environment.