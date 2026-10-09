-- pfQuest-Router
-- Turns the spawn points pfQuest draws for a database search (/db <name>)
-- into a closed loop and drives the pfQuest arrow along it, waypoint by
-- waypoint, forever.

local floor, ceil, sqrt, abs, pi = math.floor, math.ceil, math.sqrt, math.abs, math.pi
local min, max = math.min, math.max
local getn, insert = table.getn, table.insert
local strlower, strfind, format = string.lower, string.find, string.format
local GetTime = GetTime

pfQuestRouter_data = pfQuestRouter_data or {}

local DEFAULT_RADIUS = 2 -- map units; spawns closer than this share a waypoint
local TWO_OPT_PASSES = 20

-- active route: { name, zone, raw = { {x,y}, .. }, points = { {x,y}, .. }, cur }
local route

local router = CreateFrame("Frame", "pfQuestRouter", UIParent)
pfQuestRouter = router

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest Router|r: " .. msg)
end

-- /pfr debug: explain every waypoint change and arrow hand-over in chat
local function Debug(msg)
  if pfQuestRouter_data.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfR|cffaaaaaa debug:|r " .. msg)
  end
end

local function modulo(val, by)
  return val - floor(val / by) * by
end

-- same metric as pfQuest: zone maps are 3:2, so x counts 1.5 times
local function Dist(ax, ay, bx, by)
  local dx, dy = (ax - bx) * 1.5, ay - by
  return sqrt(dx * dx + dy * dy)
end

local function Radius()
  return tonumber(pfQuestRouter_data.radius) or DEFAULT_RADIUS
end

local function ArrivalRadius()
  return max(0.5, Radius() / 2)
end

local function CurrentMap()
  return pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())
end

-- player position in map units, only while the displayed map is `zone`
local function PlayerPos(zone)
  local x, y = GetPlayerMapPosition("player")
  if (x == 0 and y == 0) or CurrentMap() ~= zone then
    return nil
  end
  return x * 100, y * 100
end

-- gather the spawn points pfQuest currently has on `zone`
-- filter: optional lowercase name, matched against node title and spawn
local function Collect(zone, filter)
  local raw, names = {}, {}

  for addon, maps in pairs(pfMap.nodes) do
    if addon ~= "PFQUEST" and maps[zone] then
      for coords, node in pairs(maps[zone]) do
        local match
        for title, meta in pairs(node) do
          if
            not meta.cluster
            and (not filter or strlower(title) == filter or (meta.spawn and strlower(meta.spawn) == filter))
          then
            match = title
            break
          end
        end

        if match then
          local _, _, x, y = strfind(coords, "(.*)|(.*)")
          x, y = tonumber(x), tonumber(y)
          if x and y then
            insert(raw, { x, y })
            names[match] = true
          end
        end
      end
    end
  end

  return raw, names
end

-- merge spawns that sit within `radius` of each other into one waypoint
local function Cluster(raw, radius)
  local clusters = {}

  for _, p in ipairs(raw) do
    local best, bestdist
    for id, c in ipairs(clusters) do
      local d = Dist(p[1], p[2], c[1], c[2])
      if d <= radius and (not bestdist or d < bestdist) then
        best, bestdist = id, d
      end
    end

    if best then
      local c = clusters[best]
      c[1] = (c[1] * c[3] + p[1]) / (c[3] + 1)
      c[2] = (c[2] * c[3] + p[2]) / (c[3] + 1)
      c[3] = c[3] + 1
    else
      insert(clusters, { p[1], p[2], 1 })
    end
  end

  return clusters
end

