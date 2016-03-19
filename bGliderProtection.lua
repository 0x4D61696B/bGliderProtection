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
require "lib/lib_HudManager"
require "lib/lib_InterfaceOptions"
require "lib/lib_Slash"
require "lib/lib_Vector"

Debug.EnableLogging(false)

-- =============================================================================
--  Constants
-- =============================================================================

local FRAME = Component.GetFrame("Main")
local STATUS = Component.GetWidget("Status")


-- =============================================================================
--  Variables
-- =============================================================================

local g_Away = false
local g_Count = 0
local g_ForceEnabled = false
local g_Incidents = {}

local CB2_CancelGlider
local CB2_CleanUpIncidents


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
        UpdateStatusWidget()
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
    local itemInfo = Game.GetItemInfoByType(io_Settings.Item)
    local itemCooldown = 0
    Debug.Table("itemInfo", itemInfo)

    if (itemInfo and itemInfo.abilityId) then
        local abilityState = Player.GetAbilityState(itemInfo.abilityId)
        Debug.Table("abilityState", abilityState)

        if (abilityState and abilityState.requirements and abilityState.requirements.remainingCooldown) then
            itemCooldown = tonumber(abilityState.requirements.remainingCooldown) + 0.1
        end
    end

    if (itemCooldown > 0) then
        Debug.Log("Item is recharging, rescheduling callback:", itemCooldown)
        CB2_CancelGlider:Schedule(itemCooldown)
    else
        Debug.Log("Trying to activate item")
        local status, err = pcall(function()
            Player.ActivateTech(nil, io_Settings.Item)
        end)

        Debug.Table("pcall()", {status = status, err = err})
        Component.SetInputMode("default")
    end
end

function CleanUpIncidents()
    Debug.Log("CleanUpIncidents()")
    log("Previous incidents: " .. tostring(g_Incidents))
    Notification("Cleaning up " .. tostring(g_Count) .. " incident records, check console for more information")
    g_Count = 0
    g_Incidents = {}
end

function UpdateStatusWidget()
    if (io_Settings.Enabled and (g_Away or g_ForceEnabled)) then
        FRAME:Show(true)
    else
        FRAME:Show(false)
    end
end

function OnHudShow(show, duration)
    FRAME:ParamTo("alpha", tonumber(show), duration)
end

function OnSlashCommand(args)
    local stateText = "disabled"
    g_ForceEnabled = not g_ForceEnabled

    if (g_ForceEnabled) then
        stateText = "enabled"
    end

    Notification("Forced protection " .. stateText)
    UpdateStatusWidget()
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

    CB2_CleanUpIncidents = Callback2.Create()
    CB2_CleanUpIncidents:Bind(CleanUpIncidents)

    HudManager.BindOnShow(OnHudShow)

    InterfaceOptions.SetCallbackFunc(OnOptionChanged)
    InterfaceOptions.AddMovableFrame({
        frame = FRAME,
        label = "bGliderProtection",
        scalable = true
    })

    FRAME:Show(false)
    STATUS:SetText("bGliderProtection ACTIVE")
    STATUS:SetTextColor("#327662")
end

function OnAFKChanged(args)
    Debug.Event(args)

    if (args.isAfk) then
        g_Away = true
    else
        g_Away = false
    end

    UpdateStatusWidget()
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
                Debug.Log("Glider pad distance:", distance)

                if (distance <= io_Settings.Distance) then
                    local localUnixTime = System.GetLocalUnixTime()
                    g_Count = g_Count + 1

                    Debug.Log("Total incident count:", g_Count)
                    Debug.Log("Local UNIX time:", localUnixTime)
                    Debug.Table("g_Incidents", g_Incidents)

                    if (ownerTargetInfo and ownerTargetInfo.name) then
                        local normalizedOwnerName = tostring(normalize(ownerTargetInfo.name))

                        if (g_Incidents[normalizedOwnerName]) then
                            Debug.Log("Found a record for possible offender, updating entry")
                            local count = g_Incidents[normalizedOwnerName].counter + 1
                            g_Incidents[normalizedOwnerName].counter = count

                            if (tonumber(System.GetElapsedUnixTime(g_Incidents[normalizedOwnerName].timestamp)) > 60) then
                                g_Incidents[normalizedOwnerName].timestamp = localUnixTime
                                Notification(tostring(ChatLib.EncodePlayerLink(ownerTargetInfo.name)) .. " placed " .. tostring(targetInfo.name) .. " near you (" .. tostring(count) .. ")")
                            end
                        else
                            Debug.Log("No record for possible offender, creating new entry")
                            g_Incidents[normalizedOwnerName] = {}
                            g_Incidents[normalizedOwnerName].counter = 1
                            g_Incidents[normalizedOwnerName].timestamp = localUnixTime

                            Notification(tostring(ChatLib.EncodePlayerLink(ownerTargetInfo.name)) .. " placed " .. tostring(targetInfo.name) .. " near you (1)")
                        end
                    else
                        local deployableName = tostring(unicode.upper(targetInfo.name))

                        if (g_Incidents[deployableName]) then
                            Debug.Log("Found a record for this Glider Pad type, updating entry")
                            local count = g_Incidents[deployableName].counter + 1
                            g_Incidents[deployableName].counter = count

                            if (tonumber(System.GetElapsedUnixTime(g_Incidents[deployableName].timestamp)) > 60) then
                                g_Incidents[deployableName].timestamp = localUnixTime
                                Notification(tostring(targetInfo.name) .. " was placed near you (" .. tostring(count) .. ")")
                            end
                        else
                            Debug.Log("No record for this Glider Pad type, creating new entry")
                            g_Incidents[deployableName] = {}
                            g_Incidents[deployableName].counter = 1
                            g_Incidents[deployableName].timestamp = localUnixTime

                            Notification(tostring(targetInfo.name) .. " was placed near you (1)")
                        end
                    end

                    if (CB2_CleanUpIncidents:Pending()) then
                        Debug.Log("Rescheduling CB2_CleanUpIncidents")
                        CB2_CleanUpIncidents:Reschedule(300)
                    else
                        Debug.Log("Scheduling CB2_CleanUpIncidents")
                        CB2_CleanUpIncidents:Schedule(300)
                    end
                end
            end
        end
    end
end
