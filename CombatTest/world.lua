world = {}
regionSize = 48

function NET(xStart, yStart, xSize, ySize, sizeCell)
    xStart = xStart - sizeCell
    for i = 1, xSize*ySize do
        if i == 1 then
            localX = xStart + sizeCell
            localY = yStart
        else
            localX = localX + sizeCell
        end
        if localX <= (((xSize+4)/2)*sizeCell) then
            table.insert(world, i, {x = localX, y = localY, division = nil, owner = "red"})
        else
            table.insert(world, i, {x = localX, y = localY, division = nil, owner = "blue"})
        end
        if localX == sizeCell*xSize + xStart then
            localY = localY + sizeCell
            localX = xStart 
        end
    end
end