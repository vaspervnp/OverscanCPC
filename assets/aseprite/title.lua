-- ===========================================================================
-- title.lua - the title screen, as a picture rather than as text.
--
-- The one the game boots into now is drawn by the text engine: the name in
-- big letters, two coral bands, and nothing else. This is the poster - the
-- name in the game's own font at six times the size with an outline and a
-- shadow, the cat drawn properly rather than at twelve pixels across, and the
-- cast standing round it, stamped from the same art the rooms use.
--
-- One in each language. Everything but the lettering is shared, because the
-- cat does not need translating.
--
-- 192 x 272 mode 0 pixels, which is the whole overscan screen: 384 x 272 on
-- the monitor. Pen 0 is left transparent - that is the background the game
-- sets, and at the title it is navy.
-- ===========================================================================

local A = dofile(ASEDIR .. "/cpcart.lua")
local CAST = dofile(ASEDIR .. "/cast.lua")
local FONT = A.readFont(ASEDIR .. "/font.txt")
local SPR = ASEDIR .. "/spr/"
local DEC = ASEDIR .. "/png/"

local W, H = 192, 272
local FLOOR = 240

--- "THE GREAT" -> glyph names. Greek is passed as a list, because folding it
--- onto the Latin shapes is tools/mktext.py's job, not this script's.
local function ascii(s)
  local out = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    out[#out + 1] = (c == " ") and "SPACE" or c
  end
  return out
end

-- --- the cat, drawn at the size a title screen wants ----------------------
local function loukoumas(x0, y0)
  local function e(cx, cy, rx, ry, pen, fill)
    A.ellipse(x0 + cx, y0 + cy, rx, ry, pen, fill)
  end

  -- tail, curling up behind him
  for t = 0, 24 do
    local a = t / 24
    A.ellipse(x0 + 46 + 8 * a, y0 + 62 - 34 * a * a, 2.5, 3, 2)
  end
  for t = 0, 2 do
    A.ellipse(x0 + 50 + t * 2, y0 + 50 - t * 11, 2.5, 3, 7)
  end

  -- ears first, so the head covers the bottom of them
  A.tri(x0 + 8, y0 + 0, x0 + 4, y0 + 18, x0 + 20, y0 + 12, 2)
  A.tri(x0 + 42, y0 + 0, x0 + 46, y0 + 18, x0 + 30, y0 + 12, 2)
  A.tri(x0 + 9, y0 + 5, x0 + 8, y0 + 15, x0 + 17, y0 + 12, 1)
  A.tri(x0 + 41, y0 + 5, x0 + 42, y0 + 15, x0 + 33, y0 + 12, 1)

  e(25, 58, 23, 24, 2)                        -- body
  e(25, 66, 15, 15, 15)                       -- and the belly he is on a diet for
  e(9, 78, 8, 5, 15)                          -- back paws
  e(41, 78, 8, 5, 15)
  e(25, 26, 21, 21, 2)                        -- head

  for _, s in ipairs({{17, 6}, {25, 4}, {33, 6}}) do   -- forehead stripes
    A.line(x0 + s[1], y0 + s[2], x0 + s[1] + 1, y0 + s[2] + 7, 7)
    A.line(x0 + s[1] + 1, y0 + s[2], x0 + s[1] + 2, y0 + s[2] + 7, 7)
  end

  e(17, 24, 5, 7, 3)                          -- eyes, the size the design
  e(33, 24, 5, 7, 3)                          -- document asked for
  e(17, 25, 2.5, 4, 4)
  e(33, 25, 2.5, 4, 4)
  A.px(x0 + 15, y0 + 22, 11)
  A.px(x0 + 31, y0 + 22, 11)

  e(25, 37, 10, 6, 15)                        -- muzzle
  e(25, 33, 2.5, 2, 1)                        -- nose
  A.line(x0 + 25, y0 + 35, x0 + 25, y0 + 38, 4)
  A.line(x0 + 21, y0 + 40, x0 + 24, y0 + 38, 4)
  A.line(x0 + 29, y0 + 40, x0 + 26, y0 + 38, 4)
  for _, wy in ipairs({34, 37, 40}) do        -- whiskers
    A.line(x0 + 14, y0 + wy, x0 + 2, y0 + wy - 3, 3)
    A.line(x0 + 36, y0 + wy, x0 + 48, y0 + wy - 3, 3)
  end

  -- and what all of this is for
  A.stampRows(CAST.SAUSAGE, x0 + 19, y0 + 50, 2, 2)
  e(13, 54, 7, 6, 15)                         -- front paws, holding it
  e(37, 54, 7, 6, 15)
end

-- --- the Pitsos, open, with the light on ----------------------------------
local function fridge(x0, y0)
  A.rect(x0, y0, 52, 140, 5)                  -- the body
  A.frame(x0, y0, 52, 140, 3)
  A.rect(x0 + 4, y0 + 4, 30, 132, 15)         -- the light inside
  for _, sy in ipairs({28, 60, 92}) do        -- shelves
    A.rect(x0 + 4, y0 + sy, 30, 3, 3)
  end
  A.stampRows(CAST.SAUSAGE, x0 + 8, y0 + 20, 2, 2)
  A.stampRows(CAST.SAUSAGE, x0 + 20, y0 + 52, 2, 2)
  A.stampRows(CAST.SAUSAGE, x0 + 10, y0 + 84, 2, 2)
  A.rect(x0 + 38, y0, 14, 140, 5)             -- the door, swung back
  A.frame(x0 + 38, y0, 14, 140, 3)
  A.line(x0 + 38, y0, x0 + 38, y0 + 139, 6)   -- the hinge
  A.rect(x0 + 41, y0 + 30, 3, 20, 3)          -- handles
  A.rect(x0 + 41, y0 + 86, 3, 20, 3)
  for _, ly in ipairs({100, 108, 116, 124}) do
    A.rect(x0 + 6, y0 + ly, 3, 5, 13)         -- the four digital locks
  end
  -- the light, lying across the floorboards
  A.tri(x0 + 2, FLOOR, x0 + 34, FLOOR, x0 - 34, H - 1, 15)
  A.tri(x0 + 34, FLOOR, x0 + 6, H - 1, x0 - 34, H - 1, 15)
end

-- --- the poster ------------------------------------------------------------
local function poster(title, subtitle, name)
  A.art(W, H)

  -- night above, floorboards below
  A.stampPng(DEC .. "MOON.png", 4, 64, 1, 1)
  for _, s in ipairs({{28, 70}, {184, 96}, {150, 88}, {36, 96}, {176, 128}}) do
    A.px(s[1], s[2], 3)
  end
  A.rect(0, FLOOR, W, H - FLOOR, 6)
  A.rect(0, FLOOR, W, 2, 7)
  for x = 0, W - 1, 24 do A.rect(x, FLOOR + 2, 1, H - FLOOR - 2, 7) end

  fridge(136, 100)

  -- the cast, all of it, standing where it would stand
  A.stampRows(CAST.ROBOT, 4, FLOOR - 28, 2, 2)
  A.stampRows(CAST.CANARY, 20, 108, 2, 2)
  A.stampPng(SPR .. "DOG.png", 114, FLOOR - 32, 2, 2)
  A.stampPng(SPR .. "PIGEON.png", 6, 152, 2, 2)
  A.stampPng(SPR .. "BAT.png", 114, 82, 2, 2)
  A.stampPng(SPR .. "STRAY.png", 148, 100 - 28, 2, 2)   -- up on the fridge
  A.stampPng(SPR .. "BALL.png", 106, 146, 2, 2)
  A.stampPng(SPR .. "WASP.png", 66, 124, 2, 2)
  A.stampPng(SPR .. "MILK.png", 28, FLOOR - 16, 2, 2)
  A.stampRows(CAST.SAUSAGE, 94, FLOOR - 16, 2, 2)
  A.stampRows(CAST.SAUSAGE, 104, FLOOR - 12, 2, 2)

  loukoumas(44, 156)

  -- the name, at six times the size, with a shadow under it
  local sx, sy, gap = 3, 6, 3
  local tw = A.textWidth(title, sx, gap)
  local tx = math.floor((W - tw) / 2)
  A.text(FONT, title, tx + 2, 8, sx, sy, 12, gap)
  A.text(FONT, title, tx, 6, sx, sy, 2, gap)
  A.outline(2, 4)

  local sw = A.textWidth(subtitle, 1, 1)
  A.text(FONT, subtitle, math.floor((W - sw) / 2), 56, 1, 2, 1, 1)

  A.save(ARTDIR, name)
end

poster(ascii("LOUKOUMAS"), ascii("THE GREAT SAUSAGE CHASE"), "TITLE_EN")
poster({"Λ", "O", "Y", "K", "O", "Y", "M", "A", "Σ"},
       {"T", "O", "SPACE", "K", "Y", "N", "H", "Γ", "I", "SPACE",
        "T", "O", "Y", "SPACE",
        "Λ", "O", "Y", "K", "A", "N", "I", "K", "O", "Y"}, "TITLE_EL")
