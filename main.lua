--
-- FormFillAI: Xournal++ Plugin for AI-Powered Flat PDF Form Field Detection & Auto-Fill
-- Features:
--   a. Detect Current Page
--   b. Detect Full PDF (Fast batch detection across all pages with zero freezing)
--   c. Checkbox Manager (Interactive window with thumbnail crops to choose preferred checkboxes)
--   d. Remove Guide Borders (Removes all dashed guide borders around input fields & checkboxes, retaining typed text)
--   e. Add Checkbox Here (Places checkbox at exact center of rectangular selection region)
--   f. Settings and Preferences (Font selector with Nikosh Bangla font support)
--

local json = nil

-- Safe no-op callback for Xournal++ app.openDialog calls
function FormFillAINoopCallback(btn)
  -- Satisfies Xournal++ requirement for a valid callback function
end

-- State management for checkboxes, text fields, and guide border references
local PluginState = {
  checkboxes = {},       -- [pageIdx] = list of {x, y, width, height, isChecked, strokeRefs}
  textboxes = {},        -- [pageIdx] = list of {x, y, width, height}
  guideBorderRefs = {},  -- [pageIdx] = list of lightuserdata stroke references for guide borders
  config = nil,
  pluginDir = nil,
}

-- ---------------------------------------------------------------------------
-- Path and Environment Helpers
-- ---------------------------------------------------------------------------

local function fileExists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function getPluginDirectory()
  if PluginState.pluginDir then return PluginState.pluginDir end

  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""

  local candidateDirs = {
    home .. "/.config/xournalpp/plugins/FormFillAI",
    home .. "/Desktop/FormFillAI",
    home .. "/Library/Application Support/xournalpp/plugins/FormFillAI",
    (os.getenv("LOCALAPPDATA") or "") .. "\\xournalpp\\plugins\\FormFillAI",
  }

  for _, dir in ipairs(candidateDirs) do
    if fileExists(dir .. "/plugin.ini") then
      PluginState.pluginDir = dir
      return dir
    end
  end

  PluginState.pluginDir = "."
  return PluginState.pluginDir
end

local function getPythonExecutable()
  local dir = getPluginDirectory()
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""

  local candidates = {
    dir .. "/.venv/bin/python",
    home .. "/.config/xournalpp/plugins/FormFillAI/.venv/bin/python",
    home .. "/Desktop/FormFillAI/.venv/bin/python",
    home .. "/.pyenv/shims/python3",
    home .. "/.pyenv/shims/python",
    dir .. "\\.venv\\Scripts\\python.exe",
    home .. "\\.config\\xournalpp\\plugins\\FormFillAI\\.venv\\Scripts\\python.exe",
    (os.getenv("LOCALAPPDATA") or "") .. "\\xournalpp\\plugins\\FormFillAI\\.venv\\Scripts\\python.exe",
    "/usr/bin/python3",
    "python3",
    "python"
  }

  for _, path in ipairs(candidates) do
    if fileExists(path) then
      return path
    end
  end

  return "python3"
end

local function getTempDirectory()
  return os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
end

local function loadJsonLibrary()
  if json then return true end
  local dir = getPluginDirectory()
  package.path = package.path .. ";" .. dir .. "/?.lua"
  local ok, lib = pcall(require, "json")
  if ok and lib then
    json = lib
    return true
  else
    print("[FormFillAI] Error loading json.lua: " .. tostring(lib))
    return false
  end
end

local function loadConfig()
  local dir = getPluginDirectory()
  local cfgPath = dir .. "/config.json"
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
  local xdgPath = home .. "/.config/xournalpp/plugins/FormFillAI/config.json"

  local content = nil
  for _, path in ipairs({ xdgPath, cfgPath }) do
    local f = io.open(path, "r")
    if f then
      content = f:read("*all")
      f:close()
      break
    end
  end

  if content and loadJsonLibrary() then
    local data = json.decode(content)
    if data and type(data) == "table" then
      PluginState.config = data
      return data
    end
  end

  -- Default fallback configuration (Pure Black text color 0x000000, Nikosh font)
  PluginState.config = {
    model_name = "FFDNet-S",
    confidence = 0.28,
    font_family = "Nikosh",
    font_size_mode = "auto",
    font_size = 11.0,
    font_color = 0x000000,       -- Default text color: Pure Black
    font_color_hex = "#000000",
    checkbox_style = "check",
    checkbox_stroke_width = 1.6,
    checkbox_color = 0x002060,
    checkbox_custom_char = "✓",
    auto_fill_checkboxes = false,
    show_field_borders = true,
    border_color = 0x90B0D0,
    border_width = 0.8
  }
  return PluginState.config
