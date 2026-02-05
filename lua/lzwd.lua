if lzwd ~= nil then return end

AddCSLuaFile()

include( "includes/loader.lua" )
include( "core_extensions.lua" )


lzwd = lzwd or {}

function lzwd.Log( msg )
    MsgC( "LzWD > ", msg, "\n" )
end


loader.AutoDir( "lzwd" )

loader.Shared( "includes/extensions/lzwd/resource.lua" )
loader.Client( "includes/lzwd/optional_addons.lua" )