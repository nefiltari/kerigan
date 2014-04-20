Kerigan = exports? and exports or @Kerigan = {}

## Libs

coffee = require 'coffee-script'
require 'coffee-script/register'
_ = require 'underscore'
async = require 'async'

## Code

Kerigan.Engine = (config = {}) ->
  eg = new (require('events').EventEmitter)
  eg.config = config

  # Process the next round with a skill
  eg.next = (skill) ->
    valid = true
    eg.emit 'validation', eg, skill, (v) -> valid = v and valid
    unless eg.finished
      if valid
        eg.emit 'next', eg, skill
        skill eg
        for buff in eg.buffs
          if buff.initial
            buff.emit 'add', eg
            buff.initial = false
          else buff.emit 'tick', eg, skill
        eg.rounds += 1
        eg.emit 'check-finish', eg
      else eg.emit 'invalid', eg, skill
    else eg.emit 'finished', eg

  # Initialize the engine
  eg.init = (init) ->
    eg.state = init or {}
    eg.values = {}  # The temporary processor units from type Kerigan.Value
    eg.emit 'init', eg
    do eg.reset

  # Reset the engine
  eg.reset = ->
    eg.rounds = 0
    eg.buffs = []
    eg.finished = false
    eg.emit 'reset', eg

  # Checks if the current state has a buff (id or directly)
  eg.chk_buff = (buff) ->
    if typeof buff is 'string'
      _.any eg.buffs, (bf) -> bf.id is buff
    else _.contains eg.buffs, buff

  # Returns a buff object(s) from id as Array
  eg.get_buff = (id) ->
    _.filter eg.buffs, (buff) -> buff.id is id
    # buffs = buffs[0] if buffs.length is 1

  # Add a buff to alter the state
  eg.add_buff = (buff) ->
    eg.del_buff(mutual) for mutual in buff.mutuals
    eg.buffs.push buff
    # buff.emit 'init', eg

  # Delete a buff (buff is a buff object or id)
  eg.del_buff = (buff) ->
    if typeof buff is 'string'
      removed = _.filter eg.buffs, (bf) -> bf.id is buff
      eg.buffs = _.filter eg.buffs, (bf) -> bf.id isnt buff
      bf.emit('delete', eg) for bf in removed
    else
      eg.buffs = _.without eg.buffs, buff
      buff.emit 'delete', eg

  eg.inspect = ->
    util = require 'util'
    result = ''
    inspect_state = (obj, d) ->
      d += 1
      for key, value of obj
        _.times d, -> result += '  '
        if typeof value isnt 'object'
          value = parseFloat value.toFixed(3) if typeof value is 'number'
          result += util.inspect(value)
          result += '\n'
        else
          result += "#{key}:\n"
          inspect_state value, d
    result += 'State:\n'
    inspect_state eg.state, 0
    result += '\n'
    result += 'Rounds: ' + (util.inspect eg.rounds, { colors: true }) + '\n\n'
    result += 'Buffs:\n'
    (result += '  ' + util.inspect(buff) + '\n') for buff in eg.buffs
    result

  # The successor
  eg.successor = (chance) ->
    return true if eg.config.best_case? and eg.config.best_case
    return false if eg.config.worst_case? and eg.config.worst_case
    rand = do Math.random
    return rand unless chance?
    if chance >= 1.0
      return true
    else
      if chance >= rand
        return rand
      else false

  # Blank initialize the Engine
  do eg.init

  eg._this = @
  eg._type = Kerigan.Engine
  eg