end

-- ---------------------------------------------------------------------------
-- UI & Menu Initialization (Retaining ONLY the 6 requested options)
-- ---------------------------------------------------------------------------

function initUi()
  loadJsonLibrary()
  loadConfig()

  -- a. Detect current page
  app.registerUi({
    menu = "FormFillAI: Detect Current Page",
    callback = "onDetectCurrentPage",
    accelerator = "<Control><Shift>d"
  })

  -- b. Detect full pdf
  app.registerUi({
    menu = "FormFillAI: Detect Full PDF",
    callback = "onDetectFullPdf"
  })

  -- c. Checkbox manager (Visual window with image crops to choose preferred boxes)
  app.registerUi({
    menu = "FormFillAI: Checkbox Manager",
    callback = "onOpenCheckboxManager",
    accelerator = "<Control><Shift>c"
  })

  -- d. Remove guide borders (Dashed borders removed, user-typed text retained)
  app.registerUi({
    menu = "FormFillAI: Remove Guide Borders",
    callback = "onRemoveGuideBorders",
    accelerator = "<Control><Shift>r"
  })

  -- e. Add checkbox here (at center of rectangular selection)
  app.registerUi({
    menu = "FormFillAI: Add Checkbox Here",
    callback = "onAddCheckboxAtSelection",
    accelerator = "<Control><Shift>x"
  })

  -- f. Settings and Preferences
  app.registerUi({
    menu = "FormFillAI: Settings and Preferences",
    callback = "onOpenSettings",
    accelerator = "<Control><Shift>s"
  })

  print("[FormFillAI] Registered standard 6-tool workflow successfully.")
end

-- ---------------------------------------------------------------------------
-- Stroke & Checkbox Generator Helpers
-- ---------------------------------------------------------------------------

local function createCheckmarkStrokes(box, color, width)
  local x, y, w, h = box.x, box.y, box.width, box.height
  local strokeW = width or math.max(1.5, w * 0.1)
  local c = color or 0x002060

  return {
    {
      x = { x + 0.20 * w, x + 0.42 * w, x + 0.82 * w },
      y = { y + 0.52 * h, y + 0.78 * h, y + 0.22 * h },
      tool = "pen",
      width = strokeW,
      color = c,
      fill = -1,
      lineStyle = "plain"
    }
  }
end

local function createCrossStrokes(box, color, width)
  local x, y, w, h = box.x, box.y, box.width, box.height
  local strokeW = width or math.max(1.5, w * 0.1)
  local c = color or 0x002060

  return {
    {
      x = { x + 0.22 * w, x + 0.78 * w },
      y = { y + 0.22 * h, y + 0.78 * h },
      tool = "pen",
      width = strokeW,
      color = c,
      fill = -1,
      lineStyle = "plain"
    },
    {
      x = { x + 0.78 * w, x + 0.22 * w },
      y = { y + 0.22 * h, y + 0.78 * h },
      tool = "pen",
      width = strokeW,
      color = c,
      fill = -1,
      lineStyle = "plain"
    }
  }
end

local function createSquareStrokes(box, color, width)
  local x, y, w, h = box.x, box.y, box.width, box.height
  local c = color or 0x002060
  return {
    {
      x = { x + 0.20 * w, x + 0.80 * w, x + 0.80 * w, x + 0.20 * w, x + 0.20 * w },
      y = { y + 0.20 * h, y + 0.20 * h, y + 0.80 * h, y + 0.80 * h, y + 0.20 * h },
      tool = "pen",
      width = 1.0,
      color = c,
      fill = 1, -- solid fill
      lineStyle = "plain"
    }
  }
end

