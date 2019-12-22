-- Command signals
local DEPLOY_SIGNAL = {name="construction-robot", type="item"}
local DECONSTRUCT_SIGNAL = {name="deconstruction-planner", type="item"}
local COPY_SIGNAL = {name="signal-C", type="virtual"}
local WIDTH_SIGNAL = {name="signal-W", type="virtual"}
local HEIGHT_SIGNAL = {name="signal-H", type="virtual"}
local X_SIGNAL = {name="signal-X", type="virtual"}
local Y_SIGNAL = {name="signal-Y", type="virtual"}
local ROTATE_SIGNAL = {name="signal-R", type="virtual"}

-- local COMMAND_SIGNALS= { DEPLOY_SIGNAL, DECONSTUCT_SIGNAL, COPY_SIGNAL, WIDTH_SIGNAL, HEIGHT_SIGNAL, X_SIGNAL, Y_SIGNAL, ROTATE_SIGNAL}

function on_init()
  global.deployers_new = {}
  on_mods_changed()
end

function on_mods_changed()
  if global.deployers then global.deployers = nil
  if not global.deployers_new then global.deployers_new = {} end

  -- Construction robotics unlocks deployer chest
  for _,force in pairs(game.forces) do
    if force.technologies["construction-robotics"].researched then
      force.recipes["blueprint-deployer"].enabled = true
    end
  end

  -- Collect all modded blueprint signals in one table
  global.blueprint_signals = {}
  for _,item in pairs(game.item_prototypes) do
    if item.type == "blueprint"
    or item.type == "blueprint-book"
    or item.type == "upgrade-item"
    or item.type == "deconstruction-item" then
      table.insert(global.blueprint_signals, {name=item.name, type="item"})
    end
  end
  
  local new_delay= settings.startup.order_delay.value
  if global.old_delay and global.old_delay > new_delay then
    local tick42
    for key, deployer in pairs(global.deployers_new) do
      if deployer.waiting_list and #(deployer.waiting_list) > new_delay then
        if not tick42 then
          for i, _ in pairs deployer.waiting_list do
            if tick42 then
              if tick42<i then
                tick42= i
              end
            else
              tick42=i
            end
          end
        end
        for i = tick42- global.old_delay+1 , tick42 - new_delay do
          deployer.waiting_list[i]=nil
        end
      end     
    end
  end        
  global.old_delay= new_delay
end

function on_built(event)
  local entity = event.created_entity or event.entity or event.destination
  if not entity or not entity.valid then return end
  if entity.name == "blueprint-deployer" then
    table.insert(global.deployers_new, {entity= entity, waiting_list ={}})
  end
end

function on_destroyed(event)
  local entity = event.entity
  if not entity or not entity.valid then return end
  if entity.name == "blueprint-deployer" then
  end
end

function on_tick(event)
  local delay = global.old_delay
  for key, deployer in pairs(global.deployers_new) do
    if deployer.entity.valid then
      deployer.waiting_list[event.tick]= deployer.entity.get_merged_signals() or {}
      on_tick_deployer(deployer.entity, deployer.waiting_list[event.tick - delay] or {})
      deployer.waiting_list[event.tick-delay]= nil
    else
      global.deployers_new[key] = nil
    end
  end
end

function on_tick_deployer(deployer,signals)
  local bp = nil
  local deploy = get_signal_from_set(DEPLOY_SIGNAL, signals)
  if deploy > 0 then
    bp = deployer.get_inventory(defines.inventory.chest)[1]
    if not bp.valid_for_read then return end
    if bp.is_blueprint then
      -- Deploy blueprint
      deploy_blueprint(bp, deployer,signals)
    elseif bp.is_blueprint_book then
      -- Deploy blueprint from book
      local inventory = bp.get_inventory(defines.inventory.item_main)
      if deploy > inventory.get_item_count() then
        deploy = bp.active_index
      end
      deploy_blueprint(inventory[deploy], deployer,signals)
    elseif bp.is_deconstruction_item then
      -- Deconstruct area
      deconstruct_area(bp, deployer,signals, true)
    elseif bp.is_upgrade_item then
      -- Upgrade area
      upgrade_area(bp, deployer, signals, true)
    end
    return
  end

  if deploy == -1 then
    bp = deployer.get_inventory(defines.inventory.chest)[1]
    if not bp.valid_for_read then return end
    if bp.is_deconstruction_item then
      -- Cancel deconstruction in area
      deconstruct_area(bp, deployer, signals, false)
    elseif bp.is_upgrade_item then
      -- Cancel upgrade upgrade in area
      upgrade_area(bp, deployer, signals, false)
    end
    return
  end

  local deconstruct = get_signal_from_set( DECONSTRUCT_SIGNAL, signals)
  if deconstruct == -1 then
    -- Deconstruct area
    deconstruct_area(bp, deployer,signals, true)
    return
  elseif deconstruct == -2 then
    -- Deconstruct Self
    deployer.order_deconstruction(deployer.force)
    return
  elseif deconstruct == -3 then
    -- Cancel deconstruction in area
    deconstruct_area(bp, deployer, signals, false)
    return
  end

  local copy = get_signal_from_set( COPY_SIGNAL, signals)
  if copy == 1 then
    -- Copy blueprint
    copy_blueprint(deployer,signals)
    return
  elseif copy == -1 then
    -- Delete blueprint
    local stack = deployer.get_inventory(defines.inventory.chest)[1]
    if not stack.valid_for_read then return end
    if stack.is_blueprint
    or stack.is_blueprint_book
    or stack.is_upgrade_item
    or stack.is_deconstruction_item then
      stack.clear()
    end
    return
  end
