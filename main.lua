--
-- FormFillAI: Xournal++ Plugin for AI-Powered Flat PDF Form Field Detection & Auto-Fill
-- Features:
--   1. Auto-detect flat PDF form fields using FFDNet-S and FFDNet-L AI models.
--   2. Overlay text boxes matching exact form field width and height (non-movable, non-resizable in Text mode).
--   3. Delete overlays, add manual overlays, choose fonts (full system fonts + prioritized Bangla fonts like Nikosh/Kalpurush), font size, and font colors.
--   4. Fill checkboxes with custom shapes (checked ✓, crossed ✗, square ■, bullet ●, custom symbol).
--   5. Manually add and check checkboxes when AI misses any.
--   6. Settings GUI dialog (non-blocking) and persistent configuration.
--

local json = nil

-- Safe no-op callback for Xournal++ app.openDialog calls
function FormFillAINoopCallback(btn)
  -- Satisfies Xournal++ requirement for a valid callback function
end

-- State management for checkboxes and form fields per page
local PluginState = {
  checkboxes = {}, -- [pageIdx] = list of {x, y, width, height, isChecked, checkStyle}
  textboxes = {},  -- [pageIdx] = list of {x, y, width, height}
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
    -- Linux / macOS XDG path
    home .. "/.config/xournalpp/plugins/FormFillAI",
    -- Workspace path (for development and direct execution)
    home .. "/Desktop/FormFillAI",
    -- macOS Application Support
    home .. "/Library/Application Support/xournalpp/plugins/FormFillAI",
    -- Windows LocalAppData
    (os.getenv("LOCALAPPDATA") or "") .. "\\xournalpp\\plugins\\FormFillAI",
  }

  for _, dir in ipairs(candidateDirs) do
    if fileExists(dir .. "/plugin.ini") then
      PluginState.pluginDir = dir
      return dir
    end
  end

  -- Fallback to current directory
  PluginState.pluginDir = "."
  return PluginState.pluginDir
end

