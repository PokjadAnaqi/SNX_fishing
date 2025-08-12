---@param first { price: integer }
---@param second { price: integer }
local function sortByPrice(first, second)
    return first.price < second.price
end

table.sort(Config.fishingRods, sortByPrice)
table.sort(Config.baits, sortByPrice)

---@type { normal: number, radius: number }[], CZone[]
local blips, zones = {}, {}
---@type { index: integer, locationIndex: integer }?
local currentZone

---@param level number
local function updateBlips(level)
    for _, blip in ipairs(blips) do
        RemoveBlip(blip.normal)
        RemoveBlip(blip.radius)
    end

    table.wipe(blips)

    for _, zone in ipairs(Config.fishingZones) do
        if zone.blip and zone.minLevel <= level then
            for _, coords in ipairs(zone.locations) do
                local blip = Utils.createBlip(coords, {
                    name = zone.blip.name,
                    sprite = zone.blip.sprite,
                    color = 0,
                    scale = zone.blip.scale
                })
                local radiusBlip = Utils.createRadiusBlip(coords, zone.radius, zone.blip.color)
                
                table.insert(blips, { normal = blip, radius = radiusBlip })
            end
        end
    end
end

---@param level number
local function updateZones(level)
    for _, zone in ipairs(zones) do
        zone:remove()
    end

    table.wipe(zones)

    for index, data in ipairs(Config.fishingZones) do
        if data.minLevel <= level then
            for locationIndex, coords in ipairs(data.locations) do
                local zone = lib.zones.sphere({
                    coords = coords,
                    radius = data.radius,
                    onEnter = function()
                        if currentZone?.index == index and currentZone?.locationIndex == index then return end

                        currentZone = { index = index, locationIndex = locationIndex }
    
                        if data.message then
                            ShowNotification(data.message.enter, 'success')
                        end
                    end,
                    onExit = function()
                        if currentZone?.index ~= index
                        or currentZone?.locationIndex ~= locationIndex then return end
    
                        currentZone = nil

                        if data.message then
                            ShowNotification(data.message.exit, 'inform')
                        end
                    end
                })
    
                table.insert(zones, zone)
            end
        end
    end
end

---@param level integer
function Update(level)
    updateBlips(level)
    updateZones(level)
end

local function createRodObject()
    local model = `prop_fishing_rod_01`

    lib.requestModel(model)

    local coords = GetEntityCoords(cache.ped)
    local object = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
    local boneIndex = GetPedBoneIndex(cache.ped, 18905)

    AttachEntityToEntity(object, cache.ped, boneIndex, 0.1, 0.05, 0.0, 70.0, 120.0, 160.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)

    return object
end

local function hasWaterInFront()
    if IsPedSwimming(cache.ped) or IsPedInAnyVehicle(cache.ped, true) then
        return false
    end
    
    local headCoords = GetPedBoneCoords(cache.ped, 31086, 0.0, 0.0, 0.0)
    local coords = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 45.0, -27.5)
    local hasWater = TestProbeAgainstWater(headCoords.x, headCoords.y, headCoords.z, coords.x, coords.y, coords.z)

    if not hasWater then
        ShowNotification(locale('no_water'), 'error')
    end

    return hasWater
end

lib.callback.register('SNX_fishing:getCurrentZone', function()
    return hasWaterInFront(), currentZone
end)

local function setCanRagdoll(state)
    SetPedCanRagdoll(cache.ped, state)
    SetPedCanRagdollFromPlayerImpact(cache.ped, state)
    SetPedRagdollOnCollision(cache.ped,statefalse)
end

---@param bait FishingBait
---@param fish Fish
lib.callback.register('SNX_fishing:itemUsed', function(bait, fishId)
    local zone = Config.fishingZones[currentZone] or Config.outside
    local object = createRodObject()

    -- preload anims + prep state
    lib.requestAnimDict('mini@tennis')
    lib.requestAnimDict('amb@world_human_stand_fishing@idle_a')
    setCanRagdoll(false)
    ShowUI(locale('cancel'), 'ban')

    local p = promise.new()
    local cancelWithX = false

    -- cancel watcher ( X key, or anim broken)
    local interval = SetInterval(function()
        if IsControlPressed(0, 73) -- X cancel
        or (not IsEntityPlayingAnim(cache.ped, 'mini@tennis', 'forehand_ts_md_far', 3)
        and not IsEntityPlayingAnim(cache.ped, 'amb@world_human_stand_fishing@idle_a', 'idle_c', 3)) then
            HideUI()
            if IsControlPressed(0, 73) then
                cancelWithX = true
            end
            p:resolve(false)
        end
    end, 100)

    local function wait(ms)
        Wait(ms)
        return p.state == 0
    end

    CreateThread(function()
        -- cast
        TaskPlayAnim(cache.ped, 'mini@tennis', 'forehand_ts_md_far', 3.0, 3.0, 1.0, 16, 0, false, false, false)
        if not wait(1500) then return end

        -- idle fishing
        TaskPlayAnim(cache.ped, 'amb@world_human_stand_fishing@idle_a', 'idle_c', 3.0, 3.0, -1, 11, 0, false, false, false)

        -- bite wait
        local wtMin = (zone.waitTime and zone.waitTime.min) or 2
        local wtMax = (zone.waitTime and zone.waitTime.max) or 6
        if wtMax < wtMin then wtMax = wtMin end

        local waitDiv = tonumber(bait and bait.waitDivisor) or 1.0
        if waitDiv <= 0 then waitDiv = 1.0 end

        local biteMs = math.random(wtMin, wtMax) / waitDiv * 1000
        if not wait(biteMs) then return end

        -- bite!
        ShowNotification(locale('felt_bite'), 'warn')
        HideUI()

        if interval then ClearInterval(interval) interval = nil end
        if not wait(math.random(2000, 4000)) then return end

        local chance
        if type(fishId) == 'table' then
            chance = fishId.chance
            if not chance then
                local key = fishId.id or fishId.name
                if key and Config.fish[key] then chance = Config.fish[key].chance end
            end
        elseif type(fishId) == 'string' then
            chance = Config.fish[fishId] and Config.fish[fishId].chance
        end
        chance = tonumber(chance) or 15

        -- unified skill check
        local success = DoFishingSkillCheckByChance(chance)
        if success then
            ShowNotification(locale('catch_success'), 'success')
            exports.xperience:AddXP(20)
        else
            ShowNotification(locale('catch_failed'), 'error')
        end

        p:resolve(success)
    end)

    local success = Citizen.Await(p)

    if interval then ClearInterval(interval) interval = nil end

    -- cleanup
    if cancelWithX then
        DeleteEntity(object)
    end

    ClearPedTasks(cache.ped)
    setCanRagdoll(true)

    return success
end)