end

function deploy_blueprint(bp, deployer,signals)
  if not bp then return end
  if not bp.valid_for_read then return end
  if not bp.is_blueprint_setup() then return end

  -- Find anchor point
  local anchor_entity = nil
  local entities = bp.get_blueprint_entities()
  if entities then
    for _, entity in pairs(entities) do
      if entity.name == "wooden-chest" then
        anchor_entity = entity
        break
      elseif entity.name == "blueprint-deployer" and not anchor_entity then
        anchor_entity = entity
      end
    end
  end
  local anchorX, anchorY = 0, 0
  if anchor_entity then
    anchorX = anchor_entity.position.x
    anchorY = anchor_entity.position.y
  end

  -- Rotate
  local rotation = get_signal_from_set(ROTATE_SIGNAL, signals)
  local direction = defines.direction.north
  if (rotation == 1) then
    direction = defines.direction.east
    anchorX, anchorY = -anchorY, anchorX
  elseif (rotation == 2) then
    direction = defines.direction.south
    anchorX, anchorY = -anchorX, -anchorY
  elseif (rotation == 3) then
    direction = defines.direction.west
    anchorX, anchorY = anchorY, -anchorX
  end

  local position = {
    x = deployer.position.x - anchorX + get_signal_from_set(X_SIGNAL, signals),
    y = deployer.position.y - anchorY + get_signal_from_set(Y_SIGNAL, signals),
  }

  -- Check for building out of bounds
  if position.x > 1000000
  or position.x < -1000000
  or position.y > 1000000
  or position.y < -1000000 then
    return
  end

  local result = bp.build_blueprint{
    surface = deployer.surface,
    force = deployer.force,
    position = position,
    direction = direction,
    force_build = true,
  }

  for _, entity in pairs(result) do
    script.raise_event(defines.events.script_raised_built, {
      entity = entity,
      stack = bp,
    })
  end
end

function deconstruct_area(bp, deployer,signals, deconstruct)
  local area = get_area(deployer,signals)
  if deconstruct == false then
    -- Cancel Area
    deployer.surface.cancel_deconstruct_area{
      area = area,
      force = deployer.force,
      skip_fog_of_war = false,
      item = bp,
    }
  else
    -- Deconstruct Area
    local deconstruct_self = deployer.to_be_deconstructed(deployer.force)
    deployer.surface.deconstruct_area{
      area = area,
      force = deployer.force,
      skip_fog_of_war = false,
      item = bp,
    }
    if not deconstruct_self then
       -- Don't deconstruct myself in an area order
      deployer.cancel_deconstruction(deployer.force)
    end
  end
end

function upgrade_area(bp, deployer,signals, upgrade)
  local area = get_area(deployer,signals)
  if upgrade == false then
    -- Cancel area
    deployer.surface.cancel_upgrade_area{
      area = area,
      force = deployer.force,
      skip_fog_of_war = false,
      item = bp,
    }
  else
    -- Upgrade area
    deployer.surface.upgrade_area{
      area = area,
      force = deployer.force,
      skip_fog_of_war = false,
      item = bp,
    }
  end
end