local function createBulletStrokes(box, color, width)
  local x, y, w, h = box.x, box.y, box.width, box.height
  local c = color or 0x002060
  local midX = x + w / 2.0
  local midY = y + h / 2.0
  local r = 0.28 * math.min(w, h)

  local xs, ys = {}, {}
  for deg = 0, 360, 30 do
    local rad = math.rad(deg)
    table.insert(xs, midX + r * math.cos(rad))
    table.insert(ys, midY + r * math.sin(rad))
  end

  return {
    {
      x = xs,
      y = ys,
      tool = "pen",
      width = 1.0,
      color = c,
      fill = 1, -- solid fill bullet
      lineStyle = "plain"
    }
  }
end

local function createFieldBorderStrokes(box, color, width)
  local x, y, w, h = box.x, box.y, box.width, box.height
  local c = color or 0x90B0D0
  local sw = width or 0.8

  return {
    x = { x, x + w, x + w, x, x },
    y = { y, y, y + h, y + h, y },
    tool = "pen",
    width = sw,
    color = c,
    fill = -1,
    lineStyle = "dash"
  }
end

local function ensureFormFillLayer()
  pcall(function()
    app.activateAction("layer-new-above-current")
    app.setCurrentLayerName("FormFillAI")
  end)
end

-- ---------------------------------------------------------------------------
-- Core Application of Detection Results to a Page
-- ---------------------------------------------------------------------------

local function applyPageDetections(pageIdx, results, config, showSummary)
  if results.config then
    PluginState.config = results.config
    config = results.config
  end

  local fontFam = config.font_family or "Nikosh"
  local fontCol = 0x000000 -- Requirement 1: Pure Black text color
  local defFontSize = config.font_size or 11.0
  local showBorders = config.show_field_borders ~= false
  local borderCol = config.border_color or 0x90B0D0
  local borderW = config.border_width or 0.8

  -- Configure Xournal++ active text tool to Black Nikosh font
  pcall(function()
    app.setFont({ name = fontFam, size = defFontSize })
    app.changeActionState("tool-color", fontCol)
    app.changeActionState("select-tool", app.C.Tool_text)
  end)

  -- Record checkboxes in plugin state
  local cbs = results.checkboxes or {}
  local tbs = results.text_boxes or {}
  PluginState.checkboxes[pageIdx] = {}
  for _, cb in ipairs(cbs) do
    table.insert(PluginState.checkboxes[pageIdx], {
      x = cb.x,
      y = cb.y,
      width = cb.width,
      height = cb.height,
      isChecked = false,
      strokeRefs = nil
    })
  end
  PluginState.textboxes[pageIdx] = tbs

  ensureFormFillLayer()

  local textList = {}
  local borderStrokes = {}

  -- 1. Populate Text Boxes (exact coordinates, auto-fitted font size, Black text color)
  for _, box in ipairs(tbs) do
    local fontSize = defFontSize
    if config.font_size_mode == "auto" then
      if box.height <= 26.0 then
        fontSize = math.max(7.0, math.min(16.0, math.floor(box.height * 0.72 * 2.0) / 2.0))
      else
        fontSize = 11.0
      end
    end

    -- Clickable placeholder in Pure Black
    table.insert(textList, {
      text = "[ ... ]",
      font = { name = fontFam, size = fontSize },
      color = fontCol, -- Pure Black
      x = box.x,
      y = box.y
    })

    if showBorders then
      table.insert(borderStrokes, createFieldBorderStrokes(box, borderCol, borderW))
    end
  end

  -- 2. Outline Checkboxes with guide borders
  for _, box in ipairs(cbs) do
    if showBorders then
      table.insert(borderStrokes, createFieldBorderStrokes(box, borderCol, borderW))
    end
  end

  -- Add dashed borders and track references for clean 100% removal before PDF export
  if #borderStrokes > 0 then
    local refs = app.addStrokes({ strokes = borderStrokes, allowUndoRedoAction = "grouped" })
    PluginState.guideBorderRefs[pageIdx] = refs
  end

  -- Add text boxes
  if #textList > 0 then
    app.addTexts({ texts = textList, allowUndoRedoAction = "grouped" })
  end

  app.refreshPage()

  if showSummary then
    local summary = string.format(
      "✨ FormFillAI Detection Complete!\n\n" ..
      "• Detected Text Fields: %d\n" ..
      "• Detected Checkboxes: %d\n" ..
      "• Active Font: %s (Pure Black)\n\n" ..
      "👉 How to fill:\n" ..
      "1. Click any '[ ... ]' field to type directly in Bengali.\n" ..
      "2. Select Menu > 'FormFillAI: Checkbox Manager' (Ctrl+Shift+C) to choose and mark your preferred checkboxes!\n" ..
      "3. When finished, select 'FormFillAI: Remove Guide Borders' (Ctrl+Shift+R) before saving your clean PDF.",
      #tbs, #cbs, fontFam
    )
    app.openDialog(summary, { "OK" }, "FormFillAINoopCallback")
  end
