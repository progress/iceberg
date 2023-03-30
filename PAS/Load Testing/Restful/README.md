# RESTful Testing #

A simple set of test which demonstrates the use of JMeter or SoapUI to place stress on the Web/REST transports. Note that the included example application code does not provide nor require a database in order to keep the setup simple and limited in scope to only a single PAS instance.

----------

## Requirements ##

- Download and install your test platform of choice, so long as those choices at present are either [JMeter](https://jmeter.apache.org/download_jmeter.cgi) or [SoapUI](https://www.soapui.org/downloads/soapui/).
- OpenEdge 12.2+ (Due to use of .handlers deployment for services using the WEB transport)
- PAS for OpenEdge

## Deployment ##

### Server ###

Assuming use of the default **oepas1** instance using **OpenEdge 12.2** or later, perform the following steps to prepare the environment for a set of predetermined stress tests.

1. Copy the contents of the **server/openedge** folder to the instance's `/ablapp/oepas1/openedge` folder. This will provide the ABL code to be executed, along with a a description of services for the DataObjectHandler.
2. Copy the contents of the **server/web** folder to the instances `/webapps/ROOT/WEB-INF/adapters/web` folder. This deploys a set of WebHandler definitions for the ROOT WebApp, `/_oeping` and `/pdo/{service}`. *This deployment approach is only supported as of OpenEdge 12.2 and avoids the need to edit the openedge.properties file.*

### Client ###

Load the appropriate test script for the test utility of choice.

**JMeter:** RunTests.jmx - Utilizes the Web transport to perform an initial Ping on the local PAS instance, followed by a set of stress tests. The tests are placed in "Thread Groups" and named accordingly: Peak Tests and Sustained Tests. The former attempts to run the specified # of threads (users) over the course of some ramp-up period; once each thread completes its task, the test is done for that thread. The latter starts a specified # of threads (users) over the course of some ramp-up period; as each thread completes a task it immediately runs again for the stated duration.

**SoapUI:** RunTests.xml - Implements a simple set of RESTful requests as a "test suite". This is meant to exercise certain portions of application code. Import as a project into SoapUI.