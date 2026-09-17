-- ===========================================================================
-- cpcart.lua - the drawing kit the LOUKOUMAS artwork is built with.
--
-- Run inside Aseprite (batch mode, through the MCP server). It knows two
-- things the art has to obey and nothing else does:
--
--   * the sixteen pens are the CPC's, by hardware colour number, and a pixel
--     may only ever be one of them - tools/mkart.py refuses anything else;
--   * a mode 0 pixel is twice as wide as it is tall. Every canvas here is in
--     mode 0 pixels, so a circle has to be drawn half as wide as it is tall
--     to come out round on the monitor. ell() takes the on-screen radius and
--     halves it for you; everything else is raw.
--
-- Art is composed rather than typed: ellipses, lines and fills for the shapes
-- that are hard to place by hand, then single pixels for eyes and highlights.
-- ===========================================================================

local M = {}

-- Pen -> RGB, from pal_play in src/play.asm. The comment is the hardware
-- colour number written to the Gate Array.
M.PEN = {
  [0]  = {0, 0, 128},       --  4 deep navy - the wall, and the sky at night
  [1]  = {255, 128, 128},   --  7 coral
  [2]  = {255, 255, 0},     -- 10 butter yellow - the cat
  [3]  = {255, 255, 255},   -- 11 white
  [4]  = {0, 0, 0},         -- 20 black
  [5]  = {128, 128, 128},   --  0 grey - steel, tarmac, pigeons
  [6]  = {128, 128, 0},     -- 30 olive - wood in shadow
  [7]  = {255, 128, 0},     -- 14 orange - wood in the light, brick, fur
  [8]  = {0, 128, 0},       -- 22 dark green - leaves
  [9]  = {0, 255, 0},       -- 18 bright green - grass
  [10] = {0, 128, 128},     --  6 teal
  [11] = {0, 255, 255},     -- 19 bright cyan - water, glass
  [12] = {128, 0, 0},       -- 28 dark red
  [13] = {255, 0, 0},       -- 12 bright red
  [14] = {128, 0, 128},     -- 24 purple
  [15] = {255, 255, 128},   --  3 pale yellow - lamplight
}

local W, H, buf

--- Start a new picture, W by H mode 0 pixels, all of it transparent.
function M.art(w, h)
  W, H = w, h
  buf = {}
  for y = 0, h - 1 do
    buf[y] = {}
    for x = 0, w - 1 do buf[y][x] = -1 end
  end
end

function M.size() return W, H end

--- One pixel. pen -1 rubs it out again, which is how a crescent moon is made.
function M.px(x, y, pen)
  x, y = math.floor(x), math.floor(y)
  if x >= 0 and x < W and y >= 0 and y < H then buf[y][x] = pen end
end

function M.get(x, y)
  if x >= 0 and x < W and y >= 0 and y < H then return buf[y][x] end
  return -1
end

function M.rect(x, y, w, h, pen)
  for j = y, y + h - 1 do
    for i = x, x + w - 1 do M.px(i, j, pen) end
  end
end

function M.frame(x, y, w, h, pen)
  for i = x, x + w - 1 do M.px(i, y, pen); M.px(i, y + h - 1, pen) end
  for j = y, y + h - 1 do M.px(x, j, pen); M.px(x + w - 1, j, pen) end
end

--- An ellipse given its radii in mode 0 pixels. fill=false outlines it.
function M.ellipse(cx, cy, rx, ry, pen, fill)
  if fill == nil then fill = true end
  for y = math.ceil(cy - ry), math.floor(cy + ry) do
    for x = math.ceil(cx - rx), math.floor(cx + rx) do
      local dx, dy = (x - cx) / (rx + 0.5), (y - cy) / (ry + 0.5)
      local d = dx * dx + dy * dy
      if d <= 1.0 then
        if fill then
          M.px(x, y, pen)
        else
          -- keep only what is near the rim
          local inner = 0
          local ix, iy = (x - cx) / math.max(rx - 0.6, 0.1), (y - cy) / math.max(ry - 0.6, 0.1)
          inner = ix * ix + iy * iy
          if inner > 1.0 then M.px(x, y, pen) end
        end
      end
    end
  end
end

--- A circle that comes out round on the monitor: the radius is in scanlines,
--- and mode 0 pixels are two scanlines wide, so x gets half of it.
function M.ell(cx, cy, r, pen, fill)
  M.ellipse(cx, cy, r / 2, r, pen, fill)
end

--- Bresenham, because a slide and an aerial are all diagonals.
function M.line(x0, y0, x1, y1, pen)
  x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    M.px(x0, y0, pen)
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

--- Flood fill, four ways, over whatever pen is already at (x,y).
function M.flood(x, y, pen)
  local want = M.get(x, y)
  if want == pen then return end
  local stack = {{x, y}}
  while #stack > 0 do
    local p = table.remove(stack)
    local px, py = p[1], p[2]
    if px >= 0 and px < W and py >= 0 and py < H and buf[py][px] == want then
      buf[py][px] = pen
      stack[#stack + 1] = {px + 1, py}
      stack[#stack + 1] = {px - 1, py}
      stack[#stack + 1] = {px, py + 1}
      stack[#stack + 1] = {px, py - 1}
    end
  end
end

--- Replace one pen with another across the whole picture.
function M.recolour(from, to)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if buf[y][x] == from then buf[y][x] = to end
    end
  end
end

--- Hand the picture to Aseprite and write it out as a PNG.
function M.save(dir, name)
  local spr = Sprite(W, H, ColorMode.RGB)
  local img = Image(W, H, ColorMode.RGB)      -- a new image is transparent
  local used = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local pen = buf[y][x]
      if pen >= 0 then
        local c = M.PEN[pen]
        if not c then error(name .. ": no such pen " .. pen) end
        used[pen] = true
        img:drawPixel(x, y, app.pixelColor.rgba(c[1], c[2], c[3], 255))
      end
    end
  end
  local layer = spr.layers[1]
  local cel = layer:cel(1)
  if cel then
    cel.image = img
    cel.position = Point(0, 0)
  else
    spr:newCel(layer, 1, img, Point(0, 0))
  end
  local pal = Palette(16)
  for i = 0, 15 do
    local c = M.PEN[i]
    pal:setColor(i, Color{r = c[1], g = c[2], b = c[3], a = 255})
  end
  spr:setPalette(pal)
  spr:saveAs(dir .. "/" .. name .. ".png")
  spr:close()
  local n = 0
  for _ in pairs(used) do n = n + 1 end
  print(string.format("%-10s %2d x %2d  %d pens", name, W, H, n))
end

return M
