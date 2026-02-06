require( "deferred" )

local insert = table.insert
local format, find, match, StartWith, Explode = string.format, string.find, string.match, string.StartWith, string.Explode
local AsyncRead = file.AsyncRead
local ParseProperties = util.ParseProperties

local Log = lzwd.Log


--[[
        Caching
--]]

local CACHE_DIR = "lzwd/"
local CACHE_FILEPATH_SAVED = CACHE_DIR .. "cache.txt"

local SavedAddons = {}

local function CACHE_FILEPATH_GMA( wsid )
    return CACHE_DIR .. wsid .. ".gma.dat"
end

local function ReadCacheIndex()
    SavedAddons = {}

    local data = file.Read( CACHE_FILEPATH_SAVED, "DATA" )
    if data == nil then return end

    for _, line in ipairs( Explode( "\n", data ) ) do
        if line == "" then continue end
        line = Explode( " ", line )

        local wsid = line[1]
        local timestamp = tonumber( line[2] )

        local filepath = CACHE_FILEPATH_GMA( wsid )

        if file.Exists( filepath, "DATA" ) then
            SavedAddons[wsid] = timestamp
        end
    end
end

local function WriteCacheIndex()
    local cache = file.OpenEnsureDir( CACHE_FILEPATH_SAVED, "w", "DATA" )
    if cache == nil then
        error( "Failed to write cache descriptor file" )
    end

    for wsid, timestamp in pairs( SavedAddons ) do
        cache:Write( wsid .. " " .. timestamp .. "\n" )
    end

    cache:Close()
end

ReadCacheIndex()


local function CacheGMA( workshopid, gma, timestamp )
    local cache = file.OpenEnsureDir( CACHE_FILEPATH_GMA( workshopid ), "wb", "DATA" )
    if cache == nil then
        error( format( "Failed to write cache file '%s'", workshopid ) )
    end

    while not gma:EndOfFile() do
        cache:Write( gma:Read( 16 * 1024 * 1024 ) )
    end

    cache:Close()

    SavedAddons[workshopid] = timestamp
    WriteCacheIndex()
end

local function GetCachedGMAFilepath( workshopid, timestamp )
    local cache_timestamp = SavedAddons[workshopid]
    
    if cache_timestamp == nil 
        or (timestamp ~= nil and cache_timestamp < timestamp) 
    then
        return nil
    end

    return "data/" .. CACHE_FILEPATH_GMA( workshopid )
end


--[[
        Mounting
--]]
local function CompileGMAFile( filepath, identifier )
    local d = deferred.new()

    AsyncRead( filepath, "WORKSHOP", function( filename, _, status, data )
        if status == FSASYNC_OK then
            Log( "compiling '" .. filename .. "'" )

            d:resolve( CompileString( data, filename ) )
        else
            d:reject( "unable to read '" .. filepath .. "': " .. status )
        end
    end )

    return d
end

local function MountLocalization( filepath )
    local d = deferred.new()

    AsyncRead( filepath, "WORKSHOP", function( filename, _, status, data )
        if status == FSASYNC_OK then
            ParseProperties( data, language.Add )

            d:resolve()
        else
            d:reject( "unable to read '" .. filepath .. "': " .. status )
        end
    end )

    return d
end


local LANGUAGE = GetConVar( "gmod_language" ):GetString()

local PATH_LUA          = "lua/"
local PATH_LOCALIZATION = "resource/localization/"

local PATTERN_PATH_LOCALE = "([^/]+)/[^/]+%.properties"

-- https://wiki.facepunch.com/gmod/Lua_Loading_Order#clientloadingorder
local PATTERNS_INORDER = {
    PATH_LUA .. "autorun/[^/]+%.lua",
    PATH_LUA .. "autorun/client/[^/]+%.lua",
    PATH_LUA .. "postprocess/[^/]+%.lua"
}

local sort_entries = function( a, b )
    if a.pathOrder ~= b.pathOrder then
        return a.pathOrder < b.pathOrder
    end

    return a.fileOrder < b.fileOrder
end

