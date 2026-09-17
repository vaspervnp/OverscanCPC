-- ===========================================================================
-- sprites.lua - the enemies the house did not have.
--
-- The flat has a robot vacuum and a canary in it, which is all a flat needs.
-- The other nineteen rooms are a back yard, a pavement, a playground, a park,
-- six rooms of school, a car park, a bus, a vet's and a run of rooftops, and
-- a robot vacuum patrolling a park bench is not a joke that survives being
-- told nineteen times.
--
-- There are still only two behaviours - something that walks a platform and
-- something that flies an arc - because two is all the movement code needs to
-- be. What changes is what you are being chased by. See src/enemykind.asm.
--
-- Sizes are mode 0 pixels across and scanlines down, and a mode 0 pixel is
-- two scanlines wide: the dog below is 10 across, which is 20 pixels on the
-- monitor, against the cat's 24.
-- ===========================================================================

local A = dofile(ASEDIR .. "/cpcart.lua")
local OUT = ARTDIR

-- --- DOG: the terrier from next door. Back yard, pavement, the vet's -------
A.art(10, 16)
A.line(1, 6, 0, 2, 7)                         -- tail, up and wagging
A.ellipse(4, 8, 3.5, 4, 7)                    -- body
A.rect(2, 11, 2, 5, 7)                        -- legs
A.rect(6, 11, 2, 5, 7)
A.px(2, 15, 3); A.px(3, 15, 3); A.px(6, 15, 3); A.px(7, 15, 3)
A.ellipse(6, 10, 1.5, 2, 3)                   -- white chest
A.ellipse(8, 5, 2, 3, 7)                      -- head
A.ellipse(7, 2, 1, 2, 12)                     -- ear
A.px(9, 6, 3); A.px(9, 7, 3)                  -- muzzle
A.px(9, 5, 4)                                 -- nose
A.px(8, 4, 4)                                 -- eye
A.save(OUT, "DOG")

-- --- PIGEON: park, pavement, rooftops --------------------------------------
A.art(8, 10)
A.line(0, 8, 2, 6, 5)                         -- tail
A.ellipse(4, 6, 3, 3, 5)                      -- body
A.ellipse(3, 6, 2, 2, 3)                      -- wing
A.ellipse(6, 3, 1.5, 2, 5)                    -- head
A.px(5, 5, 9)                                 -- the green in its neck
A.px(7, 4, 7)                                 -- beak
A.px(6, 3, 4)                                 -- eye
A.px(3, 9, 1); A.px(5, 9, 1)                  -- feet
A.save(OUT, "PIGEON")

-- --- WASP: anywhere there are flowers --------------------------------------
A.art(6, 8)
A.ellipse(1, 2, 1.5, 1.5, 3)                  -- wings
A.ellipse(4, 1, 1.5, 1, 3)
A.ellipse(3, 5, 2, 2.5, 2)                    -- body
A.line(1, 4, 5, 4, 4)                         -- stripes
A.line(1, 6, 5, 6, 4)
A.ellipse(5, 2, 1, 1.5, 4)                    -- head
A.px(0, 7, 4)                                 -- sting
A.save(OUT, "WASP")

-- --- BALL: playground, gym, pitch ------------------------------------------
A.art(6, 12)
A.ell(3, 6, 6, 3)
A.ell(3, 6, 5, -1)
A.ell(3, 6, 5, 3)                             -- back again: a clean rim
A.px(2, 3, 4); A.px(3, 3, 4)                  -- the black patches
A.px(1, 6, 4); A.px(4, 6, 4)
A.px(2, 9, 4); A.px(3, 9, 4)
A.px(3, 5, 4); A.px(2, 7, 4)
A.save(OUT, "BALL")

-- --- PLANE: a paper dart, doing the rounds of the school -------------------
A.art(10, 8)
A.line(0, 1, 9, 4, 3)                         -- the top of the wing
A.line(0, 1, 2, 5, 3)
A.line(2, 5, 9, 4, 3)
A.flood(3, 4, 3)
A.line(0, 7, 9, 4, 5)                         -- and the shaded underside
A.line(0, 7, 2, 5, 5)
A.flood(3, 6, 5)
A.line(2, 5, 8, 4, 5)                         -- the crease
A.save(OUT, "PLANE")

