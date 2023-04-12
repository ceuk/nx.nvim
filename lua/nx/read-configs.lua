local utils = require 'nx.utils'
local _M = {}

_M.scandir = function(directory)
	local t, popen = {}, io.popen
	local pfile = popen('ls -a "' .. directory .. '"')
	if pfile == nil then
		return {}
	end

	for filename in pfile:lines() do
		table.insert(t, filename)
	end
	pfile:close()

	return t
end

_M.rf = function(fname)
	local f = io.open(vim.fn.resolve(fname), 'r')

	if f == nil then
		return nil
	end

	local s = f:read 'a' -- a = all

	local table = vim.json.decode(s)

	f:close()
	return table
end

---Reads nx.json and sets its global var
_M.read_nx = function()
	_G.nx.nx = _M.rf './nx.json'
end

---Reads nx graph and stores as a global var
_M.read_graph = function()
	local s = _G.nx.nx_cmd_root .. ' graph --file /tmp/nx-graph.json'
	vim.fn.system(s)
	_G.nx.graph = vim.v.shell_error == 0 and _M.rf('/tmp/nx-graph.json').graph
		or nil
end

---Reads workspace.json and sets its global var
_M.read_workspace = function()
	local s = _G.nx.nx_cmd_root .. ' print-affected --all'
	local r = vim.fn.system(s)
	_G.nx.workspace = nil
	if vim.v.shell_error == 0 then
		_M.read_graph()
		_G.nx.workspace = vim.json.decode(r)
	end
end

---Reads package.json and sets its global var
_M.read_package_json = function()
	_G.nx.package_json = _M.rf './package.json'
end

---Reads all projects configurations
_M.read_projects = function()
	for key, value in pairs(_G.nx.workspace.projects or {}) do
		local v = _G.nx.graph.nodes[value].data

		_G.nx.projects[value] = v
	end
end

---Reads workspace generators
_M.read_workspace_generators = function()
	local gens = {}

	for _, value in ipairs(_M.scandir './tools/generators') do
		local schema = _M.rf('./tools/generators/' .. value .. '/schema.json')
		if schema then
			table.insert(gens, {
				schema = schema,
				name = value,
				run_cmd = 'workspace-generator ' .. value,
				package = 'workspace-generator',
			})
		end
	end

	_G.nx.generators.workspace = gens
end

---Reads node_modules generators (only those specified in package.json, not lock)
_M.read_external_generators = function()
	local deps = {}
	for _, value in ipairs(utils.keys(_G.nx.package_json.dependencies)) do
		table.insert(deps, value)
	end
	for _, value in ipairs(utils.keys(_G.nx.package_json.devDependencies)) do
		table.insert(deps, value)
	end

	local gens = {}

	for _, value in ipairs(deps) do
		local f = _M.rf('./node_modules/' .. value .. '/package.json')
		if f ~= nil and f.schematics ~= nil then
			local schematics =
				_M.rf('./node_modules/' .. value .. '/' .. f.schematics)

			if schematics and schematics.generators then
				for name, gen in pairs(schematics.generators) do
					local schema =
						_M.rf('./node_modules/' .. value .. '/' .. gen.schema)
					if schema then
						table.insert(gens, {
							schema = schema,
							name = name,
							run_cmd = 'generate ' .. value .. ':' .. name,
							package = value,
						})
					end
				end
			end
		end
	end

	_G.nx.generators.external = gens
end

---Reads all configs
_M.read_nx_root = function()
	_M.read_nx()
	_M.read_workspace()
	_M.read_package_json()

	if _G.nx.workspace ~= nil and _G.nx.graph ~= nil then
		_M.read_projects()
	end

	_M.read_workspace_generators()
	if _G.nx.package_json ~= nil then
		_M.read_external_generators()
	end
end

return _M