-- closed tour: nearest neighbour, then 2-opt to remove crossings
local function Tour(points)
  local n = getn(points)
  if n < 3 then
    return points
  end

  local tour, used = { points[1] }, { [1] = true }
  for i = 2, n do
    local last, best, bestdist = tour[i - 1], nil, nil
    for id, p in ipairs(points) do
      if not used[id] then
        local d = Dist(last[1], last[2], p[1], p[2])
        if not bestdist or d < bestdist then
          best, bestdist = id, d
        end
      end
    end
    used[best] = true
    tour[i] = points[best]
  end

  for pass = 1, TWO_OPT_PASSES do
    local improved = nil
    for i = 1, n - 1 do
      for j = i + 1, n do
        if not (i == 1 and j == n) then
          local a, b = tour[i], tour[i + 1]
          local c, d = tour[j], tour[j == n and 1 or j + 1]
          local delta = Dist(a[1], a[2], c[1], c[2]) + Dist(b[1], b[2], d[1], d[2])
            - Dist(a[1], a[2], b[1], b[2]) - Dist(c[1], c[2], d[1], d[2])

          if delta < -0.0001 then
            local lo, hi = i + 1, j
            while lo < hi do
              tour[lo], tour[hi] = tour[hi], tour[lo]
              lo, hi = lo + 1, hi - 1
            end
            improved = true
          end
        end
      end
    end
    if not improved then
      break
    end
  end

  return tour
end

local function Length(points)
  local n, len = getn(points), 0
  for i = 1, n do
    local a, b = points[i], points[i == n and 1 or i + 1]
    len = len + Dist(a[1], a[2], b[1], b[2])
  end
  return len
end

local function Nearest(points, x, y)
  local best, bestdist
  for id, p in ipairs(points) do
    local d = Dist(x, y, p[1], p[2])
    if not bestdist or d < bestdist then
      best, bestdist = id, d
    end
  end
  return best
end

-- waypoints that were not removed from the route via right-click
local function Active(all)
  local active = {}
  for _, p in ipairs(all) do
    if not p.off then
      insert(active, p)
    end
  end
  return active
end

-- one-line summary of the route as it is right now
-- change: optional note on what was just done to it
local function Report(change)
  local spawns = 0
  for _, p in ipairs(route.points) do
    spawns = spawns + p[3]
  end

  local removed = getn(route.all) - getn(route.points)
  Print(
    format(
      "%s|cffffcc00%s|r in %s: %d spawns, %d waypoints%s, loop length %.0f.",
      change and change .. " - " or "",
      route.name,
      pfMap:GetMapNameByID(route.zone) or route.zone,
      spawns,
      getn(route.points),
      removed > 0 and " (" .. removed .. " removed)" or "",
      Length(route.points)
    )
  )
end

local function Build(name, zone, raw)
  local all = Cluster(raw, Radius())
  if getn(all) == 0 then
    return nil
  end

  -- all: every waypoint, points: the loop over the ones still in use
  local points = Tour(Active(all))
  route = { name = name, zone = zone, raw = raw, all = all, points = points, cur = 1 }

  local px, py = PlayerPos(zone)
  if px then
    route.cur = Nearest(points, px, py)
  end

  router.valid = nil
  router.tick = nil
  router.redraw, router.miniredraw = true, true

  Report()
  return true
end

local function Stop()
  route = nil
  router.valid = nil
  router.redraw, router.miniredraw = true, true
end

-- /pfr start: route over everything the database search put on this map
local function StartFromMap()
  local zone = CurrentMap()
  if not zone then
    Print("Open the zone map that shows your search results first.")
    return
  end

  local raw, names = Collect(zone)
  if getn(raw) == 0 then
    Print("No database spawn points on this map. Pick something via |cff33ffcc/db <name>|r first, or use |cff33ffcc/pfr <name>|r.")
    return
  end

  local name, count = nil, 0
  for title in pairs(names) do
    count = count + 1
    if count <= 2 then
      name = (name and name .. ", " or "") .. title
    end
  end
  if count > 2 then
    name = name .. ", ..."
  end

  Build(name, zone, raw)
end

