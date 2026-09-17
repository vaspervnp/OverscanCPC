-- ===========================================================================
-- decals.lua - the scenery that is not a rectangle.
--
-- Furniture in this game is a list of filled boxes, which is why fifty bytes
-- can hold a sofa and why nothing in the flat costs any memory worth counting.
-- It also means everything has corners. That was fine indoors - a fridge does
-- have corners - but nineteen new rooms are back yards, parks, a playground
-- and a set of rooftops, and a tree drawn as three stacked boxes looks like
-- three stacked boxes.
--
-- So these are bitmaps: drawn here with ellipses and lines, exported as PNGs
-- and turned into Z80 data by tools/mkart.py. They are painted once into the
-- background when a room loads and never touched again, so they cost nothing
-- while the game is running - only the bytes they take up.
--
-- Sizes are in mode 0 pixels across and scanlines down. A mode 0 pixel is two
-- scanlines wide, so a canvas 24 across is 48 wide on the monitor.
-- ===========================================================================

local A = dofile(ASEDIR .. "/cpcart.lua")
local OUT = ARTDIR

--- The underside of a cloud, or of anything else the light comes down onto:
--- find the lowest pixel in each column and shade the two above it.
local function shade_bottom(pen, depth)
  local W, H = A.size()
  for x = 0, W - 1 do
    local low = nil
    for y = 0, H - 1 do
      if A.get(x, y) >= 0 then low = y end
    end
    if low then
      for y = low - depth + 1, low do
        if A.get(x, y) >= 0 then A.px(x, y, pen) end
      end
    end
  end
end

-- --- CLOUD: four puffs with a flat bottom, 48 x 16 on the monitor ----------
A.art(24, 16)
A.ellipse(4, 10, 3, 5, 3)
A.ellipse(10, 8, 4, 7, 3)
A.ellipse(16, 9, 3.5, 6, 3)
A.ellipse(20, 11, 2, 3.5, 3)
for y = 14, 15 do for x = 0, 23 do A.px(x, y, -1) end end
shade_bottom(5, 2)
A.save(OUT, "CLOUD")

-- --- CLOUD2: the small one, so a sky can have two ------------------------
A.art(16, 10)
A.ellipse(5, 6, 3, 4, 3)
A.ellipse(10, 5, 3.5, 5, 3)
for y = 9, 9 do for x = 0, 15 do A.px(x, y, -1) end end
shade_bottom(5, 1)
A.save(OUT, "CLOUD2")

-- --- TREETOP: a lemon tree's canopy. The trunk is a box in the room -------
A.art(20, 24)
A.ellipse(10, 12, 9, 11, 8)
A.ellipse(7, 8, 5, 6, 9)
A.ellipse(14, 16, 4, 5, 6)
for _, p in ipairs({{5, 16}, {13, 6}, {16, 12}}) do
  A.ellipse(p[1], p[2], 1, 2, 2)              -- three lemons
end
A.px(4, 11, 9); A.px(16, 8, 9); A.px(8, 19, 8)
A.save(OUT, "TREETOP")

-- --- BUSHY: a shrub with berries in it ------------------------------------
A.art(14, 12)
A.ellipse(7, 7, 6, 5, 8)
A.ellipse(5, 5, 3, 3, 9)
A.px(10, 6, 13); A.px(4, 9, 13); A.px(8, 3, 13)
A.save(OUT, "BUSHY")

-- --- SUN: a disc with eight short rays -------------------------------------
A.art(14, 22)
A.ell(7, 11, 8, 2)
A.ell(7, 11, 5, 15)
for _, r in ipairs({{7, 0}, {7, 21}, {1, 11}, {13, 11},
                    {3, 4}, {11, 4}, {3, 18}, {11, 18}}) do
  A.px(r[1], r[2], 2)
end
A.save(OUT, "SUN")

-- --- MOON: the same disc with a bite out of it, and three stars ------------
A.art(14, 22)
A.ell(6, 11, 9, 15)
A.ell(11, 11, 9, -1)                          -- carve the crescent out again
A.px(12, 4, 3); A.px(13, 14, 3); A.px(10, 20, 3)
A.save(OUT, "MOON")

-- --- FLOWERS: a clump at the foot of a wall --------------------------------
A.art(12, 10)
local stems = {{2, 4, 13}, {6, 3, 15}, {9, 5, 1}}
for _, f in ipairs(stems) do
  A.line(f[1], 9, f[1], f[2] + 2, 9)
  A.ellipse(f[1], f[2], 1, 2, f[3])
  A.px(f[1], f[2], 2)                         -- the middle of the flower
end
A.px(1, 7, 8); A.px(5, 8, 8); A.px(10, 7, 8)
A.save(OUT, "FLOWERS")

-- --- GRASS: a strip of blades to break the line of a floor -----------------
A.art(16, 6)
local blade = {3, 5, 2, 4, 5, 3, 5, 2}
for i, h in ipairs(blade) do
  local x = (i - 1) * 2
  A.line(x, 5, x + 1, 5 - h, 9)
  A.px(x, 5, 8)
end
A.save(OUT, "GRASS")

