# LeaderosConnect Plugin for Garry's Mod

This plugin allows you to connect your Garry's Mod server to LeaderOS, enabling you to send commands to the server through the LeaderOS platform.

## Installation

### 1. Download the addon

Download the latest release as a ZIP file from the link below and extract it:

[https://www.leaderos.net/plugin/gmod](https://www.leaderos.net/plugin/gmod)

### 2. Upload the addon

Copy the `leaderos_connect` folder from the extracted ZIP into your server's addons directory:

```
garrysmod/addons/leaderos_connect/
```

### 3. First restart

Restart your server. This will generate the config file at:

```
garrysmod/addons/leaderos_connect/lua/leaderos/config.lua
```

### 4. Configure the addon

Open `config.lua` and fill in your credentials:

```lua
LeaderOS.Config = {
   WebsiteURL   = "https://yourwebsite.com",
   APIKey       = "YOUR_API_KEY_HERE",
   ConnectToken = "YOUR_SERVER_TOKEN_HERE",
   DebugMode    = false,
   CheckOnline  = true,
   FreqMinutes  = 2,
}
```

### 5. Configure server.cfg

Add the following line to `garrysmod/cfg/server.cfg`:

```
sv_hibernate_think 1
```

> **Important:** This is required. Without it, Lua timers do not run when no players are on the server, and the addon will not poll the queue.

### 6. Final restart

Restart your server. The addon is now active. Run `leaderos_status` in the server console to confirm everything is working.

## Configuration

| Option | Description |
|---|---|
| `WebsiteURL` | The URL of your LeaderOS website (e.g., `https://yourwebsite.com`). |
| `APIKey` | Your LeaderOS API key. Find it on `Dashboard > Settings > API` |
| `ConnectToken` | Your server token. Find it on `Dashboard > Store > Servers > Your Server > Server Token` |
| `DebugMode` | Set to `true` to enable debug logging, or `false` to disable it. |
| `CheckOnline` | Set to `true` to check if players are online before sending commands, or `false` to skip this check. |
| `FreqMinutes` | How often (in minutes) the addon polls the command queue. |

## Console Commands

| Command | Description |
|---|---|
| `leaderos_status` | Displays the current configuration and timer status. |
| `leaderos_reload` | Reloads the config file, restarts the timer, and triggers an immediate poll. |
| `leaderos_poll` | Triggers an immediate queue poll without restarting the timer. |
| `leaderos_debug` | Toggles debug mode on or off. |