-- /pfr <name>: search the database ourselves, then route
local function StartFromSearch(name)
  local maps = pfDatabase:SearchMob(name, { ["addon"] = "PFDB" }, "LOWER")
  if not next(maps or {}) then
    maps = pfDatabase:SearchObject(name, { ["addon"] = "PFDB" }, "LOWER")
  end
  if not next(maps or {}) then
    Print("Nothing found for |cffffcc00" .. name .. "|r.")
    return
  end

  -- prefer the zone we are looking at, otherwise the one with most spawns
  local zone = CurrentMap()
  if not zone or not maps[zone] then
    zone = pfDatabase:GetBestMap(maps)
  end

  local raw, names = Collect(zone, strlower(name))
  if getn(raw) == 0 then
    Print("Nothing found for |cffffcc00" .. name .. "|r.")
    return
  end

  Build(next(names) or name, zone, raw)
end

local function Wrap(id)
  return modulo(id - 1, getn(route.points)) + 1
end

local function Step(by)
  route.cur = Wrap(route.cur + by)
  router.redraw, router.miniredraw = true, true
  Debug(format("manual %s, heading for waypoint %d/%d", by > 0 and "next" or "prev", route.cur, getn(route.points)))
end

local function ReverseList(points)
  local lo, hi = 1, getn(points)
  while lo < hi do
    points[lo], points[hi] = points[hi], points[lo]
    lo, hi = lo + 1, hi - 1
  end
end

local function Reverse()
  ReverseList(route.points)
  -- we were heading to cur, so now head back to the waypoint before it
  route.cur = Wrap(getn(route.points) - route.cur + 2)
  -- that one was just visited: don't send the player back to it
  if route.points[route.cur] == router.visited then
    route.cur = Wrap(route.cur + 1)
  end
  router.redraw, router.miniredraw = true, true
  Debug(format("manual reverse, heading for waypoint %d/%d", route.cur, getn(route.points)))

  Report("Direction reversed")
end

-- signed area of the loop; the sign tells which way round it runs
local function Area(points)
  local n, area = getn(points), 0
  for i = 1, n do
    local a, b = points[i], points[i == n and 1 or i + 1]
    area = area + a[1] * b[2] - b[1] * a[2]
  end
  return area
end

-- take a waypoint out of the loop, or put it back in
local function Toggle(p)
  if not p.off and getn(route.points) <= 1 then
    Print("Can't remove the last waypoint, use |cff33ffcc/pfr stop|r instead.")
    return
  end

  local target, follow = route.points[route.cur], route.points[Wrap(route.cur + 1)]
  local area = Area(route.points)

  p.off = not p.off or nil

  -- keep walking the same way round
  local points = Tour(Active(route.all))
  if area * Area(points) < 0 then
    ReverseList(points)
  end

  -- keep heading for the same waypoint, or the one after it if it was removed
  local cur
  for id, q in ipairs(points) do
    if q == target or (not cur and q == follow) then
      cur = id
    end
  end

  -- the new loop may start anywhere: rotate it so the target keeps its number
  cur = cur or 1
  local n, want = getn(points), min(route.cur, getn(points))
  local rotated = {}
  for i = 1, n do
    rotated[i] = points[modulo(i - 1 + cur - want, n) + 1]
  end

  route.points = rotated
  route.cur = want
  router.redraw, router.miniredraw = true, true

  Debug(
    format(
      "route re-planned, heading for waypoint %d/%d (%s)",
      want,
      n,
      rotated[want] == target and "same target as before" or "target was removed, taking the one after it"
    )
  )
  Report(p.off and "Waypoint removed" or "Waypoint added")
end

local function SetTarget(p)
  for id, q in ipairs(route.points) do
    if q == p then
      route.cur = id
      router.redraw, router.miniredraw = true, true
      Debug(format("map click, heading for waypoint %d/%d", id, getn(route.points)))
    end
  end
end

