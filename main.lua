--
-- FormFillAI: Xournal++ Plugin for AI-Powered Flat PDF Form Field Detection & Auto-Fill
-- Features:
--   1. Auto-detect flat PDF form fields using FFDNet-S and FFDNet-L AI models.
--   2. Fillable overlay text boxes with exact dimensions and Bangla (Nikosh) font support.
--   3. Interactive Checkbox Selector & Assistant to choose individual preferred checkboxes (Checked ✓, Crossed ✗, etc.).
--   4. One-click Guide Border Removal so borders are NEVER included in saved or exported PDFs.
--   5. Fast, non-freezing All-Pages detection with batch Python inference.
--   6. Full system font discovery (446 fonts, 100 Bangla variants) and persistent preferences.
--

local json = nil

-- Safe no-op callback for Xournal++ app.openDialog calls
function FormFillAINoopCallback(btn)
  -- Satisfies Xournal++ requirement for a valid callback function
end

-- State management for checkboxes, text fields, and guide border references
local PluginState = {
  checkboxes = {},       -- [pageIdx] = list of {x, y, width, height, isChecked, checkStyle, strokeRefs}
  textboxes = {},        -- [pageIdx] = list of {x, y, width, height}
  guideBorderRefs = {},  -- [pageIdx] = list of lightuserdata stroke references for guide borders
  config = nil,
  pluginDir = nil,
  lastDetectionJson = nil,
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

  -- 1. Detection Actions
  app.registerUi({
    menu = "FormFillAI: Detect Form Fields (Current Page)",
    callback = "onDetectCurrentPage",
    accelerator = "<Control><Shift>d"
  })

  app.registerUi({
    menu = "FormFillAI: Detect Form Fields (All Pages)",
    callback = "onDetectAllPages"
  })

  -- 2. Assistant & Checkbox Manager (Problem 3: Choose & click preferred box)
  app.registerUi({
    menu = "FormFillAI: Form Fill Assistant & Checkbox Manager...",
    callback = "onOpenAssistant",
    accelerator = "<Control><Shift>a"
  })

  app.registerUi({
    menu = "FormFillAI: Apply Fills from Assistant",
    callback = "onApplyAssistantFills"
  })

  app.registerUi({
    menu = "FormFillAI: Toggle / Mark Nearest Checkbox",
    callback = "onToggleNearestCheckbox",
    accelerator = "<Control><Shift>t"
  })

  -- 3. Bulk Checkbox Actions
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
    menu = "FormFillAI: Clear All Checkboxes (Current Page)",
    callback = "onClearCheckboxesCurrentPage"
  })

  -- 4. Guide Border Cleaning (Problem 4: NEVER in saved PDF)
  app.registerUi({
    menu = "FormFillAI: Remove Guide Borders (Clean for PDF Export - Current Page)",
    callback = "onRemoveGuideBorders",
    accelerator = "<Control><Shift>r"
  })

  app.registerUi({
    menu = "FormFillAI: Remove Guide Borders (Clean for PDF Export - All Pages)",
    callback = "onRemoveGuideBordersAllPages"
  })

  -- 5. Manual Tools & Overlays
  app.registerUi({
    menu = "FormFillAI: Add Text Field Overlay (at Selection / Center)",
    callback = "onAddManualTextField"
  })

  app.registerUi({
    menu = "FormFillAI: Add Checkbox Here (at Selection / Center)",
    callback = "onAddManualCheckbox"
  })

  app.registerUi({
    menu = "FormFillAI: Clear All Form Overlays (Current Page)",
    callback = "onClearOverlaysCurrentPage"
  })

  -- 6. Settings Dialog
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
-- Core Application of Detection Results to a Page
-- ---------------------------------------------------------------------------

