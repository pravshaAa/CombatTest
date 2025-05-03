-- main.lua
require "world"
require "divisions"

local tickInterval = 0.5
local timeSinceLastTick = 0
local selectedDivision = nil

function love.load()
    NET(130, 130, 20, 10, regionSize)
    
    -- Инициализация дивизий
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
            -- Добавляем соседние клетки
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
    return startPos -- Если не нашли свободную, оставляем на месте
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
                if not world[neighbor].division then
                    local newPath = {}
                    for _, v in ipairs(current.path) do table.insert(newPath, v) end
                    table.insert(newPath, neighbor)
                    table.insert(queue, {pos = neighbor, path = newPath})
                end
            end
        end
    end
    
    return {} -- путь не найден
end

function love.update(dt)
    timeSinceLastTick = timeSinceLastTick + dt
    
	for _, division in ipairs(divisions) do
		if world[division.position].owner ~= division.owner then
			world[division.position].owner = division.owner
		end
	end
	
    if timeSinceLastTick >= tickInterval then
        timeSinceLastTick = timeSinceLastTick - tickInterval
        
        -- Перемещаем все дивизии по их путям
        for _, division in ipairs(divisions) do
            if division.path and #division.path > 0 then
                local nextPos = division.path[1]
                
                -- Освобождаем текущую позицию
                world[division.position].division = nil
                
                -- Занимаем новую позицию
                division.position = nextPos
                world[nextPos].division = division
                
                -- Удаляем пройденную точку из пути
                table.remove(division.path, 1)
            end
        end
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then -- ЛКМ
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
                -- Устанавливаем цель и вычисляем путь
                if world[regionIndex].owner == selectedDivision.owner then
                    selectedDivision.targetPosition = regionIndex
                    selectedDivision.path = calculatePath(selectedDivision, selectedDivision.position, regionIndex)
                else
					--print("Нельзя переместить дивизию на территорию противника!")
					selectedDivision.targetPosition = regionIndex
                    selectedDivision.path = calculatePath(selectedDivision, selectedDivision.position, regionIndex)
					--world[regionIndex].owner = 
                end
                --selectedDivision = nil
            elseif world[regionIndex].division then
                -- Выбираем дивизию
                selectedDivision = world[regionIndex].division
            end
        end
    end
	
	if button == 2 then
		selectedDivision = nil
	end
end

function love.draw()
    -- Отрисовка регионов
    for i, region in ipairs(world) do
        -- Цвет владельца
        if region.owner == "red" then
            love.graphics.setColor(1, 0, 0)
        elseif region.owner == "blue" then
            love.graphics.setColor(0, 0, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5)
        end
        love.graphics.rectangle("fill", region.x, region.y, regionSize, regionSize)
        
        -- Маркер дивизии
        if world[i].division then
            love.graphics.setColor(1, 1, 0)
            love.graphics.rectangle("fill", region.x + 12, region.y + 12, 24, 24)
        end
    end
    
    -- Отрисовка пути выбранной дивизии (отдельным проходом)
    if selectedDivision and selectedDivision.path and #selectedDivision.path > 0 then
        for step, pathPos in ipairs(selectedDivision.path) do
            local region = world[pathPos]
            if region then
                -- Градиент от желтого к белому
                local progress = step / #selectedDivision.path
                love.graphics.setColor(1, 1, progress, 0.7)
                love.graphics.rectangle("fill", region.x + 8, region.y + 8, regionSize - 16, regionSize - 16)
                
                -- Номер шага
                love.graphics.setColor(0, 0, 0)
                love.graphics.print(step, region.x + regionSize/2 - 4, region.y + regionSize/2 - 6)
            end
        end
    end
    
    -- Выделение выбранной дивизии
    if selectedDivision and world[selectedDivision.position].division == selectedDivision then
        local region = world[selectedDivision.position]
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", region.x - 2, region.y - 2, regionSize + 4, regionSize + 4)
    end
    
    -- Подсказка управления
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("ЛКМ - выбрать/переместить дивизию", font, 10, 10)
	love.graphics.print("ПКМ - отменить выбор", font, 10, 25)
end