-- waypoint progress
router:SetScript("OnUpdate", function()
  if not route then
    return
  end

  if (this.tick or 0) > GetTime() then
    return
  end
  this.tick = GetTime() + 0.1

  local px, py = PlayerPos(route.zone)
  if not px then
    if this.valid then
      local x, y = GetPlayerMapPosition("player")
      Debug(
        format(
          "paused, arrow back to pfQuest (%s)",
          (x == 0 and y == 0) and "no player position on this map"
            or "map shows zone " .. tostring(CurrentMap()) .. ", route is in " .. tostring(route.zone)
        )
      )
    end
    this.valid = nil
    return
  end

  if not this.valid then
    Debug(format("following route, heading for waypoint %d/%d", route.cur, getn(route.points)))
  end

  -- advance on arrival only. Coming near a waypoint, or near a later one on
  -- the way, never skips ahead: spawns need time to come back, so the loop
  -- is walked strictly in order.
  local p = route.points[route.cur]
  local d = Dist(px, py, p[1], p[2])
  if d <= ArrivalRadius() then
    local from = route.cur
    route.cur = Wrap(route.cur + 1)
    this.visited = p
    this.redraw, this.miniredraw = true, true

    local q = route.points[route.cur]
    Debug(
      format(
        "waypoint %d reached (distance %.1f) -> %d/%d, %.1f away",
        from,
        d,
        route.cur,
        getn(route.points),
        Dist(px, py, q[1], q[2])
      )
    )
  end

  this.valid = true
  if not pfQuest.route.arrow:IsShown() then
    pfQuest.route.arrow:Show()
  end
end)

-- routes are session-only, like /db search results; drop ones saved by
-- earlier versions
router:RegisterEvent("VARIABLES_LOADED")
router:SetScript("OnEvent", function()
  pfQuestRouter_data.route = nil
end)

-- arrow: take over pfQuest's arrow while a route is being followed
local arrow = pfQuest.route.arrow
local original = arrow:GetScript("OnUpdate")
local owned, lasttext, lastdist

arrow:SetScript("OnUpdate", function()
  if not route or not router.valid or UnitIsDead("player") or UnitIsGhost("player") then
    if owned then
      -- hand the arrow back and make pfQuest rewrite its texts
      owned, lasttext, lastdist = nil, nil, nil
      Debug(
        "arrow handed back to pfQuest ("
          .. (not route and "route stopped" or not router.valid and "route paused" or "dead")
          .. ")"
      )
      this.distance.number = nil
      pfMap.queue_update = GetTime()
    end
    if original then
      original()
    end
    return
  end

  local x, y = GetPlayerMapPosition("player")
  if x == 0 and y == 0 then
    return
  end

  local target = route.points[route.cur]
  local dx, dy = (target[1] - x * 100) * 1.5, target[2] - y * 100
  local angle = math.atan2(-dx, -dy) - pfQuestCompat.GetPlayerFacing()

  local perc = abs((pi - abs(angle)) / pi)
  local r, g, b = pfUI.api.GetColorGradient(floor(perc * 100) / 100)
  local cell = modulo(floor(angle / (pi * 2) * 108 + 0.5), 108)
  local column, row = modulo(cell, 9), floor(cell / 9)

  this.model:SetTexCoord((column * 56) / 512, ((column + 1) * 56) / 512, (row * 42) / 512, ((row + 1) * 42) / 512)
  this.model:SetVertexColor(r, g, b)
  this.model:SetAlpha(1)
  this.texture:SetAlpha(0)

  local text = route.cur .. "/" .. getn(route.points)
  if text ~= lasttext or not owned then
    this.title:SetText("|cff33ffcc" .. route.name .. "|r")
    this.description:SetText("|cffffffffWaypoint " .. text .. "|r")
    lasttext = text
  end

  local distance = floor(sqrt(dx * dx + dy * dy) * 10) / 10
  if distance ~= lastdist or not owned then
    this.distance:SetText("|cffaaaaaa" .. pfQuest_Loc["Distance"] .. ": " .. format("%.1f", distance))
    lastdist = distance
  end

  owned = true
end)

-- worldmap: draw the loop
local overlay = CreateFrame("Frame", "pfQuestRouterOverlay", WorldMapButton)
overlay:SetAllPoints(WorldMapButton)
overlay:SetFrameLevel(113)

local dots, used = {}, 0

