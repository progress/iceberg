using Progress.Lang.AppError from propath.
using Progress.Json.ObjectModel.* from propath.
using Common.OSTools from propath.

block-level on error undo, throw.

/**
 * A static class with OS helper methods
 */
class Common.OSTools:

    define private static temp-table ttDirStruct no-undo
        field ParentDir  as character
        field FileName   as character
        field FullPath   as character
        field isDir      as logical
        field DestDir    as character
        index idxPrimary as primary ParentDir FileName.

    /**
     * Sets a custom subdirectory for config files, applicable under PASOE.
     * Note that this could be a possible security risk, so the set method
     * attempts to avoid setting the value if the string is deemed invalid.
     */
    define public static property configProjectDir as character no-undo initial ""
        get.
        set(input configDir as character):
            if (configDir gt "") eq true and not configDir begins "../" then
                configProjectDir = configDir.
        end set.

    /**
     * Return the DLC directory
     */
    define public static property dlcdir as character init ? no-undo
        get():
            if dlcdir eq ? then
            do:
                dlcdir = OSTools:getFullPathname(os-getenv("DLC")).
                if dlcdir eq ? and opsys = "WIN32" then
                do:
                    get-key-value section 'Startup' key 'DLC' value dlcdir.
                    dlcdir = OSTools:getFullPathname(dlcdir).
                end.
                if dlcdir eq ? then
                    undo, throw new AppError("Unable to determine the DLC directory", 0).
            end.
            return dlcdir.
        end get.
        private set.

    /**
     * Return the current working directory of the app server agent
     * Under PASOE, this will be $CATALINA_BASE/work
     */
    define public static property wrkdir as character init ? no-undo
        get():
            if wrkdir eq ? then
            do:
                wrkdir = OSTools:getFullPathname(".").
                if wrkdir eq ? then
                    undo, throw new AppError("Unable to determine the current working directory", 0).
            end.
            return wrkdir.
        end get.
        private set.

    /**
     * Return the current temp directory of the app server agent
     * Under PASOE, this will be $CATALINA_BASE/temp
     */
    define public static property tmpdir as character init ? no-undo
        get():
            if tmpdir eq ? then
            do:
                tmpdir = OSTools:getFullPathname(session:temp-directory).
                if tmpdir eq ? then
                    undo, throw new AppError("Unable to determine the current temp directory", 0).
            end.
            return tmpdir.
        end get.
        private set.

    /**
     * Return the Spark configuration directory
     */
    define public static property sparkConf as character init ? no-undo
        get():
            if sparkConf eq ? then
            do:
                if (configProjectDir gt "") eq true then
                    sparkConf = OSTools:getFullPathname(OSTools:catalinaBase + "conf/" + configProjectDir).
                else
                    sparkConf = OSTools:getFullPathname(os-getenv("SPARK_CONF")).

                if session:client-type eq "4GLCLIENT" then
                    sparkConf = session:temp-directory + "Deploy/Conf".

                if sparkConf eq ? then
                    sparkConf = OSTools:getFullPathname(OSTools:catalinaBase + "conf/spark").
                if sparkConf eq ? then
                    sparkConf = OSTools:getFullPathname(OSTools:catalinaBase + "conf").
                if sparkConf eq ? then
                    sparkConf = "".

                sparkConf = right-trim(replace(sparkConf, "~\", "~/"), "~/") + "~/".
            end.
            return sparkConf.
        end get.
        private set.

    /**
     * Return the $CATALINA_BASE OS environment variable if set
     */
    define public static property catalinaBase as character init ? no-undo
        get():
            if catalinaBase eq ? then
            do:
                catalinaBase = OSTools:getFullPathname(os-getenv("CATALINA_BASE")).
                if catalinaBase eq ? then
                    catalinaBase = "".
            end.
            return catalinaBase.
        end get.
        private set.

    /**
     * Get the full pathname of a file or directory
     * Will return with "/" as the directory separator
     * Directories are returned with a trailing "/"
     */
    method public static character getFullPathname ( input pcFile as character ):
        define variable cReturn as character no-undo.

        file-info:filename = pcFile.
        cReturn = right-trim(replace(file-info:full-pathname,"~\","/"),"/").

        if cReturn ne ? and
           index(file-info:file-type, "D") ne 0 then
        cReturn = cReturn + "/".

        return cReturn.

    end method.

    method public static void osCopyDir ( input pcFrom as character, input pcTo as character ):

        define variable cFrom     as character no-undo.
        define variable cTo       as character no-undo.
        define variable iOsError  as integer   no-undo.

        cFrom = getFullPathname(pcFrom).
        if cFrom eq ? then
            undo, throw new AppError(substitute("Unknown source &1", pcFrom), 0).

        cTo = getFullPathname(pcTo).
        if cTo eq ? then
        do:
            os-create-dir value(pcTo).
            iOsError = os-error.
            if iOsError ne 0 then
                undo, throw new AppError(substitute("Unable to create the directory &1. System Error # &2", pcTo, osErrorMsg(iOsError)), 0).
        end.
        cTo = getFullPathname(pcTo).
        if cTo eq ? then
            undo, throw new AppError(substitute("Unknown destination &1.", pcTo), 0).

        if substring(cFrom, length(cFrom), 1) ne "/" then
        do:
            osCopyFile(cFrom, cTo).
        end.
        else do:
            empty temp-table ttDirStruct.
            drillDir(cFrom).
            processDir(cFrom, cTo).
        end.

        finally:
            empty temp-table ttDirStruct.
        end finally.

    end method.

    method public static JsonArray recurseDir ( input pcFrom as character, input plOmitDirs as logical ):

        define variable hTable as handle     no-undo.
        define variable oTable as JsonObject no-undo.

        empty temp-table ttDirStruct.
        drillDir(right-trim(replace(pcFrom,"~\","/"),"/")).

        if plOmitDirs then
            for each ttDirStruct
               where ttDirStruct.isDir:
                delete ttDirStruct.
            end.

        oTable = new JsonObject().
        hTable = temp-table ttDirStruct:handle.
        oTable:read(hTable).
        return oTable:GetJsonArray("ttDirStruct").

    end method.

    method private static void drillDir ( input pcFrom as character ):

        define variable cFileName as character no-undo.
        define variable cFullName as character no-undo.
        define variable cCodes    as character no-undo.

        input from os-dir(pcFrom) no-echo.
        repeat:
            import cFileName cFullName cCodes.

            if cFileName = "." or
               cFileName = ".." then next.

            create ttDirStruct.
            assign
                ttDirStruct.ParentDir = pcFrom
                ttDirStruct.FileName  = cFileName
                ttDirStruct.FullPath  = getFullPathname(cFullName)
                ttDirStruct.isDir     = (index(cCodes, "D":U) ne 0)
                .
            release ttDirStruct no-error.
        end.
        input close.

        for each ttDirStruct
           where ttDirStruct.ParentDir eq pcFrom
             and ttDirStruct.isDir:
            drillDir(substitute("&1/&2", ttDirStruct.ParentDir, ttDirStruct.FileName)).
        end.

    end method.

    method private static void processDir ( input pcFrom as character, input pcTo as character ):

        define variable iOsError as integer   no-undo.
        define variable cFrom    as character no-undo.
        define variable cTo      as character no-undo.

        for each ttDirStruct:
            ttDirStruct.DestDir = pcTo + replace(ttDirStruct.FullPath, pcFrom, "").

            if ttDirStruct.isDir then
            do:
                os-create-dir value(ttDirStruct.DestDir).
                iOsError = os-error.
                if iOsError ne 0 then
                    undo, throw new AppError(substitute("Unable to create the directory &1. System Error - &2", pcTo, osErrorMsg(iOsError)), 0).
            end.
        end.

        for each ttDirStruct where not ttDirStruct.isDir:
            osCopyFile(ttDirStruct.FullPath, ttDirStruct.DestDir).
        end.

    end method.

    method public static void osCopyFile ( input pcFrom as character, input pcTo as character ):

        define variable iOsError as integer no-undo.

        os-copy value(pcFrom) value(pcTo).
        iOsError = os-error.
        if iOsError ne 0 then
            undo, throw new AppError(substitute("Unable to copy file &1 to &2. System Error - &3", pcFrom, pcTo, osErrorMsg(iOsError)), 0).

    end method.

    method public static character osCreateDirTree ( input pcDir as character ):

        define variable iOsError as integer no-undo.
        define variable iLoop as integer no-undo.
        define variable iCnt as integer no-undo.
        define variable cFullPath as character no-undo.
        define variable cPath as character no-undo.

        cFullPath = getFullPathname(pcDir).

        if cFullPath ne ? then
            return cFullPath.

        pcDir = replace(pcDir, "~\", "/").
        iCnt = num-entries(pcDir, "/").

        cPath = "".
        do iLoop = 1 to iCnt:
            cPath = cPath + entry(iLoop, pcDir, "/") + "/".
            cFullPath = getFullPathname(cPath).
            if iLoop eq 1 and cFullPath eq ? and cPath matches "*:*" then
                undo, throw new AppError(substitute("Unable to create directory &1. Invalid Drive &2", pcDir, cPath), 0).

            if cFullPath eq ? then
            do:
                os-create-dir value(cPath).
                iOsError = os-error.
                if iOsError ne 0 then
                    undo, throw new AppError(substitute("Unable to create directory &1. System Error - &2", cPath, osErrorMsg(iOsError)), 0).
                cFullPath = getFullPathname(cPath).
            end.

        end.

        return cFullPath.

    end method.

    method public static character osErrorMsg ( input piOsError as integer ):

        if piOsError ne 0 then
            case piOsError:
                when 1   then return "Not owner".
                when 2   then return "No such file or directory".
                when 3   then return "Interrupted system call".
                when 4   then return "I/O error".
                when 5   then return "Bad file number".
                when 6   then return "No more processes".
                when 7   then return "Not enough core memory".
                when 8   then return "Permission denied".
                when 9   then return "Bad address".
                when 10  then return "File exists".
                when 11  then return "No such device".
                when 12  then return "Not a directory".
                when 13  then return "Is a directory".
                when 14  then return "File table overflow".
                when 15  then return "Too many open files".
                when 16  then return "File too large".
                when 17  then return "No space left on device".
                when 18  then return "Directory not empty".
                when 999 then return "Unmapped error".
            end case.

    end method.

end class.