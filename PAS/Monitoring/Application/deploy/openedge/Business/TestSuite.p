/*------------------------------------------------------------------------
    File        : TestSuite.p
    Purpose     : Run all code tests in a single procedure
    Syntax      :
    Description :
    Author(s)   : Dustin Grau
    Created     : Thu Jan 16 14:37:37 EST 2020
    Notes       :
  ----------------------------------------------------------------------*/

block-level on error undo, throw.

/* ***************************  Main Block  *************************** */

mainblk:
do on error undo, throw:
    define variable oRunCode   as Business.UnitTest.RunCode   no-undo.
    define variable oLeakyCode as Business.UnitTest.LeakyCode no-undo.

    assign oRunCode = new Business.UnitTest.RunCode().
    assign oLeakyCode = new Business.UnitTest.LeakyCode().

    define variable iElapsed as integer no-undo.
    oRunCode:lookBusy(random(200, 400), output iElapsed).
    message substitute("Completed 'LookBusy' in &1ms", iElapsed).

    define variable iPointerSize  as integer no-undo.
    define variable iPointerValue as int64   no-undo.
    oLeakyCode:badMemptr(output iPointerSize, output iPointerValue).
    message substitute("Created memptr with size &1 at 0x&2", iPointerSize, iPointerValue).

    define variable cMessage as character no-undo.
    oLeakyCode:badHandle(output cMessage).
    message substitute("Ran procedure with message: &1", cMessage).

    finally:
        delete object oRunCode   no-error.
        delete object oLeakyCode no-error.
    end finally.
end.
