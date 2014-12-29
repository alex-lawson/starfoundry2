--PIPES
pipes = {}

--Materials
pipes.materials = {
  "sewerpipe"
}

--Hooks
pipes.hooks = {
  put = "onPipeReceive",  --Should take whatever argument get returns
  get = "onPipeRequest", --Should return whatever argument you want to plug into the put hook, can take whatever argument you want like a filter or something
  peekPut = "beforePipeReceive", --Should return true if object will put the item
  peekGet = "beforePipeRequest" --Should return true if object will get the item
}

pipes.nodesConfigParameter = "pipeNodes"

--Directions
pipes.directions = {{1, 0}, {0, 1}, {-1, 0}, {0, -1}}
pipes.otherDirections = {{-1, 0}, {0, -1}, {1, 0}, {0, 1}}
pipes.reverseDir = {
  ["1.0"] = {-1, 0},
  ["0.1"] = {0, -1},
  ["-1.0"] = {1, 0},
  ["0.-1"] = {0, 1}
}

--- Initialize, always run this in init (when init args == false)
-- @returns nil
function pipes.init()
  pipes.loadRegions = true

  pipes.walkInterval = 1
  pipes.tilesPerInterval = 1000
  
  pipes.nodes = {} 
  pipes.nodeEntities = {}
  pipes.virtualNodes = {}
  pipes.walkers = {}
  
  pipes.nodes = entity.configParameter(pipes.nodesConfigParameter)
  pipes.nodeEntities = {}
  pipes.virtualNodes = {}
  pipes.nodeLengths = {}

  for i,pipeNode in ipairs(pipes.nodes) do
    pipes.nodeEntities[i] = {}
    pipes.virtualNodes[i] = {}
    pipes.nodeLengths[i] = pipes.tilesPerInterval / pipes.walkInterval
  end

  pipes.rejectNode = {}
end

--- Checks if two pipes connect up, direction-wise
-- @param firstDirection vec2 - vector2 of direction to match
-- @param secondDirections array of vec2s - List of directions to match against
-- @returns true if the secondDirections can connect to the firstDirection
function pipes.pipesConnect(firstDirection, secondDirections)
  for _,secondDirection in ipairs(secondDirections) do
    if firstDirection[1] == -secondDirection[1] and firstDirection[2] == -secondDirection[2] then
      return true
    end
  end
  return false
end

--- Matches pipe against a pipe type and layer
-- @param position vec2 - world position to check
-- @param layer - layer to check ("foreground" or "background")
-- @param pipeType - type of pipe to check for, if nil it will return whatever it finds
-- @returns Hook return if successful, false if unsuccessful
function pipes.pipeMatches(position, layer, pipeType, nodeId)
  local checkedTile = world.material(position, layer)
  if not checkedTile then
    if checkedTile == nil and pipes.loadRegions then
      world.loadRegion({position[1], position[2], position[1] + 1, position[2] + 1})
      return nil
    end
    return false
  elseif (pipeType == checkedTile) or (pipeType == nil and table.contains(pipes.materials, checkedTile)) then
    return checkedTile
  end
  return false
end

--- Gets the directions + layer for a connecting pipe, prioritises the layer specified in layerMode
-- @param position vec2 - world position to check
-- @param layerMode - layer to prioritise
-- @param direction (optional) - direction to compare to, if specified it will return false if the pipe does not connect
-- @returns Hook return if successful, false if unsuccessful
function pipes.getPipeTileData(position, layerMode, typeMode, nodeId)
  local checkBothLayers = false
  if layerMode == nil then checkBothLayers = true end
  layerMode = layerMode or "foreground"

  local otherLayer = {foreground = "background", background = "foreground"}
  
  local firstCheck = pipes.pipeMatches(position, layerMode, typeMode, nodeId)
  local secondCheck = nil
  if checkBothLayers then secondCheck = pipes.pipeMatches(position, otherLayer[layerMode], typeMode, nodeId) end

  if firstCheck == nil and secondCheck == nil then return nil end

  --Return relevant values
  if firstCheck then
    if typeMode == nil then typeMode = firstCheck end
    return typeMode, layerMode
  elseif secondCheck then
    if typeMode == nil then typeMode = secondCheck end
    return secondCheck, otherLayer[layerMode]
  end
  return false, false
end

