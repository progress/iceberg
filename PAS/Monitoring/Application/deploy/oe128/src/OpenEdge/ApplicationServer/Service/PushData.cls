/*------------------------------------------------------------------------
    File        : PushData
    Purpose     : Abstract service for pushing diagnostic data externally
    Description :
    Author(s)   : Dustin Grau
    Created     : Thu Jul 18 15:23:28 EDT 2019
    Notes       :
  ----------------------------------------------------------------------*/

using Progress.Lang.* from propath.
using OpenEdge.Logging.ILogWriter from propath.
using OpenEdge.Logging.LoggerBuilder from propath.
using OpenEdge.ApplicationServer.Service.PushConfig from propath.

block-level on error undo, throw.

class OpenEdge.ApplicationServer.Service.PushData implements OpenEdge.ApplicationServer.Service.IPushData abstract:

    define public property ABLAppName as character no-undo initial "" get. set.

    define public property InstanceURI as character no-undo initial "" get. set.

    define public property AgentPID as integer no-undo initial 0 get. set.

    /* Offer a local logger implementation for messaging to a configurable log. */
    define protected property oLogger as ILogWriter no-undo
        get:
            if not valid-object(oLogger) then
                assign oLogger = LoggerBuilder:GetLogger(this-object:getClass()).
            return oLogger.
        end get.
        set.

    constructor public PushData ( ):
        super ().

        this-object:Discovery().
    end constructor.

    destructor public PushData ( ):
        delete object oLogger no-error.
    end destructor.

    method private void Discovery ( ):
        /* Initially treat the directory name of the PAS instance as the default ABLApp name. */
        this-object:ABLAppName = entry(num-entries(PushConfig:CatalinaBase, "~/"), PushConfig:CatalinaBase, "~/").

        /* Obtain a default instance URI for identification of the server. */
        this-object:InstanceURI = PushConfig:InstanceURI. /* Self-discovered static property. */
    end method. /* Discovery */

    method public Progress.Json.ObjectModel.JsonObject PrepareData ( input plData as longchar ):
        define variable oParser as Progress.Json.ObjectModel.ObjectModelParser no-undo.

        /* Simply convert a longchar JSON string into a real JSON object and return. */
        assign oParser = new Progress.Json.ObjectModel.ObjectModelParser().
        return cast(oParser:Parse(plData), Progress.Json.ObjectModel.JsonObject).

        catch parseErr as Progress.Json.JsonParserError:
            undo, throw new Progress.Lang.AppError(substitute("Error parsing JSON at &1: &2", parseErr:Offset, parseErr:GetMessage(1))).
        end catch.
        catch err as Progress.Lang.Error:
            oLogger:Error(substitute("Error while preparing request: &1", err:GetMessage(1))).
            return ?.
        end catch.
        finally:
            delete object oParser no-error.
        end finally.
    end method. /* PrepareData */

    method public Progress.Json.ObjectModel.JsonObject PrepareData ( input pcABLAppName    as character,
                                                                     input pcInstanceURL   as character,
                                                                     input plData          as longchar ):
        /* Forward to the most full-featured method. */
        return this-object:PrepareData(pcABLAppName,
                                       pcInstanceURL,
                                       0,  /* AgentPID */
                                       0,  /* ABLSessionID */
                                       ?,  /* pdRequestStart */
                                       0,  /* piRequestLength */
                                       "", /* pcTransport */
                                       "", /* pcAPIEntryPt */
                                       "", /* pcTestRun */
                                       plData).
    end method. /* PrepareData */

    method public Progress.Json.ObjectModel.JsonObject PrepareData ( input pcABLAppName    as character,
                                                                     input pcInstanceURL   as character,
                                                                     input piAgentPID      as int64,
                                                                     input piABLSessionID  as int64,
                                                                     input pdRequestStart  as datetime,
                                                                     input piRequestLength as int64,
                                                                     input pcTransport     as character,
                                                                     input pcAPIEntryPt    as character,
                                                                     input pcTestRun       as character,
                                                                     input plData          as longchar ):
        /* Creates the data payload in JSON format for the remote server. */
        return ?.
    end method. /* PrepareData */

    method public logical SendData ( input piAgentPID as int64,
                                     input pcHttpUrl  as character,
                                     input poData     as Progress.Json.ObjectModel.JsonObject ):
        /* Sends the JSON payload to the remote server. */
        return ?.
    end method. /* SendData */

end class.
