function init(virtual)
  if virtual == false then
    entity.setInteractive(true)
    pipes.init({liquidPipe})

    if entity.direction() < 0 then
      pipes.nodes = entity.configParameter("flippedPipeNodes")
    end

    entity.setAnimationState("pumping", "off")
    
    self.pumping = false
    self.pumpRate = entity.configParameter("pumpRate")
    self.pumpTimer = 0

    buildFilter()
    
    if storage.state == nil then storage.state = false end
  end
end

function onInboundNodeChange(args)
  storage.state = args.level
end

function onNodeConnectionChange()
  storage.state = entity.getInboundNodeLevel(0)
end

function onInteraction(args)
  --pump liquid
  if entity.isInboundNodeConnected(0) == false then
    storage.state = not storage.state
  end
end

function die()
end

function update(dt)
  pipes.update(dt)
  
  if storage.state then
    if self.pumpTimer > self.pumpRate then
      entity.setAnimationState("pumping", "powered")
      local canGetLiquid = peekPullLiquid(1, self.filter)
      local canPutLiquid = peekPushLiquid(2, canGetLiquid)

      if canGetLiquid and canPutLiquid then
        entity.setAnimationState("pumping", "pump")
        entity.setAllOutboundNodes(true)
        
        local liquid = pullLiquid(1, self.filter)
        pushLiquid(2, liquid)
      else
        entity.setAllOutboundNodes(false)
        if canGetLiquid then
          entity.setAnimationState("pumping", "error")
        end
      end
      self.pumpTimer = self.pumpTimer - self.pumpRate
    end
    self.pumpTimer = self.pumpTimer + dt
  else
    entity.setAllOutboundNodes(false)
    entity.setAnimationState("pumping", "off")
  end
end

function buildFilter()
  self.filter = {}
  for i = 0, 20 do
    self.filter[tostring(i)] = {0.25, 1}
  end
end

--- Pushes liquid
-- @param nodeId the node to push from
-- @param liquid the liquid to push, specified as array {liquidId, amount}
-- @returns true if successful, false if unsuccessful
function pushLiquid(nodeId, liquid)
  if not liquid then return false end

  local pushResult = pipes.push(nodeId, liquid)


  if not pushResult and next(pipes.virtualNodes[nodeId]) then
    for _,vNode in ipairs(pipes.virtualNodes[nodeId]) do
      local liquidPos = {vNode.pos[1] + 0.5, vNode.pos[2] + 0.5}
      local curLiquid = world.liquidAt(liquidPos)
      if not curLiquid or curLiquid[1] == liquid[1] then
        if curLiquid then liquid[2] = liquid[2] + curLiquid[2] end
        world.spawnLiquid(liquidPos, liquid[1], liquid[2])
        pushResult = true
        break
      end
    end
  end
  return pushResult
end

--- Pulls liquid
-- @param nodeId the node to push from
-- @param filter array of filters of liquids {liquidId = {minAmount,maxAmount}, otherLiquidId = {minAmount,maxAmount}}
-- @returns liquid if successful, false if unsuccessful
function pullLiquid(nodeId, filter)
  local pullResult = pipes.pull(nodeId, filter)

  if not pullResult and next(pipes.virtualNodes[nodeId]) then
    for _,vNode in ipairs(pipes.virtualNodes[nodeId]) do
      local liquidPos = {vNode.pos[1] + 0.5, vNode.pos[2] + 0.5}
      local getLiquid = canGetLiquid(filter, liquidPos)
      if pullResult == false or getLiquid[1] == pullResult[1] then
        local destroyed = world.destroyLiquid(liquidPos)
        if destroyed[2] > getLiquid[2] then
          world.spawnLiquid(liquidPos, destroyed[1], destroyed[2] - getLiquid[2])
        end
        pullResult = convertLiquids(getLiquid)
        break
      end
    end
  end
  return pullResult
end

--- Peeks a liquid push, does not go through with the transfer
-- @param nodeId the node to push from
-- @param liquid the liquid to push, specified as array {liquidId, amount}
-- @returns true if successful, false if unsuccessful
function peekPushLiquid(nodeId, liquid)
  if not liquid then return false end

  local pushResult = pipes.peekPush(nodeId, liquid)

  if not pushResult and next(pipes.virtualNodes[nodeId]) then
    for _,vNode in ipairs(pipes.virtualNodes[nodeId]) do
      local liquidPos = {vNode.pos[1] + 0.5, vNode.pos[2] + 0.5}
      local curLiquid = world.liquidAt(liquidPos)
      if not curLiquid or curLiquid[1] == liquid[1] then
        pushResult = true
      end
    end
  end
  return pushResult
end

--- Peeks a liquid pull, does not go through with the transfer
-- @param nodeId the node to push from
-- @param filter array of filters of liquids {liquidId = {minAmount,maxAmount}, otherLiquidId = {minAmount,maxAmount}}
-- @returns liquid if successful, false if unsuccessful
function peekPullLiquid(nodeId, filter)
  local pullResult = pipes.peekPull(nodeId, filter)

  if not pullResult and next(pipes.virtualNodes[nodeId]) then
    for _,vNode in ipairs(pipes.virtualNodes[nodeId]) do
      local liquidPos = {vNode.pos[1] + 0.5, vNode.pos[2] + 0.5}
      local getLiquid = canGetLiquid(filter, liquidPos)

      if getLiquid then
        pullResult = getLiquid
        break
      end
    end
  end
  --world.logInfo("%s", pullResult)
  return pullResult
end

function canGetLiquid(filter, position)
  local availableLiquid = world.liquidAt(position)
  if availableLiquid then
    local liquid = convertLiquids(availableLiquid)

    local returnLiquid = filterLiquids(filter, {liquid})
    --world.logInfo("(canGetLiquid) filter result: %s", returnLiquid)
    
    if returnLiquid then
      return returnLiquid
    end
  end
  return false
end