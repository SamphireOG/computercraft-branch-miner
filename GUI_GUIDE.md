# Turtle GUI System Guide

## Overview
The Branch Miner now includes a comprehensive GUI system for turtles, making project management and configuration much easier. No need to run the installer every time you want to join or leave a project!

## Features

### Main Menu
Access the main menu by:
- Starting the turtle when not assigned to a project (automatic)
- Pressing **'M'** key during operation (anytime)

### Menu Options

#### 1. Start Mining
- Only available when assigned to a project
- Begins the mining operation
- Turtle will request work assignments from the coordinator

#### 2. Join Project
- Discover available projects on the network
- View project details (name, channel, turtle count, tunnel length)
- Select and join a project
- Set turtle name/label
- Only available when not currently in a project

#### 3. Project Info
- View current project assignment
- See project name, channel, turtle ID
- Check Y-level configuration
- View when you joined the project

#### 4. Leave Project
- Leave your current project
- Confirmation required to prevent accidents
- Announces offline status to coordinator
- Clears project assignment
- Allows joining a different project

#### 5. Exit
- Close the GUI
- Return to shell

## Keyboard Shortcuts

- **M** - Open menu (during operation)
- Mouse clicks work for all buttons

## Usage Guide

### First Time Setup
1. Run the installer (`installer.lua`)
2. The turtle will download required files
3. The GUI will automatically open
4. Click "Join Project" to find and join a project
5. Enter a turtle name or press Enter for auto-name
6. Once joined, click "Start Mining"

### Switching Projects
1. Press **'M'** during operation to open menu
2. Click "Leave Project"
3. Confirm you want to leave
4. Click "Join Project"
5. Select new project
6. Click "Start Mining"

### Checking Status
1. Press **'M'** to open menu
2. Click "Project Info"
3. View all project details
4. Press any key to return

## GUI Components

### Visual Elements
- **Header** - Blue bar showing current screen title
- **Buttons** - Gray boxes that highlight on hover
  - Hover: Light gray
  - Click: White flash
  - Colors indicate function:
    - Green: Start/positive actions
    - Blue: Information/navigation
    - Orange: Caution actions
    - Red: Exit/cancel/destructive actions
- **Footer** - Gray bar with helpful hints

### Button States
- **Enabled** - Normal color, clickable
- **Disabled** - Black color, not clickable
- **Hover** - Light gray with border indicator

## Project Discovery

The GUI uses the discovery protocol to find available projects:
- Broadcasts on channel 100
- Searches for 10 seconds
- Shows all active projects with details
- Real-time project information

## Technical Details

### Files
- `turtle-gui.lua` - Main GUI system
- `gui.lua` - GUI helper library (buttons, visual elements)
- `project-client.lua` - Discovery and project management
- `miner.lua` - Main turtle program (GUI integrated)

### Integration
The GUI is seamlessly integrated into the miner program:
- Automatic startup when not assigned
- Keyboard shortcut access during operation
- State preservation (no data loss)
- Automatic reconnection after project changes

### Safety Features
- Confirmation required for leaving projects
- Error handling for all operations
- Clear status messages
- Automatic state saving

## Troubleshooting

### "No projects found"
- Make sure pocket computer is running
- Verify projects have been created
- Check you're within wireless range
- Ensure modem is enabled

### GUI doesn't respond
- Make sure you're clicking buttons, not empty space
- Wait for operations to complete
- Check for error messages
- Try pressing 'M' again

### Can't leave project
- You must confirm the action
- Check that you're actually in a project
- Make sure modem is connected

### Lost connection to project
- Press 'M' to open menu
- Check "Project Info" for details
- Leave and rejoin if necessary
- Verify pocket computer is running

## Tips

1. **Press 'M' anytime** - The menu is always accessible during operation
2. **Auto-names are fine** - "Miner-123" works great for turtle names
3. **Check project info** - Verify your configuration before mining
4. **Leave cleanly** - Always use the GUI to leave projects
5. **First turtle** - If you're first to join, you set the home base!

## Developer Notes

### Extending the GUI
The GUI system is modular and can be extended:
- Add new menu items in `turtleGUI.showMainMenu()`
- Create new screens with `drawHeader()` and `drawFooter()`
- Use `gui.createButton()` for interactive elements
- Handle events in the main loop

### Custom Screens
To add a custom screen:
```lua
function turtleGUI.showCustomScreen()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader("My Screen")
    
    -- Your content here
    
    drawFooter("Press any key")
    os.pullEvent("key")
end
```

## Version
GUI System v1.0 - Integrated Project Management

