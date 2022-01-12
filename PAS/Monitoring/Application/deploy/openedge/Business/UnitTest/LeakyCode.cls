/*------------------------------------------------------------------------
    File        : LeakyCode
    Purpose     : Test harness for leaky code examples
    Author(s)   : Dustin Grau (dugrau@progress.com)
    Created     : Mon Mar 18 010:48:07 EDT 2019
    Notes       :
  ----------------------------------------------------------------------*/

@program FILE(name="LeakyCode.cls", module="AppServer").
@openapi.openedge.export FILE(type="REST", executionMode="singleton", useReturnValue="false", writeDataSetBeforeImage="false").
@progress.service.resource FILE(name="leakycode", URI="/leakycode", schemaName="", schemaFile="").

using Progress.Lang.* from propath.
using Progress.Json.ObjectModel.* from propath.

block-level on error undo, throw.

class Business.UnitTest.LeakyCode use-widget-pool:

    /* Will be used to demonstrate a hanging buffer. */
    define temp-table tt1
        field f1 as character
        .

    /* Will be used to illustrate a lingering object. */
    define public property oArray as JsonArray no-undo
        get():
            if not valid-object(oArray) then
                assign oArray = new JsonArray().

            return oArray.
        end get.
        private set.

    method private void LoadArray ( ):
        define variable oJsonObj as JsonObject no-undo.
        define variable ix       as integer no-undo.

        do ix = 1 to 100:
            assign oJsonObj = new JsonObject().
            oJsonObj:Add("iteration", ix).
            oJsonObj:Add("company", substitute("Progress: &1", ix)).
            this-object:oArray:Add(cast(oJsonObj:Clone(), JsonObject)).
            delete object oJsonObj no-error.
        end.
    end method. /* LoadPropArray */

    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/buffer", alias="buffer", mediaType="application/json").
    method public void badBuffer ( output completed as logical ):
        /* Create a buffer that will not be cleaned up. */
        define variable hDS as handle.

        create dataset hDS.

        assign completed = true.

        /* DO NOT clean up the datasets nor buffer handle. */
    end method. /* badBuffer */

    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/handle", alias="handle", mediaType="application/json").
    method public void badHandle ( output textMessage as character ):
        define variable hProc as handle no-undo.

        run Business/HelloProc persistent set hProc.
        run sayHello in hProc ( "World", output textMessage).

        /* DO NOT clean up the persistent handle, but instead let it linger. */
    end method. /* badHandle */

    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/memptr", alias="memptr", mediaType="application/json").
    method public void badMemptr ( output pointerSize  as integer,
                                   output pointerValue as int64 ):
        define variable mPtr as memptr no-undo.

        /* Set a size, but DO NOT reset to 0 after use.*/
        set-size(mPtr) = random(100, 200).
        assign pointerSize = get-size(mPtr).
        assign pointerValue = get-pointer-value(mPtr).
    end method. /* badMemptr */

    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/object", alias="object", mediaType="application/json").
    method public void badObject ( output arrayLength as integer ):
        this-object:LoadArray(). /* Add data to the class-scoped array. */
        assign arrayLength = this-object:oArray:Length.

        /* DO NOT clean up the JSON array created. */
    end method. /* badObject */

end class.