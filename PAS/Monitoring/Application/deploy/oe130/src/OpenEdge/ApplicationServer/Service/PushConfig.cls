/*------------------------------------------------------------------------
    File        : PushConfig
    Purpose     : Provide static config values for diagnostic push logic
    Description : Tracks instance variables that are rarely changed
    Author(s)   : Dustin Grau
    Created     : Thu Aug 15 10:41:41 EDT 2019
    Notes       : 
  ----------------------------------------------------------------------*/

using Progress.Lang.* from propath.
using OpenEdge.Logging.ILogWriter from propath.
using OpenEdge.Logging.LoggerBuilder from propath.
using OpenEdge.ApplicationServer.Service.PushConfig from propath.

block-level on error undo, throw.

class OpenEdge.ApplicationServer.Service.PushConfig:

    /* Standard environment variable for PAS instance location. */
    define public static property CatalinaBase as character no-undo initial ""
        get():
            if CatalinaBase eq "" then do:
                file-info:filename = trim(os-getenv("CATALINA_BASE")).
                assign CatalinaBase = right-trim(replace(file-info:full-pathname, "~\", "~/"), "~/").
            end.
            return CatalinaBase.
        end get.
        set.

    /* Used as a standard location for creating temporary files. */
    define public static property TemporaryDir as character no-undo initial ""
        get():
            if TemporaryDir eq "" then
                assign TemporaryDir = right-trim(replace(session:temp-directory, "~\", "~/"), "~/").
            return TemporaryDir.
        end get.
        set.

    /*------------------------------------------------------------------------------
     Purpose: Obtain basic URI for the current PAS instance, based on Tomcat config
     Notes: Defaults to a loopback address plus the determined HTTP/S ports
    ------------------------------------------------------------------------------*/
    define public static property InstanceURI as character no-undo initial ""
    get:
        if InstanceURI eq "" then do:
            if PushConfig:InstancePort[1] gt 0 then
                InstanceURI = substitute("http://127.0.0.1:&1", PushConfig:InstancePort[1]).
            else if PushConfig:InstancePort[2] gt 0 then
                InstanceURI = substitute("https://127.0.0.1:&1", PushConfig:InstancePort[2]).
        end. /* InstanceURI eq "" */

        return InstanceURI.
    end get.
    private set.

    /*------------------------------------------------------------------------------
     Purpose: Stores the configured ports as follows: HTTP (1) and HTTPS (2)
    ------------------------------------------------------------------------------*/
    define public static property InstancePort as integer extent 2 no-undo initial 0 get. private set.

    /*------------------------------------------------------------------------------
     Purpose: Stores the instance's HealthCheck port and enablement status
    ------------------------------------------------------------------------------*/
    define public static property HealthCheckPort    as integer no-undo initial 0     get. private set.
    define public static property HealthCheckEnabled as logical no-undo initial false get. private set.

    constructor static PushConfig ( ):
        GetPorts(). /* Use config data to get the HTTP/S ports. */
        GetFlags(). /* Use config data to obtain special flags. */
    end constructor.

    /*------------------------------------------------------------------------------
     Purpose: Obtain ports used for the current PAS instance, based on Tomcat config
     Notes: Utilizes static property as catalina.properties is infrequently updated
    ------------------------------------------------------------------------------*/
    method private static void GetPorts ( ):
        define variable cLine          as character no-undo.
        define variable lcConfigTemp   as longchar  no-undo initial "".
        define variable iLines         as integer   no-undo initial 0.
        define variable iLine          as integer   no-undo.
        define variable iHttpPort      as integer   no-undo.
        define variable iHttpsPort     as integer   no-undo.

        /* Examine the catalina.properties for info about the available ports. */
        file-info:file-name = substitute("&1/conf/catalina.properties", PushConfig:CatalinaBase).
        if file-info:full-pathname ne ? then do:
            /* Read the file into a longchar value (avoids keeping the file open). */
            copy-lob from file file-info:full-pathname to lcConfigTemp no-error.

            if (lcConfigTemp gt "") eq true then
                assign iLines = num-entries(lcConfigTemp, "~n").

            if iLines ge 1 then
            LINEBLK:
            do iLine = 1 to iLines:
                assign cLine = trim(entry(iLine, lcConfigTemp, "~n")).

                case true:
                    when cLine begins "psc.as.http.port=" then
                        InstancePort[1] = integer(trim(entry(2, cLine, "="))) no-error.
                    when cLine begins "psc.as.https.port=" then
                        InstancePort[2] = integer(trim(entry(2, cLine, "="))) no-error.
                    when cLine begins "psc.as.healthcheck.port=" then
                        HealthCheckPort = integer(trim(entry(2, cLine, "="))) no-error.
                end case.
            end. /* do iLines */
        end. /* catalina.properties */

        finally:
            assign lcConfigTemp = ?. /* Reset the variable. */
        end finally.
    end method.

    /*------------------------------------------------------------------------------
     Purpose: Check features enabled for the current PAS instance, based on Tomcat config
     Notes: Utilizes static property as appserver.properties is infrequently updated
    ------------------------------------------------------------------------------*/
    method private static void GetFlags ( ):
        define variable cLine          as character no-undo.
        define variable lcConfigTemp   as longchar  no-undo initial "".
        define variable iLines         as integer   no-undo initial 0.
        define variable iLine          as integer   no-undo.

        /* Examine the appserver.properties for info about the HealthScanner. */
        file-info:file-name = substitute("&1/conf/appserver.properties", PushConfig:CatalinaBase).
        if file-info:full-pathname ne ? then do:
            /* Read the file into a longchar value (avoids keeping the file open). */
            copy-lob from file file-info:full-pathname to lcConfigTemp no-error.

            if (lcConfigTemp gt "") eq true then
                assign iLines = num-entries(lcConfigTemp, "~n").

            if iLines ge 1 then
            LINEBLK:
            do iLine = 1 to iLines:
                assign cLine = trim(entry(iLine, lcConfigTemp, "~n")).

                case true:
                    when cLine begins "psc.as.health.enabled=" then do:
                        HealthCheckEnabled = logical(trim(entry(2, cLine, "="))) no-error.
                        leave LINEBLK.
                    end.
                end case.
            end. /* do iLines */
        end. /* appserver.properties */

        finally:
            assign lcConfigTemp = ?. /* Reset the variable. */
        end finally.
    end method.

end class.