/*------------------------------------------------------------------------
    Copyright (c) 2020-2023 by Progress Software Corporation. All rights reserved.

    File        : HelloProc.p
    Purpose     :
    Description :
    Author(s)   : Dustin Grau (dugrau@progress.com)
    Created     : Wed Oct 28 13:32:24 EDT 2020
    Notes       :
  ----------------------------------------------------------------------*/

block-level on error undo, throw.

/* Used for testing persistent procedures. */
define variable cUser as character no-undo.

/* Used for session-managed APSV connections. */
procedure setHelloUser:
    define input parameter toWhom as character no-undo.

    pause 0.4 no-message. /* Just add a bit of fake think-time. */

    assign cUser = toWhom.
end procedure.

/* Used for session-managed APSV connections. */
procedure sayHelloStoredUser:
    define output parameter greeting as character no-undo.

    pause 0.4 no-message. /* Just add a bit of fake think-time. */

    assign greeting = substitute("Hello &1", cUser).
end procedure.

procedure sayHello:
    define input  parameter toWhom   as character no-undo.
    define output parameter greeting as character no-undo.

    pause 0.2. /* Just add a bit of fake think-time. */

    assign greeting = substitute("Hello &1", toWhom).
end procedure.

procedure sayHello2Many:
    define input  parameter recipients as Progress.Json.ObjectModel.JsonArray no-undo.
    define output parameter greeting   as character no-undo.

    define variable ix as integer no-undo.
    if valid-object(recipients) then
    do ix = 1 to recipients:length:
        if recipients:GetType(ix) eq Progress.Json.ObjectModel.JsonDataType:string then
            assign greeting = substitute("&1, Hello &2", greeting, recipients:GetCharacter(ix)).
    end.

    assign greeting = trim(left-trim(greeting, ",")).
end procedure.
