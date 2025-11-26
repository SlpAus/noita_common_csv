---@class common_csv
local common_csv = {}

---@class parsed_csv
---@field _csv string
---@field _data table
---@field _lines table
local parsed_csv = {}
parsed_csv.__index = parsed_csv
function parsed_csv:__tostring()
  return self._csv
end

---@param csv_string string
---@param start_pos number
---@param finish_pos number
---@return string|nil
---@return number|nil
local function _next(csv_string, start_pos, finish_pos)
  if start_pos > finish_pos then
    return nil
  end

  local in_quotes = false
  local i = start_pos

  while i <= finish_pos do
    local byte = csv_string:byte(i)

    if byte == 34 --[[ '"' ]] then
      if i < finish_pos and csv_string:byte(i + 1) == 34 then
        i = i + 1
      else
        if in_quotes == true then
          return csv_string:sub(start_pos, i - 1), i + 2
        else
          in_quotes = true
          start_pos = i + 1
        end
      end
    elseif in_quotes == false and byte == 44 --[[ ',' ]] then
      return csv_string:sub(start_pos, i - 1), i + 1
    end
    i = i + 1
  end

  return nil
end

---@param csv_string string
---@return parsed_csv
function common_csv.parse(csv_string)
  local parser = setmetatable({}, parsed_csv)
  parser._csv = csv_string
  parser._data = {}
  parser._lines = {}

  local len = #csv_string
  if len == 0 then
    return parser
  end

  local pos = 1
  while pos <= len do
    local line_end_pos
    local next_line_start = csv_string:find('\n', pos)
    if next_line_start ~= nil then
      if csv_string:byte(next_line_start - 1) == 13 --[[ '\r' ]] then
        line_end_pos = next_line_start - 2
      else
        line_end_pos = next_line_start - 1
      end
    else
      line_end_pos = len
      next_line_start = len
    end

    if pos > line_end_pos then
      break
    end

    local key, value_start = _next(csv_string, pos, line_end_pos)
    if key ~= nil and key ~= '' then
      parser._data[key] = { value_start, line_end_pos }
    end

    table.insert(parser._lines, { pos, line_end_pos })

    pos = next_line_start + 1
  end

  return parser
end

---@param key string
---@return string[]|nil
function parsed_csv:query(key)
  local csv_string = self._csv
  local indices = self._data[key]

  if indices == nil then
    return nil
  end

  local current_pos, finish_pos = indices[1], indices[2]
  local results = {}

  local field
  while current_pos <= finish_pos do
    field, current_pos = _next(csv_string, current_pos, finish_pos)

    if field == nil then
      break
    end

    table.insert(results, field)
  end

  return results
end

---@param index number
---@return string[]|nil
function parsed_csv:line(index)
  local csv_string = self._csv
  local indices = self._lines[index]

  if indices == nil then
    return nil
  end

  local current_pos, finish_pos = indices[1], indices[2]
  local results = {}

  local field
  while current_pos <= finish_pos do
    field, current_pos = _next(csv_string, current_pos, finish_pos)

    if field == nil then
      break
    end

    table.insert(results, field)
  end

  return results
end

---@param line_array string[]
---@return string[] language_list
---@return number min_columns
function common_csv.parse_header_line(line_array)
  local language_list = {}

  local array_length = #line_array
  if array_length < 2 then
    return language_list, 1
  end

  for col = 2, array_length do
    local field = line_array[col]
    if field == "" then
      return language_list, col - 1
    end
    table.insert(language_list, field)
  end

  return language_list, array_length
end

---@param line_index number|nil
---@return string[] language_list
---@return number min_columns
function parsed_csv:parse_header(line_index)
  local line_data = self:line(line_index or 1)
  if line_data == nil then
    return {}, 1
  end

  return common_csv.parse_header_line(line_data)
end