local function MountFiles( files, compileLua )
    compileLua = compileLua ~= false


    local lua, localization = {}, { [LANGUAGE] = {}, ["en"] = {} }

    for i = 1, #files do
        local filepath = files[i]
        
        if compileLua and StartWith( filepath, PATH_LUA ) then
            for j = 1, #PATTERNS_INORDER do
                local pattern = PATTERNS_INORDER[j]

                if find( filepath, pattern ) then
                    insert( lua, {
                        filepath = filepath,
                        pathOrder = j,
                        fileOrder = i,
                    } )

                    break
                end
            end

        elseif StartWith( filepath, PATH_LOCALIZATION ) then
            local locale = match( filepath, PATTERN_PATH_LOCALE )
            if not localization[locale] then continue end
            
            insert( localization[locale], filepath )
        end
    end


    local promises = {}

    if #lua > 0 then
        table.sort( lua, sort_entries )

        local d = deferred.new()
        
        for i = 1, #lua do
            lua[i] = CompileGMAFile( lua[i].filepath )
        end

        deferred.all( lua ):next(
            function( results )
                for i = 1, #results do
                    -- fn = nil => there was an error
                    --  (?) reject in that case
                    local fn = results[i]
                    if fn then fn() end
                end

                d:resolve()
            end,
            function( results )
                d:reject( "compilation failed" )
            end
        )

        insert( promises, d )
    end

    local localizationNative = localization[LANGUAGE]
    if #localizationNative > 0 then
        insert( promises, deferred.map( localizationNative, MountLocalization ) )
    else
        -- localization["en"] may be empty too, however it's not gonna break. 
        insert( promises, deferred.map( localization["en"], MountLocalization ) )
    end

    return deferred.all( promises )
end

local function MountGMA( path, compileLua, onSuccess, onFailure )
    local success, files = game.MountGMA( path )
    if not success then
        onFailure( "game.MountGMA failed" )
        return
    end

    MountFiles( files, compileLua ):next( onSuccess, onFailure )
end


--[[
        Downloading
--]] 

local function DownloadUGC( workshopid, retries, onSuccess, onFailure )
    retries = retries or 6

    steamworks.DownloadUGC( workshopid, function( path, gma )
        if path ~= nil then 
            onSuccess( path, gma )
        else
            if retries > 0 then
                timer.Simple( 2, function()
                    Log( format( "Failed to download '%s', retrying (attempt %i)", workshopid, retries ) )

                    DownloadUGC( workshopid, retries - 1, onSuccess, onFailure )
                end )
            else
                onFailure()
            end
        end
    end )
end


local Loaded = {}

local function IsLoaded( workshopid )
    return Loaded[workshopid] or false
end
lzwd.IsLoaded = IsLoaded

local function LoadAddon_Internal( filepath, workshopid, timestamp, compileLua, onSuccess, onFailure )
    if filepath then
        MountGMA( filepath, compileLua,
            function()
                Log( format( "loaded '%s' (%s)", workshopid, filepath ) )

                Loaded[workshopid] = true

                if onSuccess then onSuccess() end 
            end, 
            function( err )
                ErrorNoHaltWithStack( format( "Failed to load addon '%s': mount failed (%s)", workshopid, err or "unknown" ) )

                if onFailure then onFailure() end
            end 
        )
    else
        DownloadUGC( workshopid, nil,
            function( path, gma )
                LoadAddon_Internal( path, workshopid, nil, compileLua, onSuccess, onFailure )

                if timestamp then
                    CacheGMA( workshopid, gma, timestamp )
                end
            end,
            function()
                ErrorNoHaltWithStack( format( "Failed to load addon '%s': download failed", workshopid ) )

                if onFailure then onFailure() end
            end
        )
    end
end

local function LoadAddon( workshopid, compileLua, onSuccess, onFailure )
    if IsLoaded( workshopid ) then return end

    local addon = engine.FindAddon( workshopid )
    if addon then
        -- mount
        LoadAddon_Internal( addon.file, workshopid, nil, compileLua, onSuccess, onFailure )
        return
    end

    steamworks.FileInfo( workshopid, function( data )
        if data ~= nil then
            --[[
                if cached then
                    mount
                else
                    download
                    mount
                    cache
            --]]
            
            local filepath = GetCachedGMAFilepath( workshopid, data.updated )

            LoadAddon_Internal( filepath, workshopid, data.updated, compileLua, onSuccess, onFailure )
        else
            --[[
                if cached then
                    mount
                else
                    download
                    mount
            --]]

            Log( format( "Failed to fetch info '%s', will try to mount cached or download without caching.", workshopid ) )

            local filepath = CACHE_FILEPATH_GMA( workshopid )

            LoadAddon_Internal( filepath, workshopid, nil, compileLua, onSuccess, onFailure )
        end
    end )
end
lzwd.LoadAddon = LoadAddon


hook.Add( "InitPostEntity", "LzWD", function()
    timer.Simple( 6, function()
        RunConsoleCommand( "lzwd_request_addons" )
    end )
end )

net.Receive( "LzWD_WorkshopAddons", function()
    local count = net.ReadUInt( 8 )


    local function onResult()
        count = count - 1

        if count == 0 then
            RunConsoleCommand( "spawnmenu_reload" )
        end
    end

    for i = 1, count do
        LoadAddon( net.ReadString(), false, onResult, onResult )
    end
end )