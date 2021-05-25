# ABL Management #

Utilizing the [RESTful API's](https://docs.progress.com/bundle/pas-for-openedge-reference/page/REST-API-Reference-for-oemanager.war.html) offered by the oemanager WebApp, the included ABL code may provide either a comprehensive view of a running instance or means to manage an ABL Application. All actions can be run via a command-line interface using ANT tasks on either Windows or Unix environments.

## Requirements ##

Use of **proant** is required to execute the **build.xml** included. This can be accessed via the `DLC/bin` directory, typically via a **PROENV** session. If necessary, ABL code may be compiled before deployment in an environment where a 4GL compiler is not available.

**Note:** Some data may only be displayed in an OpenEdge 12 environment, such as the Dynamic Session Limit which was added as part of the Agent self-management feature. Other values such as **RequestID** (where applicable) will only be displayed if the **Enhanced MDC Logging** is enabled--this is on by default in OpenEdge 12 though it must be manually enabled in OpenEdge 11.7.x (via **openedge_setenv.[bat|sh]**). And lastly, some runtime metrics such as counts and time values will only be present if **collectMetrics** has been set to 3 for the AppServer and each WebApp (via openedge.properties).

## Deployment ##

Simply run **proant** from this directory to obtain usage information as shown below. Parameters may be specified via command-line or by editing the `build.properties` file in advance.

     [echo] Usage Instructions:
     [echo]
     [echo]  TCMAN Shortcuts:
     [echo]
     [echo]  proant startup - Use TCMAN to start the oepas1 PAS instance
     [echo]
     [echo]  proant query - Use TCMAN to query the oepas1 PAS instance
     [echo]
     [echo]  proant shutdown - Use TCMAN to stop the oepas1 PAS instance
     [echo]
     [echo]
     [echo]  Internal Tools:
     [echo]
     [echo]  proant inventory - Bundle useful PAS instance files (as .zip) for support tickets
     [echo]
     [echo]  proant compile - Compile all utility procedures to r-code (for production use)
     [echo]
     [echo]
     [echo]  Status/Management:
     [echo]
     [echo]  proant status - [RO] Obtain MSAgent/connection status information for an ABL App
     [echo]
     [echo]  proant stacks - [RO] Obtain stack information for all MSAgents for an ABL App
     [echo]
     [echo]  proant flush - [RO] Flush the available deferred log buffer to agent log file
     [echo]
     [echo]  proant trimhttp - Trim all Session Manager and Tomcat HTTP sessions for an ABL/Web App
     [echo]                    [OPTIONAL] -Dterminateopt=0 (0 for graceful termination and 1 for forced termination)
     [echo]
     [echo]  proant trimidle - Trim all IDLE ABL Sessions for each MSAgent for an ABL App
     [echo]
     [echo]  proant trimall - Trim all ABL Sessions for each MSAgent for an ABL App
     [echo]
     [echo]  proant refresh - Refresh ABL Sessions for each MSAgent for an ABL App (OE 12 Only)
     [echo]
     [echo]  proant clean - Perform a 'soft restart' (status, flush, trimhttp, stop) of an ABL App
     [echo]                 [OPTIONAL] -Dsleep={sleep time in minutes} (Default: 1)
     [echo]
     [echo]  proant stop - Gracefully stops all MSAgents (+stacks output) for an ABL App
     [echo]                [OPTIONAL] -Dwaitfinish=120000 (How long to wait in milliseconds if the MSAgent is busy serving a request)
     [echo]                [OPTIONAL] -Dwaitafter=60000 (Additional time to wait in milliseconds before killing [hard stop] the MSAgent)
     [echo]
     [echo]  proant locks - [RO] Display database users and their table locks related to an MSAgent-Session
     [echo]                 This utilizes a single DBConnection; edit build.xml to add more as needed
     [echo]                 Note: will only provide session data if using self-service DB connections
     [echo]                 [OPTIONAL] -Ddb.name=Sports2020 (Database name to check)
     [echo]                 [OPTIONAL] -Ddb.host=localhost (Database host to check)
     [echo]                 [OPTIONAL] -Ddb.port=8600 (Database port to check)
     [echo]
     [echo]  proant users - [RO] Alias for 'locks' target
     [echo]
     [echo]
     [echo] Available parameters with their defaults, override as necessary:
     [echo]   -Dscheme=http
     [echo]     -Dhost=localhost
     [echo]     -Dport=8810
     [echo]   -Duserid=tomcat
     [echo]   -Dpasswd=tomcat
     [echo]   -Dpas.root=C:\OpenEdge\WRK (PAS parent directory)
     [echo]   -Dinstance=oepas1 (Physical instance name)
     [echo]   -Dablapp=oepas1
     [echo]   -Dwebapp=ROOT (Used by trimhttp/clean to access the Tomcat manager webapp)
     [echo]   -Ddebug=false (When enabled, outputs OEManager REST API URL's and enables [ABL] HttpClient logging)
     [echo]
     [echo] NOTE: The name of the ABLApp is case-sensitive!
     [echo]
     [echo] CATALINA_HOME: C:\Progress\OpenEdge\servers\pasoe
     [echo] CATALINA_BASE: C:\OpenEdge\WRK\oepas1

## Security Notes ##

It is strongly recommended to [secure the oemanager and manager WebApps](https://docs.progress.com/bundle/openedge-activedirectory-authentication/page/Secure-the-Tomcat-Manager-and-OpenEdge-Manager-web-applications.html) when deployed in a production environment.