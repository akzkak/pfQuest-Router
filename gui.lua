-- pfQuest-Router window: start/stop the active route and manage saved ones
-- toggled with /pfr

local getn, insert, sort = table.getn, table.insert, table.sort
local router = pfQuestRouter

local WIDTH, ROWS, ROWHEIGHT = 250, 8, 18
local font, fontsize = pfUI.font_default, pfUI_config.global.font_size

local gui = CreateFrame("Frame", "pfQuestRouterGUI", UIParent)
gui:Hide()
gui:SetWidth(WIDTH)
gui:SetHeight(152 + ROWS * ROWHEIGHT)
gui:SetPoint("CENTER", 0, 0)
-- below the world map, so the window waits behind it while the route is
-- edited there and is back as soon as the map closes
gui:SetFrameStrata("DIALOG")
gui:SetMovable(true)
gui:EnableMouse(true)
gui:SetClampedToScreen(true)
gui:SetScript("OnMouseDown", function()
  this:StartMoving()
end)
gui:SetScript("OnMouseUp", function()
  this:StopMovingOrSizing()
end)
pfUI.api.CreateBackdrop(gui, nil, true, 0.75)

local function CreateText(parent, size, layer)
  local text = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontWhite")
  text:SetFont(font, size or fontsize, "OUTLINE")
  return text
end

local function CreateButton(parent, label, onclick)
  local button = CreateFrame("Button", nil, parent)
  button:SetHeight(20)
  button.text = CreateText(button)
  button.text:SetAllPoints(button)
  button.text:SetText(label)
  button:SetScript("OnClick", onclick)
  pfUI.api.SkinButton(button)
  return button
end

gui.title = CreateText(gui, 14)
gui.title:SetPoint("TOP", gui, "TOP", 0, -8)
gui.title:SetText("|cff33ffccpf|rQuest Router")

gui.close = CreateFrame("Button", nil, gui)
gui.close:SetPoint("TOPRIGHT", -5, -5)
gui.close:SetHeight(20)
gui.close:SetWidth(20)
gui.close.texture = gui.close:CreateTexture(nil, "OVERLAY")
gui.close.texture:SetTexture(pfQuestConfig.path .. "\\compat\\close")
gui.close.texture:SetVertexColor(1, 0.25, 0.25, 1)
gui.close.texture:SetPoint("TOPLEFT", gui.close, "TOPLEFT", 4, -4)
gui.close.texture:SetPoint("BOTTOMRIGHT", gui.close, "BOTTOMRIGHT", -4, 4)
gui.close:SetScript("OnClick", function()
  gui:Hide()
end)
pfUI.api.SkinButton(gui.close, 1, 0.5, 0.5)

-- active route
gui.status = CreateText(gui)
gui.status:SetPoint("TOPLEFT", gui, "TOPLEFT", 8, -32)
gui.status:SetPoint("TOPRIGHT", gui, "TOPRIGHT", -8, -32)
gui.status:SetHeight(36)
gui.status:SetJustifyH("LEFT")
gui.status:SetJustifyV("TOP")

local third = (WIDTH - 16 - 8) / 3

gui.start = CreateButton(gui, "Start", function()
  router.Start()
  gui:Refresh()
end)
gui.start:SetWidth(third)
gui.start:SetPoint("TOPLEFT", gui, "TOPLEFT", 8, -72)

gui.reverse = CreateButton(gui, "Reverse", function()
  router.Reverse()
  gui:Refresh()
end)
gui.reverse:SetWidth(third)
gui.reverse:SetPoint("LEFT", gui.start, "RIGHT", 4, 0)

gui.stop = CreateButton(gui, "Stop", function()
  router.Stop()
  gui:Refresh()
end)
gui.stop:SetWidth(third)
gui.stop:SetPoint("LEFT", gui.reverse, "RIGHT", 4, 0)

-- save the active route under a name
local function SaveInput()
  if router.Save(gui.input:GetText()) then
    gui.input:SetText("")
  end
  gui.input:ClearFocus()
  gui:Refresh()
end

gui.save = CreateButton(gui, "Save", SaveInput)
gui.save:SetWidth(50)
gui.save:SetPoint("TOPRIGHT", gui, "TOPRIGHT", -8, -100)

gui.input = CreateFrame("EditBox", "pfQuestRouterGUIInput", gui)
gui.input:SetFont(font, fontsize, "OUTLINE")
gui.input:SetAutoFocus(false)
gui.input:SetJustifyH("LEFT")
gui.input:SetHeight(20)
gui.input:SetPoint("TOPLEFT", gui, "TOPLEFT", 8, -100)
gui.input:SetPoint("RIGHT", gui.save, "LEFT", -4, 0)
gui.input:SetTextInsets(5, 5, 4, 4)
gui.input:SetScript("OnEnterPressed", SaveInput)
gui.input:SetScript("OnEscapePressed", function()
  this:ClearFocus()
end)
pfUI.api.CreateBackdrop(gui.input, nil, true)

gui.hint = CreateText(gui.input)
gui.hint:SetPoint("LEFT", gui.input, "LEFT", 5, 0)
gui.hint:SetTextColor(0.5, 0.5, 0.5, 1)
gui.hint:SetText("Name for the active route")
-- the hint only shows while the box is empty and not being typed in,
-- otherwise the cursor blinks on top of it
local function UpdateHint()
  if gui.input:GetText() == "" and not gui.input.focus then
    gui.hint:Show()
  else
    gui.hint:Hide()
  end
