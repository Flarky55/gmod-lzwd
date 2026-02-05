hook.Add( "PopulateToolMenu", "OptionalAddons", function()
    spawnmenu.AddToolMenuOption( "Utilities", "User", "OptionalAddons", "#spawnmenu.utilities.optionaladdons", nil, nil, function( cpanel )

        local label = cpanel:Help( "#optionaladdons.settings.note" )
        label:SetHighlight( true )

        local categories = {}
        for wsid, data in pairs( resource.GetAllOptional() ) do
            local dataCategory = data.category or "#optionaladdons.category.other"

            local form = categories[dataCategory]
            if form == nil then
                form = vgui.Create( "DForm" )
                form:SetName( dataCategory )

                cpanel:AddPanel( form )

                categories[dataCategory] = form
            end

            
            local checkbox = form:CheckBox( "N/A" )
            checkbox:SetChecked( resource.IsOptionalLoaded( wsid ) )
            checkbox.OnChange = function( s, bVal )
                if bVal then
                    resource.EnableOptional( wsid )
                else
                    resource.DisableOptional( wsid )
                end
            end
            
            local label = form:ControlHelp( wsid )
            label:SetMouseInputEnabled( true )
            label:SetCursor( "hand" )
            label.DoClick = function()
                steamworks.ViewFile( wsid )
            end

            steamworks.FileInfo( wsid, function( info )
                checkbox:SetText( info.title )
            end )
        end

    end )
end )