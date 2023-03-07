# OEManager CLI Tools #

*Formerly referred to as the "PROANT Tools"*

This suite of tools utilizes the [RESTful API's](https://docs.progress.com/bundle/pas-for-openedge-reference/page/REST-API-Reference-for-oemanager.war.html) offered by the **oemanager** WebApp to provide a comprehensive insight to a running PAS instance or to manage any ABL Application belonging to a PAS instance. All operations are executed via a command-line interface (using ANT and PCT internally) on either Windows or Linux environments.

## Requirements ##

1. Run a **PROENV** session which will set the necessary environment variables to execute the tools. This will provide access to the DLC and JAVA_HOME environment variables and any OpenEdge binaries such as "PROANT" which is useful for deployment.
	- You should ideally the latest OpenEdge release version available to you, or at a minimum the same release version as used by the PAS for OpenEdge instances you wish to manage.
1. The OpenEdge Manager (oemanager.war) and Tomcat Manager (manager.war) webapps must be deployed to the PAS instance in order to make use of these tools. For ease of deployment, run the `proant deploy_oemanager` or `proant deploy_manager` as necessary to install the webapps into a PAS instance specified via the parameter `-Dinstance=[PATH_TO_INSTANCE]`.
	- **WARNING:** It is strongly recommended to [secure the oemanager and manager WebApps](https://docs.progress.com/bundle/openedge-security-and-auditing/page/Secure-the-Tomcat-Manager-and-OpenEdge-Manager-web-applications.html) when deployed in a production environment. You will need to update the `oemanager.properties` after deployment with any updated credentials.

## Deployment ##

The deployment method has changed since previous versions with use of a new **utils.zip** file now being preferred. The tools may be deployed either automatically or manually via the following processes:

**Automated Deployment**

Run the command `proant deploy -Dpath=[PATH_TO_INSTANCE]` to expand/unzip the **utils.zip** into your PAS instance's **CATALINA_BASE/utils/** folder. A new folder will be created if necessary, and any existing files will be overwritten if deploying on top of a prior deployment. This will overwrite any customization to an `oemanager.properties` file.

**Manual Deployment**

Unzip the **utils.zip** file into a new "utils" folder on the target OS image (physical or virtual machine, or container). This may be placed in either a PAS instance you have direct access to (via the OS filesystem) or a central location if desiring to manage multiple remote PAS instances.

- If placed within a PAS instance in a "utils" folder the tools will automatically tailor themselves to use properties from the PAS instance, such as the HTTP or HTTPS port.
- If **not** placed directly within a PAS instance then you must either pass command-line parameters or edit the `oemanager.properties` file to supply the necessary defaults for either or both of the following groups of properties:
	- To control remote PAS instances: set the `scheme`, `hostname`, and `port` properties for the intended instance.
		- eg. "-Dscheme=http -Dhostname=localhost -Dport=8810"
	- To control local PAS instances: the `pas.root` and `instance` properties (these will form the CATALINA_BASE path).
		- eg. "-Dpas.root=C:/OpenEdge/WRK -Dinstance=oepas1" for an instance at C:/OpenEdge/WRK/oepas1

## Usage ##

# For a full explanation of available tasks and use-cases please see the [expanded usage guide in USAGE.md](USAGE.md). #

## Output ##

Output for all commands should be displayed via standard out and appear within the same terminal/command window where executed. Log files may be generated for sanity checks as part of the normal operation. All commands will be logged to a `commands.log` file and cannot be disabled as this ensures an audit trail of management actions taken for a PAS instance. The included `logging.config` enables logging via the ABL Logger framework for additional insight into the operations made against a PAS instance and can be configured with alternate logging levels and output options. By default, the logging level is set to DEBUG and will output messages to a `OEMgrConn.log` file. This will produce output similar to the `commands.log` file though it can be silenced by changing the logging level to ERROR or lower.

**Note:** Some data may only be displayed in an OpenEdge 12 environment, such as the Dynamic Session Limit which was added as part of the Agent self-management feature. Other values such as **RequestID** (where applicable) will only be displayed if the **Enhanced MDC Logging** is enabled--this is enabled by default in OpenEdge 12 releases though it must be manually enabled in OpenEdge 11.7.x (via **openedge_setenv.[bat|sh]**). Lastly, some runtime metrics such as counts and time values will only be present if **collectMetrics** has been set to 3 for the AppServer and each WebApp (via openedge.properties).