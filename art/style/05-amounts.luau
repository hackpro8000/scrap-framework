-- The plain kit's look amounts: flat colour with a light edge highlight and
-- contact shadow so forms read, and nothing else. Raise these to give the
-- game more shading; the framework helpers read every name here.
local EDGE_HIGHLIGHT = 0.35
local CONTACT_SHADOW = 0.3
-- Highlights take a lighter shade of the part's own colour, not a cream tint.
local EDGE_BLEND = 1
-- No top-to-bottom darkening.
local GRADIENT = 0
-- No wear: every part's wear amount is multiplied by this.
local WEAR = 0
-- No warp: panels stay perfectly flat and square.
local WARP = 0
local SMOOTH_ANGLE = 30
local TEXTURE = 256
