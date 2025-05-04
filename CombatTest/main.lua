require "world"
require "divisions"
require "Battalions"

local tickInterval = 0.5
local timeSinceLastTick = 0
local selectedDivision = nil
local combatLog = {}
local activeCombats = {}


function love.load()
    NET(130, 130, 20, 10, regionSize)
    
    -- Initialize divisions
    for _, division in ipairs(divisions) do
        if world[division.position] then
            if world[division.position].division then
                local newPos = findNearestEmptyPosition(division.position, division.owner)
                division.position = newPos
            end
            world[division.position].division = division
            world[division.position].owner = division.owner
            division.path = {}
            division.targetPosition = division.position
            
            -- Initialize combat stats
            division.organization = 100
            division.combatWidth = 5
            division.aggressiveness = math.random(70, 90) -- Высокая агрессивность
        end
    end
    
    font = love.graphics.newFont("fonts/AA_Stetica_Regular.otf", 15)
end

function findNearestEmptyPosition(startPos, owner)
    local checked = {}
    local queue = {startPos}
    
    while #queue > 0 do
        local current = table.remove(queue, 1)
        
        if not world[current].division and world[current].owner == owner then
            return current
        end
        
        if not checked[current] then
            checked[current] = true
            local neighbors = {
                current - 1, current + 1, current - 20, current + 20
            }
            
            for _, neighbor in ipairs(neighbors) do
                if neighbor >= 1 and neighbor <= #world and world[neighbor].owner == owner then
                    table.insert(queue, neighbor)
                end
            end
        end
    end
    return startPos
end

function getNeighbors(position)
    local neighbors = {}
    local gridWidth = 20
    
    if position % gridWidth ~= 1 then table.insert(neighbors, position - 1) end
    if position % gridWidth ~= 0 then table.insert(neighbors, position + 1) end
    if position > gridWidth then table.insert(neighbors, position - gridWidth) end
    if position <= #world - gridWidth then table.insert(neighbors, position + gridWidth) end
    
    return neighbors
end

function calculatePath(division, startPos, endPos)
    local queue = {{pos = startPos, path = {}}}
    local visited = {}
    
    while #queue > 0 do
        local current = table.remove(queue, 1)
        
        if current.pos == endPos then
            return current.path
        end
        
        if not visited[current.pos] then
            visited[current.pos] = true
            
            for _, neighbor in ipairs(getNeighbors(current.pos)) do
                if not world[neighbor].division or (neighbor == endPos and world[neighbor].division.owner ~= division.owner) then
                    local newPath = {}
                    for _, v in ipairs(current.path) do table.insert(newPath, v) end
                    table.insert(newPath, neighbor)
                    table.insert(queue, {pos = neighbor, path = newPath})
                end
            end
        end
    end
    
    return {}
end

function startLocalBattle(attacker, defender)
    local battle = {
        attacker = attacker,
        defender = defender,
        battlefield = {},
        turn = 1,
        attackerDeployment = {},
        defenderDeployment = {},
        attackerReserves = {infantry = attacker.infantry, arty = attacker.arty},
        defenderReserves = {infantry = defender.infantry, arty = defender.arty},
        attackerControl = 25,
        defenderControl = 25,
        combatLog = {}
    }
    
    -- Initialize battlefield with colored sides
    for y = 1, 10 do
        battle.battlefield[y] = {}
        for x = 1, 10 do
            battle.battlefield[y][x] = {
                controlledBy = y <= 5 and "attacker" or "defender",
                battalion = nil
            }
        end
    end
    
    -- Deploy battalions
    deployBattalions(battle, "attacker")
    deployBattalions(battle, "defender")
    
    table.insert(activeCombats, battle)
    return battle
end

function deployBattalions(battle, side)
    local reserves = battle[side.."Reserves"]
    local startY = (side == "attacker") and 1 or 6
    local backY = (side == "attacker") and 5 or 6
    
    -- Deploy infantry in front lines
    for y = startY, startY + 4 do
        for x = 1, 10 do
            if reserves.infantry > 0 then
                battle.battlefield[y][x].battalion = {
                    type = "infantry",
                    strength = 100,
                    organization = 100,
                    order = "advance", -- Все начинают с наступления
                    side = side,
                    hasMoved = false
                }
                reserves.infantry = reserves.infantry - 1
            end
        end
    end
    
    -- Deploy artillery in back lines
    for x = 1, 10 do
        if reserves.arty > 0 then
            battle.battlefield[backY][x].battalion = {
                type = "arty",
                strength = 100,
                organization = 100,
                order = "support",
                side = side,
                hasMoved = false
            }
            reserves.arty = reserves.arty - 1
        end
    end
