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

local FRAME         = Component.GetFrame("Main")
local STATUS        = Component.GetWidget("Status")

local c_ChecksMax   = 5


-- =============================================================================
--  Variables
-- =============================================================================

local g_Away            = false
local g_Checks          = 0
local g_Count           = 0
local g_ForceEnabled    = false
local g_Incidents       = {}

local CB2_CancelGlider
local CB2_CheckGlider
local CB2_CleanUpIncidents


-- =============================================================================
--  Interface Options
-- =============================================================================

local io_Settings = {
    Debug               = false,
    Enabled             = false,
    Notification        = false,
    CancelForcedMode    = false,
    Distance            = 1.5,
    Item                = 121257
}

function OnOptionChanged(id, value)
    if     (id == "DEBUG_ENABLE") then
        Debug.EnableLogging(value)

    elseif (id == "GENERAL_ENABLE") then
        g_Checks            = 0
        io_Settings.Enabled = value

        UpdateStatusWidget()

    elseif (id == "GENERAL_NOTIFICATION") then
        io_Settings.Notification = value

    elseif (id == "GENERAL_CANCEL_FORCED_MODE") then
        io_Settings.CancelForcedMode = value

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
    InterfaceOptions.AddCheckBox({id = "GENERAL_CANCEL_FORCED_MODE", label = "Automatically cancel forced mode when using abilities or items", default = io_Settings.CancelForcedMode})
    InterfaceOptions.AddSlider({id = "GENERAL_DISTANCE", label = "Notification distance", default = io_Settings.Distance, min = 0.5, max = 5.0, inc = 0.1, format = "%0.1f", suffix = "m"})
    InterfaceOptions.AddTextInput({id = "GENERAL_ITEM", label = "Item SDB ID", default = io_Settings.Item, numeric = true, whitespace = false})
end


-- =============================================================================
--  Functions
-- =============================================================================

function Notification(message)
    ChatLib.Notification({text = "[bGliderProtection] " .. tostring(message)})
end

function CheckGlider()
    Debug.Log("CheckGlider()")

    if (io_Settings.Enabled and (g_Away or g_ForceEnabled)) then
        local gliderStatus = Player.GetGliderStatus()
        Debug.Table("gliderStatus", gliderStatus)

        -- Check if actually gliding
        if (gliderStatus and gliderStatus.glider_state and unicode.match(gliderStatus.glider_state, "Glider")) then
            -- Schedule the glider cancelation
            if (not CB2_CancelGlider:Pending()) then
                Component.SetInputMode("cursor")
                CB2_CancelGlider:Schedule(0.1)
            end

        -- Not gliding, schedule a check anyway in case something messed up the timing
        elseif (not CB2_CheckGlider:Pending() and g_Checks < 5) then
            g_Checks = g_Checks + 1

            Debug.Log("Not gliding, rescheduling callback to verify: check", g_Checks, "of", c_ChecksMax)
            CB2_CheckGlider:Schedule(3)

        -- Reset the check counter
        else
            g_Checks = 0
        end
    end
end

function CancelGlider()
    Debug.Log("CancelGlider()")

    if (io_Settings.Enabled and (g_Away or g_ForceEnabled)) then
        -- Get the item info
        local itemInfo      = Game.GetItemInfoByType(io_Settings.Item)
        local itemCooldown  = 0
        Debug.Table("itemInfo", itemInfo)

        -- Get the ability info and state of the item
        if (itemInfo and itemInfo.abilityId) then
            local abilityState = Player.GetAbilityState(itemInfo.abilityId)
            Debug.Table("abilityState", abilityState)

            -- Try to get the ability cooldown
            if (abilityState and abilityState.requirements and abilityState.requirements.remainingCooldown) then
                itemCooldown = tonumber(abilityState.requirements.remainingCooldown) + 0.1
            end
        end

        -- Item is still recharging, reschedule the callback
        if (itemCooldown > 0) then
            if (not CB2_CancelGlider:Pending()) then
                Debug.Log("Item is recharging, rescheduling callback:", itemCooldown)
                CB2_CancelGlider:Schedule(itemCooldown)

            -- If the callback is already scheduled, check if the recharge time of the item is shorter and reschedule if so
            elseif (CB2_CancelGlider:Pending() and CB2_CancelGlider:GetRemainingTime() > itemCooldown) then
                Debug.Log("Item is recharging, rescheduling callback:", itemCooldown)
                CB2_CancelGlider:Reschedule(itemCooldown)
            end

        -- Item is not recharging, try to activate right away
        else
            Debug.Log("Trying to activate item:", itemInfo.name)
            local status, err = pcall(function()
                Player.ActivateTech(nil, io_Settings.Item)
            end)

            Debug.Table("pcall()", {status = status, err = err})

            -- Set input mode to default
            Component.SetInputMode("default")

            -- Schedule a callback to see if the glider was actually canceled (Icarus boost ...)
            if (not CB2_CheckGlider:Pending()) then
                g_Checks = 0

                Debug.Log("Scheduling callback to check if glider was canceled")
                CB2_CheckGlider:Schedule(1)
            end
        end
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
    g_ForceEnabled = not g_ForceEnabled

    Notification("Forced protection " .. (g_ForceEnabled and "enabled" or "disabled"))
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

    CB2_CheckGlider = Callback2.Create()
    CB2_CheckGlider:Bind(CheckGlider)

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

function OnAbilityUsed(args)
    Debug.Event(args)
    local itemInfo = Game.GetItemInfoByType(io_Settings.Item)

    -- Cancel the forced protection if we activate an ability ourself that is not the item set in options
    if (io_Settings.CancelForcedMode and g_ForceEnabled and args.id and itemInfo and itemInfo.abilityId and tonumber(args.id) ~= tonumber(itemInfo.abilityId)) then
        g_ForceEnabled = false
        Notification("Forced protection disabled")
        UpdateStatusWidget()
    end
end

function OnAFKChanged(args)
    Debug.Event(args)

    g_Away = args.isAfk
    UpdateStatusWidget()
end

function OnPlayerGlide(args)
    Debug.Event(args)

    if (io_Settings.Enabled and (g_Away or g_ForceEnabled) and args.gliding) then
        if (not CB2_CheckGlider:Pending()) then
            CB2_CheckGlider:Execute()
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
