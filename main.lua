--
-- FormFillAI: Xournal++ Plugin for AI-Powered Flat PDF Form Field Detection & Auto-Fill
-- Features:
--   1. FormFillAI: Detect Current Page (<Control><Shift>d)
--   2. FormFillAI: Detect Full PDF
--   3. FormFillAI: Add Checkbox Here (<Control><Shift>x)
--   4. FormFillAI: Settings and Preferences (<Control><Shift>s)
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
  textBoxRefs = {},      -- [pageIdx] = list of lightuserdata text references
  formLayers = {},       -- [pageIdx] = layerNr (integer index of dedicated FormFillAI layer)
  currentDocId = nil,    -- tracks current document to reset stale layer mapping
  config = nil,
  pluginDir = nil,
}

-- ---------------------------------------------------------------------------
-- Path and Environment Helpers (Multiplatform: Linux Native, Flatpak, Snap, macOS, Windows)
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

  -- 1. Try resolving directory directly from the loaded main.lua source path
  local src = debug.getinfo(1, "S")
  if src and src.source and src.source:sub(1, 1) == "@" then
    local path = src.source:sub(2)
    local dir = path:match("^(.*)[/\\]")
    if dir and fileExists(dir .. "/plugin.ini") then
      PluginState.pluginDir = dir
      return dir
    end
  end

  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""

  -- 2. Multiplatform & Multi-packaging candidates
  local candidateDirs = {
    -- Linux Native (RPM, DEB, Arch, Source)
    home .. "/.config/xournalpp/plugins/FormFillAI",
    -- Linux Flatpak sandbox
    home .. "/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/FormFillAI",
    -- Linux Snap sandbox
    home .. "/snap/xournalpp/current/.config/xournalpp/plugins/FormFillAI",
    home .. "/snap/xournalpp/common/.config/xournalpp/plugins/FormFillAI",
    -- macOS (DMG, Homebrew)
    home .. "/Library/Application Support/xournalpp/plugins/FormFillAI",
    -- Windows (EXE, Portable, LocalAppData & AppData)
    (os.getenv("LOCALAPPDATA") or "") .. "\\xournalpp\\plugins\\FormFillAI",
    (os.getenv("APPDATA") or "") .. "\\xournalpp\\plugins\\FormFillAI",
    -- Workspace fallback
    home .. "/Desktop/FormFillAI",
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
    -- Dedicated virtual environments
    dir .. "/.venv/bin/python",
    dir .. "/.venv/bin/python3",
    dir .. "\\.venv\\Scripts\\python.exe",
    home .. "/.config/xournalpp/plugins/FormFillAI/.venv/bin/python",
    home .. "/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/FormFillAI/.venv/bin/python",
    home .. "/Desktop/FormFillAI/.venv/bin/python",
    (os.getenv("LOCALAPPDATA") or "") .. "\\xournalpp\\plugins\\FormFillAI\\.venv\\Scripts\\python.exe",
    -- macOS Homebrew / Framework Python
    "/opt/homebrew/bin/python3",
    "/usr/local/bin/python3",
    "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
    -- Pyenv / Version managers
    home .. "/.pyenv/shims/python3",
    home .. "/.pyenv/shims/python",
    -- Linux / Unix standard paths
    "/usr/bin/python3",
    "/usr/bin/python",
    "python3",
    "python",
    "py -3",
    "py"
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
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""

  local candidateConfigs = {
    dir .. "/config.json",
    home .. "/.config/xournalpp/plugins/FormFillAI/config.json",
    home .. "/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/FormFillAI/config.json",
    home .. "/Library/Application Support/xournalpp/plugins/FormFillAI/config.json",
    (os.getenv("LOCALAPPDATA") or "") .. "\\xournalpp\\plugins\\FormFillAI\\config.json"
  }

  local content = nil
  for _, path in ipairs(candidateConfigs) do
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

  -- Default fallback configuration (Pure Black text & shapes 0x000000, Nikosh font)
  PluginState.config = {
    model_name = "FFDNet-S",
    confidence = 0.28,
    font_family = "Nikosh",
    font_size_mode = "auto",
    font_size = 11.0,
    font_color = 0x000000,       -- Pure Black text
    font_color_hex = "#000000",
    checkbox_style = "check",
    checkbox_stroke_width = 1.6,
    checkbox_color = 0x000000,   -- Pure Black shapes
    checkbox_color_hex = "#000000",
    checkbox_custom_char = "✓",
    auto_fill_checkboxes = false,
    show_field_borders = false,  -- No dashed borders
    border_color = 0x90B0D0,
    border_width = 0.8
  }
  return PluginState.config
end

-- ---------------------------------------------------------------------------
-- UI & Menu Initialization (4 Core Actions)
-- ---------------------------------------------------------------------------

function initUi()
  loadJsonLibrary()
  loadConfig()

  -- 1. Detect current page
  app.registerUi({
    menu = "FormFillAI: Detect Current Page",
    callback = "onDetectCurrentPage",
    accelerator = "<Control><Shift>d"
  })

  -- 2. Detect full pdf
  app.registerUi({
    menu = "FormFillAI: Detect Full PDF",
    callback = "onDetectFullPdf"
  })

  -- 3. Add checkbox here (Choose shape: Check ✓, Cross ✗, Square ■, Bullet ●, Box ☐; drops & resizes with handles)
  app.registerUi({
    menu = "FormFillAI: Add Checkbox Here",
    callback = "onAddCheckboxPrompt",
    accelerator = "<Control><Shift>x"
  })

  -- 4. Settings and Preferences
  app.registerUi({
    menu = "FormFillAI: Settings and Preferences",
    callback = "onOpenSettings",
    accelerator = "<Control><Shift>s"
  })

  print("[FormFillAI] Registered standard 4-tool workflow successfully.")
end

-- ---------------------------------------------------------------------------
-- Stroke & Shape Generator Helpers (Pure Black Color 0x000000)
-- ---------------------------------------------------------------------------

local function createCheckmarkStrokes(box, color, width)
  local x, y, w, h = box.x, box.y, box.width, box.height
  local strokeW = width or math.max(1.5, w * 0.1)
  local c = color or 0x000000 -- Pure Black

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
  local c = color or 0x000000 -- Pure Black

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
  local c = color or 0x000000 -- Pure Black
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
  local c = color or 0x000000 -- Pure Black
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

local function createEmptyBoxStrokes(box, color, width)
  local x, y, w, h = box.x, box.y, box.width, box.height
  local c = color or 0x000000 -- Pure Black
  local sw = width or 1.2

  return {
    {
      x = { x + 0.15 * w, x + 0.85 * w, x + 0.85 * w, x + 0.15 * w, x + 0.15 * w },
      y = { y + 0.15 * h, y + 0.15 * h, y + 0.85 * h, y + 0.85 * h, y + 0.15 * h },
      tool = "pen",
      width = sw,
      color = c,
      fill = -1,
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

local function ensureFormFillLayer(pageIdx)
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages then return end

  pageIdx = pageIdx or doc.currentPage or 1
  local pageInfo = doc.pages[pageIdx]
  if not pageInfo then return end

  -- Invalidate stale page layer mappings if document has changed
  local docId = (doc.pdfBackgroundFilename or "") .. "::" .. (doc.xoppFilename or "")
  if PluginState.currentDocId ~= docId then
    PluginState.currentDocId = docId
    PluginState.formLayers = {}
    PluginState.checkboxes = {}
    PluginState.textboxes = {}
    PluginState.textBoxRefs = {}
  end

  local totalLayers = pageInfo.layers and #pageInfo.layers or 1
  local currentLayer = pageInfo.currentLayer or 1

  -- Check if we already have a valid FormFillAI layer tracked for this page
  local targetLayer = PluginState.formLayers[pageIdx]
  if targetLayer and targetLayer >= 1 and targetLayer <= totalLayers then
    -- Dedicated FormFillAI layer already exists! Switch to it if not active
    if currentLayer ~= targetLayer then
      pcall(function()
        app.setCurrentLayer(targetLayer, false)
      end)
    end
    return targetLayer
  end

  -- No dedicated FormFillAI layer exists on this page yet: create it ONCE
  pcall(function()
    app.activateAction("layer-new-above-current")
    app.setCurrentLayerName("FormFillAI")
  end)

  local updatedDoc = app.getDocumentStructure()
  local updatedPage = updatedDoc and updatedDoc.pages and updatedDoc.pages[pageIdx]
  local newLayerNr = updatedPage and updatedPage.currentLayer or (totalLayers + 1)
  PluginState.formLayers[pageIdx] = newLayerNr
  return newLayerNr
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
  local fontCol = 0x000000 -- Requirement: Pure Black text color
  local defFontSize = config.font_size or 11.0
  local showBorders = config.show_field_borders ~= false
  local borderCol = config.border_color or 0x90B0D0
  local borderW = config.border_width or 0.8

  -- Configure Xournal++ active text tool to Pure Black Nikosh font
  pcall(function()
    app.setFont({ name = fontFam, size = defFontSize })
    app.changeActionState("tool-color", fontCol)
    app.changeActionState("select-tool", app.C.Tool_text)
  end)

  -- Preserve any manually added checkboxes on this page
  local existingCbs = PluginState.checkboxes[pageIdx] or {}
  local manualCbs = {}
  for _, cb in ipairs(existingCbs) do
    if cb.strokeRefs then
      table.insert(manualCbs, cb)
    end
  end
  PluginState.checkboxes[pageIdx] = manualCbs

  -- Record newly detected checkboxes in plugin state
  local cbs = results.checkboxes or {}
  local tbs = results.text_boxes or {}
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

  -- Ensure we are on the single dedicated FormFillAI layer
  ensureFormFillLayer(pageIdx)

  -- Check existing texts on layer to avoid placing overlays over already-typed fields
  local existingTexts = app.getTexts("layer") or {}
  local function isFieldAlreadyFilled(box)
    for _, t in ipairs(existingTexts) do
      local str = t.text or ""
      local meaningful = str:gsub("\xc2\xa0", ""):gsub("%s", "")
      if meaningful ~= "" and meaningful ~= "[ ... ]" and meaningful ~= "..." then
        if t.x >= box.x - 5 and t.x <= box.x + box.width and
           t.y >= box.y - 5 and t.y <= box.y + box.height then
          return true
        end
      end
    end
    return false
  end

  -- Clean up previously placed empty placeholder overlays on this layer so they don't duplicate on re-detection
  local oldEmptyRefs = {}
  for _, t in ipairs(existingTexts) do
    local str = t.text or ""
    local meaningful = str:gsub("\xc2\xa0", ""):gsub("%s", "")
    if (meaningful == "" or meaningful == "[ ... ]" or meaningful == "...") and t.ref then
      table.insert(oldEmptyRefs, t.ref)
    end
  end
  if #oldEmptyRefs > 0 then
    app.clearSelection()
    app.addToSelection(oldEmptyRefs)
    app.activateAction("delete")
  end

  -- 1. Create bounded fillable text box overlays matching exact field dimensions
  local textList = {}
  for _, box in ipairs(tbs) do
    if not isFieldAlreadyFilled(box) then
      local fSize = defFontSize
      if config.font_size_mode == "auto" or not config.font_size then
        fSize = math.min(11.0, math.max(8.0, box.height * 0.85))
      end

      -- Non-breaking space buffer spanning field width:
      -- Makes the entire field boundary clickable in Xournal++ while remaining visually invisible
      local numSpaces = math.max(2, math.floor(box.width / 4.0))
      local nbspText = string.rep("\xc2\xa0", numSpaces)

      table.insert(textList, {
        text = nbspText,
        font = { name = fontFam, size = fSize },
        color = fontCol,
        x = box.x,
        y = box.y,
        wrap = box.width
      })
    end
  end

  if #textList > 0 then
    local textRefs = app.addTexts({
      texts = textList,
      allowUndoRedoAction = "grouped"
    })
    if not PluginState.textBoxRefs then PluginState.textBoxRefs = {} end
    PluginState.textBoxRefs[pageIdx] = textRefs
  end

  -- Return active tool to text tool so fields are immediately clickable
  pcall(function()
    app.changeActionState("select-tool", app.C.Tool_text)
  end)

  -- 2. Do NOT draw dashed guide borders (pure fillable text fields as requested)
  app.refreshPage()

  if showSummary then
    local count = #tbs
    local msg
    if count == 0 then
      msg = "FormFillAI: No form fields detected on this page."
    elseif count == 1 then
      msg = "FormFillAI: 1 form field ready to fill."
    else
      msg = string.format("FormFillAI: %d form fields ready to fill.", count)
    end
    app.openDialog(msg, { "OK" }, "FormFillAINoopCallback")
  end
end

-- ---------------------------------------------------------------------------
-- 1. Detect Current Page
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
-- 2. Detect Full PDF (Fast, Batch, Non-Freezing)
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
  if PluginState.formLayers and PluginState.formLayers[origPage] then
    pcall(function()
      app.setCurrentLayer(PluginState.formLayers[origPage], false)
    end)
  end
  pcall(function()
    app.changeActionState("select-tool", app.C.Tool_text)
  end)
  app.refreshPage()

  local counts = results.counts or {}
  local count = counts.text_boxes or 0
  local msg = string.format(
    "FormFillAI: %d form field%s ready across %d page%s.",
    count, count == 1 and "" or "s",
    totalPages, totalPages == 1 and "" or "s"
  )
  app.openDialog(msg, { "OK" }, "FormFillAINoopCallback")
end

-- ---------------------------------------------------------------------------
-- 3. Add Checkbox Here (Choose shape: drops shape on PDF with handles to resize & reposition)
-- ---------------------------------------------------------------------------

function onAddCheckboxPrompt()
  app.openDialog(
    "Select shape to insert:",
    { "✓ Check", "✗ Cross", "■ Square", "● Bullet", "☐ Box" },
    "cbOnChooseCheckboxShape"
  )
end

function cbOnChooseCheckboxShape(btn)
  if not btn or btn < 1 or btn > 5 then return end

  local shapeNames = { "check", "cross", "square", "bullet", "box" }
  local chosenShape = shapeNames[btn] or "check"

  local config = loadConfig()
  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1
  local pageInfo = doc and doc.pages[pageIdx]
  local pageWidth = pageInfo and pageInfo.pageWidth or 612.0
  local pageHeight = pageInfo and pageInfo.pageHeight or 792.0

  local size = 18.0
  local posX = (pageWidth - size) / 2.0
  local posY = (pageHeight - size) / 2.5

  local newBox = {
    x = posX,
    y = posY,
    width = size,
    height = size,
    isChecked = true,
    strokeRefs = nil
  }

  if not PluginState.checkboxes[pageIdx] then
    PluginState.checkboxes[pageIdx] = {}
  end
  table.insert(PluginState.checkboxes[pageIdx], newBox)

  ensureFormFillLayer(pageIdx)

  local color = 0x000000 -- Requirement 2: Pure Black for all shapes
  local width = config.checkbox_stroke_width or 1.6

  local strokes = {}
  if chosenShape == "cross" then
    strokes = createCrossStrokes(newBox, color, width)
  elseif chosenShape == "square" then
    strokes = createSquareStrokes(newBox, color, width)
  elseif chosenShape == "bullet" then
    strokes = createBulletStrokes(newBox, color, width)
  elseif chosenShape == "box" then
    strokes = createEmptyBoxStrokes(newBox, color, width)
  else
    strokes = createCheckmarkStrokes(newBox, color, width)
  end

  local refs = app.addStrokes({ strokes = strokes, allowUndoRedoAction = "individual" })
  newBox.strokeRefs = refs

  -- Activate Selection Tool FIRST so that the selection model is active and ready
  pcall(function()
    app.changeActionState("select-tool", app.C.Tool_selectRect)
  end)

  -- Immediately select the new shape so 8 resize/drag handles appear on screen
  app.clearSelection()
  if refs and #refs > 0 then
    app.addToSelection(refs)
  end

  app.refreshPage()
end

-- ---------------------------------------------------------------------------
-- 5. Settings and Preferences
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