end

function processLocalBattle(battle)
    -- Update control
    battle.attackerControl = 0
    battle.defenderControl = 0
    for y = 1, 10 do
        for x = 1, 10 do
            if battle.battlefield[y][x].controlledBy == "attacker" then
                battle.attackerControl = battle.attackerControl + 1
            else
                battle.defenderControl = battle.defenderControl + 1
            end
        end
    end
    
    -- Check victory conditions
    if battle.turn >= 50 then return "timeout" end
    
    -- Check if attacker reached defender's back line
    for x = 1, 10 do
        if battle.battlefield[10][x].controlledBy == "attacker" then
            return "attacker_win"
        end
    end
    
    -- Check if defender reached attacker's back line
    for x = 1, 10 do
        if battle.battlefield[1][x].controlledBy == "defender" then
            return "defender_win"
        end
    end
    
    -- Reset moved flags
    for y = 1, 10 do
        for x = 1, 10 do
            if battle.battlefield[y][x].battalion then
                battle.battlefield[y][x].battalion.hasMoved = false
            end
        end
    end
    
    -- AI gives orders
    if battle.attacker.owner == "blue" then
        giveAIOrders(battle, "attacker")
    end
    if battle.defender.owner == "blue" then
        giveAIOrders(battle, "defender")
    end
    
    -- Process combat with aggressive pursuit
    processCombat(battle)
    
    battle.turn = battle.turn + 1
    return "ongoing"
end

function giveAIOrders(battle, side)
    local enemySide = (side == "attacker") and "defender" or "attacker"
    
    for y = 1, 10 do
        for x = 1, 10 do
            local cell = battle.battlefield[y][x]
            if cell.battalion and cell.battalion.side == side and not cell.battalion.hasMoved then
                -- Always be aggressive
                if cell.battalion.type == "infantry" then
                    cell.battalion.order = "advance"
                else
                    -- Artillery supports or repositions
                    cell.battalion.order = math.random() < 0.7 and "support" or "reposition"
                end
            end
        end
    end
end

function processCombat(battle)
    -- Process movement and combat
    for y = 10, 1, -1 do
        for x = 1, 10 do
            local cell = battle.battlefield[y][x]
            if cell.battalion and not cell.battalion.hasMoved then
                if cell.battalion.order == "advance" then
                    local dir = cell.battalion.side == "attacker" and 1 or -1
                    local targetY = y + dir
                    
                    if targetY >= 1 and targetY <= 10 then
                        local targetCell = battle.battlefield[targetY][x]
                        
                        if targetCell.battalion then
                            -- Combat
                            if targetCell.battalion.side ~= cell.battalion.side then
                                local attPower = batallions[cell.battalion.type].attack * cell.battalion.strength/100
                                local defPower = batallions[targetCell.battalion.type].defence * targetCell.battalion.strength/100
                                
                                if math.random() < attPower/(attPower+defPower) then
                                    -- Attacker wins
                                    targetCell.battalion.strength = math.max(0, targetCell.battalion.strength - 20)
                                    targetCell.battalion.organization = math.max(0, targetCell.battalion.organization - 25)
                                    
                                    if targetCell.battalion.strength <= 30 or targetCell.battalion.organization <= 30 then
                                        retreatBattalion(battle, targetY, x)
                                        -- Pursue immediately!
                                        targetCell.battalion = cell.battalion
                                        cell.battalion = nil
                                        targetCell.battalion.hasMoved = true
                                        targetCell.controlledBy = targetCell.battalion.side
                                    end
                                else
                                    -- Defender wins
                                    cell.battalion.strength = math.max(0, cell.battalion.strength - 20)
                                    cell.battalion.organization = math.max(0, cell.battalion.organization - 25)
                                    
                                    if cell.battalion.strength <= 30 or cell.battalion.organization <= 30 then
                                        retreatBattalion(battle, y, x)
                                    end
                                end
                            end
                        else
                            -- Move forward
                            targetCell.battalion = cell.battalion
                            cell.battalion = nil
                            targetCell.battalion.hasMoved = true
                            targetCell.controlledBy = targetCell.battalion.side
                        end
                    end
                elseif cell.battalion.order == "reposition" and cell.battalion.type == "arty" then
                    -- Find better position
                    local newX = math.max(1, math.min(10, x + math.random(-1, 1)))
                    if not battle.battlefield[y][newX].battalion then
                        battle.battlefield[y][newX].battalion = cell.battalion
                        cell.battalion = nil
                    end
                end
            end
        end
    end
    
    -- Process artillery support
    for y = 1, 10 do
        for x = 1, 10 do
            local cell = battle.battlefield[y][x]
            if cell.battalion and cell.battalion.type == "arty" and cell.battalion.order == "support" then
                local dir = cell.battalion.side == "attacker" and 1 or -1
                local targetY = y + dir
                
                if targetY >= 1 and targetY <= 10 then
                    local targetCell = battle.battlefield[targetY][x]
                    if targetCell.battalion and targetCell.battalion.side ~= cell.battalion.side then
                        targetCell.battalion.strength = math.max(0, targetCell.battalion.strength - 10)
                        targetCell.battalion.organization = math.max(0, targetCell.battalion.organization - 15)
                        
                        if targetCell.battalion.strength <= 30 or targetCell.battalion.organization <= 30 then
                            retreatBattalion(battle, targetY, x)
                        end
                    end
                end
            end
        end
    end