--- Should be run in main
-- @param dt number - delta time
-- @returns nil
function pipes.update(dt)
  local position = entity.position()

  --Get connected entities
  for i,pipeNode in ipairs(pipes.nodes) do
    if not pipes.walkers[i] then 
      pipes.walkers[i] = coroutine.wrap(pipes.walkPipes)
    end

    --Tick coroutine
    local walkSpeed = (pipes.nodeLengths[i] / pipes.walkInterval) * dt
    local pathLength, nodeEntities, virtualNodes = pipes.walkers[i](walkSpeed, pipeNode.offset, pipeNode.dir, i)
    if nodeEntities then
      pipes.nodeEntities[i] = nodeEntities
      pipes.virtualNodes[i] = virtualNodes
      pipes.nodeLengths[i] = pathLength / pipes.walkInterval
      pipes.walkers[i] = nil
    elseif pathLength and pathLength > pipes.nodeLengths[i]then
      pipes.nodeLengths[i] = pathLength * 2
    end
  end
end

--- Walks through placed pipe tiles to find connected entities
-- @param startOffset vec2 - Position *relative to the object* to start looking, should be set to a node's position
-- @param startDir vec2 - Direction to start looking in, should be set to a node's direction
-- @returns List of connected entities with ID, remote Node ID, and path info, sorted by nearest-first
function pipes.walkPipes(tilesPerUpdate, startOffset, startDir, nodeId)
  local position = entity.position()

  local validEntities = {}
  local visitedTiles = {}
  local tilesToVisit = {}
  local totalTiles = 0
  local typeMode = nil

  tilesToVisit[1] =  {pos = {startOffset[1] + startDir[1], startOffset[2] + startDir[2]}, layer = nil, dir = startDir, pathLength = 0, neighbors = 1 } 

  local checkedTiles = 0
  while #tilesToVisit > 0 do
    local tile = tilesToVisit[1]
    local tilePos = entity.toAbsolutePosition(tile.pos)

    local pipe, layer = pipes.getPipeTileData(tilePos, tile.layer, typeMode, nodeId)
    checkedTiles = checkedTiles + 1
    totalTiles = totalTiles + 1

    --Maybe wait until the tile is loaded
    while pipe == nil do
      tilesPerUpdate = coroutine.yield(totalTiles)
      pipe, layer = pipes.getPipeTileData(tilePos, tile.layer, typeMode, nodeId)
    end

    --If a tile, add connected spaces to the visit list
    if pipe then
      tile.layer = layer
      typeMode = pipe

      if pipes.loadRegions then
        world.loadRegion({tilePos[1], tilePos[2], tilePos[1] + 1, tilePos[2] + 1})
      end

      world.debugPoint({tilePos[1] + 0.5, tilePos[2] + 0.5}, "green")

      visitedTiles[tile.pos[1].."."..tile.pos[2]] = tile --Add to global visited

      --Add surrounding tiles to the list
      for index,dir in ipairs(pipes.directions) do
        local newPos = {tile.pos[1] + dir[1], tile.pos[2] + dir[2]}
        local visited = visitedTiles[newPos[1].."."..newPos[2]]
        if not visited then
          local newTile = {pos = newPos, prev = tile.pos[1].."."..tile.pos[2], layer = tile.layer, neighbors = 0, dir = dir, pathLength = tile.pathLength + 1}
          table.insert(tilesToVisit, newTile)
        else
          visited.neighbors = visited.neighbors + 1
          tile.neighbors = tile.neighbors + 1
        end
      end
    end

    table.remove(tilesToVisit, 1)

    if checkedTiles >= tilesPerUpdate then
      tilesPerUpdate = coroutine.yield(totalTiles)
      checkedTiles = 0
    end
  end

  local pipeOpenings = pipes.getVirtualNodes(visitedTiles)

  --Check for objects where there are pipe openings
  for openingIndex = #pipeOpenings, 1, -1 do
    local opening = pipeOpenings[openingIndex]
    local connectedObjects = world.entityQuery(opening.pos, vec2.add(opening.pos, 1), {
      includedTypes = {"object"},
      boundMode = "MetaBoundBox"
    })
    for key,objectId in ipairs(connectedObjects) do
      local connectedNode = world.callScriptedEntity(objectId, "pipes.entityConnectsAt", entity.toAbsolutePosition(opening.tilePosition), opening.dir)
      if connectedNode then
        table.insert(validEntities, {id = objectId, nodeId = connectedNode, path = table.copy(tile.path)})
        if pipeOpenings[openingIndex] then
      world.debugPoint(opening.pos, "red")
          table.remove(pipeOpenings, openingIndex)
        end
      end
    end
  end

  table.sort(validEntities, function(a,b) return a.pathLength < b.pathLength end)
  table.sort(pipeOpenings, function(a,b) return a.pathLength < b.pathLength end)

  return totalTiles, validEntities, pipeOpenings
end


function pipes.getVirtualNodes(tiles)
  local vNodes = {}
  for _,tile in pairs(tiles) do
    if tile.neighbors == 1 then
      local nodePos = entity.toAbsolutePosition(tile.pos)
      nodePos[1] = nodePos[1] + tile.dir[1]
      nodePos[2] = nodePos[2] + tile.dir[2]
      table.insert(vNodes, {pos = nodePos, pathLength = tile.pathLength, tilePosition = table.copy(tile.pos), dir = table.copy(tile.dir)})
    end
  end
  table.sort(vNodes, function(a,b) return a.pathLength < b.pathLength end)
  return vNodes
