-- =============================================================================
--  bGliderProtection
--    by: BurstBiscuit
-- =============================================================================

require "math"
require "table"
require "unicode"

require "lib/lib_Callback2"
require "lib/lib_ChatLib"
require "lib/lib_Debug"
require "lib/lib_InterfaceOptions"
require "lib/lib_Slash"
require "lib/lib_Vector"

Debug.EnableLogging(false)


-- =============================================================================
--  Variables
-- =============================================================================

local g_Away = false
local g_ForceEnabled = false
local CB2_CancelGlider


-- =============================================================================
--  Interface Options
-- =============================================================================

local io_Settings = {
    Debug = false,
    Enabled = false,
    Notification = false,
    Distance = 1.5,
    Item = 121257
}

function OnOptionChanged(id, value)
    if (id == "DEBUG_ENABLE") then
        Debug.EnableLogging(value)
    elseif (id == "GENERAL_ENABLE") then
        io_Settings.Enabled = value
    elseif (id == "GENERAL_NOTIFICATION") then
        io_Settings.Notification = value
    elseif (id == "GENERAL_DISTANCE") then
        io_Settings.Distance = tonumber(value)
    elseif (id == "GENERAL_ITEM") then
        if (Game.GetItemInfoByType(tonumber(value)) ~= nil) then
            if (Game.CanUIActivateItem(nil, tonumber(value))) then
                io_Settings.Item = tonumber(value)
            else
                Notification("Unable to set new item: item can't be activated by the UI")
            end
        else
            Notification("Unable to set new item: item with supplied SDB id does not exist")
        end
    end
end

do
    InterfaceOptions.SaveVersion(1)

    InterfaceOptions.AddCheckBox({id = "DEBUG_ENABLE", label = "Debug mode", default = io_Settings.Debug})
    InterfaceOptions.AddCheckBox({id = "GENERAL_ENABLE", label = "Addon enabled", default = io_Settings.Enabled})
    InterfaceOptions.AddCheckBox({id = "GENERAL_NOTIFICATION", label = "Show notification in chat", default = io_Settings.Notification})
    InterfaceOptions.AddSlider({id = "GENERAL_DISTANCE", label = "Notification distance", default = io_Settings.Distance, min = 0.5, max = 5.0, inc = 0.1, format = "%0.1f", suffix = "m"})
    InterfaceOptions.AddTextInput({id = "GENERAL_ITEM", label = "Item SDB ID", default = io_Settings.Item, numeric = true, whitespace = false})
end


-- =============================================================================
--  Functions
-- =============================================================================

function Notification(message)
    ChatLib.Notification({text = "[bGliderProtection] " .. tostring(message)})
end

function CancelGlider()
    pcall(function()
        Player.ActivateTech(nil, io_Settings.Item)
    end)
    Component.SetInputMode("default")
end

function OnSlashCommand(args)
    g_ForceEnabled = not g_ForceEnabled
    Notification("g_ForceEnabled set to " .. tostring(g_ForceEnabled))
end


-- =============================================================================
--  Events
-- =============================================================================

function OnComponentLoad()
    LIB_SLASH.BindCallback({
        slash_list = "bgliderprotection, bgp",
        description = "bGliderProtection: Enables or disables forced protection",
        func = OnSlashCommand
    })

    CB2_CancelGlider = Callback2.Create()
    CB2_CancelGlider:Bind(CancelGlider)

    InterfaceOptions.SetCallbackFunc(OnOptionChanged)
end

function OnAFKChanged(args)
    Debug.Event(args)

    if (args.isAfk) then
        g_Away = true
    else
        g_Away = false
    end
end

function OnPlayerGlide(args)
    Debug.Event(args)

    if (io_Settings.Enabled and (g_Away or g_ForceEnabled) and args.gliding) then
        if (not CB2_CancelGlider:Pending()) then
            Component.SetInputMode("cursor")
            CB2_CancelGlider:Schedule(0.1)
        end
    end
end

function OnEntityAvailable(args)
    if (io_Settings.Enabled and io_Settings.Notification and (g_Away or g_ForceEnabled) and args.entityId and Game.IsTargetAvailable(args.entityId)) then
        local targetInfo = Game.GetTargetInfo(args.entityId)

        if (targetInfo and targetInfo.deployableCategory and unicode.upper(targetInfo.deployableCategory) == "GLIDER PAD") then
            local ownerTargetInfo = nil
            local playerTargetBounds = Game.GetTargetBounds(Player.GetTargetId())
            local targetBounds = Game.GetTargetBounds(args.entityId)

            if (targetInfo.ownerId and Game.IsTargetAvailable(targetInfo.ownerId)) then
                ownerTargetInfo = Game.GetTargetInfo(targetInfo.ownerId)
            end

            if (playerTargetBounds and targetBounds) then
                local distance = Vec3.Distance(playerTargetBounds, targetBounds)
                Debug.Log("Glider pad distance: " .. tostring(distance))

                if (distance <= io_Settings.Distance) then
                    if (ownerTargetInfo and ownerTargetInfo.name) then
                        Notification(tostring(targetInfo.name) .. " was placed near you by " .. tostring(ChatLib.EncodePlayerLink(ownerTargetInfo.name)))
                    else
                        Notification(tostring(targetInfo.name) .. " was placed near you")
                    end
                end
            end
        end
    end
end
