-- Disable specific features at load time
echidna_features.disable("Feature_AntiAim")
echidna_features.disable("Feature_NoSpread")
echidna_features.disable("Feature_EnginePrediction")
--echidna_features.disable("Feature_GlowSuppression")
--echidna_features.disable("Feature_PunchAngleRemoval")

-- Re-enable later
--echidna_features.enable("Feature_AntiAim")

-- Check state
--print(echidna_features.is_enabled("Feature_Hitscan"))  -- true

-- List all known flags and their states
for _, pair in ipairs(echidna_features.list()) do print(pair[1], pair[2]) end