end

gui.input:SetScript("OnTextChanged", UpdateHint)
gui.input:SetScript("OnEditFocusGained", function()
  this.focus = true
  UpdateHint()
end)
gui.input:SetScript("OnEditFocusLost", function()
  this.focus = nil
  UpdateHint()
end)

-- saved routes
gui.caption = CreateText(gui)
gui.caption:SetPoint("TOPLEFT", gui, "TOPLEFT", 8, -130)
gui.caption:SetTextColor(0.2, 1, 0.8, 1)

gui.list = CreateFrame("Frame", nil, gui)
gui.list:SetPoint("TOPLEFT", gui, "TOPLEFT", 8, -146)
gui.list:SetPoint("BOTTOMRIGHT", gui, "BOTTOMRIGHT", -8, 6)
gui.list:EnableMouseWheel(true)
gui.list:SetScript("OnMouseWheel", function()
  gui.offset = (gui.offset or 0) - arg1
  gui:Refresh()
end)

gui.empty = CreateText(gui.list)
gui.empty:SetPoint("TOP", gui.list, "TOP", 0, -8)
gui.empty:SetTextColor(0.5, 0.5, 0.5, 1)
gui.empty:SetText("No saved routes")

gui.rows = {}
for i = 1, ROWS do
  local row = CreateFrame("Button", nil, gui.list)
  row:SetHeight(ROWHEIGHT)
  row:SetPoint("TOPLEFT", gui.list, "TOPLEFT", 0, -(i - 1) * ROWHEIGHT)
  row:SetPoint("RIGHT", gui.list, "RIGHT", -ROWHEIGHT - 2, 0)

  row.highlight = row:CreateTexture(nil, "BACKGROUND")
  row.highlight:SetAllPoints(row)
  row.highlight:SetTexture(1, 1, 1, 0.1)
  row.highlight:Hide()

  row.info = CreateText(row)
  row.info:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.info:SetJustifyH("RIGHT")
  row.info:SetTextColor(0.6, 0.6, 0.6, 1)

  row.text = CreateText(row)
  row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.text:SetPoint("RIGHT", row.info, "LEFT", -4, 0)
  row.text:SetJustifyH("LEFT")

  row:SetScript("OnEnter", function()
    this.highlight:Show()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(this.name, 0.2, 1, 0.8)
    GameTooltip:AddLine("Click to load this route", 1, 1, 1)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function()
    this.highlight:Hide()
    GameTooltip:Hide()
  end)
  row:SetScript("OnClick", function()
    router.Load(this.name)
    gui:Refresh()
  end)

  -- delete needs a second click, the first one only arms the button
  row.delete = CreateFrame("Button", nil, gui.list)
  row.delete:SetWidth(ROWHEIGHT - 2)
  row.delete:SetHeight(ROWHEIGHT - 2)
  row.delete:SetPoint("LEFT", row, "RIGHT", 2, 0)
  row.delete.text = CreateText(row.delete)
  row.delete.text:SetAllPoints(row.delete)
  row.delete.row = row
  row.delete:SetScript("OnClick", function()
    if gui.confirm == this.row.name then
      gui.confirm = nil
      router.Delete(this.row.name)
    else
      gui.confirm = this.row.name
    end
    gui:Refresh()
  end)
  row.delete:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Delete saved route", 1, 0.3, 0.3)
    GameTooltip:AddLine("Click twice to delete", 1, 1, 1)
    GameTooltip:Show()
  end)
  row.delete:SetScript("OnLeave", function()
    GameTooltip:Hide()
    if gui.confirm then
      gui.confirm = nil
      gui:Refresh()
    end
  end)
  pfUI.api.SkinButton(row.delete, 1, 0.5, 0.5)

  gui.rows[i] = row
end

function gui:Refresh()
  local name, summary = router.Active()
  self.status:SetText(summary or "|cff888888No active route. Search with /db, then press Start.")

  local names = {}
  for saved in pairs(pfQuestRouter_routes) do
    insert(names, saved)
  end
  sort(names)

  local count = getn(names)
  self.offset = math.max(0, math.min(self.offset or 0, count - ROWS))
  self.caption:SetText("Saved routes (" .. count .. ")")

  if count == 0 then
    self.empty:Show()
  else
    self.empty:Hide()
  end

  for i = 1, ROWS do
    local row, saved = self.rows[i], names[i + self.offset]
    if saved then
      local data = pfQuestRouter_routes[saved]
      row.name = saved
      row.info:SetText((pfMap:GetMapNameByID(data.zone) or "?") .. ", " .. getn(data.order or {}))

      if self.confirm == saved then
        row.text:SetText("|cffff5555Delete?|r " .. saved)
        row.delete.text:SetText("|cffff3333!")
      else
        row.text:SetText((saved == name and "|cffffcc00" or "|cffffffff") .. saved)
        row.delete.text:SetText("|cffff8888x")
      end

      row:Show()
      row.delete:Show()
    else
      row:Hide()
      row.delete:Hide()
    end
  end
end

gui:SetScript("OnShow", function()
  this.confirm = nil
  this:Refresh()
end)

-- the route also changes from outside the window (slash commands, map
-- clicks), so keep the display current while it is open
gui:SetScript("OnUpdate", function()
  if (this.tick or 0) > GetTime() then
    return
  end
  this.tick = GetTime() + 0.5
  this:Refresh()
end)
