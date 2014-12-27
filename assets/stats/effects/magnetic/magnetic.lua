function init()
  if effect.configParameter("magnetCharge") > 0 then
    animator.setAnimationState("magnet", "pos")
  else
    animator.setAnimationState("magnet", "neg")
  end
end

function update(dt)
  local myCharge = effect.configParameter("magnetCharge")
  local objectsNearby = world.entityQuery(mcontroller.position(), 20, {includedTypes = {"object"}, boundMode = "Position"})

  local totalForce = {0, 0}
  for i, objectId in ipairs(objectsNearby) do
    local objectCharge = world.objectConfigParameter(objectId, "magnetCharge")
    if objectCharge then
      local objectOffset = entity.distanceToEntity(objectId)
      local objectDistance = math.max(1.0, vec2.mag(objectOffset))
      local thisForce = vec2.mul(objectOffset, (myCharge * objectCharge * dt * -1) / (objectDistance * objectDistance))
      totalForce = vec2.add(totalForce, thisForce)
    end
  end

  -- world.logInfo("Total force this tick is %s", totalForce)

  mcontroller.controlForce(totalForce)
end

function uninit()
  animator.setAnimationState("magnet", "off")
end
