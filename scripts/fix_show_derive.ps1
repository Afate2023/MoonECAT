
# Script to generate impl Show for T that delegates to Debug
# For each package directory with types that derive(Debug), 
# create or append show_bridge.mbt with Show impls

$root = "E:\MoonECAT"
$excludePatterns = @("*\_build*", "*Reference_Project*", "*References*", "*.mooncakes*", "*scripts*", "*fixtures*", "*docs*")

# Collect all type definitions with derive(Debug) per package directory
$packageTypes = @{}

Get-ChildItem -Path $root -Recurse -Filter "*.mbt" | Where-Object {
    $path = $_.FullName
    $exclude = $false
    foreach ($p in $excludePatterns) {
        if ($path -like $p) { $exclude = $true; break }
    }
    -not $exclude -and $_.Name -notlike "*_test.mbt" -and $_.Name -notlike "*_wbtest.mbt" -and $_.Name -notlike "*.mbti" -and $_.Name -ne "show_bridge.mbt"
} | ForEach-Object {
    $file = $_
    $dir = $file.DirectoryName
    $lines = Get-Content $file.FullName
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        # Skip if line doesn't have derive with Debug (that was Show)
        if ($line -notmatch 'derive\([^)]*\bDebug\b') { continue }
        
        # Check if this derive was from our Show->Debug replacement
        # We look for type definitions
        
        $typeName = $null
        $typeParams = $null
        $vis = ""
        
        # Pattern 1: Single-line type definition: type/struct/enum/suberror ... derive(...)
        if ($line -match '^\s*(pub(?:\(all\))?\s+)?(?:struct|enum|suberror|type)\s+(\w+)(?:\[([^\]]+)\])?\s*(?:\(.*?\))?\s*derive\(') {
            $vis = $Matches[1]
            $typeName = $Matches[2]
            $typeParams = $Matches[3]
        }
        # Pattern 2: Closing brace with derive: } derive(...)
        elseif ($line -match '^\s*\}\s*derive\(') {
            # Walk backwards to find the type definition start
            for ($j = $i - 1; $j -ge 0; $j--) {
                if ($lines[$j] -match '^\s*(pub(?:\(all\))?\s+)?(?:struct|enum|suberror|type)\s+(\w+)(?:\[([^\]]+)\])?\s') {
                    $vis = $Matches[1]
                    $typeName = $Matches[2]
                    $typeParams = $Matches[3]
                    break
                }
            }
        }
        
        if ($typeName) {
            if (-not $packageTypes.ContainsKey($dir)) {
                $packageTypes[$dir] = @()
            }
            $existing = $packageTypes[$dir] | Where-Object { $_.Name -eq $typeName }
            if (-not $existing) {
                $packageTypes[$dir] += @{
                    Name = $typeName
                    TypeParams = $typeParams
                }
            }
        }
    }
}

# Check if Show impl already exists for each type in the package
foreach ($dir in $packageTypes.Keys) {
    $types = $packageTypes[$dir]
    $allMbtContent = ""
    Get-ChildItem -Path $dir -Filter "*.mbt" | Where-Object { $_.Name -ne "show_bridge.mbt" } | ForEach-Object {
        $allMbtContent += Get-Content $_.FullName -Raw
    }
    
    $filteredTypes = @()
    foreach ($t in $types) {
        $name = $t.Name
        # Check if impl Show for TypeName already exists
        if ($allMbtContent -match "impl\s+Show\s+for\s+$name\b") {
            Write-Host "Skipping $name in $dir - Show impl already exists"
        } else {
            $filteredTypes += $t
        }
    }
    $packageTypes[$dir] = $filteredTypes
}

# Generate show_bridge.mbt files
foreach ($dir in $packageTypes.Keys) {
    $types = $packageTypes[$dir]
    if ($types.Count -eq 0) { continue }
    
    $content = ""
    foreach ($t in $types) {
        $name = $t.Name
        $params = $t.TypeParams
        
        if ($params) {
            # Generic type - need constraint
            $paramNames = ($params -split ',\s*' | ForEach-Object { ($_ -split '\s*:\s*')[0].Trim() })
            $constraints = ($paramNames | ForEach-Object { "$_ : Debug" }) -join ", "
            $typeExpr = "$name[$($paramNames -join ', ')]"
            $content += "///|`nimpl[$constraints] Show for $typeExpr with output(self, logger) {`n  logger.write_string(@debug.render(Debug::to_repr(self)))`n}`n`n"
        } else {
            $content += "///|`nimpl Show for $name with output(self, logger) {`n  logger.write_string(@debug.render(Debug::to_repr(self)))`n}`n`n"
        }
    }
    
    $bridgeFile = Join-Path $dir "show_bridge.mbt"
    Write-Host "Creating $bridgeFile with $($types.Count) Show impls"
    Set-Content -Path $bridgeFile -Value $content -NoNewline
}

Write-Host "`nDone! Created show_bridge.mbt files."