local function Dot(x, y, size, r, g, b, a)
  used = used + 1
  local tex = dots[used]
  if not tex then
    tex = overlay:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(pfQuestConfig.path .. "\\img\\route")
    dots[used] = tex
  end

  tex:SetWidth(size)
  tex:SetHeight(size)
  tex:SetVertexColor(r, g, b, a)
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", WorldMapButton, "TOPLEFT", x / 100 * WorldMapButton:GetWidth(), -y / 100 * WorldMapButton:GetHeight())
  tex:Show()
end

-- waypoint markers are buttons: right-click takes a waypoint out of the loop
-- (the marker stays, so it can be right-clicked back in), left-click heads
-- for it next
local markers, usedmarkers = {}, 0

local function MarkerEnter()
  local p = this.point
  local tooltip = WorldMapTooltip or GameTooltip
  tooltip:SetOwner(this, "ANCHOR_RIGHT")
  tooltip:SetText(route and route.name or "", 0.2, 1, 0.8)
  if p.off then
    tooltip:AddLine("Removed from route", 1, 0.3, 0.3)
    tooltip:AddLine("Right-click: add back", 1, 1, 1)
  else
    tooltip:AddLine("Waypoint " .. (p.order or "?") .. "/" .. (route and getn(route.points) or "?"), 1, 1, 1)
    tooltip:AddLine("Left-click: go here next", 1, 1, 1)
    tooltip:AddLine("Right-click: remove from route", 1, 1, 1)
  end
  tooltip:Show()
end

local function MarkerLeave()
  local tooltip = WorldMapTooltip or GameTooltip
  tooltip:Hide()
end

local function MarkerClick()
  if not route then
    return
  end

  if arg1 == "RightButton" then
    Toggle(this.point)
  elseif not this.point.off then
    SetTarget(this.point)
  end
end

local function Marker(p, size, r, g, b, a)
  usedmarkers = usedmarkers + 1
  local marker = markers[usedmarkers]
  if not marker then
    marker = CreateFrame("Button", nil, overlay)
    marker:SetFrameLevel(overlay:GetFrameLevel() + 1)
    marker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    marker:SetScript("OnClick", MarkerClick)
    marker:SetScript("OnEnter", MarkerEnter)
    marker:SetScript("OnLeave", MarkerLeave)
    marker.tex = marker:CreateTexture(nil, "OVERLAY")
    marker.tex:SetTexture(pfQuestConfig.path .. "\\img\\route")
    marker.tex:SetAllPoints(marker)
    markers[usedmarkers] = marker
  end

  marker.point = p
  marker:SetWidth(size)
  marker:SetHeight(size)
  marker.tex:SetVertexColor(r, g, b, a)
  marker:ClearAllPoints()
  marker:SetPoint(
    "CENTER",
    WorldMapButton,
    "TOPLEFT",
    p[1] / 100 * WorldMapButton:GetWidth(),
    -p[2] / 100 * WorldMapButton:GetHeight()
  )
  marker:Show()
end

local function Draw()
  used, usedmarkers = 0, 0

  if route and CurrentMap() == route.zone then
    local points, n = route.points, getn(route.points)
    for i = 1, n do
      local a, b = points[i], points[i == n and 1 or i + 1]
      -- the leg leading to the current waypoint is highlighted
      local hl = (i == n and 1 or i + 1) == route.cur
      a.order = i

      if n > 1 then
        local count = max(1, ceil(Dist(a[1], a[2], b[1], b[2])))
        for step = 1, count - 1 do
          local x = a[1] + (b[1] - a[1]) / count * step
          local y = a[2] + (b[2] - a[2]) / count * step
          if hl then
            Dot(x, y, 4, 1, 0.8, 0.4, 1)
          else
            Dot(x, y, 4, 0.2, 1, 0.8, 0.8)
          end
        end
      end
    end

    local target = points[route.cur]
    for _, p in ipairs(route.all) do
      if p.off then
        Marker(p, 10, 1, 0.2, 0.2, 0.8)
      elseif p == target then
        Marker(p, 14, 1, 0.8, 0.2, 1)
      else
        Marker(p, 10, 0.2, 1, 0.8, 1)
      end
    end
  end

  for i = used + 1, getn(dots) do
    dots[i]:Hide()
  end
  for i = usedmarkers + 1, getn(markers) do
    markers[i]:Hide()
  end
