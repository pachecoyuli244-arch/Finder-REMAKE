-- PVFinder V3 sin panel: pon aqui una clave de recolector de uso exclusivo.
-- No publiques ni guardes este archivo con la clave real en GitHub.
local env=(type(getgenv)=="function" and getgenv()) or _G
env.PVFINDER_COLLECTOR_TOKEN="PEGAR_CLAVE_PVF_DE_ESTE_BOT"
loadstring(game:HttpGet("https://pvfinder.onrender.com/bot-headless.lua"))()
