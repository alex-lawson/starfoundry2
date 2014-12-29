--Liquids

liquidConversions =  { 
  {8, 2}
}

function convertLiquids(liquid)
  for _,liquidTo in ipairs(liquidConversions) do
    if liquid[1] == liquidTo[1] then
      liquid[1] = liquidTo[2]
      break
    end
  end
  return liquid
end

function filterLiquids(filter, liquids)
  if filter then
    for i,liquid in ipairs(liquids) do
      local liquidId = tostring(liquid[1])
      if filter[liquidId] and liquid[2] >= filter[liquidId][1]then
        if liquid[2] <= filter[liquidId][2] then
          return liquid, i
        else
          return {liquid[1], filter[liquidId][2]}, i
        end
      end
    end
  else
    return liquids[1], 1
  end
end