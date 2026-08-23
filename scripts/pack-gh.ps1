param(
    [string]$SourceBin,
    [string]$SourceRoot,
    [string]$Translations,
    [string]$OutDir
)
$ErrorActionPreference = "Stop"

$stamp   = Get-Date -Format "yyyy-MM-dd_HHmm"
$staging = Join-Path $OutDir "staging"
$releaseDir = Join-Path $staging "release"
if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$releaseDir\x64","$releaseDir\x32","$releaseDir\translations" | Out-Null

# 1. 拷贝运行文件 (排除编译残留)
$excludeExt = @(".lib",".exp",".pdb",".ilk",".map")
foreach ($pair in @(@("x64","x64"),@("x32","x32"))) {
    $arch = $pair[0]
    $from = Join-Path $SourceBin $pair[1]
    if (-not (Test-Path $from)) { throw "build output missing: $from" }
    Get-ChildItem -LiteralPath $from -Recurse -Force | ForEach-Object {
        if ($_.FullName -match "\\tests($|\\)") { return }
        if ($_.PSIsContainer) { return }
        if ($_.Name -like ".deps_*") { return }
        if ($excludeExt -contains $_.Extension.ToLower()) { return }
        $rel  = $_.FullName.Substring($from.Length).TrimStart("\")
        $dest = Join-Path $releaseDir "$arch\$rel"
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
    }
}

# 2. 翻译
Get-ChildItem -LiteralPath $Translations -Filter "*.qm" -ErrorAction Stop | Copy-Item -Destination "$releaseDir\translations" -Force

# 3. pluginsdk (从源码组装)
$sdk = Join-Path $staging "pluginsdk"
New-Item -ItemType Directory -Force -Path $sdk | Out-Null
foreach ($pat in @("_plugin_types.h","_plugins.h","_scriptapi*.h","_dbgfunctions.h")) {
    Get-ChildItem -LiteralPath (Join-Path $SourceRoot "src\dbg") -Filter $pat -ErrorAction Stop | Copy-Item -Destination $sdk -Force
}
Get-ChildItem -LiteralPath (Join-Path $SourceRoot "src\bridge") -Filter "bridge*.h" | Copy-Item -Destination $sdk -Force
foreach ($lib in @("x32\x32bridge.lib","x32\x32dbg.lib","x64\x64bridge.lib","x64\x64dbg.lib")) {
    Copy-Item -LiteralPath (Join-Path $SourceBin $lib) -Destination $sdk -Force
}

# 4. commithash
$commit = git -C $SourceRoot rev-parse HEAD
Set-Content -LiteralPath (Join-Path $staging "commithash.txt") -Value $commit -Encoding ascii

# 5. 打 zip
$zip = Join-Path $OutDir ("snapshot_" + $stamp + ".zip")
Compress-Archive -Path "$staging\*" -DestinationPath $zip -Force
Remove-Item -LiteralPath $staging -Recurse -Force
Write-Host ("zip: " + $zip)
Write-Host ("size: " + [math]::Round((Get-Item $zip).Length/1MB,1) + " MB")
