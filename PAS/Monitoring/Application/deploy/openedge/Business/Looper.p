/*------------------------------------------------------------------------
    File        : Looper.p
    Purpose     : Run a loop to simulate CPU load
    Description :
    Author(s)   : Dustin Grau
    Created     : Wed May 12 13:34:40 EDT 2021
    Notes       :
  ----------------------------------------------------------------------*/

block-level on error undo, throw.

define output parameter elapsedTime as int64 no-undo.

define variable dStart as datetime no-undo extent 2.
define variable iX     as integer  no-undo.

assign dStart[1] = now.

do iX = 1 to 500000:
end.

assign dStart[2] = now.

assign elapsedTime = interval(dStart[2], dStart[1], "milliseconds").
