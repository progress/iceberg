/*
    Copyright 2020-2021 Progress Software Corporation

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/
/*------------------------------------------------------------------------
    File        : getLockStats.p
    Purpose     : Return DB table lock statistics via temp-table
    Author(s)   : Dustin Grau (dugrau@progress.com)
    Created     : Thu Nov 12 16:16:42 EST 2020
    Notes       : Must set "dictdb" alias for target DB before calling!
  ----------------------------------------------------------------------*/

block-level on error undo, throw.

define temp-table ttLock no-undo
    field UserNum      as int64
    field UserName     as character
    field DomainName   as character
    field TenantName   as character
    field DatabaseName as character
    field TableName    as character
    field LockFlags    as character
    field TransID      as int64
    field PID          as int64
    field SessionID    as int64
    .

define input-output parameter table for ttLock.

define variable cUserName   as character no-undo.
define variable cDomainName as character no-undo.
define variable cTenantName as character no-undo.
define variable cTableName  as character no-undo.
define variable cLockFlags  as character no-undo.
define variable iUserNum    as int64     no-undo.
define variable iTransID    as int64     no-undo.
define variable iConnectPID as int64     no-undo.
define variable iSessionID  as int64     no-undo.
define variable hConnQuery  as handle    no-undo.
define variable hLockQuery  as handle    no-undo.
define variable hConnBuffer as handle    no-undo.
define variable hLockBuffer as handle    no-undo.
define variable hTranBuffer as handle    no-undo.
define variable hFileBuffer as handle    no-undo.
define variable hSecBuffer  as handle    no-undo.

if not connected("dictdb") then
    return. /* We cannot continue without a database. */

create buffer hConnBuffer for table "dictdb._Connect".
create buffer hLockBuffer for table "dictdb._Lock".
create buffer hTranBuffer for table "dictdb._Trans".
create buffer hFileBuffer for table "dictdb._File".
create buffer hSecBuffer  for table "dictdb._sec-authentication-domain".

create query hConnQuery.
hConnQuery:set-buffers(hConnBuffer).

create query hLockQuery.
hLockQuery:set-buffers(hLockBuffer).

/* Only look for connections from PASN client types. */
hConnQuery:query-prepare(substitute("for each &1 where _Connect-Usr ne ? and _Connect-ClientType eq 'PASN'", hConnBuffer:name)).
hConnQuery:query-open().

CONNECTBLK:
repeat:
    hConnQuery:get-next(no-lock).
    if hConnQuery:query-off-end then leave CONNECTBLK.

    assign
        iUserNum    = hConnBuffer::_Connect-Usr
        cUserName   = hConnBuffer::_Connect-Name
        iConnectPID = hConnBuffer::_Connect-Pid
        iSessionID  = if hConnBuffer::_Connect-Device begins "AS-" and num-entries(hConnBuffer::_Connect-Device, "-") gt 1
                      then integer(entry(2, hConnBuffer::_Connect-Device, "-")) else ?
        .

    hLockQuery:query-prepare(substitute("for each &1 where _Lock-Usr eq &2", hLockBuffer:name, iUserNum)).
    hLockQuery:query-open().

    LOCKBLK:
    repeat:
        hLockQuery:get-next(no-lock).
        if hLockQuery:query-off-end then leave LOCKBLK.

        assign cLockFlags = hLockBuffer::_Lock-flags.

        /* Get a transaction ID. */
        hTranBuffer:find-first(substitute("where _Trans-Usrnum eq &1", hLockBuffer::_Lock-Table), no-lock) no-error.
        assign iTransID = if hTranBuffer:available then hTranBuffer::_Trans-Id else ?.

        /* Get a user-friendly table name. */
        hFileBuffer:find-first(substitute("where _File-Number eq &1", hLockBuffer::_Lock-Table), no-lock) no-error.
        assign cTableName = if hFileBuffer:available then hFileBuffer::_File-Name else "N/A".

        assign /* Reset values for each _Lock record. */
            cDomainName = ""
            cTenantName = ""
            .

        /* Get a user-friendly domain & tenant name. */
        hSecBuffer:find-first(substitute("where _Domain-Id eq &1", hLockBuffer::_Lock-DomainId), no-lock) no-error.
        if hSecBuffer:available then do:
            assign
                cDomainName = if hSecBuffer::_Domain-Name eq ? then "N/A" else hSecBuffer::_Domain-Name
                cTenantName = if hSecBuffer::_Tenant-Name eq ? then "N/A" else hSecBuffer::_Tenant-Name
                .
        end. /* for first _sec-authentication-domain */

        create ttLock.
        assign
            ttLock.UserNum      = iUserNum
            ttLock.UserName     = cUserName
            ttLock.DomainName   = cDomainName
            ttLock.TenantName   = cTenantName
            ttLock.DatabaseName = pdbname("dictdb")
            ttLock.TableName    = cTableName
            ttLock.TransID      = iTransID
            ttLock.LockFlags    = cLockFlags
            ttLock.PID          = iConnectPID
            ttLock.SessionID    = iSessionID
            .
        release ttLock no-error.
    end. /* repeat - LOCKBLK */

    /* If no locks found for this user, just create a record for basics. */
    if not can-find(first ttLock where ttLock.UserNum eq iUserNum) then do:
        create ttLock.
        assign
            ttLock.UserNum      = iUserNum
            ttLock.UserName     = cUserName
            ttLock.DomainName   = ""
            ttLock.TenantName   = ""
            ttLock.DatabaseName = pdbname("dictdb")
            ttLock.TableName    = ""
            ttLock.TransID      = ?
            ttLock.LockFlags    = ""
            ttLock.PID          = iConnectPID
            ttLock.SessionID    = iSessionID
            .
        release ttLock no-error.
    end.
end. /* repeat - CONNECTBLK */
hConnQuery:query-close().

