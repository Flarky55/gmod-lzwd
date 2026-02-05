if SERVER then
    
    resource.AddWorkshopLazy = lzwd.AddClientAutoload

else

    resource = {}


    local KEY = "OptionalAddons"

    function resource.GetAllOptional()
        return list.Get( KEY )
    end

    local function GetOptional( workshopid )
        return list.GetEntry( KEY, workshopid )
    end
    resource.GetOptional = GetOptional

    local function HasOptional( workshopid )
        return list.HasEntry( KEY, workshopid )
    end
    resource.HasOptional = HasOptional

    function resource.AddWorkshopOptional( workshopid, data )
        list.Set( KEY, workshopid, data )
    end


    local Enabled = {}

    local function ReadEnabled()
        local content = file.Read( "optionaladdons.txt", "DATA" )
        if content == nil then return end

        Enabled = {}

        local workshopids = string.Explode( "\n", content )
        for _, workshopid in ipairs( workshopids ) do
            -- if workshopid == "" then continue end

            Enabled[workshopid] = true
        end
    end

    local function WriteEnabled()
        local content = table.concat( table.GetKeys( Enabled ), "\n" )

        local success = file.Write( "optionaladdons.txt", content )
        if not success then
            ErrorNoHalt( "Failed to write 'data/optionaladdons.txt'", "\n" )
            return
        end
    end

    ReadEnabled()


    local IsOptionalLoaded = lzwd.IsLoaded
    resource.IsOptionalLoaded = IsOptionalLoaded

    local function EnableOptional( workshopid )
        if IsOptionalLoaded( workshopid ) then return end

        local data = GetOptional( workshopid )
        if data == nil then return end

        lzwd.LoadAddon( workshopid, data.compileLua, data.onLoaded )

        Enabled[workshopid] = true
        WriteEnabled()
    end
    resource.EnableOptional = EnableOptional

    local function DisableOptional( workshopid )
        if not IsOptionalLoaded( workshopid ) then return end

        Enabled[workshopid] = nil
        WriteEnabled()
    end
    resource.DisableOptional = DisableOptional


    hook.Add( "InitPostEntity", "resource", function()
        for wsid in pairs( Enabled ) do
            EnableOptional( wsid )
        end
    end )

end