-- --- MOP: the school caretaker's bucket, still wet -------------------------
A.art(8, 16)
A.line(6, 0, 4, 6, 6)                         -- handle
A.ellipse(6, 1, 2, 2, 15)                     -- the mop head
A.px(7, 3, 15); A.px(5, 3, 15)
for i = 0, 6 do
  local t = math.floor(i / 4)
  A.rect(1 + t, 7 + i, 6 - t * 2, 1, 11)
end
A.rect(1, 6, 6, 1, 3)                         -- rim
A.rect(2, 7, 4, 1, 3)                         -- water
A.rect(1, 14, 2, 2, 4)                        -- wheels
A.rect(5, 14, 2, 2, 4)
A.save(OUT, "MOP")

-- --- BLOB: whatever was in the beaker, and it has opinions ------------------
A.art(8, 10)
A.ellipse(4, 6, 4, 4, 9)
A.ellipse(5, 8, 2.5, 2, 8)
A.px(1, 2, 9); A.px(6, 1, 9)                  -- it is still dripping upwards
A.px(2, 3, 15)
A.px(2, 4, 3); A.px(5, 4, 3)                  -- eyes
A.px(2, 5, 4); A.px(5, 5, 4)
A.save(OUT, "BLOB")

-- --- SYRINGE: the vet's, and it floats --------------------------------------
A.art(10, 6)
A.rect(0, 1, 1, 4, 5)                         -- thumb rest
A.rect(1, 2, 2, 2, 5)                         -- plunger
A.rect(3, 1, 4, 4, 3)                         -- barrel
A.rect(4, 2, 3, 2, 11)                        -- and what is in it
A.line(7, 3, 9, 3, 5)                         -- needle
A.px(3, 0, 3); A.px(3, 5, 3)
A.save(OUT, "SYRINGE")

-- --- BAT: the rooftops, after dark ------------------------------------------
A.art(12, 8)
A.line(6, 2, 0, 0, 14)                        -- the leading edge of the wings
A.line(5, 2, 11, 0, 14)
A.line(0, 0, 1, 4, 14)
A.line(11, 0, 10, 4, 14)
A.line(1, 4, 4, 3, 14)
A.line(10, 4, 7, 3, 14)
A.flood(3, 2, 14)
A.flood(8, 2, 14)
A.ellipse(5.5, 4, 1.5, 3, 4)                  -- body
A.px(5, 0, 4); A.px(6, 0, 4)                  -- ears
A.px(5, 3, 13); A.px(6, 3, 13)                -- eyes
A.save(OUT, "BAT")

-- --- STRAY: the tom who was here first. Rooftops, and the car park ---------
A.art(12, 14)
A.line(11, 9, 11, 4, 5)                       -- tail
A.px(10, 4, 5)
A.ellipse(6, 9, 5, 4, 5)                      -- body
A.rect(3, 12, 2, 2, 5)                        -- legs
A.rect(7, 12, 2, 2, 5)
A.ellipse(3, 5, 3, 3.5, 5)                    -- head
A.line(0, 0, 1, 3, 5)                         -- ears
A.line(2, 0, 1, 3, 5)
A.line(4, 0, 5, 3, 5)
A.line(6, 0, 5, 3, 5)
A.ellipse(3, 7, 2, 1.5, 3)                    -- muzzle
A.px(2, 5, 9); A.px(4, 5, 9)                  -- green eyes, unlike the cat's
A.px(3, 7, 1)                                 -- nose
A.line(5, 8, 9, 8, 4)                         -- tabby stripes
A.line(6, 10, 9, 10, 4)
A.save(OUT, "STRAY")

-- --- MILK: a saucer of it, on the hardest shelf of every third room --------
-- Not an enemy. It is picked up like a sausage and blitted like one, so it
-- wants a mask the same way: see check_pickups in play.asm.
A.art(8, 8)
A.ellipse(3.5, 4, 4, 1.5, 3)                  -- the rim, seen from just above
A.ellipse(3.5, 4, 3, 1, 11)                   -- and what is in it
A.px(2, 3, 3); A.px(5, 4, 3)                  -- two highlights on the milk
for i = 0, 2 do A.rect(1 + i, 5 + i, 6 - i * 2, 1, 3) end
A.rect(2, 7, 4, 1, 5)                         -- the shadow under it
A.save(OUT, "MILK")
