-- GUI Helper Library for Branch Miner Control
-- Provides button creation, click handling, and visual elements

local gui = {}

-- ========== BUTTON SYSTEM ==========

gui.buttons = {}
gui.hoveredButton = nil

function gui.createButton(id, x, y, width, height, text, callback, bgColor, textColor)
    local button = {
        id = id,
        x = x,
        y = y,
        width = width,
        height = height,
        text = text,
        callback = callback,
        bgColor = bgColor or colors.gray,
        textColor = textColor or colors.white,
        hoverBgColor = colors.lightGray,
        pressedBgColor = colors.white,
        enabled = true,
        visible = true
    }
    
    gui.buttons[id] = button
    return button
end

function gui.isPointInButton(button, x, y)
    if not button.visible or not button.enabled then
        return false
    end
    
    return x >= button.x and x < button.x + button.width and
           y >= button.y and y < button.y + button.height
end

function gui.handleClick(x, y)
    for _, button in pairs(gui.buttons) do
        if gui.isPointInButton(button, x, y) then
            if button.callback then
                button.callback()
            end
            return button.id
        end
    end
    return nil
end

function gui.updateHover(x, y)
    gui.hoveredButton = nil
    for _, button in pairs(gui.buttons) do
        if gui.isPointInButton(button, x, y) then
            gui.hoveredButton = button.id
            return button.id
        end
    end
    return nil
end

function gui.drawButton(button, isPressed)
    if not button.visible then return end
    
    local isHovered = (gui.hoveredButton == button.id)
    local bgColor = button.bgColor
    
    if isPressed then
        bgColor = button.pressedBgColor
    elseif isHovered then
        bgColor = button.hoverBgColor
    end
    
    if not button.enabled then
        bgColor = colors.black
    end
    
    -- Draw button background
    term.setBackgroundColor(bgColor)
    term.setTextColor(button.textColor)
    
    for dy = 0, button.height - 1 do
        term.setCursorPos(button.x, button.y + dy)
        term.write(string.rep(" ", button.width))
    end
    
    -- Draw button text (centered)
    local textY = button.y + math.floor(button.height / 2)
    local textX = button.x + math.floor((button.width - #button.text) / 2)
    term.setCursorPos(textX, textY)
    term.write(button.text)
end

function gui.drawAllButtons()
    for _, button in pairs(gui.buttons) do
        gui.drawButton(button, false)
    end
end

function gui.clearButtons()
    gui.buttons = {}
    gui.hoveredButton = nil
end

-- ========== VISUAL ELEMENTS ==========

function gui.drawBox(x, y, width, height, bgColor, borderColor)
    term.setBackgroundColor(bgColor or colors.black)
    
    -- Fill box
    for dy = 0, height - 1 do
        term.setCursorPos(x, y + dy)
        term.write(string.rep(" ", width))
    end
    
    -- Draw border if specified
    if borderColor then
        term.setTextColor(borderColor)
        -- Top and bottom
        term.setCursorPos(x, y)
        term.write(string.rep("-", width))
        term.setCursorPos(x, y + height - 1)
        term.write(string.rep("-", width))
        
        -- Sides
        for dy = 1, height - 2 do
            term.setCursorPos(x, y + dy)
            term.write("|")
            term.setCursorPos(x + width - 1, y + dy)
            term.write("|")
        end
    end
end

function gui.drawStatusBadge(x, y, text, bgColor, textColor)
    term.setCursorPos(x, y)
    term.setBackgroundColor(bgColor)
    term.setTextColor(textColor)
    term.write(" " .. text .. " ")
end

function gui.drawProgressBar(x, y, width, percent, fillColor, bgColor)
    local filled = math.floor((percent / 100) * width)
    
    term.setCursorPos(x, y)
    term.setBackgroundColor(fillColor)
    term.write(string.rep(" ", filled))
    
    term.setBackgroundColor(bgColor)
    term.write(string.rep(" ", width - filled))
end

-- ========== CLICKABLE LIST ==========

function gui.createListItem(id, x, y, width, text, callback)
    return gui.createButton(id, x, y, width, 1, text, callback, colors.gray, colors.white)
end

return gui

