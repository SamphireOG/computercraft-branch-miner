-- Advanced GUI System for ComputerCraft
-- Full-screen dynamic interface with no terminal bleeding through

local gui = {}

-- ========== CONFIGURATION ==========

gui.width, gui.height = term.getSize()
gui.theme = {
    primary = colors.blue,
    secondary = colors.cyan,
    success = colors.lime,
    danger = colors.red,
    warning = colors.orange,
    info = colors.lightBlue,
    background = colors.black,
    surface = colors.gray,
    surfaceLight = colors.lightGray,
    text = colors.white,
    textDim = colors.lightGray,
    border = colors.gray
}

-- ========== SCREEN MANAGEMENT ==========

local screenBuffer = {}
local dirtyRegions = {}
local currentScreen = nil

function gui.initScreen()
    term.setBackgroundColor(gui.theme.background)
    term.clear()
    term.setCursorBlink(false)
    screenBuffer = {}
    for y = 1, gui.height do
        screenBuffer[y] = {}
        for x = 1, gui.width do
            screenBuffer[y][x] = {char = " ", fg = colors.white, bg = gui.theme.background}
        end
    end
end

function gui.clearScreen()
    term.setBackgroundColor(gui.theme.background)
    term.clear()
    for y = 1, gui.height do
        for x = 1, gui.width do
            screenBuffer[y][x] = {char = " ", fg = colors.white, bg = gui.theme.background}
        end
    end
end

function gui.setPixel(x, y, char, fg, bg)
    if x < 1 or x > gui.width or y < 1 or y > gui.height then
        return
    end
    
    screenBuffer[y][x] = {
        char = char or " ",
        fg = fg or colors.white,
        bg = bg or gui.theme.background
    }
end

function gui.render()
    -- Render entire screen buffer
    for y = 1, gui.height do
        term.setCursorPos(1, y)
        for x = 1, gui.width do
            local pixel = screenBuffer[y][x]
            term.setTextColor(pixel.fg)
            term.setBackgroundColor(pixel.bg)
            term.write(pixel.char)
        end
    end
end

-- ========== DRAWING PRIMITIVES ==========

function gui.drawBox(x, y, width, height, bgColor, borderColor, borderStyle)
    borderStyle = borderStyle or "none" -- "none", "single", "double", "rounded"
    bgColor = bgColor or gui.theme.surface
    
    -- Fill background
    for dy = 0, height - 1 do
        for dx = 0, width - 1 do
            gui.setPixel(x + dx, y + dy, " ", colors.white, bgColor)
        end
    end
    
    -- Draw border
    if borderColor and borderStyle ~= "none" then
        local corners, horiz, vert
        
        if borderStyle == "single" then
            corners = {"+", "+", "+", "+"}
            horiz, vert = "-", "|"
        elseif borderStyle == "double" then
            corners = {"#", "#", "#", "#"}
            horiz, vert = "=", "|"
        elseif borderStyle == "rounded" then
            corners = {"/", "\\", "\\", "/"}
            horiz, vert = "-", "|"
        end
        
        -- Top and bottom edges
        for dx = 1, width - 2 do
            gui.setPixel(x + dx, y, horiz, borderColor, bgColor)
            gui.setPixel(x + dx, y + height - 1, horiz, borderColor, bgColor)
        end
        
        -- Left and right edges
        for dy = 1, height - 2 do
            gui.setPixel(x, y + dy, vert, borderColor, bgColor)
            gui.setPixel(x + width - 1, y + dy, vert, borderColor, bgColor)
        end
        
        -- Corners
        gui.setPixel(x, y, corners[1], borderColor, bgColor)
        gui.setPixel(x + width - 1, y, corners[2], borderColor, bgColor)
        gui.setPixel(x + width - 1, y + height - 1, corners[3], borderColor, bgColor)
        gui.setPixel(x, y + height - 1, corners[4], borderColor, bgColor)
    end
end

