# APSV Testing #

A simple set of tools which demonstrates the use of parallel ANT tasks to place stress on the APSV transport. By default the included task will execute 5 batches of 10 client connections against the configured endpoint. The tests run for a set amount of time, executing requests against the AppServer, pausing, and running again. By default a session-managed model is used, together with a persistent procedure to produce bound clients on the PAS instance's ABL Application. This approach mimics a common pattern as observed in customer applications.

## Requirements ##

Use of **proant** is required to execute the **build.xml** included. This can be accessed via the `DLC/bin` directory, typically via a **PROENV** session. If necessary, ABL code may be compiled before deployment in an environment where a 4GL compiler is not available. A database is not provided nor required for this sample application.

- OpenEdge 11.7.x or 12.2+
- PAS for OpenEdge

## Deployment ##

### Server ###

For demonstrating a simple "Hello World" test, place the included **server/Business** folder within the PROPATH of an ABL Application on your PAS instance. Note the name of a WebApp associated with this ABL Application which has the APSV adapter enabled--this will be your means of access to the test code. The included **HelloProc.p** offers simple procedures to demonstrate 2 typical coding patterns for APSV:

1. **setHelloUser** and **sayHelloStoredUser** - Used to demonstrate a session-managed session-model where the remote procedure is run persistently. The former procedure is called to set a context value, while the latter performs the business logic to return the context value and an additional string.
2. **sayHello** - Simple procedure for the session-free session-model which accepts a character parameter and immediately returns a character response. (This test case is not currently configured, but exists as a basic sanity-check if/when needed.)

### Client ###

Simply run **proant** from this directory to obtain usage information as shown below. Parameters may be specified via command-line or by editing the `build.properties` file in advance. Note the parameters for port and webapp which will most likely need to be specified for your instance.

     [echo] Usage Instructions:
     [echo]
     [echo]  proant runtest - Run concurrent tests against the APSV transport using session-managed model
     [echo]    -Dbad=[true|false] - Run without cleaning up persistent procedure handles (Default: false)
     [echo]   -Dtype=[hello|looper] - Type of test to be run on the PAS instance (Default: hello)
     [echo]
     [echo] Standard parameters with their defaults:
     [echo]   -Dscheme=http
     [echo]     -Dhost=localhost
     [echo]     -Dport=8810
     [echo]   -Dwebapp=ROOT