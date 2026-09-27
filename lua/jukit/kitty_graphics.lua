local M = {}

local ESC = string.char(27)
local ST = ESC .. "\\"
local CHUNK_SIZE = 4096

local function command(control, payload)
  local keys = {}
  for key, _ in pairs(control) do
    keys[#keys + 1] = key
  end
  table.sort(keys)

  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = string.format("%s=%s", key, tostring(control[key]))
  end

  return ESC .. "_G" .. table.concat(parts, ",") .. ";" .. (payload or "") .. ST
end

local function send(content)
  if not vim.api.nvim_ui_send then
    error("vim-jukit Kitty-protocol graphics requires Neovim >= 0.12")
  end
  vim.api.nvim_ui_send(content)
end

function M.upload(path, image_id, cols, rows)
  image_id = assert(tonumber(image_id), "invalid Kitty image id")
  cols = assert(tonumber(cols), "invalid Kitty image width")
  rows = assert(tonumber(rows), "invalid Kitty image height")

  local file = assert(io.open(path, "rb"))
  local bytes = file:read("*a")
  file:close()

  if #bytes == 0 then
    error("cannot upload an empty PNG")
  end

  local encoded = vim.base64.encode(bytes)
  local offset = 1
  local first = true
  while offset <= #encoded do
    local last = math.min(offset + CHUNK_SIZE - 1, #encoded)
    local chunk = encoded:sub(offset, last)
    local more = last < #encoded and 1 or 0
    local control = { m = more }

    if first then
      control.a = "t"
      control.f = 100
      control.t = "d"
      control.i = image_id
      control.q = 2
      first = false
    end

    send(command(control, chunk))
    offset = last + 1
  end

  send(command({
    a = "p",
    U = 1,
    i = image_id,
    c = cols,
    r = rows,
    q = 2,
  }))

  return 1
end

return M