# Time-based state altering (mod collection)
Kerigan.Buff = (id) ->
  bf = new (require('events').EventEmitter)
  bf.id = id

  # Standard event handler
  bf.on 'add', (engine) ->
    setup.value.install bf.id, setup.mod for setup in bf.mods

  bf.on 'tick', (engine) ->
    bf.life -= 1 if bf.life isnt 'infinite' and bf.life isnt 0
    engine.del_buff(bf) if bf.life is 0

  bf.on 'delete', (engine) ->
    setup.value.uninstall bf.id for setup in bf.mods

  # Initialization
  bf.init = (life, init, mutuals...) ->
    bf.state = init or {}
    bf.mutuals = mutuals
    bf.mutuals.push bf.id
    bf.life = life or 0
    bf.mods = []
    bf.initial = true
    bf.emit 'init'

  # Update all values with installed buff mods
  bf.update = ->
    (do setup.value.update) for setup in bf.mods

  # Let the buff know which mod to which value should be installed/uninstalled
  bf.install = (value, mod) ->
    bf.mods.push value: value, mod: mod

  # Debug output
  bf.inspect = ->
    util = require 'util'
    "#{bf.id}: " + util.inspect(bf.life, { colors: true }) + ', ' + util.inspect(bf.state, { colors: true })

  # Aliases
  bf.add_mod = bf.install
  bf.reset = bf.init

  # Blank init
  do bf.init

  bf._this = @
  bf._type = Kerigan.Buff
  bf

# The skills
Kerigan.Skill = (id, action) ->
  sk = (engine) ->
    sk.action.call sk, engine
  sk.id = id

  # Initialization
  sk.init = (cost, init) ->
    sk.state = init or {}
    sk.cost = cost

  # Aliases
  sk.action = action
  sk.reset = sk.init
  sk.exec = sk

  # Blank init
  do sk.init

  sk._this = @
  sk._type = Kerigan.Skill
  sk

# Karigan Value - A value that can be changed with modifications
Kerigan.Value = (id, val, cache = true) ->
  va = ->
    if cache
      va.cache
    else
      do va.update
  va.id = id
  va.events = new (require('events').EventEmitter)

  # Initialization
  va.init = (value) ->
    va.base = value
    va.cache = value
    va.modifiers = []

  # Process the value with all mods and update the cache
  va.update = ->
    va.cache = _.inject va.modifiers, ((akk, mod) -> mod.call(va, akk)), va.base

  # Get an installed mod with id (or mods)
  va.get_mod = (id) ->
    result = _.filter va.modifiers, (mod) -> mod.id is id
    # result = result[0] if result.length is 1
    result

  # Add a mod to an position (pos) with id (pos is optional)
  # The mod has following structure: (akk) -> # return modified_akk
  va.add_mod = (id, mod, pos) ->
    mod.id = id
    unless pos?
      va.modifiers.push mod
      va.cache = mod.call va, va.cache
    else
      va.modifiers.splice pos, 0, mod
      do va.update
    va.events.emit 'install', mod, pos

  # Delete a mod with id or directly
  va.del_mod = (mod) ->
    if typeof mod is 'string'
      removed = _.filter va.modifiers, (m) -> m.id is mod
      va.modifiers = _.filter va.modifiers, (m) -> m.id isnt mod
      va.emit('uninstall', m) for m in removed
    else
      va.modifiers = _.without va.modifiers, mod
      va.emit 'uninstall', mod
    do va.update

  # Count the installed mods
  va.count = -> va.modifiers.length

  # Debug output
  va.inspect = ->
    util = require 'util'
    value = va()
    value = parseFloat value.toFixed(3) if typeof value is 'number'
    "#{va.id}: " + util.inspect value, { colors: true }

  # Aliases (also EventEmitter Mappers)
  va.length = va.count
  va.get = va
  va.reset = va.set = va.init
  va.install = va.add_mod
  va.uninstall = va.del_mod
  va.on = (p...) -> va.events.on.apply va.events, p
  va.emit = (p...) -> va.events.emit.apply va.events, p
  va.removeListener = (p...) -> va.events.removeListener.apply va.events, p
  va.removeAllListeners = (p...) -> va.events.removeAllListeners.apply va.events, p
  va.once = (p...) -> va.events.once.apply va.events, p

  # Blank init
  va.init val

  va._this = @
  va._type = Kerigan.Value
  va

###
  The 'validation' event validates the consisiting state and set
  engine['valid'] and engine['finished'] to their appropriate values
###