function ShowNotification(message, notifyType, title, duration)
    notifyType = notifyType or 'inform'
    title = title or 'Notification'
    duration = duration or Config.NotificationDuration

    if Config.NotificationSystem == "ox" and lib and lib.notify then
        lib.notify({
            description = message,
            type = notifyType, -- 'inform', 'success', 'error', 'warning'
            position = Config.NotificationPosition
        })

    elseif Config.NotificationSystem == "okok" and exports['okokNotify'] then
        local typeMap = {
            inform = 'info',
            info = 'info',
            success = 'success',
            error = 'error',
            warning = 'warning'
        }
        local okokType = typeMap[notifyType] or 'info'

        exports['okokNotify']:Alert(title, message, duration, okokType)

    else
        BeginTextCommandThefeedPost("STRING")
        AddTextComponentSubstringPlayerName(message)
        EndTextCommandThefeedPostMessagetext("CHAR_DEFAULT", "CHAR_DEFAULT", false, 1, title, "")
        EndTextCommandThefeedPostTicker(false, false)
    end
end

RegisterNetEvent('SNX_fishing:showNotification')
AddEventHandler('SNX_fishing:showNotification', ShowNotification)

function ShowUI(text, icon)
    if Config.UISystem == "ox" and lib and lib.showTextUI then
        -- ox_lib version
        if not icon or icon == 0 then
            lib.showTextUI(text)
        else
            lib.showTextUI(text, { icon = icon })
        end

    elseif Config.UISystem == "okok" and exports['okokTextUI'] then
        -- okokTextUI version
        exports['okokTextUI']:Open(text, Config.DefaultUIColor, "right") 
        -- Possible colors: 'lightblue', 'lightgreen', 'darkgreen', 'red', etc.

    else
        print("^3[UI] ^7" .. text)
    end
end

function HideUI()
    if Config.UISystem == "ox" and lib and lib.hideTextUI then
        lib.hideTextUI()
    elseif Config.UISystem == "okok" and exports['okokTextUI'] then
        exports['okokTextUI']:Close()
    end
end

function ShowProgressBar(text, duration, canCancel, anim, prop)
    duration = duration or 5000
    canCancel = canCancel ~= false -- default true

    if Config.ProgressBarSystem == "ox" and lib and lib.progressBar then
        -- ox_lib version
        return lib.progressBar({
            duration = duration,
            label = text,
            useWhileDead = false,
            canCancel = canCancel,
            disable = {
                car = true,
                move = true,
                combat = true
            },
            anim = anim,
            prop = prop
        })

    elseif Config.ProgressBarSystem == "qb" and exports['progressbar'] then
        local animDict, animName = nil, nil
        if anim and anim.dict and anim.clip then
            animDict = anim.dict
            animName = anim.clip
        end

        exports['progressbar']:Progress({
            name = 'custom_progress',
            duration = duration,
            label = text,
            useWhileDead = false,
            canCancel = canCancel,
            controlDisables = {
                disableMovement = true,
                disableCarMovement = true,
                disableCombat = true,
            },
            animation = {
                animDict = animDict,
                anim = animName
            },
            prop = prop
        }, function(cancelled)
            if cancelled then
                TriggerEvent('progressbar:cancelled')
            else
                TriggerEvent('progressbar:finished')
            end
        end)
        return not cancelled

    else
        print("^3[ProgressBar] ^7Fallback — " .. text .. " (" .. duration .. "ms)")
        Wait(duration)
        return true
    end
end

function _getOxDifficultiesByChance(chance)
    for _, rule in ipairs(Config.FishingSkillRules.ox) do
        if chance >= rule.minChance then
            return rule.difficulties
        end
    end
    return { 'medium', 'hard' } -- fallback
end

function _getPsParamsByChance(chance)
    for _, rule in ipairs(Config.FishingSkillRules.ps) do
        if chance >= rule.minChance then
            return rule.circles, rule.ms
        end
    end
    return 3, 18 -- fallback
end

-- One API to run a skill check; returns boolean
function DoFishingSkillCheck(fishId)
    local f = Config.fish[fishId]
    if not f then return false end

    local chance = tonumber(f.chance) or 15

    if Config.SkillSystem == 'ox' and lib and lib.skillCheck then
        local diffs = _getOxDifficultiesByChance(chance)
        return lib.skillCheck(diffs, { 'e' }) == true

    elseif Config.SkillSystem == 'ps' and exports['ps-ui'] then
        local circles, ms = _getPsParamsByChance(chance)
        local p = promise.new()
        exports['ps-ui']:Circle(function(success)
            p:resolve(success and true or false)
        end, circles, ms)
        return Citizen.Await(p) == true
    end

    -- If neither is available, succeed to avoid soft-locks (or change to false if you prefer)
    return true
end

function SetVehicleFuel(vehicle, fuelLevel)
    -- sanitize
    fuelLevel = tonumber(fuelLevel) or 0
    if fuelLevel < 0 then fuelLevel = 0 end
    if fuelLevel > 100 then fuelLevel = 100 end

    -- LegacyFuel
    if GetResourceState('LegacyFuel') == 'started' and exports['LegacyFuel'] then
        exports['LegacyFuel']:SetFuel(vehicle, fuelLevel)
        return
    end

    -- cdn-fuel
    if GetResourceState('cdn-fuel') == 'started' and exports['cdn-fuel'] then
        exports['cdn-fuel']:SetFuel(vehicle, fuelLevel)
        return
    end

    -- ox_fuel (statebag)
    if GetResourceState('ox_fuel') == 'started' then
        Entity(vehicle).state.fuel = fuelLevel
        return
    end

    -- fallback native (works if you’re using GTA’s internal fuel level)
    SetVehicleFuelLevel(vehicle, fuelLevel + 0.0)
end

function SetVehicleOwner(plate)
    if Framework.name == 'es_extended' then
        -- Not implemented
    elseif Framework.name == 'qb-core' then
        TriggerEvent("vehiclekeys:client:SetOwner", plate)
    end
end

local function isStarted(resourceName)
    return GetResourceState(resourceName) == 'started'
end

---@type string
local path

if isStarted('ox_inventory') then
    path = 'nui://ox_inventory/web/images/%s.png'
elseif isStarted('qb-inventory') then
    path = 'nui://qb-inventory/html/images/%s.png'
elseif isStarted('ps-inventory') then
    path = 'nui://ps-inventory/html/images/%s.png'
elseif isStarted('lj-inventory') then
    path = 'nui://lj-inventory/html/images/%s.png'
elseif isStarted('qs-inventory') then
    path = 'nui://qs-inventory/html/images/%s.png' -- Not really sure
end

---Returns the NUI path of an icon.
---@param itemName string
---@return string?
---@diagnostic disable-next-line: duplicate-set-field
function GetInventoryIcon(itemName)
    if not path then
        warn('Inventory images path not set in cl_edit.lua!')
        return
    end

    return path:format(itemName) .. '?height=128'
end