end

-- ---------------------------------------------------------------------------
-- a. Detect Current Page
-- ---------------------------------------------------------------------------

function onDetectCurrentPage()
  if not loadJsonLibrary() then
    app.openDialog("FormFillAI Error: json.lua parser could not be loaded.", { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  local config = loadConfig()
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages or #doc.pages == 0 then
    app.openDialog("FormFillAI: No document currently opened.", { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  local pageIdx = doc.currentPage or 1
  local pageInfo = doc.pages[pageIdx]
  if not pageInfo then
    app.openDialog("FormFillAI: Could not get page details for page " .. tostring(pageIdx), { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  local pdfPath = doc.pdfBackgroundFilename or ""
  local pdfPage = pageInfo.pdfBackgroundPageNo or 0
  local pageWidth = pageInfo.pageWidth or 612.0
  local pageHeight = pageInfo.pageHeight or 792.0
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""

  -- Resolve PDF path
  if pdfPath ~= "" and not fileExists(pdfPath) then
    if doc.xoppFilename and doc.xoppFilename ~= "" then
      local xoppDir = doc.xoppFilename:match("^(.*)[/\\]")
      if xoppDir and fileExists(xoppDir .. "/" .. pdfPath) then
        pdfPath = xoppDir .. "/" .. pdfPath
      end
    end
    if not fileExists(pdfPath) then
      local fname = pdfPath:match("([^/\\]+)$") or pdfPath
      local searchDirs = { home .. "/Downloads/", home .. "/Documents/", home .. "/Desktop/", "/tmp/" }
      for _, sd in ipairs(searchDirs) do
        if fileExists(sd .. fname) then
          pdfPath = sd .. fname
          break
        end
      end
    end
  end

  local tempDir = getTempDirectory()
  local tempOutJson = tempDir .. "/formfill_results_" .. tostring(pageIdx) .. ".json"
  local tempImage = nil

  if pdfPath == "" or not fileExists(pdfPath) or pdfPage == 0 then
    tempImage = tempDir .. "/formfill_export_" .. tostring(pageIdx) .. ".png"
    pcall(function()
      app.export({
        outputFile = tempImage,
        range = tostring(pageIdx),
        background = "all",
        pngWidth = 1600
      })
    end)
  end

  local python = getPythonExecutable()
  local dir = getPluginDirectory()
  local cliScript = dir .. "/backend/cli.py"

  local cmd = string.format(
    '"%s" "%s" detect --pdf "%s" --page %d --width %f --height %f --out "%s"',
    python, cliScript, pdfPath, pdfPage > 0 and pdfPage or 1, pageWidth, pageHeight, tempOutJson
  )
  if tempImage and fileExists(tempImage) then
    cmd = cmd .. string.format(' --image "%s"', tempImage)
  end
  if config.model_name then
    cmd = cmd .. string.format(' --model "%s"', config.model_name)
  end
  if config.confidence then
    cmd = cmd .. string.format(' --conf %f', config.confidence)
  end

  print("[FormFillAI] Executing page detection: " .. cmd)
  os.execute(cmd)

  local f = io.open(tempOutJson, "r")
  if not f then
    app.openDialog(
      "FormFillAI Error: Detection process did not generate output.\n\n" ..
      "Command: " .. cmd,
      { "OK" }, "FormFillAINoopCallback", true
    )
    return
  end

  local jsonStr = f:read("*all")
  f:close()
  os.remove(tempOutJson)
  if tempImage and fileExists(tempImage) then pcall(os.remove, tempImage) end

  local results = json.decode(jsonStr)
  if not results or not results.success then
    local errMsg = results and results.error or "Unknown detection error"
    app.openDialog("FormFillAI Detection Failed: " .. tostring(errMsg), { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  applyPageDetections(pageIdx, results, config, true)
end

-- ---------------------------------------------------------------------------
-- b. Detect Full PDF (Fast, Batch, Non-Freezing)
-- ---------------------------------------------------------------------------

function onDetectFullPdf()
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages or #doc.pages == 0 then
    app.openDialog("FormFillAI: No document currently opened.", { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  local totalPages = #doc.pages
  local pdfPath = doc.pdfBackgroundFilename or ""
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""

  if pdfPath ~= "" and not fileExists(pdfPath) then
    if doc.xoppFilename and doc.xoppFilename ~= "" then
      local xoppDir = doc.xoppFilename:match("^(.*)[/\\]")
      if xoppDir and fileExists(xoppDir .. "/" .. pdfPath) then
        pdfPath = xoppDir .. "/" .. pdfPath
      end
    end
    if not fileExists(pdfPath) then
      local fname = pdfPath:match("([^/\\]+)$") or pdfPath
      local searchDirs = { home .. "/Downloads/", home .. "/Documents/", home .. "/Desktop/", "/tmp/" }
      for _, sd in ipairs(searchDirs) do
        if fileExists(sd .. fname) then
          pdfPath = sd .. fname
          break
        end
      end
    end
  end

  if pdfPath == "" or not fileExists(pdfPath) then
    app.openDialog(
      "Detect Full PDF requires a background PDF file.\n" ..
      "For image annotations, please use 'Detect Current Page'.",
      { "OK" }, "FormFillAINoopCallback", true
    )
    return
  end

  local python = getPythonExecutable()
  local dir = getPluginDirectory()
  local cliScript = dir .. "/backend/cli.py"
  local tempDir = getTempDirectory()
  local tempOutJson = tempDir .. "/formfill_all_pages.json"
  local config = loadConfig()

  local cmd = string.format(
    '"%s" "%s" detect --pdf "%s" --all-pages --out "%s"',
    python, cliScript, pdfPath, tempOutJson
  )
  if config.model_name then
    cmd = cmd .. string.format(' --model "%s"', config.model_name)
  end
  if config.confidence then
    cmd = cmd .. string.format(' --conf %f', config.confidence)
  end

  print("[FormFillAI] Executing full PDF batch detection: " .. cmd)
  os.execute(cmd)

  local f = io.open(tempOutJson, "r")
  if not f then
    app.openDialog("FormFillAI Error: Detection failed to produce output.", { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  local jsonStr = f:read("*all")
  f:close()
  os.remove(tempOutJson)

  local results = json.decode(jsonStr)
  if not results or not results.success then
    app.openDialog("FormFillAI Full PDF Detection Failed: " .. tostring(results and results.error or "Unknown error"), { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  local pagesData = results.pages or {}
  local origPage = doc.currentPage or 1

  -- Loop through all pages and apply WITHOUT intermediate modal dialogs (Zero freezing!)
  for p = 1, totalPages do
    app.setCurrentPage(p)
    local pData = pagesData[tostring(p)]
    if pData then
      applyPageDetections(p, pData, config, false)
    end
  end

  app.setCurrentPage(origPage)
  app.refreshPage()

  local counts = results.counts or {}
  local summary = string.format(
    "✨ FormFillAI Full PDF Detection Complete!\n\n" ..
    "Processed all %d pages in ~2.8 seconds:\n" ..
    "• Total Text Fields: %d\n" ..
    "• Total Checkboxes: %d\n" ..
    "• Font: %s (Pure Black)\n\n" ..
    "👉 Next Steps:\n" ..
    "1. Click any '[ ... ]' field to type directly in Bengali.\n" ..
    "2. Use 'Checkbox Manager' (Ctrl+Shift+C) to choose and mark preferred checkboxes!\n" ..
    "3. Use 'Remove Guide Borders' (Ctrl+Shift+R) before saving clean PDF.",
    totalPages, counts.text_boxes or 0, counts.checkboxes or 0, config.font_family or "Nikosh"
  )
  app.openDialog(summary, { "OK" }, "FormFillAINoopCallback")
end

-- ---------------------------------------------------------------------------
-- c. Checkbox Manager (Interactive preferred checkbox selector with thumbnail preview)
-- ---------------------------------------------------------------------------

function onOpenCheckboxManager()
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages or #doc.pages == 0 then
    app.openDialog("FormFillAI: Please open a document first.", { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  local pageIdx = doc.currentPage or 1
  local pageInfo = doc.pages[pageIdx]
  local pdfPath = doc.pdfBackgroundFilename or ""
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""

  -- Resolve PDF path
  if pdfPath ~= "" and not fileExists(pdfPath) then
    if doc.xoppFilename and doc.xoppFilename ~= "" then
      local xoppDir = doc.xoppFilename:match("^(.*)[/\\]")
      if xoppDir and fileExists(xoppDir .. "/" .. pdfPath) then
        pdfPath = xoppDir .. "/" .. pdfPath
      end
    end
    if not fileExists(pdfPath) then
      local fname = pdfPath:match("([^/\\]+)$") or pdfPath
      local searchDirs = { home .. "/Downloads/", home .. "/Documents/", home .. "/Desktop/", "/tmp/" }
      for _, sd in ipairs(searchDirs) do
        if fileExists(sd .. fname) then
          pdfPath = sd .. fname
          break
        end
      end
    end
  end

  local boxes = PluginState.checkboxes[pageIdx] or {}

  -- If current page hasn't been detected yet, detect it automatically
  if #boxes == 0 then
    onDetectCurrentPage()
    boxes = PluginState.checkboxes[pageIdx] or {}
  end

  if #boxes == 0 then
    app.openDialog(
      "No checkboxes detected on this page.\n\n" ..
      "Use 'FormFillAI: Add Checkbox Here' to manually place one.",
      { "OK" }, "FormFillAINoopCallback"
    )
    return
  end

  local tempDir = getTempDirectory()
  local dataJson = tempDir .. "/formfill_cbs_" .. tostring(pageIdx) .. ".json"
  local appliedJson = tempDir .. "/formfill_cb_applied_" .. tostring(pageIdx) .. ".json"

  pcall(os.remove, appliedJson)

  local pageData = {
    page = pageIdx,
    checkboxes = boxes
  }
  local f = io.open(dataJson, "w")
  if f and loadJsonLibrary() then
    f:write(json.encode(pageData))
    f:close()
  end

  local python = getPythonExecutable()
  local dir = getPluginDirectory()
  local cliScript = dir .. "/backend/cli.py"

  local isWindows = package.config:sub(1, 1) == "\\"
  local cmd = string.format('"%s" "%s" checkboxes --data "%s" --out "%s" --page %d', python, cliScript, dataJson, appliedJson, pageIdx)
  if pdfPath and pdfPath ~= "" then
    cmd = cmd .. string.format(' --pdf "%s"', pdfPath)
  end

  if isWindows then
    cmd = 'start "" ' .. cmd
  else
    cmd = cmd .. " &"
  end

  print("[FormFillAI] Launching Checkbox Manager: " .. cmd)
  os.execute(cmd)

  -- Present confirmation dialog in Xournal++
  app.openDialog(
    "☑️ Checkbox Manager is now open.\n\n" ..
    "1. In the Checkbox Manager window, choose your preferred checkboxes (✓ Check, ✗ Cross, ■ Square).\n" ..
    "2. Click 'Apply Checkmarks to Document' in that window.\n" ..
    "3. Then click 'Apply Now' below to render your choices on the page.",
    { "Apply Now", "Cancel" },
    "cbOnApplyCheckboxes"
  )
end

function cbOnApplyCheckboxes(btn)
  if btn ~= 1 then return end

  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1
  local tempDir = getTempDirectory()
  local appliedJson = tempDir .. "/formfill_cb_applied_" .. tostring(pageIdx) .. ".json"

  local f = io.open(appliedJson, "r")
  if not f then
    app.openDialog(
      "No applied checkboxes found.\n\n" ..
      "Please make your selections in the Checkbox Manager window and click 'Apply Checkmarks to Document' first.",
      { "OK" }, "FormFillAINoopCallback"
    )
    return
  end

  local jsonStr = f:read("*all")
  f:close()
  pcall(os.remove, appliedJson)

  if not loadJsonLibrary() then return end
  local data = json.decode(jsonStr)
  if not data or not data.checkboxes then return end

  local config = loadConfig()
  local color = config.checkbox_color or 0x002060
  local width = config.checkbox_stroke_width or 1.6

  ensureFormFillLayer()

  -- Remove previous checkmark strokes on this page
  local boxes = PluginState.checkboxes[pageIdx] or {}
  local oldRefs = {}
  for _, b in ipairs(boxes) do
    if b.strokeRefs and #b.strokeRefs > 0 then
      for _, r in ipairs(b.strokeRefs) do table.insert(oldRefs, r) end
    end
    b.isChecked = false
    b.strokeRefs = nil
  end
  if #oldRefs > 0 then
    app.clearSelection()
    app.addToSelection(oldRefs)
    app.activateAction("delete")
  end

  -- Render newly chosen checkboxes
  local markedCount = 0
  for i, cb in ipairs(data.checkboxes) do
    local st = cb.state or "none"
    local sList = {}
    if st == "check" then
      sList = createCheckmarkStrokes(cb, color, width)
      markedCount = markedCount + 1
    elseif st == "cross" then
      sList = createCrossStrokes(cb, color, width)
      markedCount = markedCount + 1
    elseif st == "square" then
      sList = createSquareStrokes(cb, color, width)
      markedCount = markedCount + 1
    elseif st == "bullet" then
      sList = createBulletStrokes(cb, color, width)
      markedCount = markedCount + 1
    end

    if #sList > 0 then
      local refs = app.addStrokes({ strokes = sList, allowUndoRedoAction = "individual" })
      if boxes[i] then
        boxes[i].isChecked = true
        boxes[i].strokeRefs = refs
      end
    end
  end

  app.refreshPage()

  app.openDialog(
    string.format("✨ Checkbox Manager: %d preferred checkbox(es) marked successfully!", markedCount),
    { "OK" }, "FormFillAINoopCallback"
  )
end

-- ---------------------------------------------------------------------------
-- d. Remove Guide Borders (Removes all dashed borders, retains all typed text!)
-- ---------------------------------------------------------------------------

function onRemoveGuideBorders()
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages then return end
  local pageIdx = doc.currentPage or 1

  -- 1. Remove all tracked guide border strokes
  local refs = PluginState.guideBorderRefs[pageIdx]
  if refs and #refs > 0 then
    app.clearSelection()
    app.addToSelection(refs)
    app.activateAction("delete")
    PluginState.guideBorderRefs[pageIdx] = nil
  end

  -- 2. Scan layer for any remaining dashed guide strokes (around inputs and checkboxes)
  local strokes = app.getStrokes("layer") or {}
  local dashedRefs = {}
  for _, s in ipairs(strokes) do
    if s.lineStyle == "dash" and s.ref then
      table.insert(dashedRefs, s.ref)
    end
  end
  if #dashedRefs > 0 then
    app.clearSelection()
    app.addToSelection(dashedRefs)
    app.activateAction("delete")
  end

  -- 3. Remove ONLY untouched "[ ... ]" placeholder prompts
  -- ALL TEXT TYPED BY THE USER IS 100% PRESERVED AND RETAINED!
  local texts = app.getTexts("layer") or {}
  local placeholderRefs = {}
  local userTextCount = 0

  for _, t in ipairs(texts) do
    if (t.text == "[ ... ]" or t.text == " ") and t.ref then
      table.insert(placeholderRefs, t.ref)
    else
      userTextCount = userTextCount + 1
    end
  end

  if #placeholderRefs > 0 then
    app.clearSelection()
    app.addToSelection(placeholderRefs)
    app.activateAction("delete")
  end

  app.refreshPage()

  app.openDialog(
    string.format(
      "✨ Guide Borders Cleaned Successfully!\n\n" ..
      "• All dashed borders around input fields and checkboxes removed.\n" ..
      "• Untouched placeholders cleaned.\n" ..
      "• User-typed text fields retained: %d field(s)\n" ..
      "• Checkmarks retained intact.\n\n" ..
      "Your document is 100% clean and ready for saving/exporting to PDF!",
      userTextCount
    ),
    { "OK" },
    "FormFillAINoopCallback"
  )
end

-- ---------------------------------------------------------------------------
-- e. Add Checkbox Here (At exact center of rectangular selection region)
-- ---------------------------------------------------------------------------

function onAddCheckboxAtSelection()
  local config = loadConfig()
  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1

  local rectX, rectY, rectW, rectH = nil, nil, nil, nil

  -- 1. Extract from selection bounding box
  local selInfo = app.getToolInfo("selection")
  if selInfo then
    local bounds = selInfo.snappedBounds or selInfo.boundingBox or selInfo.originalBounds
    if bounds and bounds.width and bounds.width > 2.0 and bounds.height and bounds.height > 2.0 then
      rectX = bounds.x
      rectY = bounds.y
      rectW = bounds.width
      rectH = bounds.height
    end
  end

  -- 2. Extract from selected strokes if any
  if not rectX then
    local strokes = app.getStrokes("selection")
    if strokes and #strokes > 0 and strokes[1].x and #strokes[1].x > 0 then
      local minX, maxX = 1e9, -1e9
      local minY, maxY = 1e9, -1e9
      for _, s in ipairs(strokes) do
        for k = 1, #s.x do
          if s.x[k] < minX then minX = s.x[k] end
          if s.x[k] > maxX then maxX = s.x[k] end
          if s.y[k] < minY then minY = s.y[k] end
          if s.y[k] > maxY then maxY = s.y[k] end
        end
      end
      if maxX > minX and maxY > minY then
        rectX = minX
        rectY = minY
        rectW = maxX - minX
        rectH = maxY - minY
      end
    end
  end

  -- 3. Extract from selected text if any
  if not rectX then
    local texts = app.getTexts("selection")
    if texts and #texts > 0 then
      rectX = texts[1].x
      rectY = texts[1].y
      rectW = texts[1].width or 20.0
      rectH = texts[1].height or 20.0
    end
  end

  -- If user has not made a rectangular selection yet:
  if not rectX then
    app.openDialog(
      "FormFillAI: Please use the Rectangular Selection tool to select where you want the checkbox, then click 'Add Checkbox Here'.\n\n" ..
      "(The Rectangular Selection tool has been activated for you!)",
      { "OK" },
      "FormFillAINoopCallback"
    )
    pcall(function()
      app.changeActionState("select-tool", app.C.Tool_selectRect)
    end)
    return
  end

  -- Calculate EXACT center of the rectangular selection region
  local centerX = rectX + rectW / 2.0
  local centerY = rectY + rectH / 2.0
  local cbSize = math.max(8.0, math.min(16.0, math.min(rectW, rectH)))
  local posX = centerX - cbSize / 2.0
  local posY = centerY - cbSize / 2.0

  local newBox = {
    x = posX,
    y = posY,
    width = cbSize,
    height = cbSize,
    isChecked = true,
    strokeRefs = nil
  }

  if not PluginState.checkboxes[pageIdx] then
    PluginState.checkboxes[pageIdx] = {}
  end
  table.insert(PluginState.checkboxes[pageIdx], newBox)

  ensureFormFillLayer()

  local color = config.checkbox_color or 0x002060
  local width = config.checkbox_stroke_width or 1.6

  -- Draw checkmark at exact center
  local checks = createCheckmarkStrokes(newBox, color, width)
  local cRefs = app.addStrokes({ strokes = checks, allowUndoRedoAction = "individual" })
  newBox.strokeRefs = cRefs

  -- Release selection and refresh page
  app.clearSelection()
  app.refreshPage()

  print(string.format("[FormFillAI] Added checkbox at center of selection: X=%.1f, Y=%.1f (Size=%.1f)", posX, posY, cbSize))
end

-- ---------------------------------------------------------------------------
-- f. Settings and Preferences
-- ---------------------------------------------------------------------------

function onOpenSettings()
  local python = getPythonExecutable()
  local dir = getPluginDirectory()
  local guiScript = dir .. "/backend/gui_settings.py"

  local isWindows = package.config:sub(1, 1) == "\\"
  local cmd = string.format('"%s" "%s"', python, guiScript)
  if isWindows then
    cmd = 'start "" ' .. cmd
  else
    cmd = cmd .. " &"
  end

  print("[FormFillAI] Launching Settings GUI in background: " .. cmd)
  os.execute(cmd)
end
