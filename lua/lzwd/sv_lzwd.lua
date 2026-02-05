local Addons = {}

function lzwd.AddClientAutoload( workshopid )
    if table.HasValue( Addons, workshopid ) then return end

    table.insert( Addons, workshopid )
end


util.AddNetworkString( "LzWD_WorkshopAddons" )

concommand.Add( "lzwd_request_addons", function( requester )
    if not IsValid( requester ) then
        print( "This command should only be run by players!" )
        return
    end

    net.Start( "LzWD_WorkshopAddons" )
        net.WriteUInt( #Addons, 8 )

        for _, workshopid in ipairs(Addons) do
            net.WriteString(workshopid) -- As GLua does not supports 64-bit integers and addon ID will go over 32 bits (it is already >31 bit), 
                                        -- writing addon id as string is only futureproof way
        end
    net.Send( requester )
end )