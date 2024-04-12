/*------------------------------------------------------------------------
    File        : IPushData
    Purpose     : Provide an interface compatible with the CCS IService
    Description :
    Author(s)   : Dustin Grau
    Created     : Wed Jul 17 13:13:16 EDT 2019
    Notes       :
  ----------------------------------------------------------------------*/

using Progress.Json.ObjectModel.JsonObject from propath.

interface OpenEdge.ApplicationServer.Service.IPushData:

    define public property ABLAppName as character no-undo get. set.

    define public property InstanceURI as character no-undo get. set.

    define public property AgentPID as integer no-undo get. set.

    method public JsonObject PrepareData ( input plData as longchar ).

    method public JsonObject PrepareData( input pcABLAppName    as character,
                                          input pcInstanceURL   as character,
                                          input plData          as longchar ).

    method public JsonObject PrepareData ( input pcABLAppName    as character,
                                           input pcInstanceURL   as character,
                                           input piAgentPID      as int64,
                                           input piABLSessionID  as int64,
                                           input pdRequestStart  as datetime,
                                           input piRequestLength as int64,
                                           input pcTransport     as character,
                                           input pcAPIEntryPt    as character,
                                           input pcTestRun       as character,
                                           input plData          as longchar ).

    method public logical SendData ( input piAgentPID as int64,
                                     input pcHttpUrl as character,
                                     input poData    as JsonObject ).

end interface.