---@param field string
---@return string|nil
local function _process_field(field)
  local pos = 1
  while true do
    local start_seq = field:find('"', pos, true)
    if start_seq == nil then
      break
    end

    local end_seq_pos = field:find('[^"]', start_seq + 1, true)

    if end_seq_pos == nil then
      if (#field - start_seq + 1) % 2 ~= 0 then
        return nil
      end
      break
    end

    local count = end_seq_pos - start_seq
    if count % 2 ~= 0 then
      return nil
    end

    pos = end_seq_pos + 1
  end

  if field:find(',') then
    return '"' .. field .. '"'
  end

  return field
end

---@param key string
---@param value string[]
---@param min_columns number|nil
---@return string|nil
function common_csv.build_line_kv(key, value, min_columns)
  min_columns = min_columns or 0

  local fields = {}

  local processed_field = _process_field(key)
  if processed_field == nil then
    return nil
  end
  table.insert(fields, processed_field)

  local column_count = 1
  for _, field in ipairs(value) do
    processed_field = _process_field(field)
    if processed_field == nil then
      return nil
    end
    table.insert(fields, processed_field)
    column_count = column_count + 1
  end

  if column_count < min_columns then
    table.insert(fields, string.rep(',', min_columns - column_count - 1))
  end

  table.insert(fields, "")

  return table.concat(fields, ",")
end

---@param value string[]
---@param min_columns number|nil
---@return string|nil
function common_csv.build_line_array(value, min_columns)
  min_columns = min_columns or 0

  local fields = {}

  local column_count = 0
  for _, field in ipairs(value) do
    local processed_field = _process_field(field)
    if processed_field == nil then
      return nil
    end
    table.insert(fields, processed_field)
    column_count = column_count + 1
  end

  if column_count == 0 then
    return nil
  end

  if column_count < min_columns then
    table.insert(fields, string.rep(',', min_columns - column_count - 1))
  end

  table.insert(fields, "")

  return table.concat(fields, ",")
end

---@param data_table table
---@param min_columns number|nil
---@return string
function common_csv.build_csv(data_table, min_columns)
  local lines = {}

  local array_keys = {}
  for index, value in ipairs(data_table) do
    array_keys[index] = true
    local line = common_csv.build_line_array(value, min_columns)
    if line ~= nil then
      table.insert(lines, line)
    end
  end
  for key, value in pairs(data_table) do
    if array_keys[key] ~= true then
      local line = common_csv.build_line_kv(key, value, min_columns)
      if line ~= nil then
        table.insert(lines, line)
      end
    end
  end
  table.insert(lines, "")
  return table.concat(lines, "\n")
end

---@param data_table table
---@param min_columns number|nil
function parsed_csv:append(data_table, min_columns)
  local old_csv = self._csv
  local end_pos = 0

  local line_count = #self._lines
  if line_count > 0 then
    end_pos = self._lines[line_count][2]
  end

  local new_parts = {}
  local current_offset
  if end_pos == 0 then
    current_offset = -1
  else
    new_parts[1] = ""
    current_offset = end_pos
  end

  local function _append_single_line(key_raw, line_str)
    table.insert(new_parts, line_str)

    local line_len = #line_str
    local line_start = current_offset + 2
    local line_end = current_offset + 1 + line_len

    if key_raw:find(',') == nil then
      if key_raw ~= '' then
        self._data[key_raw] = { line_start + #key_raw + 1, line_end }
      end
    else
      self._data[key_raw] = { line_start + #key_raw + 3, line_end }
    end

    table.insert(self._lines, { line_start, line_end })

    current_offset = line_end
  end

  local array_keys = {}
  for index, value in ipairs(data_table) do
    array_keys[index] = true
    local key = value[1]
    local line_str = common_csv.build_line_array(value, min_columns)
    if line_str ~= nil then
      _append_single_line(key, line_str)
    end
  end

  for key, value in pairs(data_table) do
    if not array_keys[key] then
      local line_str = common_csv.build_line_kv(key, value, min_columns)
      if line_str ~= nil then
        _append_single_line(key, line_str)
      end
    end
  end

  if new_parts[2] == nil then
    return
  end

  if end_pos ~= 0 then
    new_parts[1] = old_csv:sub(1, end_pos)
  end

  table.insert(new_parts, "")
  self._csv = table.concat(new_parts, '\n')
end

return common_csv