end

function retreatBattalion(battle, y, x)
    local cell = battle.battlefield[y][x]
    if not cell.battalion then return end
    
    local side = cell.battalion.side
    local dir = side == "attacker" and -1 or 1
    local retreatY = y + dir
    
    if retreatY >= 1 and retreatY <= 10 then
        local retreatCell = battle.battlefield[retreatY][x]
        if not retreatCell.battalion then
            retreatCell.battalion = cell.battalion
            cell.battalion = nil
            retreatCell.battalion.order = "retreat"
            retreatCell.battalion.hasMoved = true
        else
            -- Can't retreat, return to reserves
            battle[side.."Reserves"][retreatCell.battalion.type] = (battle[side.."Reserves"][retreatCell.battalion.type] or 0) + 1
            cell.battalion = nil
        end
    else
        -- Can't retreat further, return to reserves
        battle[side.."Reserves"][cell.battalion.type] = (battle[side.."Reserves"][cell.battalion.type] or 0) + 1
        cell.battalion = nil
    end
end

function endLocalBattle(battle, result)
    -- Calculate remaining forces
    local attackerRemaining = {infantry = battle.attackerReserves.infantry, arty = battle.attackerReserves.arty}
    local defenderRemaining = {infantry = battle.defenderReserves.infantry, arty = battle.defenderReserves.arty}
    
    for y = 1, 10 do
        for x = 1, 10 do
            local cell = battle.battlefield[y][x]
            if cell.battalion then
                if cell.battalion.side == "attacker" then
                    attackerRemaining[cell.battalion.type] = attackerRemaining[cell.battalion.type] + 1
                else
                    defenderRemaining[cell.battalion.type] = defenderRemaining[cell.battalion.type] + 1
                end
            end
        end
    end
    
    -- Update divisions
    battle.attacker.infantry = attackerRemaining.infantry
    battle.attacker.arty = attackerRemaining.arty
    battle.defender.infantry = defenderRemaining.infantry
    battle.defender.arty = defenderRemaining.arty
    
    -- Handle battle outcome
    if result == "attacker_win" then
        -- Check if defender is surrounded
        local isSurrounded = true
        local defenderPos = battle.defender.position
        local neighbors = getNeighbors(defenderPos)
        
        for _, neighbor in ipairs(neighbors) do
            if world[neighbor].owner == battle.defender.owner and not world[neighbor].division then
                isSurrounded = false
                break
            end
        end
        
        if isSurrounded then
            -- Defender is destroyed
            world[battle.defender.position].division = nil
            for i, div in ipairs(divisions) do
                if div == battle.defender then
                    table.remove(divisions, i)
                    break
                end
            end
        else
            -- Normal retreat
            world[battle.defender.position].division = nil
            battle.defender.position = findNearestEmptyPosition(battle.defender.position, battle.defender.owner)
            if battle.defender.position then
                world[battle.defender.position].division = battle.defender
                world[battle.defender.position].owner = battle.defender.owner
            else
                -- No retreat positions available - destroyed
                for i, div in ipairs(divisions) do
                    if div == battle.defender then
                        table.remove(divisions, i)
                        break
                    end
                end
            end
        end
        
        -- Move attacker to conquered position
        world[battle.attacker.position].division = nil
        battle.attacker.position = battle.defender.targetPosition or battle.defender.position
        world[battle.attacker.position].division = battle.attacker
        world[battle.attacker.position].owner = battle.attacker.owner
        
    elseif result == "defender_win" then
        -- Check if attacker is surrounded
        local isSurrounded = true
        local attackerPos = battle.attacker.position
        local neighbors = getNeighbors(attackerPos)
        
        for _, neighbor in ipairs(neighbors) do
            if world[neighbor].owner == battle.attacker.owner and not world[neighbor].division then
                isSurrounded = false
                break
            end
        end
        
        if isSurrounded then
            -- Attacker is destroyed
            world[battle.attacker.position].division = nil
            for i, div in ipairs(divisions) do
                if div == battle.attacker then
                    table.remove(divisions, i)
                    break
                end
            end
        else
            -- Normal retreat
            battle.attacker.path = {}
            battle.attacker.targetPosition = nil
        end
    end
    
    -- Log result
    table.insert(combatLog, {
        attacker = battle.attacker,
        defender = battle.defender,
        result = result,
        turns = battle.turn,
        destroyed = (result == "attacker_win" and isSurrounded) or (result == "defender_win" and isSurrounded)
    })
    
    -- Remove battle
    for i, combat in ipairs(activeCombats) do
        if combat == battle then
            table.remove(activeCombats, i)
            break
        end
    end