end


--USAGE

function pipes.isNodeConnected(nodeId)
  if pipes.nodeEntities == nil or pipes.nodeEntities[nodeId] == nil then return false end
  if #pipes.nodeEntities[nodeId] > 0 then
    return pipes.nodeEntities[nodeId]
  else
    return false
  end
end

--- Push, calls the put hook on the closest connected object that returns true
-- @param nodeId number - ID of the node to push through
-- @param args - The arguments to send to the put hook
-- @returns Hook return if successful, false if unsuccessful
function pipes.push(nodeId, args)
  if #pipes.nodeEntities[nodeId] > 0 and not pipes.rejectNode[nodeId] then
    for i,entity in ipairs(pipes.nodeEntities[nodeId]) do
      pipes.rejectNode[nodeId] = true
      local entityReturn = world.callScriptedEntity(entity.id, pipes.hooks.put, args, entity.nodeId)
      pipes.rejectNode[nodeId] = false
      if entityReturn then return entityReturn end
    end
  end
  return false
end

--- Pull, calls the get hook on the closest connected object that returns true
-- @param nodeId number - ID of the node to pull through
-- @param args - The arguments to send to the hook
-- @returns Hook return if successful, false if unsuccessful
function pipes.pull(nodeId, args)
  if #pipes.nodeEntities[nodeId] > 0 and not pipes.rejectNode[nodeId] then
    for i,entity in ipairs(pipes.nodeEntities[nodeId]) do
      pipes.rejectNode[nodeId] = true
      local entityReturn = world.callScriptedEntity(entity.id, pipes.hooks.get, args, entity.nodeId)
      pipes.rejectNode[nodeId] = false
      if entityReturn then return entityReturn end
    end
  end
  return false
end

--- Peek push, calls the peekPut hook on the closest connected object that returns true
-- @param nodeId number - ID of the node to peek through
-- @param args - The arguments to send to the hook
-- @returns Hook return if successful, false if unsuccessful
function pipes.peekPush(nodeId, args)
  if #pipes.nodeEntities[nodeId] > 0 and not pipes.rejectNode[nodeId] then
    for i,entity in ipairs(pipes.nodeEntities[nodeId]) do
      pipes.rejectNode[nodeId] = true
      local entityReturn = world.callScriptedEntity(entity.id, pipes.hooks.peekPut, args, entity.nodeId)
      pipes.rejectNode[nodeId] = false
      if entityReturn then return entityReturn end
    end
  end
  return false
end

--- Peek pull, calls the peekPull hook on the closest connected object that returns true
-- @param nodeId number - ID of the node to peek through
-- @param args - The arguments to send to the hook
-- @returns Hook return if successful, false if unsuccessful
function pipes.peekPull(nodeId, args)
  if #pipes.nodeEntities[nodeId] > 0 and not pipes.rejectNode[nodeId] then
    for i,entity in ipairs(pipes.nodeEntities[nodeId]) do
      pipes.rejectNode[nodeId] = true
      local entityReturn = world.callScriptedEntity(entity.id, pipes.hooks.peekGet, args, entity.nodeId)
      pipes.rejectNode[nodeId] = false
      if entityReturn then return entityReturn end
    end
  end
  return false
end

--HOOKS

--- Hook used for determining if an object connects to a specified position
-- @param position vec2 - world position to compare node positions to
-- @param pipeDirection vec2 - direction of the pipe to see if the object connects
-- @returns node ID if successful, false if unsuccessful
function pipes.entityConnectsAt(position, pipeDirection)
  if pipes.nodes == nil then
    return false 
  end
  local entityPos = entity.position()
  
  for i,node in ipairs(pipes.nodes) do
    local absNodePos = entity.toAbsolutePosition(node.offset)
    local distance = world.distance(position, absNodePos)
    if distance[1] == 0 and distance[2] == 0 and pipes.pipesConnect(node.dir, {pipeDirection}) then
      return i
    end
  end
  return false
end

--HELPERS
--- Checks if a table (array only) contains a value (not recursive)
-- @param table table - table to check
-- @param value (w/e) - value to compare
-- @returns true if table contains it, false if not
function table.contains(table, value)
  for _,val in ipairs(table) do
    if value == val then return true end
  end
  return false
end

--- Copies a table
-- @param table table - table to copy
-- @returns copied table
function table.copy(table)
  local newTable = {}
  for i,v in pairs(table) do
    if type(v) == "table" then
      newTable[i] = table.copy(v)
    else
      newTable[i] = v
    end
  end
  return newTable
end
