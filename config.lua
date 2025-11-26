-- Advanced Branch Miner Configuration
-- Shared configuration for all turtles and pocket computer controller

local config = {
    -- ========== MINING PARAMETERS ==========
    
    -- Tunnel dimensions
    TUNNEL_LENGTH = 64,          -- Blocks per tunnel (for side branches)
    TUNNEL_SPACING = 3,          -- Blocks between parallel tunnels (calculated from tunnel size)
    TUNNEL_HEIGHT = 2,           -- Blocks high (2 = efficient for diamonds)
    TUNNEL_SIZE = "2x2",         -- Tunnel size: "2x1", "2x2", or "3x3" (set by project)
    
    -- Branch spacing based on tunnel size
    BRANCH_SPACING = {
        ["2x1"] = 3,             -- 2x1 tunnels: 3 blocks apart
        ["2x2"] = 5,             -- 2x2 tunnels: 5 blocks apart
        ["3x3"] = 7              -- 3x3 tunnels: 7 blocks apart
    },
    
    -- Tunnel features
    WALL_PROTECTION = true,      -- Check walls for ore/holes and fill them (set by project)
    
    -- Vertical mining configuration
    START_Y = -59,               -- Starting Y-level (optimal for diamonds in 1.18+)
    NUM_LAYERS = 3,              -- Number of vertical layers to mine
    LAYER_SPACING = 6,           -- Vertical blocks between layers
    
    -- Torch placement
    TORCH_INTERVAL = 8,          -- Place torch every N blocks (prevents mob spawns)
    
    -- Work distribution
    MAX_TUNNELS = 100,           -- Maximum tunnels to generate in work queue
    
    -- ========== NETWORK SETTINGS ==========
    
    -- Modem configuration
    MODEM_CHANNEL = 42,          -- Primary communication channel
    PROTOCOL_VERSION = 1,        -- Protocol version (for compatibility checking)
    
    -- Timing parameters
    HEARTBEAT_INTERVAL = 10,     -- Seconds between status broadcasts
    COLLISION_TIMEOUT = 5,       -- Seconds to wait for movement clearance
    CONTROLLER_TIMEOUT = 3,      -- Seconds to wait for command ACK
    MESSAGE_RETRY_DELAY = 1,     -- Seconds between message retries
    MAX_MESSAGE_RETRIES = 3,     -- Maximum retry attempts for messages
    
    -- Heartbeat tracking
    OFFLINE_THRESHOLD = 30,      -- Seconds without heartbeat = offline
    STALLED_THRESHOLD = 60,      -- Seconds at same position = stalled
    
    -- ========== HOME BASE LOCATION ==========
    
    -- Base coordinates (where turtles start and return)
    HOME_X = 0,
    HOME_Y = 64,
    HOME_Z = 0,
    
    -- Chest positions (relative to home or absolute coords)
    CHEST_ORES = {x = 0, y = 64, z = 1},      -- Ores and valuable items
    CHEST_COBBLE = {x = 0, y = 63, z = 0},    -- Cobblestone and common blocks
    CHEST_FUEL = {x = 0, y = 65, z = 0},      -- Fuel items (coal, charcoal, etc)
    
    -- ========== SAFETY THRESHOLDS ==========
    
    -- Fuel management
    MIN_FUEL = 500,              -- Return to base if fuel below this
    LOW_FUEL_WARNING = 1000,     -- Warn when fuel below this
    FUEL_BUFFER = 200,           -- Extra fuel reserve for emergencies
    
    -- Inventory management
    MIN_FREE_SLOTS = 2,          -- Return to base if free slots below this
    COBBLE_KEEP_AMOUNT = 32,     -- Minimum building blocks to keep in slot 1 (restocks to 64)
    
    -- Error handling
    MAX_RETRIES = 5,             -- Maximum movement retry attempts
    STUCK_TIMEOUT = 30,          -- Seconds stuck before requesting help
    MAX_VEIN_DEPTH = 8,          -- Maximum blocks to follow ore vein
    
    -- ========== BLOCK IDENTIFICATION ==========
    
    -- Ore blocks to mine (vein mining)
    ORE_BLOCKS = {
        ["minecraft:coal_ore"] = true,
        ["minecraft:deepslate_coal_ore"] = true,
        ["minecraft:iron_ore"] = true,
        ["minecraft:deepslate_iron_ore"] = true,
        ["minecraft:copper_ore"] = true,
        ["minecraft:deepslate_copper_ore"] = true,
        ["minecraft:gold_ore"] = true,
        ["minecraft:deepslate_gold_ore"] = true,
        ["minecraft:redstone_ore"] = true,
        ["minecraft:deepslate_redstone_ore"] = true,
        ["minecraft:lapis_ore"] = true,
        ["minecraft:deepslate_lapis_ore"] = true,
        ["minecraft:diamond_ore"] = true,
        ["minecraft:deepslate_diamond_ore"] = true,
        ["minecraft:emerald_ore"] = true,
        ["minecraft:deepslate_emerald_ore"] = true,
        ["minecraft:nether_quartz_ore"] = true,
        ["minecraft:nether_gold_ore"] = true,
        ["minecraft:ancient_debris"] = true,
    },
    
    -- Building blocks (goes to cobble chest)
    BUILDING_BLOCKS = {
        ["minecraft:cobblestone"] = true,
        ["minecraft:stone"] = true,
        ["minecraft:diorite"] = true,
        ["minecraft:granite"] = true,
        ["minecraft:andesite"] = true,
        ["minecraft:deepslate"] = true,
        ["minecraft:cobbled_deepslate"] = true,
        ["minecraft:tuff"] = true,
        ["minecraft:dirt"] = true,
        ["minecraft:gravel"] = true,
        ["minecraft:netherrack"] = true,
    },
    
    -- Fuel items
    FUEL_ITEMS = {
        ["minecraft:coal"] = 80,
        ["minecraft:charcoal"] = 80,
        ["minecraft:coal_block"] = 800,
        ["minecraft:lava_bucket"] = 1000,
        ["minecraft:blaze_rod"] = 120,
    },
}

-- Helper functions
function config.isOre(blockName)
    return config.ORE_BLOCKS[blockName] == true
end

function config.isBuildingBlock(blockName)
    return config.BUILDING_BLOCKS[blockName] == true
end

function config.getFuelValue(itemName)
    return config.FUEL_ITEMS[itemName] or 0
end

function config.getBranchSpacing()
    -- Get spacing based on current tunnel size
    return config.BRANCH_SPACING[config.TUNNEL_SIZE] or 5
end

-- Validate configuration
function config.validate()
    assert(config.TUNNEL_LENGTH > 0, "TUNNEL_LENGTH must be positive")
    assert(config.TUNNEL_SPACING >= 2, "TUNNEL_SPACING must be at least 2")
    assert(config.TUNNEL_HEIGHT >= 2, "TUNNEL_HEIGHT must be at least 2")
    assert(config.NUM_LAYERS > 0, "NUM_LAYERS must be positive")
    assert(config.MODEM_CHANNEL >= 1 and config.MODEM_CHANNEL <= 65535, "MODEM_CHANNEL must be 1-65535")
    assert(config.MIN_FUEL > 0, "MIN_FUEL must be positive")
    return true
end

return config