local function applyPageDetections(pageIdx, results, config, showSummary)
  -- Apply active config from backend if updated
  if results.config then
    PluginState.config = results.config
    config = results.config
  end

  local fontFam = config.font_family or "Nikosh"
  local fontCol = config.font_color or 0x000000
  local defFontSize = config.font_size or 11.0
  local showBorders = config.show_field_borders ~= false
  local borderCol = config.border_color or 0x90B0D0
  local borderW = config.border_width or 0.8

  -- Configure Xournal++ active tool and font immediately
  pcall(function()
    app.setFont({ name = fontFam, size = defFontSize })
    app.changeActionState("tool-color", fontCol)
    app.changeActionState("select-tool", app.C.Tool_text)
  end)

  -- Record fields in plugin state
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
  local checkStrokes = {}

  -- 1. Populate Text Boxes (exact coordinates, auto-fitted font size, clickable prompt)
  for _, box in ipairs(tbs) do
    local fontSize = defFontSize
    if config.font_size_mode == "auto" then
      if box.height <= 26.0 then
        fontSize = math.max(7.0, math.min(16.0, math.floor(box.height * 0.72 * 2.0) / 2.0))
      else
        fontSize = 11.0
      end
    end

    -- Add clickable placeholder prompt so clicking with Text tool immediately focuses this field
    table.insert(textList, {
      text = "[ ... ]",
      font = { name = fontFam, size = fontSize },
      color = 0x708090, -- Subtle slate placeholder
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

  for _, box in ipairs(cbs) do
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

  -- Add borders and track their references so they can be 100% removed before saving PDF
  if #borderStrokes > 0 then
    local refs = app.addStrokes({ strokes = borderStrokes, allowUndoRedoAction = "grouped" })
    PluginState.guideBorderRefs[pageIdx] = refs
  end

  -- Add text boxes
  if #textList > 0 then
    app.addTexts({ texts = textList, allowUndoRedoAction = "grouped" })
  end

  -- Add auto-filled checkbox strokes
  if #checkStrokes > 0 then
    app.addStrokes({ strokes = checkStrokes, allowUndoRedoAction = "grouped" })
  end

  app.refreshPage()

  if showSummary then
    local nText = #tbs
    local nCb = #cbs
    local nSig = #(results.signatures or {})
    local summary = string.format(
      "✨ FormFillAI Detection Complete (Model: %s)\n\n" ..
      "• Text Field Overlays: %d\n" ..
      "• Checkbox Widgets: %d\n" ..
      "• Signature Lines: %d\n\n" ..
      "Font: %s (Bangladesh Govt Standard)\n\n" ..
      "👉 Tips:\n" ..
      "1. Text tool is active — click on any '[ ... ]' field to type in Bengali.\n" ..
      "2. Select a checkbox & press Ctrl+Shift+T to mark ONLY that preferred box.\n" ..
      "3. Use Ctrl+Shift+A for the visual Checkbox & Form Assistant.\n" ..
      "4. Press Ctrl+Shift+R to remove all guide borders before saving/exporting PDF!",
      results.model or "FFDNet", nText, nCb, nSig, fontFam
    )
    app.openDialog(summary, { "OK" }, "FormFillAINoopCallback")
  end
end

-- ---------------------------------------------------------------------------
-- Auto-Detect Form Fields (Current Page)
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

  -- If PDF path is still not found or invalid or pdfPage == 0, export page to PNG
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

  -- Cache latest results for Assistant
  PluginState.lastDetectionJson = tempDir .. "/formfill_latest_" .. tostring(pageIdx) .. ".json"
  local fCache = io.open(PluginState.lastDetectionJson, "w")
  if fCache then
    fCache:write(jsonStr)
    fCache:close()
  end

  applyPageDetections(pageIdx, results, config, true)
end

-- ---------------------------------------------------------------------------
-- Auto-Detect Form Fields (All Pages) - High-Speed, Non-Freezing (Problem 2)
-- ---------------------------------------------------------------------------

function onDetectAllPages()
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages or #doc.pages == 0 then
    app.openDialog("FormFillAI: No document currently opened.", { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  local totalPages = #doc.pages
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

  if pdfPath == "" or not fileExists(pdfPath) then
    app.openDialog(
      "FormFillAI All-Pages Detection requires a saved PDF background.\n" ..
      "For single-page image documents, please use 'Detect Form Fields (Current Page)'.",
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

  -- Run batch detection in ONE single fast Python process (takes under 3s for all 4 pages)
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

  print("[FormFillAI] Executing all-pages detection: " .. cmd)
  local exitCode = os.execute(cmd)

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
    app.openDialog("FormFillAI All-Pages Detection Failed: " .. tostring(results and results.error or "Unknown error"), { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  -- Cache for assistant
  PluginState.lastDetectionJson = tempDir .. "/formfill_latest_doc.json"
  local fCache = io.open(PluginState.lastDetectionJson, "w")
  if fCache then
    fCache:write(jsonStr)
    fCache:close()
  end

  local pagesData = results.pages or {}
  local origPage = doc.currentPage or 1

  -- Loop through pages and apply WITHOUT modal dialogs
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
    "✨ FormFillAI: All %d Pages Detected Successfully!\n\n" ..
    "• Total Text Fields: %d\n" ..
    "• Total Checkboxes: %d\n" ..
    "• Font: %s (Bangladesh Govt Standard)\n\n" ..
    "👉 Tips:\n" ..
    "1. Text tool is active — click on any field to type.\n" ..
    "2. Select a checkbox & press Ctrl+Shift+T to mark ONLY that preferred box.\n" ..
    "3. Use Ctrl+Shift+A for the visual Checkbox & Form Assistant.\n" ..
    "4. Press Ctrl+Shift+R to clean all guide borders before saving/exporting PDF!",
    totalPages, counts.text_boxes or 0, counts.checkboxes or 0, config.font_family or "Nikosh"
  )
  app.openDialog(summary, { "OK" }, "FormFillAINoopCallback")
end

-- ---------------------------------------------------------------------------
-- Guide Border Removal for Clean PDF Export (Problem 4)
-- ---------------------------------------------------------------------------

function onRemoveGuideBorders()
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages then return end
  local pageIdx = doc.currentPage or 1

  local refs = PluginState.guideBorderRefs[pageIdx]
  if refs and #refs > 0 then
    app.clearSelection()
    app.addToSelection(refs)
    app.activateAction("delete")
    PluginState.guideBorderRefs[pageIdx] = nil
  end

  -- Also check for untouched placeholder texts "[ ... ]" and remove them
  local texts = app.getTexts("layer") or {}
  local placeholderRefs = {}
  for _, t in ipairs(texts) do
    if t.text == "[ ... ]" and t.ref then
      table.insert(placeholderRefs, t.ref)
    end
  end
  if #placeholderRefs > 0 then
    app.clearSelection()
    app.addToSelection(placeholderRefs)
    app.activateAction("delete")
  end

  app.refreshPage()

  app.openDialog(
    "✨ Current Page Cleaned for PDF Export!\n\n" ..
    "• Removed all visual guide borders from this page.\n" ..
    "• Cleaned untouched placeholder texts.\n" ..
    "• All your filled text and checkmarks remain intact.\n\n" ..
    "You can now safely Save or Export your clean PDF without any border lines!",
    { "OK" },
    "FormFillAINoopCallback"
  )
end

function onRemoveGuideBordersAllPages()
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages then return end

  local origPage = doc.currentPage or 1
  for p = 1, #doc.pages do
    app.setCurrentPage(p)
    local refs = PluginState.guideBorderRefs[p]
    if refs and #refs > 0 then
      app.clearSelection()
      app.addToSelection(refs)
      app.activateAction("delete")
      PluginState.guideBorderRefs[p] = nil
    end

    local texts = app.getTexts("layer") or {}
    local placeholderRefs = {}
    for _, t in ipairs(texts) do
      if t.text == "[ ... ]" and t.ref then
        table.insert(placeholderRefs, t.ref)
      end
    end
    if #placeholderRefs > 0 then
      app.clearSelection()
      app.addToSelection(placeholderRefs)
      app.activateAction("delete")
    end
  end

  app.setCurrentPage(origPage)
  app.refreshPage()

  app.openDialog(
    "✨ All Pages Cleaned for PDF Export!\n\n" ..
    "Guide borders and placeholders removed across all pages.\n" ..
    "All your filled text and checkmarks are preserved.\n" ..
    "The document is 100% clean and ready for saving/printing!",
    { "OK" },
    "FormFillAINoopCallback"
  )
end

-- ---------------------------------------------------------------------------
-- Toggle / Nearest Checkbox (Problem 3: Choose preferred box)
-- ---------------------------------------------------------------------------

function onToggleNearestCheckbox()
  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1
  local boxes = PluginState.checkboxes[pageIdx] or {}
  local config = loadConfig()

  if #boxes == 0 then
    app.openDialog(
      "No detected checkboxes on current page.\n\n" ..
      "Run 'FormFillAI: Detect Form Fields' first, or use 'Add Checkbox Here' to add one manually.",
      { "OK" }, "FormFillAINoopCallback"
    )
    return
  end

  local targetX, targetY = nil, nil

  -- 1. Check selection tool bounding box
  local selInfo = app.getToolInfo("selection")
  if selInfo and selInfo.boundingBox and selInfo.boundingBox.x and selInfo.boundingBox.x > 0 then
    targetX = selInfo.boundingBox.x + (selInfo.boundingBox.width or 0) / 2.0
    targetY = selInfo.boundingBox.y + (selInfo.boundingBox.height or 0) / 2.0
  end

  -- 2. Check selected strokes
  if not targetX then
    local selStrokes = app.getStrokes("selection")
    if selStrokes and #selStrokes > 0 and selStrokes[1].x and #selStrokes[1].x > 0 then
      targetX = selStrokes[1].x[1]
      targetY = selStrokes[1].y[1]
    end
  end

  -- 3. Check selected text
  if not targetX then
    local selTexts = app.getTexts("selection")
    if selTexts and #selTexts > 0 then
      targetX = selTexts[1].x
      targetY = selTexts[1].y
    end
  end

  local bestBox = nil
  local bestIdx = 1

  if targetX and targetY then
    local bestDist = 1e9
    for i, b in ipairs(boxes) do
      local midBX = b.x + b.width / 2.0
      local midBY = b.y + b.height / 2.0
      local dist = (midBX - targetX) * (midBX - targetX) + (midBY - targetY) * (midBY - targetY)
      if dist < bestDist then
        bestDist = dist
        bestBox = b
        bestIdx = i
      end
    end
  else
    -- If no selection, toggle the first unchecked box
    for i, b in ipairs(boxes) do
      if not b.isChecked then
        bestBox = b
        bestIdx = i
        break
      end
    end
    if not bestBox then
      bestBox = boxes[1]
      bestIdx = 1
    end
  end

  if not bestBox then return end

  ensureFormFillLayer()

  local color = config.checkbox_color or 0x002060
  local width = config.checkbox_stroke_width or 1.6
  local style = config.checkbox_style or "check"

  if bestBox.isChecked then
    -- Already checked: toggle off and delete stroke
    if bestBox.strokeRefs and #bestBox.strokeRefs > 0 then
      app.clearSelection()
      app.addToSelection(bestBox.strokeRefs)
      app.activateAction("delete")
    end
    bestBox.isChecked = false
    bestBox.strokeRefs = nil
  else
    -- Mark this specific box
    local strokes = {}
    if style == "cross" then
      strokes = createCrossStrokes(bestBox, color, width)
    elseif style == "square" then
      strokes = createSquareStrokes(bestBox, color, width)
    elseif style == "bullet" then
      strokes = createBulletStrokes(bestBox, color, width)
    else
      strokes = createCheckmarkStrokes(bestBox, color, width)
    end
    local refs = app.addStrokes({ strokes = strokes, allowUndoRedoAction = "individual" })
    bestBox.isChecked = true
    bestBox.strokeRefs = refs
  end

  app.refreshPage()
end

-- ---------------------------------------------------------------------------
-- Interactive Form Fill Assistant & Checkbox Manager (Problem 3 GUI)
-- ---------------------------------------------------------------------------

function onOpenAssistant()
  local doc = app.getDocumentStructure()
  if not doc or not doc.pages or #doc.pages == 0 then
    app.openDialog("FormFillAI: Please open a document first.", { "OK" }, "FormFillAINoopCallback", true)
    return
  end

  local pageIdx = doc.currentPage or 1
  local tempDir = getTempDirectory()
  local dataJson = tempDir .. "/formfill_results_" .. tostring(pageIdx) .. ".json"
  local appliedJson = tempDir .. "/formfill_applied_" .. tostring(pageIdx) .. ".json"

  local boxes = PluginState.checkboxes[pageIdx] or {}
  local texts = PluginState.textboxes[pageIdx] or {}

  if #boxes == 0 and #texts == 0 then
    onDetectCurrentPage()
    boxes = PluginState.checkboxes[pageIdx] or {}
    texts = PluginState.textboxes[pageIdx] or {}
  end

  -- Write current state for assistant
  local pageData = {
    page = pageIdx,
    checkboxes = boxes,
    text_boxes = texts
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
  local cmd = string.format('"%s" "%s" assistant --data "%s" --out "%s" --page %d', python, cliScript, dataJson, appliedJson, pageIdx)
  if isWindows then
    cmd = 'start "" ' .. cmd
  else
    cmd = cmd .. " &"
  end

  print("[FormFillAI] Launching Assistant GUI: " .. cmd)
  os.execute(cmd)
end

function onApplyAssistantFills()
  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1
  local tempDir = getTempDirectory()
  local appliedJson = tempDir .. "/formfill_applied_" .. tostring(pageIdx) .. ".json"

  local f = io.open(appliedJson, "r")
  if not f then
    app.openDialog(
      "No applied fills found from Assistant yet.\n\n" ..
      "Open 'Form Fill Assistant' (Ctrl+Shift+A), choose your checkboxes or enter text, and click 'Apply to Document'.",
      { "OK" }, "FormFillAINoopCallback"
    )
    return
  end

  local jsonStr = f:read("*all")
  f:close()

  if not loadJsonLibrary() then return end
  local data = json.decode(jsonStr)
  if not data then return end

  if data.action == "remove_guides" or data.remove_guides then
    onRemoveGuideBorders()
    return
  end

  local config = loadConfig()
  local color = config.checkbox_color or 0x002060
  local width = config.checkbox_stroke_width or 1.6
  local fontFam = config.font_family or "Nikosh"
  local fontCol = config.font_color or 0x000000

  ensureFormFillLayer()

  -- Render checkboxes marked by user
  local strokes = {}
  for _, cb in ipairs(data.checkboxes or {}) do
    local st = cb.state or "none"
    if st == "check" then
      for _, s in ipairs(createCheckmarkStrokes(cb, color, width)) do table.insert(strokes, s) end
    elseif st == "cross" then
      for _, s in ipairs(createCrossStrokes(cb, color, width)) do table.insert(strokes, s) end
    elseif st == "square" then
      for _, s in ipairs(createSquareStrokes(cb, color, width)) do table.insert(strokes, s) end
    elseif st == "bullet" then
      for _, s in ipairs(createBulletStrokes(cb, color, width)) do table.insert(strokes, s) end
    end
  end
  if #strokes > 0 then
    app.addStrokes({ strokes = strokes, allowUndoRedoAction = "grouped" })
  end

  -- Render text fields entered by user
  local textList = {}
  for _, tb in ipairs(data.text_boxes or {}) do
    if tb.text and tb.text ~= "" then
      local fontSize = config.font_size or 11.0
      if config.font_size_mode == "auto" and tb.height then
        fontSize = math.max(7.0, math.min(16.0, math.floor(tb.height * 0.72 * 2.0) / 2.0))
      end
      table.insert(textList, {
        text = tb.text,
        font = { name = fontFam, size = fontSize },
        color = fontCol,
        x = tb.x,
        y = tb.y
      })
    end
  end
  if #textList > 0 then
    app.addTexts({ texts = textList, allowUndoRedoAction = "grouped" })
  end

  app.refreshPage()

  app.openDialog(
    string.format("✨ Fills Applied Successfully!\n\n• Checkmarks Drawn: %d\n• Text Fields Populated: %d\nFont: %s",
      #strokes, #textList, fontFam),
    { "OK" }, "FormFillAINoopCallback"
  )
end

-- ---------------------------------------------------------------------------
-- Bulk Checkbox Operations
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
    ensureFormFillLayer()
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

function onClearCheckboxesCurrentPage()
  local doc = app.getDocumentStructure()
  local pageIdx = doc and doc.currentPage or 1
  local boxes = PluginState.checkboxes[pageIdx] or {}

  local allRefs = {}
  for _, b in ipairs(boxes) do
    if b.strokeRefs and #b.strokeRefs > 0 then
      for _, r in ipairs(b.strokeRefs) do
        table.insert(allRefs, r)
      end
    end
    b.isChecked = false
    b.strokeRefs = nil
  end

  if #allRefs > 0 then
    app.clearSelection()
    app.addToSelection(allRefs)
    app.activateAction("delete")
    app.refreshPage()
  end
end

-- ---------------------------------------------------------------------------
-- Manual Overlay Addition (add text, add checkbox)
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
    local refs = app.addStrokes({
      strokes = { createFieldBorderStrokes({ x = posX, y = posY, width = width, height = height }, borderCol, borderW) },
      allowUndoRedoAction = "grouped"
    })
    if not PluginState.guideBorderRefs[pageIdx] then PluginState.guideBorderRefs[pageIdx] = {} end
    for _, r in ipairs(refs or {}) do table.insert(PluginState.guideBorderRefs[pageIdx], r) end
  end

  app.addTexts({
    texts = {
      {
        text = "[ ... ]",
        font = { name = fontFam, size = fontSize },
        color = 0x708090,
        x = posX,
        y = posY
      }
    },
    allowUndoRedoAction = "grouped"
  })

  pcall(function()
    app.setFont({ name = fontFam, size = fontSize })
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

  local newBox = { x = posX, y = posY, width = size, height = size, isChecked = true }

  if not PluginState.checkboxes[pageIdx] then
    PluginState.checkboxes[pageIdx] = {}
  end
  table.insert(PluginState.checkboxes[pageIdx], newBox)

  ensureFormFillLayer()

  local color = config.checkbox_color or 0x002060
  local width = config.checkbox_stroke_width or 1.6
  local borderCol = config.border_color or 0x90B0D0

  -- Draw box outline
  local bStrokes = { createFieldBorderStrokes(newBox, borderCol, 1.0) }
  local bRefs = app.addStrokes({ strokes = bStrokes, allowUndoRedoAction = "grouped" })
  if not PluginState.guideBorderRefs[pageIdx] then PluginState.guideBorderRefs[pageIdx] = {} end
  for _, r in ipairs(bRefs or {}) do table.insert(PluginState.guideBorderRefs[pageIdx], r) end

  -- Draw checkmark
  local checks = createCheckmarkStrokes(newBox, color, width)
  local cRefs = app.addStrokes({ strokes = checks, allowUndoRedoAction = "grouped" })
  newBox.strokeRefs = cRefs

  app.refreshPage()
end

-- ---------------------------------------------------------------------------
-- Deletion & Cleanup
-- ---------------------------------------------------------------------------

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
  PluginState.guideBorderRefs[pageIdx] = nil

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
-- Settings Dialog Launch
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
