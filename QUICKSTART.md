# Quick Start Guide

## 5-Minute Setup

### Step 1: Prepare Hardware
1. Get Advanced Mining Turtles (as many as you want)
2. Attach Ender Modem to each turtle
3. Get a Wireless Pocket Computer (optional but recommended)

### Step 2: Install Files
Place all these files on each turtle:
- `config.lua`
- `protocol.lua`
- `state.lua`
- `utils.lua`
- `coordinator.lua`
- `miner.lua`

For pocket computer controller:
- `config.lua`
- `protocol.lua`
- `control.lua`

### Step 3: Setup Home Base
Place 3 chests at your home base:
```
      [Fuel Chest]  <- Above turtle (Y+1)
           |
[Item Chest] [TURTLE] <- Base level (Y)
           |
    [Cobble Chest]  <- Below turtle (Y-1)
```

**Chest Contents:**
- **Fuel Chest (above)**: Coal, charcoal, or other fuel
- **Item Chest (front)**: Empty - for ores and valuables
- **Cobble Chest (below)**: Cobblestone (at least 64 for walls)

### Step 4: Configure System
Edit `config.lua` on all devices:

```lua
-- Set your home base coordinates
HOME_X = 0      -- Where your turtle is now
HOME_Y = 64     -- Current Y level
HOME_Z = 0      -- Current Z coordinate

-- Adjust mining if desired
TUNNEL_LENGTH = 64   -- How far to mine
START_Y = -59        -- Y-level to mine (good for diamonds)
NUM_LAYERS = 3       -- How many vertical layers
```

### Step 5: Position Turtles
1. Place each turtle at home base (HOME_X, HOME_Y, HOME_Z)
2. Make turtle face **NORTH** (towards mining area)
3. Verify chests are in correct positions

### Step 6: Start Mining
On each turtle:
```lua
miner.lua
```

Turtle will:
- ✓ Register with network
- ✓ Claim a tunnel
- ✓ Navigate to tunnel start
- ✓ Begin mining automatically

### Step 7: Start Controller (Optional)
On pocket computer:
```lua
control.lua
```

You'll see:
- All turtles listed with status
- Real-time position updates
- Fuel and inventory levels
- Control buttons

## Basic Controls

### Pocket Computer
- **[A]** - Pause all turtles
- **[Z]** - Resume all turtles
- **[F]** - Refresh status
- **[Q]** - Quit controller
- **[Up/Down]** - Select individual turtle
- **[P]** - Pause selected turtle
- **[R]** - Resume selected turtle
- **[H]** - Send turtle home
- **[S]** - Shutdown turtle

### Adding More Turtles
Just start more turtles with `miner.lua` - they'll automatically join and claim work!

## What Happens Automatically

✓ **Fuel Management** - Returns home when low  
✓ **Inventory Management** - Deposits items when full  
✓ **Collision Avoidance** - Turtles coordinate movement  
✓ **Ore Vein Mining** - Follows ore veins automatically  
✓ **Resume After Crash** - Continues from last position  
✓ **Work Distribution** - Claims tunnels from shared queue  
✓ **Status Broadcasting** - Updates every 10 seconds  

## Troubleshooting

**Turtle not moving?**
- Check fuel in chest above
- Verify Ender Modem attached
- Check for obstructions

**Controller shows no turtles?**
- Press [F] to refresh
- Verify modem channel (should be 42)
- Check turtles are running

**Turtle stuck?**
- Wait 30 seconds (auto-recovery)
- Or restart turtle (will resume)

## Tips

1. **Start with 1 turtle** - Test before scaling
2. **Watch fuel usage** - Keep chest stocked
3. **Monitor controller** - See progress in real-time
4. **Add turtles gradually** - 2-3 at a time
5. **Keep chunk loaded** - Prevents turtle pausing

## Next Steps

- Read `README.md` for detailed documentation
- Customize `config.lua` for your needs
- Scale up to 5-10 turtles for maximum efficiency
- Set up automated fuel/item processing

## Support

If something isn't working:
1. Check this guide
2. Read `README.md` Troubleshooting section
3. Verify all files are present
4. Test with single turtle first
5. Check turtle has fuel and building blocks

