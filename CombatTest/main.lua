require "world"
require "divisions"

local tickInterval = 0.5
local timeSinceLastTick = 0
local selectedDivision = nil
local combatLog = {}
local combat = {}


function love.load()
    NET(130, 130, 20, 10, regionSize)
    
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
        end
    end
	
    font = love.graphics.newFont("fonts/Thicker-Regular-TRIAL.ttf", 15)
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
                current - 1,  -- left
                current + 1,  -- right
                current - 20, -- top
                current + 20  -- bottom
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
    
    if position % gridWidth ~= 1 then -- left
        table.insert(neighbors, position - 1)
    end
    if position % gridWidth ~= 0 then -- right
        table.insert(neighbors, position + 1)
    end
    if position > gridWidth then -- top
        table.insert(neighbors, position - gridWidth)
    end
    if position <= #world - gridWidth then -- bottom
        table.insert(neighbors, position + gridWidth)
    end
    
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

function handleCombat(attacker, defender)
    local attackerPower = attacker.infantry * 1.5 + attacker.arty * 2.0 --вот тут короче считается сила. Арта лучше в атаке, пехота в обороне.
    local defenderPower = defender.infantry * 2.0 + defender.arty * 1.5 -- Мне тяжело дальше делать самому
	
    local combatResult = {
        attacker = attacker,
        defender = defender,
        attackerPower = math.floor(attackerPower),
        defenderPower = math.floor(defenderPower)
    }
    
    if math.random() < attackerPower / (attackerPower + defenderPower) then
        combatResult.winner = "attacker"
        combatResult.loser = "defender"
        
        local dx = defender.position % 20 - attacker.position % 20
        local dy = math.floor(defender.position / 20) - math.floor(attacker.position / 20)
        
        local retreatPos
        if math.abs(dx) > math.abs(dy) then
            retreatPos = defender.position + (dx > 0 and 1 or -1)
        else
            retreatPos = defender.position + (dy > 0 and 20 or -20)
        end
        
        if world[retreatPos] and world[retreatPos].owner == defender.owner and not world[retreatPos].division then
            world[defender.position].division = nil
            defender.position = retreatPos
            world[retreatPos].division = defender
            defender.path = {}
            combatResult.retreated = true
        else
            world[defender.position].division = nil
            for i, div in ipairs(divisions) do
                if div == defender then
                    table.remove(divisions, i)
                    break
                end
            end
            combatResult.destroyed = true
        end
        
        world[attacker.position].owner = attacker.owner
    else
        combatResult.winner = "defender"
        combatResult.loser = "attacker"
        attacker.path = {}
    end
    
    table.insert(combatLog, combatResult)
    printCombatResult(combatResult)
end

function printCombatResult(result)
    print(string.format("Бой: %s (%d) vs %s (%d) - победа %s",
        result.attacker.owner, result.attackerPower,
        result.defender.owner, result.defenderPower, 
        result.winner == "attacker" and "атакующий" or "защитник"))
end

function love.update(dt)
    timeSinceLastTick = timeSinceLastTick + dt
    
    if timeSinceLastTick >= tickInterval then
        timeSinceLastTick = 0
        
        for _, division in ipairs(divisions) do
            if division.path and #division.path > 0 then
                local nextPos = division.path[1]
                
                if world[nextPos].division and world[nextPos].division.owner ~= division.owner then
                    handleCombat(division, world[nextPos].division)
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
    
    if selectedDivision and world[selectedDivision.position].division == selectedDivision then
        local region = world[selectedDivision.position]
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", region.x - 2, region.y - 2, regionSize + 4, regionSize + 4)
    end
    
    love.graphics.setColor(1, 1, 1)
    for i, log in ipairs(combatLog) do
        if i <= 5 then
            local text = string.format("Бой #%d: %s (%d) vs %s (%d) - %s",
                i, log.attacker.owner, log.attackerPower, 
                log.defender.owner, log.defenderPower, 
                log.winner == "attacker" and "атака" or "защита")
            love.graphics.print(text, font, 1200, 10 + (i-1)*20)
        end
    end
    
    love.graphics.print("ЛКМ - выбрать/атаковать", font, 10, 10)
    love.graphics.print("ПКМ - отменить выбор", font, 10, 25)
end