end

-- only runs while the worldmap is visible
overlay:SetScript("OnUpdate", function()
  local zone, width = CurrentMap(), WorldMapButton:GetWidth()
  if not router.redraw and zone == this.zone and width == this.width then
    return
  end

  router.redraw = nil
  this.zone, this.width = zone, width
  Draw()
end)

-- minimap: draw the part of the loop that is in view
local minimap = CreateFrame("Frame", "pfQuestRouterMinimap", pfMap.drawlayer)
minimap:SetAllPoints(pfMap.drawlayer)
minimap:SetFrameLevel(pfMap.drawlayer:GetFrameLevel() + 1)

local MINIMAP_SPACING = 6 -- pixels between two dots of a leg

local mdots, mused = {}, 0

local function MiniDot(x, y, size, r, g, b, a)
  mused = mused + 1
  local tex = mdots[mused]
  if not tex then
    tex = minimap:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(pfQuestConfig.path .. "\\img\\route")
    mdots[mused] = tex
  end

  tex:SetWidth(size)
  tex:SetHeight(size)
  tex:SetVertexColor(r, g, b, a)
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", minimap, "CENTER", x, -y)
  tex:Show()
end

-- x, y: pixel offset from the minimap center; square minimaps come with pfUI
local function MiniVisible(x, y, pad, w, h, square)
  if square then
    return abs(x) + pad < w / 2 and abs(y) + pad < h / 2
  end
  return sqrt(x * x + y * y) + pad < w / 2
end

local function DrawMini()
  mused = 0

  local px, py, sizes
  if route and pfQuestRouter_data.minimap ~= false and pfMap:GetMapIDByName(GetRealZoneText()) == route.zone then
    px, py = PlayerPos(route.zone)
    sizes = pfMap.minimap_sizes[route.zone]
  end

  if px and sizes and pfMap:HasMinimap(route.zone) then
    local layer = pfMap.drawlayer
    local zoom = pfMap.minimap_zoom[pfMap.minimap_indoor()][layer:GetZoom()]
    local w, h = layer:GetWidth(), layer:GetHeight()
    -- pixels per map unit
    local xdraw, ydraw = w / (zoom / sizes[1]) / 100, h / (zoom / sizes[2]) / 100
    local square = pfUI.minimap
    local reach = sqrt(w * w + h * h) / 2

    local points, n = route.points, getn(route.points)
    for i = 1, n do
      local a, b = points[i], points[i == n and 1 or i + 1]
      local ax, ay = (a[1] - px) * xdraw, (a[2] - py) * ydraw
      local dx, dy = (b[1] - px) * xdraw - ax, (b[2] - py) * ydraw - ay
      local len = sqrt(dx * dx + dy * dy)

      if len > 0 then
        -- the leg leading to the current waypoint is highlighted
        local hl = (i == n and 1 or i + 1) == route.cur
        local count = ceil(len / MINIMAP_SPACING)
        -- only walk the stretch of the leg that can be in view: around its
        -- closest approach to the player
        local nearest, span = -(ax * dx + ay * dy) / (len * len), reach / len

        for step = max(1, ceil((nearest - span) * count)), min(count - 1, floor((nearest + span) * count)) do
          local x, y = ax + dx * step / count, ay + dy * step / count
          if MiniVisible(x, y, 2, w, h, square) then
            if hl then
              MiniDot(x, y, 3, 1, 0.8, 0.4, 1)
            else
              MiniDot(x, y, 3, 0.2, 1, 0.8, 0.8)
            end
          end
        end
      end

      if MiniVisible(ax, ay, 5, w, h, square) then
        if i == route.cur then
          MiniDot(ax, ay, 10, 1, 0.8, 0.2, 1)
        else
          MiniDot(ax, ay, 7, 0.2, 1, 0.8, 1)
        end
      end
    end
  end

  for i = mused + 1, getn(mdots) do
    mdots[i]:Hide()
  end
end