function get_area(deployer,signals)
  local anchor_point=settings.global["anchor-point-of-area-rectangle"].value
  local X = get_signal_from_set(X_SIGNAL, signals)
  local Y = get_signal_from_set(Y_SIGNAL, signals)
  local W = get_signal_from_set(WIDTH_SIGNAL, signals)
  local H = get_signal_from_set(HEIGHT_SIGNAL, signals)

  if W < 1 then W = 1 end
  if H < 1 then H = 1 end

  -- Align to grid
  if anchor_point == "floored-centre" then
    if W % 2 == 0 then X = X + 0.5 end
    if H % 2 == 0 then Y = Y + 0.5 end
    X=X-(W/2)
    Y=Y-(H/2)
  end
  
  if anchor_point=="lower-right" or anchor_point == "lower-left" then
    Y=Y-H
  end
  if anchor_point == "lower-right" or anchor_point== "upper-right" then
    X=X-W
  end
    
  -- Subtract 1 pixel from edges to avoid tile overlap
  W = W - 1/128
  H = H - 1/128

  return {
    {deployer.position.x+X, deployer.position.y+Y},
    {deployer.position.x+X+W, deployer.position.y+Y+H},
  }
end

function copy_blueprint(deployer,signals)
  local inventory = deployer.get_inventory(defines.inventory.chest)
  if not inventory.is_empty() then return end
  for _,signal in pairs(global.blueprint_signals) do
    -- Check for a signal before doing an expensive search
    if get_signal_from_set(signal, signals) >= 1 then
      -- Signal exists, now we have to search for the blueprint
      local stack = find_stack_in_network(deployer, signal.name)
      if stack then
        inventory[1].set_stack(stack)
        return
      end
    end
  end
end

-- Breadth-first search for an item in the circuit network
-- If there are multiple items, returns the closest one (least wire hops)
function find_stack_in_network(deployer, item_name)
  local present = {
    [con_hash(deployer, defines.circuit_connector_id.container, defines.wire_type.red)] =
    {
      entity = deployer,
      connector = defines.circuit_connector_id.container,
      wire = defines.wire_type.red,
    },
    [con_hash(deployer, defines.circuit_connector_id.container, defines.wire_type.green)] =
    {
      entity = deployer,
      connector = defines.circuit_connector_id.container,
      wire = defines.wire_type.green,
    }
  }
  local past = {}
  local future = {}
  while next(present) do
    for key, con in pairs(present) do
      -- Search connecting wires
      for _, def in pairs(con.entity.circuit_connection_definitions) do
        -- Wire color and connection points must match
        if def.target_entity.unit_number
        and def.wire == con.wire
        and def.source_circuit_id == con.connector then
          local hash = con_hash(def.target_entity, def.target_circuit_id, def.wire)
          if not past[hash] and not present[hash] and not future[hash] then
            -- Search inside the entity
            local stack = find_stack_in_container(def.target_entity, item_name)
            if stack then return stack end

            -- Add entity connections to future searches
            future[hash] = {
              entity = def.target_entity,
              connector = def.target_circuit_id,
              wire = def.wire
            }
          end
        end
      end
      past[key] = true
    end
    present = future
    future = {}
  end
end

function con_hash(entity, connector, wire)
  return entity.unit_number .. "-" .. connector .. "-" .. wire
end

function find_stack_in_container(entity, item_name)
  if entity.type == "container" or entity.type == "logistic-container" then
    local inventory = entity.get_inventory(defines.inventory.chest)
    for i = 1, #inventory do
      if inventory[i].valid_for_read and inventory[i].name == item_name then
        return inventory[i]
      end
    end
  elseif entity.type == "inserter" then
    local behavior = entity.get_control_behavior()
    if not behavior then return end
    if not behavior.circuit_read_hand_contents then return end
    if entity.held_stack.valid_for_read and entity.held_stack.name == item_name then
      return entity.held_stack
    end
  end
end



--from justarandomgeeks conman
  
  function get_signal_from_set(signal,set)
  for _,sig in pairs(set) do
    if sig.signal.type == signal.type and sig.signal.name == signal.name then
      return sig.count
    end
  end
  return 0
end
  
  
  
  
  

script.on_init(on_init)
script.on_configuration_changed(on_mods_changed)
script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_built_entity, on_built)
script.on_event(defines.events.on_robot_built_entity, on_built)
script.on_event(defines.events.on_entity_cloned, on_built)
script.on_event(defines.events.script_raised_built, on_built)
script.on_event(defines.events.script_raised_revive, on_built)
script.on_event(defines.events.on_player_mined_entity, on_destroyed)
script.on_event(defines.events.on_robot_mined_entity, on_destroyed)
script.on_event(defines.events.on_entity_died, on_destroyed)
script.on_event(defines.events.script_raised_destroy, on_destroyed)