end

function love.update(dt)
    timeSinceLastTick = timeSinceLastTick + dt
    
    if timeSinceLastTick >= tickInterval then
        timeSinceLastTick = 0
        
        -- Process divisions movement
        for _, division in ipairs(divisions) do
            if division.path and #division.path > 0 then
                local nextPos = division.path[1]
                
                if world[nextPos].division and world[nextPos].division.owner ~= division.owner then
                    -- Start local battle
                    local battle = startLocalBattle(division, world[nextPos].division)
                    division.path = {}
                elseif not world[nextPos].division then
                    world[division.position].division = nil
                    division.position = nextPos
                    world[nextPos].division = division
                    world[nextPos].owner = division.owner
                    table.remove(division.path, 1)
                else
                    division.path = {}
                end
            end
        end
        
        -- Process active battles
        for i = #activeCombats, 1, -1 do
            local battle = activeCombats[i]
            local result = processLocalBattle(battle)
            if result ~= "ongoing" then
                endLocalBattle(battle, result)
            end
        end
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then
        local regionIndex = nil
        for i, region in ipairs(world) do
            if x >= region.x and x <= region.x + regionSize and
               y >= region.y and y <= region.y + regionSize then
                regionIndex = i
                break
            end
        end
        
        if regionIndex then
            if selectedDivision then
                if world[regionIndex].division and world[regionIndex].division.owner == selectedDivision.owner then
                    selectedDivision = world[regionIndex].division
                else
                    selectedDivision.targetPosition = regionIndex
                    selectedDivision.path = calculatePath(selectedDivision, selectedDivision.position, regionIndex)
                end
            elseif world[regionIndex].division then
                selectedDivision = world[regionIndex].division
            end
        end
    elseif button == 2 then
        selectedDivision = nil
    end
end

