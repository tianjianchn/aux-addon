local type, setmetatable, setfenv, unpack, mask, _g = type, setmetatable, setfenv, unpack, bit.band, getfenv(0)
local PRIVATE, PUBLIC, MUTABLE, PROPERTY, ACCESSOR, MUTATOR, INITIALIZED = 0, 1, 2, 4, 8, 16, 32
local MODIFIER = {private=PRIVATE, public=PUBLIC, mutable=MUTABLE, accessor=ACCESSOR+PROPERTY, mutator=MUTATOR+PROPERTY}
local MODIFIER_MASK, PROPERTY_MASK = {private=MUTABLE+ACCESSOR+MUTATOR, public=MUTABLE+ACCESSOR+MUTATOR, mutable=PRIVATE+PUBLIC, accessor=PRIVATE+PUBLIC, mutator=PRIVATE+PUBLIC}, PRIVATE+PUBLIC
local error, modifier_error, property_error, immutable_error, collision_error, null_error, set_property, env_mt, interface_mt, declarator_mt, importer_mt
local _state, _modules = {}, {}
local NULL = setmetatable({}, {__metatable=false, __index=error'NULL', __newindex=error'NULL'})
function error(message, ...) return function() _g.error(format(message, unpack(arg))..'\n'..debugstack(3, 10, 0)) end end
modifier_error = error 'Invalid modifiers.'
property_error = error 'Accessor/Mutator must be function.'
function immutable_error(key) return error('Field "%s" is immutable.', key) end
function collision_error(key) return error('Field "%s" already exists.', key) end
function null_error(key) error('No field "%s".', key) end
importer_mt = {__metatable=false}
function importer_mt.__index(self, key) _state[self][self] = key; return self end
function importer_mt.__call(self, arg1, arg2)
	local name, state, module, alias
	name = arg2 or arg1
	state, module = _state[self], _modules[name]
	alias, state[self] = state[self] or name, nil
	if module then
		if alias == '_' then
			for key, modifiers in module.metadata do
				if not state.metadata[key] and mask(PUBLIC, modifiers) ~= 0 then
					state.metadata[key], state.data[key], state.accessors[key], state.mutators[key] = modifiers, module.data[key], module.accessors[key], module.mutators[key]
				end
			end
		elseif not state.metadata[alias] then
			state.metadata[alias], state.data[alias] = PRIVATE, module.interface
		end
	end
	return self
end
function set_property(data, property, value)
	if property and not data[property] and type(value) == 'function' or property_error() then
		data[property] = value
	end
end
declarator_mt = {__metatable=false}
function declarator_mt.__index(self, key)
	local state, modifier = _state[self], MODIFIER[key]; local modifiers = state.modifiers
	if modifier then
		if mask(MODIFIER_MASK[key], modifiers) ~= modifiers then modifier_error() end
		state.modifiers = modifiers + modifier; return self
	elseif not state.metadata[key] or collision_error(key) then
		if mask(PROPERTY_MASK, modifiers) ~= modifiers then modifier_error() end
		state.property, state.metadata[key], state.modifiers = key, modifiers + PROPERTY, PRIVATE
	end
end
function declarator_mt.__newindex(self, key, value)
	local state = _state[self]
	if state.metadata[key] then collision_error(key) end
	state.metadata[key] = state.modifiers
	if mask(PROPERTY, state.modifiers) == 0 then
		state.data[key] = value
	elseif type(value) == 'function' or property_error() then
		local data = mask(ACCESSOR, state.modifiers) ~= 0 and state.accessors or state.mutators
		state.property, data[key] = key, value
	end
	state.modifiers = PRIVATE
end
function declarator_mt.__call() end
do
	local function index(access, default)
		return function(self, key)
			local state = _state[self]; local modifiers = state.metadata[key]
			if modifiers and mask(access+PROPERTY, modifiers) == access then
				return state.data[key]
			else
				local accessor = state.accessors[key]
				if accessor then return accessor() else return default[key] or null_error(key) end
			end
		end
	end
	env_mt = {__metatable=false, __index=index(PRIVATE, _g)}
	function env_mt.__newindex(self, key, value)
		local state = _state[self]; local modifiers = state.metadata[key]
		if modifiers then
			local mutator = state.mutators[key]
			if mutator then return mutator(value) end
			if mask(MUTABLE, modifiers) == 0 then immutable_error(key) end
		else
			state.metadata[key] = state.modifiers
		end
		state.data[key] = value
	end
	interface_mt = {__metatable=false, __index=index(PUBLIC, {})}
	function interface_mt.__newindex(self, key, value)
		local state = _state[self]; local metadata = state.metadata or null_error(key)
		if mask(PUBLIC+MUTATOR, metadata) == PUBLIC+MUTATOR then
			return state.mutators[key](value)
		elseif mask(PUBLIC, metadata) == PUBLIC or immutable_error(key) then
			state.data[key] = value
		end
	end
end
function INIT() end
function module(name)
	if not _modules[name] then
		local state, accessors, mutators, env, interface, declarator, importer
		env, interface, declarator, importer = setmetatable({}, env_mt), setmetatable({}, interface_mt), setmetatable({}, declarator_mt), setmetatable({}, importer_mt)
		accessors = {
			private=function() state.modifiers = PRIVATE return declarator end, public=function() state.modifiers = PUBLIC return declarator end,
			mutable=function() state.modifiers = MUTABLE return declarator end,
			accessor=function() state.modifiers = PROPERTY+ACCESSOR return declarator end, mutator=function() state.modifiers = PROPERTY+MUTATOR return declarator end}
		mutators = {accessor=function(value) set_property(accessors, state.property, value) end, mutator=function(value) set_property(mutators, state.property, value) end}
		state = {
			env=env, interface=interface, modifiers=PRIVATE,
			metadata = {NULL=PRIVATE, _g=PRIVATE, _m=PRIVATE, _i=PRIVATE, import=PRIVATE, private=PROPERTY+ACCESSOR, public=PROPERTY+ACCESSOR, mutable=PROPERTY+ACCESSOR, accessor=PROPERTY+ACCESSOR+MUTATOR, mutator=PROPERTY+ACCESSOR+MUTATOR},
			data = {NULL=NULL, _g=_g, _m=env, _i=interface, import=importer}, accessors=accessors, mutators=mutators,
		}
		_modules[name], _state[env], _state[interface], _state[declarator], _state[importer] = state, state, state, state, state
		setfenv(INIT, env); INIT()
	end
	setfenv(2, _modules[name].env)
end