minimap:SetScript("OnUpdate", function()
  if not route then
    if mused > 0 then
      DrawMini()
    end
    return
  end

  if (this.throttle or 0) > GetTime() then
    return
  end
  this.throttle = GetTime() + 0.05

  -- redraw on movement, zoom and route changes, and once per second anyway
  local x, y = GetPlayerMapPosition("player")
  local zoom = pfMap.drawlayer:GetZoom()
  if
    not router.miniredraw
    and x == this.x
    and y == this.y
    and zoom == this.zoom
    and (this.tick or 0) > GetTime()
  then
    return
  end

  router.miniredraw = nil
  this.tick = GetTime() + 1
  this.x, this.y, this.zoom = x, y, zoom
  DrawMini()
end)

SLASH_PFQUESTROUTER1, SLASH_PFQUESTROUTER2 = "/pfr", "/router"
SlashCmdList["PFQUESTROUTER"] = function(input)
  input = string.gsub(input or "", "^%s*(.-)%s*$", "%1")
  local _, _, cmd, rest = strfind(input, "^(%S*)%s*(.-)$")
  cmd = strlower(cmd or "")

  if cmd == "" or cmd == "help" then
    Print("grind routes from database spawn points")
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc/pfr|cffffffff start |cffcccccc - Route over the |cff33ffcc/db|cffcccccc search results on the current map")
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc/pfr|cffffffff <name> |cffcccccc - Search a unit or object by exact name and route it")
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc/pfr|cffffffff stop |cffcccccc - Remove the route")
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc/pfr|cffffffff next|cffcccccc / |cffffffffprev |cffcccccc - Skip to the next / previous waypoint")
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc/pfr|cffffffff reverse |cffcccccc - Walk the loop in the other direction")
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cff33ffcc/pfr|cffffffff radius <n> |cffcccccc - Merge spawns closer than <n> into one waypoint (current: " .. Radius() .. ")"
    )
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cff33ffcc/pfr|cffffffff minimap |cffcccccc - Draw the route on the minimap (current: "
        .. (pfQuestRouter_data.minimap == false and "off" or "on")
        .. ")"
    )
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cff33ffcc/pfr|cffffffff debug |cffcccccc - Explain waypoint changes in chat (current: "
        .. (pfQuestRouter_data.debug and "on" or "off")
        .. ")"
    )
    if route then
      Print(format("active: |cffffcc00%s|r, waypoint %d/%d.", route.name, route.cur, getn(route.points)))
    end
    return
  end

  if cmd == "minimap" then
    -- nil means on, so the default needs no saved value
    if pfQuestRouter_data.minimap == false then
      pfQuestRouter_data.minimap = nil
    else
      pfQuestRouter_data.minimap = false
    end
    router.miniredraw = true
    Print("Minimap route " .. (pfQuestRouter_data.minimap == false and "|cffff3333OFF" or "|cff33ff33ON"))
    return
  end

  if cmd == "debug" then
    pfQuestRouter_data.debug = not pfQuestRouter_data.debug or nil
    Print("Debug mode " .. (pfQuestRouter_data.debug and "|cff33ff33ON" or "|cffff3333OFF"))
    return
  end

  if cmd == "start" or cmd == "go" then
    StartFromMap()
    return
  end

  if cmd == "radius" then
    local value = tonumber(rest)
    if not value or value < 0 then
      Print("Usage: |cff33ffcc/pfr radius <n>|r (current: " .. Radius() .. ")")
      return
    end

    pfQuestRouter_data.radius = value
    Print("Radius set to " .. value .. ".")
    if route then
      Build(route.name, route.zone, route.raw)
    end
    return
  end

  if cmd == "stop" or cmd == "next" or cmd == "skip" or cmd == "prev" or cmd == "reverse" then
    if not route then
      Print("No active route.")
    elseif cmd == "stop" then
      Stop()
      Print("Route removed.")
    elseif cmd == "prev" then
      Step(-1)
    elseif cmd == "reverse" then
      Reverse()
    else
      Step(1)
    end
    return
  end

  StartFromSearch(input)
end