function love.draw()
    -- Draw global map
    for i, region in ipairs(world) do
        if region.owner == "red" then
            love.graphics.setColor(1, 0, 0)
        elseif region.owner == "blue" then
            love.graphics.setColor(0, 0, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5)
        end
        love.graphics.rectangle("fill", region.x, region.y, regionSize, regionSize)
        
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("line", region.x, region.y, regionSize, regionSize)
        
        if world[i].division then
            love.graphics.setColor(1, 1, 0)
            love.graphics.rectangle("fill", region.x + 12, region.y + 12, 24, 24)
            
            love.graphics.setColor(0, 0, 0)
            local div = world[i].division
            love.graphics.print(div.infantry.."/"..div.arty, region.x + 15, region.y + 15)
        end
    end
    
    -- Draw path
    if selectedDivision and selectedDivision.path and #selectedDivision.path > 0 then
        for step, pathPos in ipairs(selectedDivision.path) do
            local region = world[pathPos]
            if region then
                local progress = step / #selectedDivision.path
                love.graphics.setColor(1, 1, progress, 0.7)
                love.graphics.rectangle("fill", region.x + 8, region.y + 8, regionSize - 16, regionSize - 16)
                
                love.graphics.setColor(0, 0, 0)
                love.graphics.print(step, region.x + regionSize/2 - 4, region.y + regionSize/2 - 6)
            end
        end
    end
    
    -- Draw selected division
    if selectedDivision and world[selectedDivision.position].division == selectedDivision then
        local region = world[selectedDivision.position]
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", region.x - 2, region.y - 2, regionSize + 4, regionSize + 4)
    end
    
    -- Draw combat log
    love.graphics.setColor(1, 1, 1)
    for i, log in ipairs(combatLog) do
        if i <= 5 then
            local text = string.format("Бой #%d: %s vs %s - %s (%d ходов)",
                i, log.attacker.owner, log.defender.owner, 
                log.result == "attacker_win" and "победа атак." or 
                log.result == "defender_win" and "победа защ." or "ничья",
                log.turns)
            love.graphics.print(text, font, 1200, 10 + (i-1)*20)
        end
    end
    
    -- Draw active battles
    for i, battle in ipairs(activeCombats) do
        love.graphics.print(string.format("Бой %d: %s vs %s (ход %d)", 
            i, battle.attacker.owner, battle.defender.owner, battle.turn), 
            font, 1200, 150 + (i-1)*20)
    end
    
    -- Draw local battle if any
    if #activeCombats > 0 then
        drawLocalBattle(activeCombats[1])
    end
	
	    love.graphics.setColor(1, 1, 1)
    for i, log in ipairs(combatLog) do
        if i <= 5 then
            local resultText
            if log.destroyed then
                resultText = log.result == "attacker_win" and "уничтожен защ." or "уничтожен атак."
            else
                resultText = log.result == "attacker_win" and "победа атак." or 
                           log.result == "defender_win" and "победа защ." or "ничья"
            end
            local text = string.format("Бой #%d: %s vs %s - %s (%d ходов)",
                i, log.attacker.owner, log.defender.owner, resultText, log.turns)
            love.graphics.print(text, font, 1200, 10 + (i-1)*20)
        end
    end

    
    -- Draw instructions
    love.graphics.print("ЛКМ - выбрать/атаковать", font, 10, 10)
    love.graphics.print("ПКМ - отменить выбор", font, 10, 25)
end

function drawLocalBattle(battle)
    local startX = 1150
    local cellSize = 30
    
    -- Draw battlefield
    for y = 1, 10 do
        for x = 1, 10 do
            local cellX = startX + (x-1) * cellSize
            local cellY = 300 + (y-1) * cellSize
            
            -- Draw cell background
            if battle.battlefield[y][x].controlledBy == "attacker" then
                love.graphics.setColor(1, 0, 0, 0.3)
            else
                love.graphics.setColor(0, 0, 1, 0.3)
            end
            love.graphics.rectangle("fill", cellX, cellY, cellSize, cellSize)
            
            -- Draw border
            love.graphics.setColor(0.2, 0.2, 0.2)
            love.graphics.rectangle("line", cellX, cellY, cellSize, cellSize)
            
            -- Draw battalion
            local battalion = battle.battlefield[y][x].battalion
            if battalion then
                if battalion.side == "attacker" then
                    love.graphics.setColor(1, 0.5, 0.5)
                else
                    love.graphics.setColor(0.5, 0.5, 1)
                end
                
                if battalion.type == "infantry" then
                    love.graphics.rectangle("fill", cellX + 5, cellY + 5, cellSize - 10, cellSize - 10)
                else
                    love.graphics.circle("fill", cellX + cellSize/2, cellY + cellSize/2, cellSize/3)
                end
                
                -- Draw strength
                love.graphics.setColor(0, 1, 0)
                local strWidth = (cellSize - 4) * battalion.strength / 100
                love.graphics.rectangle("fill", cellX + 2, cellY + cellSize - 6, strWidth, 2)
                
                -- Draw organization
                love.graphics.setColor(1, 1, 0)
                local orgWidth = (cellSize - 4) * battalion.organization / 100
                love.graphics.rectangle("fill", cellX + 2, cellY + cellSize - 3, orgWidth, 2)
            end
        end
    end
    
    -- Draw battle info
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(string.format("Ход: %d", battle.turn),font, startX, 270)
    love.graphics.print(string.format("Контроль: %d / %d", battle.attackerControl, battle.defenderControl),font, startX + 100, 270)
    
    -- Draw reserves
    love.graphics.print("Резервы атак.: "..battle.attackerReserves.infantry.."п "..battle.attackerReserves.arty.."а",font, startX, 650)
    love.graphics.print("Резервы защ.: "..battle.defenderReserves.infantry.."п "..battle.defenderReserves.arty.."а", font,startX, 670)
end