-- --- SLIDE: the playground's, ladder on the right --------------------------
A.art(20, 28)
A.line(15, 8, 15, 27, 5)
A.line(18, 8, 18, 27, 5)
for y = 10, 26, 4 do A.line(15, y, 18, y, 5) end
A.rect(12, 6, 7, 2, 3)
for t = 0, 30 do
  local x = 13 - 11 * t / 30
  local y = 8 + 16 * t / 30
  A.px(x, y, 3)
  A.px(x, y + 1, 11)
  A.px(x, y + 2, 11)
  A.px(x, y + 3, 5)
end
A.rect(1, 25, 4, 2, 5)
A.save(OUT, "SLIDE")

-- --- SWING: two chains and a seat ------------------------------------------
A.art(16, 22)
A.line(3, 1, 12, 1, 5)                        -- the beam
A.line(4, 2, 0, 21, 5)                        -- and the A-frame under it
A.line(5, 2, 1, 21, 5)
A.line(11, 2, 15, 21, 5)
A.line(10, 2, 14, 21, 5)
A.line(6, 2, 6, 16, 3)                        -- the chains
A.line(10, 2, 10, 16, 3)
A.rect(5, 17, 6, 2, 7)
A.rect(5, 19, 6, 1, 12)
A.save(OUT, "SWING")

-- --- GOAL: the net at the end of the school pitch ---------------------------
A.art(24, 16)
A.line(1, 1, 22, 1, 3)
A.line(1, 1, 1, 15, 3)
A.line(22, 1, 22, 15, 3)
for x = 4, 21, 3 do A.line(x, 2, x, 15, 5) end
for y = 4, 15, 3 do A.line(2, y, 21, y, 5) end
A.save(OUT, "GOAL")

-- --- HOOP: backboard, ring and net -----------------------------------------
A.art(12, 14)
A.rect(3, 0, 9, 8, 15)
A.frame(3, 0, 9, 8, 3)
A.ellipse(4, 9, 3, 1, 7)
for _, x in ipairs({1, 3, 5, 7}) do A.line(x, 10, 4, 13, 3) end
A.save(OUT, "HOOP")

-- --- LAMP: a street light, arm curving out to the right ---------------------
A.art(12, 26)
A.rect(1, 6, 2, 20, 5)
A.rect(0, 24, 4, 2, 5)
A.line(2, 6, 3, 4, 5)
A.line(3, 4, 5, 3, 5)
A.line(5, 3, 8, 3, 5)
A.rect(7, 3, 4, 2, 3)
A.rect(7, 5, 4, 2, 15)
A.px(8, 7, 15); A.px(9, 7, 15); A.px(8, 8, 15)
A.save(OUT, "LAMP")

-- --- SIGN: no entry, on a post ---------------------------------------------
A.art(12, 18)
A.rect(5, 8, 2, 10, 5)
A.ell(6, 6, 6, 3)
A.ell(6, 6, 5, 13)
A.rect(3, 5, 7, 2, 3)
A.save(OUT, "SIGN")

-- --- PLANT: a pot plant, for a reception desk or a staff room ---------------
A.art(12, 20)
for i = 0, 5 do
  local t = math.floor(i / 2)
  A.rect(1 + t, 14 + i, 10 - t * 2, 1, 7)
end
A.rect(0, 12, 12, 2, 12)
-- A leaf is two lines side by side with a lighter one up the middle, or it
-- comes out as a scribble at this size.
local function leaf(tx, ty)
  A.line(5, 12, tx, ty, 8)
  A.line(6, 12, tx + 1, ty, 8)
  A.line(6, 11, tx, ty + 1, 9)
end
leaf(0, 5); leaf(2, 1); leaf(5, 0); leaf(9, 1); leaf(10, 6)
A.save(OUT, "PLANT")

-- --- FLASK: something green, still bubbling ---------------------------------
A.art(10, 16)
A.rect(3, 0, 4, 1, 3)
A.line(4, 1, 4, 5, 3)
A.line(5, 1, 5, 5, 3)
A.line(4, 5, 0, 14, 3)
A.line(5, 5, 9, 14, 3)
A.line(0, 14, 9, 14, 3)
A.flood(5, 12, 11)
for y = 11, 13 do                             -- whatever is left in it
  for x = 0, 9 do
    if A.get(x, y) == 11 then A.px(x, y, 9) end
  end
end
A.px(3, 9, 15); A.px(6, 7, 15); A.px(4, 5, 15)
A.save(OUT, "FLASK")

-- --- GLOBE: the classroom's, on its stand -----------------------------------
A.art(10, 18)
A.ell(5, 7, 7, 11)
A.ellipse(3, 4, 1.5, 2, 8)
A.ellipse(6, 9, 2, 3, 8)
A.ellipse(2, 10, 1, 1.5, 8)
A.rect(4, 14, 2, 2, 5)
A.ellipse(5, 17, 3, 1, 5)
A.save(OUT, "GLOBE")

-- --- AERIAL: five elements on a boom, and the roofs read as roofs ----------
A.art(16, 14)
A.line(3, 2, 15, 2, 5)
A.line(3, 2, 3, 13, 5)
local el = {5, 4, 3, 3, 2}
for i, h in ipairs(el) do
  local x = 5 + (i - 1) * 2
  A.line(x, 2 - h, x, 2 + h, 5)
end
A.save(OUT, "AERIAL")