local function getPythonExecutable()
  local dir = getPluginDirectory()
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""

  local candidates = {
    -- Dedicated virtual environments inside plugin directories
    dir .. "/.venv/bin/python",
    home .. "/.config/xournalpp/plugins/FormFillAI/.venv/bin/python",
    home .. "/Desktop/FormFillAI/.venv/bin/python",
    -- Pyenv shims
    home .. "/.pyenv/shims/python3",
    home .. "/.pyenv/shims/python",
    -- Windows virtual environments
    dir .. "\\.venv\\Scripts\\python.exe",
    home .. "\\.config\\xournalpp\\plugins\\FormFillAI\\.venv\\Scripts\\python.exe",
    (os.getenv("LOCALAPPDATA") or "") .. "\\xournalpp\\plugins\\FormFillAI\\.venv\\Scripts\\python.exe",
    -- System fallbacks
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

  -- Default fallback configuration (prioritizing Nikosh for official Bangla forms)
  PluginState.config = {
    model_name = "FFDNet-S",
    confidence = 0.28,
    font_family = "Nikosh",
    font_size_mode = "auto",
    font_size = 11.0,
    font_color = 0x000000,
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
-- UI & Menu Initialization
-- ---------------------------------------------------------------------------

function initUi()
  loadJsonLibrary()
  loadConfig()

  -- Register primary actions in Menu: Plugin > FormFillAI
  app.registerUi({
    menu = "FormFillAI: Detect Form Fields (Current Page)",
    callback = "onDetectCurrentPage",
    accelerator = "<Control><Shift>d"
  })

  app.registerUi({
    menu = "FormFillAI: Detect Form Fields (All Pages)",
    callback = "onDetectAllPages"
  })

  app.registerUi({
    menu = "FormFillAI: Fill All Checkboxes (Checked ✓)",
    callback = "onFillCheckboxesCheck",
    accelerator = "<Control><Shift>c"
  })

  app.registerUi({
    menu = "FormFillAI: Fill All Checkboxes (Crossed ✗)",
    callback = "onFillCheckboxesCross"
  })

  app.registerUi({
    menu = "FormFillAI: Fill All Checkboxes (Solid Square ■)",
    callback = "onFillCheckboxesSquare"
  })

  app.registerUi({
    menu = "FormFillAI: Fill All Checkboxes (Bullet Dot ●)",
    callback = "onFillCheckboxesBullet"
  })

  app.registerUi({
    menu = "FormFillAI: Toggle / Check Nearest Checkbox",
    callback = "onToggleNearestCheckbox",
    accelerator = "<Control><Shift>t"
  })

  app.registerUi({
    menu = "FormFillAI: Add Checkbox Here (at Selection / Center)",
    callback = "onAddManualCheckbox"
  })

  app.registerUi({
    menu = "FormFillAI: Add Text Field Overlay (at Selection / Center)",
    callback = "onAddManualTextField"
  })

  app.registerUi({
    menu = "FormFillAI: Delete Selected Overlay",
    callback = "onDeleteSelectedOverlay"
  })

  app.registerUi({
    menu = "FormFillAI: Clear All Form Overlays (Current Page)",
    callback = "onClearOverlaysCurrentPage"
  })

  app.registerUi({
    menu = "FormFillAI: Settings & Preferences...",
    callback = "onOpenSettings",
    accelerator = "<Control><Shift>s"
  })

  print("[FormFillAI] Plugin registered successfully.")
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

-- ---------------------------------------------------------------------------
-- Dedicated FormFillAI Layer Management
-- ---------------------------------------------------------------------------

local function ensureFormFillLayer()
  pcall(function()
    app.activateAction("layer-new-above-current")
    app.setCurrentLayerName("FormFillAI")
  end)
end

-- ---------------------------------------------------------------------------
-- Auto-Detect Form Fields Implementation
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

  -- Resolve PDF path if relative or missing
  if pdfPath ~= "" and not fileExists(pdfPath) then
    -- Try relative to xoppFilename directory
    if doc.xoppFilename and doc.xoppFilename ~= "" then
      local xoppDir = doc.xoppFilename:match("^(.*)[/\\]")
      if xoppDir and fileExists(xoppDir .. "/" .. pdfPath) then
        pdfPath = xoppDir .. "/" .. pdfPath
      end
    end
    -- Try common search folders
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

  -- If PDF path is still not found or invalid or pdfPage == 0, export the page to PNG
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

  -- Build CLI command
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

  print("[FormFillAI] Executing detection: " .. cmd)
  local exitCode = os.execute(cmd)

  -- Read result JSON
  local f = io.open(tempOutJson, "r")
  if not f then
    app.openDialog(
      "FormFillAI Error: Detection process did not generate output.\n\n" ..
      "Command executed:\n" .. cmd .. "\n\n" ..
      "Please verify your Python environment:\n" ..
      python .. " " .. cliScript .. " detect --help",
      { "OK" }, "FormFillAINoopCallback", true
    )
    return
  end

  local jsonStr = f:read("*all")
  f:close()
  os.remove(tempOutJson)
  if tempImage and fileExists(tempImage) then pcall(os.remove, tempImage) end

  local results, err = json.decode(jsonStr)
  if not results or not results.success then
    local errMsg = results and results.error or (err or "Unknown detection error")
    app.openDialog("FormFillAI Detection Failed: " .. tostring(errMsg), { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  -- Apply active config from backend if updated
  if results.config then
    PluginState.config = results.config
    config = results.config
  end

  -- Record fields in plugin state
  PluginState.checkboxes[pageIdx] = results.checkboxes or {}
  PluginState.textboxes[pageIdx] = results.text_boxes or {}

  -- Ensure dedicated FormFillAI layer
  ensureFormFillLayer()

  local textList = {}
  local borderStrokes = {}
  local checkStrokes = {}

  local fontFam = config.font_family or "Nikosh"
  local fontCol = config.font_color or 0x000000
  local showBorders = config.show_field_borders ~= false
  local borderCol = config.border_color or 0x90B0D0
  local borderW = config.border_width or 0.8

  -- 1. Populate Text Boxes (exact width & height overlay)
  for _, box in ipairs(results.text_boxes or {}) do
    -- Calculate auto font size based on field height
    local fontSize = config.font_size or 11.0
    if config.font_size_mode == "auto" then
      if box.height <= 26.0 then
        -- Single-line field: fit height neatly (~72% of field height)
        fontSize = math.max(7.0, math.min(16.0, math.floor(box.height * 0.72 * 2.0) / 2.0))
      else
        -- Multi-line field: standard readable body font
        fontSize = 11.0
      end
    end

    -- Add text element matching field coordinates
    table.insert(textList, {
      text = " ", -- initial space so element is active & clickable in Text tool
      font = { name = fontFam, size = fontSize },
      color = fontCol,
      x = box.x,
      y = box.y
    })

    if showBorders then
      table.insert(borderStrokes, createFieldBorderStrokes(box, borderCol, borderW))
    end
  end

  -- 2. Populate Checkboxes
  local cbColor = config.checkbox_color or 0x002060
  local cbWidth = config.checkbox_stroke_width or 1.6
  local autoFillCb = config.auto_fill_checkboxes == true
  local cbStyle = config.checkbox_style or "check"

  for _, box in ipairs(results.checkboxes or {}) do
    if showBorders then
      table.insert(borderStrokes, createFieldBorderStrokes(box, borderCol, borderW))
    end

    if autoFillCb then
      local strokes = {}
      if cbStyle == "cross" then
        strokes = createCrossStrokes(box, cbColor, cbWidth)
      elseif cbStyle == "square" then
        strokes = createSquareStrokes(box, cbColor, cbWidth)
      elseif cbStyle == "bullet" then
        strokes = createBulletStrokes(box, cbColor, cbWidth)
      else
        strokes = createCheckmarkStrokes(box, cbColor, cbWidth)
      end
      for _, s in ipairs(strokes) do
        table.insert(checkStrokes, s)
      end
    end
  end

  -- Add borders to canvas
  if #borderStrokes > 0 then
    app.addStrokes({ strokes = borderStrokes, allowUndoRedoAction = "grouped" })
  end

  -- Add text boxes to canvas
  if #textList > 0 then
    app.addTexts({ texts = textList, allowUndoRedoAction = "grouped" })
  end

  -- Add auto-filled checkbox strokes
  if #checkStrokes > 0 then
    app.addStrokes({ strokes = checkStrokes, allowUndoRedoAction = "grouped" })
  end

  -- Set active tool to Text Tool so clicking on any box enters typing mode immediately
  -- without showing resize / drag handles
  pcall(function()
    app.changeActionState("select-tool", app.C.Tool_text)
  end)

  app.refreshPage()

  local nText = #(results.text_boxes or {})
  local nCb = #(results.checkboxes or {})
  local nSig = #(results.signatures or {})
  local summary = string.format(
    "✨ FormFillAI Detection Complete (Model: %s)\n\n" ..
    "• Text Field Overlays: %d\n" ..
    "• Checkbox Widgets: %d\n" ..
    "• Signature Lines: %d\n\n" ..
    "Font: %s\n\n" ..
    "Ready! Text tool is active — click on any field to type.\n" ..
    "Use 'Fill All Checkboxes' to mark checkboxes.",
    results.model or "FFDNet", nText, nCb, nSig, fontFam
  )
  app.openDialog(summary, { "OK" }, "FormFillAINoopCallback")
end

function onDetectAllPages()
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages then return end

  local totalPages = #doc.pages
  app.openDialog(
    string.format("FormFillAI will process %d page(s). Click OK to begin.", totalPages),
    { "OK", "Cancel" },
    "cbDetectAllPages"
  )
end

function cbDetectAllPages(btn)
  if btn ~= 1 then return end
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages then return end

  for p = 1, #doc.pages do
    app.setCurrentPage(p)
    onDetectCurrentPage()
  end
end

-- ---------------------------------------------------------------------------
-- Checkbox Fill Operations (Feature 3)
-- ---------------------------------------------------------------------------

local function fillCheckboxes(styleName)
  local config = loadConfig()
  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1
  local boxes = PluginState.checkboxes[pageIdx] or {}

  if #boxes == 0 then
    app.openDialog(
      "No detected checkboxes on this page.\n\n" ..
      "Run 'FormFillAI: Detect Form Fields' first, or use 'Add Checkbox Here' to add one manually.",
      { "OK" }, "FormFillAINoopCallback"
    )
    return
  end

  local color = config.checkbox_color or 0x002060
  local width = config.checkbox_stroke_width or 1.6
  local allStrokes = {}

  for _, box in ipairs(boxes) do
    local strokes = {}
    if styleName == "cross" then
      strokes = createCrossStrokes(box, color, width)
    elseif styleName == "square" then
      strokes = createSquareStrokes(box, color, width)
    elseif styleName == "bullet" then
      strokes = createBulletStrokes(box, color, width)
    else
      strokes = createCheckmarkStrokes(box, color, width)
    end
    for _, s in ipairs(strokes) do
      table.insert(allStrokes, s)
    end
  end

  if #allStrokes > 0 then
    app.addStrokes({ strokes = allStrokes, allowUndoRedoAction = "grouped" })
    app.refreshPage()
  end
end

function onFillCheckboxesCheck()
  fillCheckboxes("check")
end

function onFillCheckboxesCross()
  fillCheckboxes("cross")
end

function onFillCheckboxesSquare()
  fillCheckboxes("square")
end

function onFillCheckboxesBullet()
  fillCheckboxes("bullet")
end

-- ---------------------------------------------------------------------------
-- Toggle / Nearest Checkbox
-- ---------------------------------------------------------------------------

function onToggleNearestCheckbox()
  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1
  local boxes = PluginState.checkboxes[pageIdx] or {}
  local config = loadConfig()

  if #boxes == 0 then
    app.openDialog("No checkboxes detected on current page.", { "OK" }, "FormFillAINoopCallback")
    return
  end

  -- Find nearest box to view center (or first box)
  local pageInfo = doc.pages[pageIdx]
  local midX = (pageInfo and pageInfo.pageWidth or 612.0) / 2.0
  local midY = (pageInfo and pageInfo.pageHeight or 792.0) / 2.0

  local bestBox = boxes[1]
  local bestDist = 1e9
  for _, b in ipairs(boxes) do
    local dist = (b.x - midX) * (b.x - midX) + (b.y - midY) * (b.y - midY)
    if dist < bestDist then
      bestDist = dist
      bestBox = b
    end
  end

  local color = config.checkbox_color or 0x002060
  local width = config.checkbox_stroke_width or 1.6
  local style = config.checkbox_style or "check"

  local strokes = {}
  if style == "cross" then
    strokes = createCrossStrokes(bestBox, color, width)
  elseif style == "square" then
    strokes = createSquareStrokes(bestBox, color, width)
  else
    strokes = createCheckmarkStrokes(bestBox, color, width)
  end

  app.addStrokes({ strokes = strokes, allowUndoRedoAction = "individual" })
  app.refreshPage()
end

-- ---------------------------------------------------------------------------
-- Manual Overlay Addition (Features 2 & 3: add text, add checkbox)
-- ---------------------------------------------------------------------------

function onAddManualTextField()
  local config = loadConfig()
  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1
  local pageInfo = doc and doc.pages[pageIdx]

  local posX = 72.0
  local posY = 120.0
  local width = 160.0
  local height = 20.0

  -- Check if user has an existing selection
  local selTexts = app.getTexts("selection") or {}
  if #selTexts > 0 then
    posX = selTexts[1].x
    posY = selTexts[1].y
    width = selTexts[1].width or width
    height = selTexts[1].height or height
  elseif pageInfo then
    posX = (pageInfo.pageWidth - width) / 2.0
    posY = pageInfo.pageHeight / 3.0
  end

  local fontFam = config.font_family or "Nikosh"
  local fontSize = config.font_size or 11.0
  local fontCol = config.font_color or 0x000000

  ensureFormFillLayer()

  if config.show_field_borders ~= false then
    local borderCol = config.border_color or 0x90B0D0
    local borderW = config.border_width or 0.8
    app.addStrokes({
      strokes = { createFieldBorderStrokes({ x = posX, y = posY, width = width, height = height }, borderCol, borderW) },
      allowUndoRedoAction = "grouped"
    })
  end

  app.addTexts({
    texts = {
      {
        text = " ",
        font = { name = fontFam, size = fontSize },
        color = fontCol,
        x = posX,
        y = posY
      }
    },
    allowUndoRedoAction = "grouped"
  })

  pcall(function()
    app.changeActionState("select-tool", app.C.Tool_text)
  end)

  app.refreshPage()
end

function onAddManualCheckbox()
  local config = loadConfig()
  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1
  local pageInfo = doc and doc.pages[pageIdx]

  local posX = 72.0
  local posY = 160.0
  local size = 14.0

  if pageInfo then
    posX = pageInfo.pageWidth / 4.0
    posY = pageInfo.pageHeight / 3.0
  end

  local newBox = { x = posX, y = posY, width = size, height = size }

  -- Register in plugin state
  if not PluginState.checkboxes[pageIdx] then
    PluginState.checkboxes[pageIdx] = {}
  end
  table.insert(PluginState.checkboxes[pageIdx], newBox)

  ensureFormFillLayer()

  local color = config.checkbox_color or 0x002060
  local width = config.checkbox_stroke_width or 1.6
  local borderCol = config.border_color or 0x90B0D0

  -- Draw box outline
  local strokes = {
    createFieldBorderStrokes(newBox, borderCol, 1.0)
  }

  -- Draw checkmark
  local checks = createCheckmarkStrokes(newBox, color, width)
  for _, s in ipairs(checks) do
    table.insert(strokes, s)
  end

  app.addStrokes({ strokes = strokes, allowUndoRedoAction = "grouped" })
  app.refreshPage()
end

-- ---------------------------------------------------------------------------
-- Deletion & Cleanup (Feature 2)
-- ---------------------------------------------------------------------------

function onDeleteSelectedOverlay()
  app.activateAction("delete")
  app.refreshPage()
end

function onClearOverlaysCurrentPage()
  app.openDialog(
    "Clear all FormFillAI overlays and strokes on the current page?",
    { "Yes, Clear", "Cancel" },
    "cbClearOverlaysCurrentPage"
  )
end

function cbClearOverlaysCurrentPage(btn)
  if btn ~= 1 then return end

  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1

  -- Clear cached state for this page
  PluginState.checkboxes[pageIdx] = {}
  PluginState.textboxes[pageIdx] = {}

  -- Select all elements on current layer and delete them
  local refs = {}
  local texts = app.getTexts("layer") or {}
  for _, t in ipairs(texts) do
    if t.ref then table.insert(refs, t.ref) end
  end

  local strokes = app.getStrokes("layer") or {}
  for _, s in ipairs(strokes) do
    if s.ref then table.insert(refs, s.ref) end
  end

  if #refs > 0 then
    app.clearSelection()
    app.addToSelection(refs)
    app.activateAction("delete")
  end

  app.refreshPage()
end

-- ---------------------------------------------------------------------------
-- Settings Dialog Launch (Feature 2 & Configuration)
-- ---------------------------------------------------------------------------

function onOpenSettings()
  local python = getPythonExecutable()
  local dir = getPluginDirectory()
  local guiScript = dir .. "/backend/gui_settings.py"

  local isWindows = package.config:sub(1, 1) == "\\"
  local cmd
  if isWindows then
    cmd = string.format('start "" "%s" "%s"', python, guiScript)
  else
    cmd = string.format('"%s" "%s" &', python, guiScript)
  end

  print("[FormFillAI] Launching Settings GUI in background: " .. cmd)
  os.execute(cmd)
end
