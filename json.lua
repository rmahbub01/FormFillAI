--
-- json.lua
-- A lightweight JSON encoder / decoder in pure Lua 5.1-5.5
-- Compatible with Xournal++ Lua plugin environment.
--

local json = {}

local function kind_of(obj)
  if type(obj) ~= "table" then return type(obj) end
  local i = 1
  for _ in pairs(obj) do
    if obj[i] ~= nil then i = i + 1 else return "table" end
  end
  if i == 1 then return "empty" else return "array" end
end

local function escape_str(s)
  local in_char  = {'\\', '"', '\b', '\f', '\n', '\r', '\t'}
  local out_char = {'\\\\', '\\"', '\\b', '\\f', '\\n', '\\r', '\\t'}
  for i, c in ipairs(in_char) do
    s = s:gsub(c, out_char[i])
  end
  return s
end

function json.encode(val)
  local t = type(val)
  if t == "nil" then return "null"
  elseif t == "boolean" then return tostring(val)
  elseif t == "number" then return tostring(val)
  elseif t == "string" then return '"' .. escape_str(val) .. '"'
  elseif t == "table" then
    local kind = kind_of(val)
    local res = {}
    if kind == "array" or kind == "empty" then
      for _, v in ipairs(val) do
        table.insert(res, json.encode(v))
      end
      return "[" .. table.concat(res, ",") .. "]"
    else
      for k, v in pairs(val) do
        table.insert(res, json.encode(tostring(k)) .. ":" .. json.encode(v))
      end
      return "{" .. table.concat(res, ",") .. "}"
    end
  end
  return "null"
end

local function skip_whitespace(str, pos)
  while pos <= #str do
    local c = str:sub(pos, pos)
    if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then break end
    pos = pos + 1
  end
  return pos
end

local parse_value

local function parse_string(str, pos)
  pos = pos + 1
  local res = {}
  while pos <= #str do
    local c = str:sub(pos, pos)
    if c == '"' then
      return table.concat(res), pos + 1
    elseif c == '\\' then
      pos = pos + 1
      local next_c = str:sub(pos, pos)
      if next_c == 'n' then table.insert(res, "\n")
      elseif next_c == 't' then table.insert(res, "\t")
      elseif next_c == 'r' then table.insert(res, "\r")
      elseif next_c == 'b' then table.insert(res, "\b")
      elseif next_c == 'f' then table.insert(res, "\f")
      elseif next_c == '"' then table.insert(res, '"')
      elseif next_c == '\\' then table.insert(res, '\\')
      elseif next_c == '/' then table.insert(res, '/')
      else table.insert(res, next_c) end
    else
      table.insert(res, c)
    end
    pos = pos + 1
  end
  error("Unterminated string in JSON at position " .. pos)
end

local function parse_number(str, pos)
  local start_pos = pos
  if str:sub(pos, pos) == "-" then pos = pos + 1 end
  while pos <= #str do
    local c = str:sub(pos, pos)
    if (c >= "0" and c <= "9") or c == "." or c == "e" or c == "E" or c == "+" or c == "-" then
      pos = pos + 1
    else
      break
    end
  end
  local num_str = str:sub(start_pos, pos - 1)
  local num = tonumber(num_str)
  if not num then error("Invalid number in JSON at position " .. start_pos .. ": " .. num_str) end
  return num, pos
end

local function parse_array(str, pos)
  pos = pos + 1
  local arr = {}
  while true do
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) == "]" then return arr, pos + 1 end
    local val
    val, pos = parse_value(str, pos)
    table.insert(arr, val)
    pos = skip_whitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == "]" then return arr, pos + 1
    elseif c == "," then pos = pos + 1
    else error("Expected ',' or ']' in JSON array at position " .. pos) end
  end
end

local function parse_object(str, pos)
  pos = pos + 1
  local obj = {}
  while true do
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) == "}" then return obj, pos + 1 end
    if str:sub(pos, pos) ~= '"' then error("Expected string key in JSON object at position " .. pos) end
    local key
    key, pos = parse_string(str, pos)
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) ~= ":" then error("Expected ':' in JSON object at position " .. pos) end
    pos = pos + 1
    local val
    val, pos = parse_value(str, pos)
    obj[key] = val
    pos = skip_whitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == "}" then return obj, pos + 1
    elseif c == "," then pos = pos + 1
    else error("Expected ',' or '}' in JSON object at position " .. pos) end
  end
end

function parse_value(str, pos)
  pos = skip_whitespace(str, pos)
  local c = str:sub(pos, pos)
  if c == "{" then return parse_object(str, pos)
  elseif c == "[" then return parse_array(str, pos)
  elseif c == '"' then return parse_string(str, pos)
  elseif (c >= "0" and c <= "9") or c == "-" then return parse_number(str, pos)
  elseif str:sub(pos, pos + 3) == "true" then return true, pos + 4
  elseif str:sub(pos, pos + 4) == "false" then return false, pos + 5
  elseif str:sub(pos, pos + 3) == "null" then return nil, pos + 4
  else error("Unexpected character in JSON at position " .. pos .. ": " .. tostring(c)) end
end

function json.decode(str)
  if not str or str == "" then return nil end
  local ok, val = pcall(function()
    local v, _ = parse_value(str, 1)
    return v
  end)
  if not ok then return nil, val end
  return val
end

return json
