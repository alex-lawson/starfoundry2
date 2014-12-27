function init()
  self.specialLast = false
  self.active = false
  self.energyUsageRate = tech.parameter("energyUsageRate")
  self.polarityPositive = true
end

function input(args)
  local move = nil

  if args.moves["special"] ~= self.specialLast then  
    if args.moves["special"] == 1 then
      if self.active then
        move = "deactivate"
      else
        move = "activate"
      end
    elseif args.moves["special"] == 2 then
      move = "switchPolarity"
    end
  end

  self.specialLast = args.moves["special"]

  return move
end

function update(args)
  if self.active and (args.actions["deactivate"] or not tech.consumeTechEnergy(self.energyUsageRate * args.dt)) then
    deactivate()
  elseif args.actions["activate"] then
    activate()
  end

  if args.actions["switchPolarity"] then
    self.polarityPositive = not self.polarityPositive
  end

  if self.active then
    if self.polarityPositive then
      status.removeEphemeralEffect("magneticneg")
      status.addEphemeralEffect("magneticpos")
    else
      status.removeEphemeralEffect("magneticpos")
      status.addEphemeralEffect("magneticneg")
    end
  end
end

function activate()
  tech.playSound("activate")
  self.active = true
end

function deactivate()
  status.removeEphemeralEffect("magneticpos")
  status.removeEphemeralEffect("magneticneg")
  self.active = false
end