function gui.drawText(x, y, text, fg, bg, align)
    align = align or "left" -- "left", "center", "right"
    fg = fg or gui.theme.text
    bg = bg or gui.theme.background
    
    local drawX = x
    if align == "center" then
        drawX = x - math.floor(#text / 2)
    elseif align == "right" then
        drawX = x - #text
    end
    
    for i = 1, #text do
        gui.setPixel(drawX + i - 1, y, text:sub(i, i), fg, bg)
    end
end

function gui.drawProgressBar(x, y, width, percent, fillColor, bgColor, showPercent)
    fillColor = fillColor or gui.theme.success
    bgColor = bgColor or gui.theme.surface
    percent = math.max(0, math.min(100, percent))
    
    local filled = math.floor((percent / 100) * width)
    
    -- Draw background
    for dx = 0, width - 1 do
        local color = dx < filled and fillColor or bgColor
        gui.setPixel(x + dx, y, " ", colors.white, color)
    end
    
    -- Draw percentage text if requested
    if showPercent then
        local text = tostring(math.floor(percent)) .. "%"
        local textX = x + math.floor(width / 2)
        gui.drawText(textX, y, text, colors.white, nil, "center")
    end
end

function gui.drawLine(x1, y1, x2, y2, char, color, bg)
    char = char or "-"
    color = color or gui.theme.border
    bg = bg or gui.theme.background
    
    -- Simple horizontal/vertical lines
    if y1 == y2 then
        for x = math.min(x1, x2), math.max(x1, x2) do
            gui.setPixel(x, y1, char, color, bg)
        end
    elseif x1 == x2 then
        for y = math.min(y1, y2), math.max(y1, y2) do
            gui.setPixel(x1, y, char, color, bg)
        end
    end
end

-- ========== WIDGETS ==========

gui.widgets = {}
gui.widgetIdCounter = 0

function gui.createWidget(type, config)
    gui.widgetIdCounter = gui.widgetIdCounter + 1
    
    local widget = {
        id = config.id or ("widget_" .. gui.widgetIdCounter),
        type = type,
        x = config.x or 1,
        y = config.y or 1,
        width = config.width or 10,
        height = config.height or 3,
        visible = config.visible ~= false,
        enabled = config.enabled ~= false,
        focused = false,
        hovered = false,
        data = config.data or {}
    }
    
    gui.widgets[widget.id] = widget
    return widget
end

function gui.createButton(config)
    local button = gui.createWidget("button", config)
    button.text = config.text or "Button"
    button.callback = config.callback
    button.color = config.color or gui.theme.primary
    button.hoverColor = config.hoverColor or gui.theme.secondary
    button.textColor = config.textColor or gui.theme.text
    button.icon = config.icon
    return button
end

function gui.createLabel(config)
    local label = gui.createWidget("label", config)
    label.text = config.text or ""
    label.color = config.color or gui.theme.text
    label.bgColor = config.bgColor or gui.theme.background
    label.align = config.align or "left"
    return label
end

function gui.createPanel(config)
    local panel = gui.createWidget("panel", config)
    panel.color = config.color or gui.theme.surface
    panel.borderColor = config.borderColor
    panel.borderStyle = config.borderStyle or "single"
    panel.title = config.title
    return panel
end

function gui.createList(config)
    local list = gui.createWidget("list", config)
    list.items = config.items or {}
    list.selectedIndex = config.selectedIndex or 1
    list.scrollOffset = 0
    list.onSelect = config.onSelect
    list.color = config.color or gui.theme.surface
    list.selectedColor = config.selectedColor or gui.theme.primary
    return list
end

function gui.createTextInput(config)
    local input = gui.createWidget("textinput", config)
    input.text = config.text or ""
    input.placeholder = config.placeholder or ""
    input.maxLength = config.maxLength or 50
    input.onChange = config.onChange
    input.color = config.color or gui.theme.surface
    return input
end

-- ========== WIDGET RENDERING ==========

function gui.renderButton(button)
    if not button.visible then return end
    
    local color = button.enabled and 
                  (button.hovered and button.hoverColor or button.color) or
                  gui.theme.surface
    
    -- Draw button background
    gui.drawBox(button.x, button.y, button.width, button.height, color)
    
    -- Draw text centered
    local text = button.icon and (button.icon .. " " .. button.text) or button.text
    local textY = button.y + math.floor(button.height / 2)
    local textX = button.x + math.floor(button.width / 2)
    
    gui.drawText(textX, textY, text, button.textColor, color, "center")
    
    -- Draw focus indicator
    if button.focused then
        gui.drawBox(button.x, button.y, button.width, button.height, nil, gui.theme.warning, "single")
    end
end

function gui.renderLabel(label)
    if not label.visible then return end
    
    gui.drawText(label.x, label.y, label.text, label.color, label.bgColor, label.align)
end

function gui.renderPanel(panel)
    if not panel.visible then return end
    
    gui.drawBox(panel.x, panel.y, panel.width, panel.height, 
                panel.color, panel.borderColor, panel.borderStyle)
    
    -- Draw title if present
    if panel.title then
        local titleX = panel.x + 2
        gui.drawText(titleX, panel.y, " " .. panel.title .. " ", 
                    gui.theme.text, panel.color, "left")
    end
end

function gui.renderList(list)
    if not list.visible then return end
    
    -- Draw background
    gui.drawBox(list.x, list.y, list.width, list.height, list.color, gui.theme.border, "single")
    
    -- Calculate visible items
    local maxVisible = list.height - 2
    local startIdx = list.scrollOffset + 1
    local endIdx = math.min(startIdx + maxVisible - 1, #list.items)
    
    -- Draw items
    local itemY = list.y + 1
    for i = startIdx, endIdx do
        local item = list.items[i]
        local bg = (i == list.selectedIndex) and list.selectedColor or list.color
        local fg = (i == list.selectedIndex) and gui.theme.text or gui.theme.textDim
        
        -- Truncate text if too long
        local text = tostring(item)
        if #text > list.width - 4 then
            text = text:sub(1, list.width - 7) .. "..."
        end
        
        gui.drawText(list.x + 2, itemY, text, fg, bg, "left")
        itemY = itemY + 1
    end
    
    -- Draw scrollbar if needed
    if #list.items > maxVisible then
        local scrollbarHeight = list.height - 2
        local thumbHeight = math.max(1, math.floor(scrollbarHeight * maxVisible / #list.items))
        local thumbPos = math.floor(scrollbarHeight * list.scrollOffset / (#list.items - maxVisible))
        
        for dy = 0, scrollbarHeight - 1 do
            local char = (dy >= thumbPos and dy < thumbPos + thumbHeight) and "#" or "|"
            gui.setPixel(list.x + list.width - 1, list.y + 1 + dy, char, gui.theme.textDim, list.color)
        end
    end
end

function gui.renderTextInput(input)
    if not input.visible then return end
    
    local bg = input.focused and gui.theme.surfaceLight or input.color
    gui.drawBox(input.x, input.y, input.width, input.height, bg, gui.theme.border, "single")
    
    local displayText = input.text
    if displayText == "" and input.placeholder then
        displayText = input.placeholder
        gui.drawText(input.x + 2, input.y + 1, displayText, gui.theme.textDim, bg, "left")
    else
        -- Truncate if too long
        if #displayText > input.width - 4 then
            displayText = displayText:sub(-input.width + 4)
        end
        gui.drawText(input.x + 2, input.y + 1, displayText, gui.theme.text, bg, "left")
        
        -- Draw cursor if focused
        if input.focused then
            local cursorX = input.x + 2 + #displayText
            gui.setPixel(cursorX, input.y + 1, "_", gui.theme.text, bg)
        end
    end
end

function gui.renderWidget(widget)
    if widget.type == "button" then
        gui.renderButton(widget)
    elseif widget.type == "label" then
        gui.renderLabel(widget)
    elseif widget.type == "panel" then
        gui.renderPanel(widget)
    elseif widget.type == "list" then
        gui.renderList(widget)
    elseif widget.type == "textinput" then
        gui.renderTextInput(widget)
    end
end

function gui.renderAllWidgets()
    for _, widget in pairs(gui.widgets) do
        gui.renderWidget(widget)
    end
end

-- ========== EVENT HANDLING ==========

function gui.isPointInWidget(widget, x, y)
    return widget.visible and widget.enabled and
           x >= widget.x and x < widget.x + widget.width and
           y >= widget.y and y < widget.y + widget.height
end

function gui.updateHover(x, y)
    for _, widget in pairs(gui.widgets) do
        widget.hovered = gui.isPointInWidget(widget, x, y)
    end
end

function gui.handleClick(x, y)
    for _, widget in pairs(gui.widgets) do
        if gui.isPointInWidget(widget, x, y) then
            if widget.type == "button" and widget.callback then
                return widget.callback(widget)
            elseif widget.type == "list" then
                -- Calculate which item was clicked
                local itemY = y - widget.y - 1
                local clickedIndex = widget.scrollOffset + itemY + 1
                if clickedIndex >= 1 and clickedIndex <= #widget.items then
                    widget.selectedIndex = clickedIndex
                    if widget.onSelect then
                        widget.onSelect(widget, widget.items[clickedIndex], clickedIndex)
                    end
                end
                return widget.id
            end
            return widget.id
        end
    end
    return nil
end

function gui.handleScroll(x, y, direction)
    for _, widget in pairs(gui.widgets) do
        if widget.type == "list" and gui.isPointInWidget(widget, x, y) then
            local maxScroll = math.max(0, #widget.items - (widget.height - 2))
            widget.scrollOffset = math.max(0, math.min(maxScroll, widget.scrollOffset - direction))
            return widget.id
        end
    end
    return nil
end

function gui.handleChar(char)
    for _, widget in pairs(gui.widgets) do
        if widget.type == "textinput" and widget.focused then
            if #widget.text < widget.maxLength then
                widget.text = widget.text .. char
                if widget.onChange then
                    widget.onChange(widget, widget.text)
                end
            end
            return widget.id
        end
    end
    return nil
end

function gui.handleKey(key)
    for _, widget in pairs(gui.widgets) do
        if widget.type == "textinput" and widget.focused then
            if key == keys.backspace then
                widget.text = widget.text:sub(1, -2)
                if widget.onChange then
                    widget.onChange(widget, widget.text)
                end
                return widget.id
            end
        end
    end
    return nil
end

-- ========== SCREEN MANAGEMENT ==========

function gui.clearWidgets()
    gui.widgets = {}
end

function gui.removeWidget(id)
    gui.widgets[id] = nil
end

function gui.getWidget(id)
    return gui.widgets[id]
end

-- ========== MAIN LOOP HELPER ==========

function gui.pollEvent()
    local event, p1, p2, p3 = os.pullEvent()
    
    if event == "mouse_click" then
        return "click", p2, p3, p1 -- x, y, button
    elseif event == "mouse_drag" then
        gui.updateHover(p2, p3)
        return "drag", p2, p3
    elseif event == "mouse_scroll" then
        return "scroll", p2, p3, p1 -- x, y, direction
    elseif event == "char" then
        return "char", p1
    elseif event == "key" then
        return "key", p1
    end
    
    return event, p1, p2, p3
end

return gui
