-- ============================================================
--  LeaderOS Connect - Configuration
-- ============================================================

LeaderOS.Config = {
    WebsiteURL   = "https://yourwebsite.com", -- Panel base URL (no trailing slash)
    APIKey       = "YOUR_API_KEY_HERE",
    ConnectToken = "YOUR_SERVER_TOKEN_HERE",
    DebugMode    = false,
    CheckOnline  = true,                      -- If true, commands for offline players are queued locally
    FreqMinutes  = 2,                         -- How often to poll the queue (in minutes)
}