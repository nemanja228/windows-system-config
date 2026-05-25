# Post-install hook for Notepad++.Notepad++ — runs after winget installs the app.
# Sideloads the user's chosen plugin set from the official Notepad++ plugin JSON.
# Idempotent: each plugin is skipped if already present in the plugins folder.

Write-Host "`n--- Installing Notepad++ Plugins ---" -ForegroundColor Cyan

# 1. The list of plugins you want (using their exact display names from Plugin Admin)
$desiredPlugins = @(
    "Compare",
    "ComparePlus",
    "XML Tools",
    "Json Tools",
    "JSON Viewer",
    "MarkdownViewer++",
    "Converter"
)

# 2. Fetch the official Notepad++ x64 Plugin List JSON
$jsonUrl = "https://raw.githubusercontent.com/notepad-plus-plus/nppPluginList/master/src/pl.x64.json"
Write-Host "Fetching official Notepad++ plugin repository..."
try {
    $pluginRepo = (Invoke-RestMethod -Uri $jsonUrl)."npp-plugins"
} catch {
    Write-Host "Failed to reach Notepad++ plugin list. Skipping." -ForegroundColor Red
    return
}

$nppPluginsDir = "C:\Program Files\Notepad++\plugins"

# Ensure Notepad++ is actually installed
if (-not (Test-Path $nppPluginsDir)) {
    Write-Host "Notepad++ plugins folder not found at $nppPluginsDir. Is it installed?" -ForegroundColor Red
    return
}

# 3. Loop through your list and install
foreach ($pluginName in $desiredPlugins) {
    Write-Host "`nProcessing: $pluginName"

    # Find the plugin in the JSON by its Display Name
    $repoEntry = $pluginRepo | Where-Object { $_."display-name" -eq $pluginName }

    # Handle pre-included plugins (like Converter) that might not be in the JSON
    if (-not $repoEntry) {
        # Check if it exists locally under a common naming scheme (e.g., NppConverter)
        if (Get-ChildItem -Path $nppPluginsDir -Filter "*$pluginName*" -ErrorAction SilentlyContinue) {
            Write-Host "[$pluginName] is already pre-included/installed. Skipping." -ForegroundColor Yellow
        } else {
            Write-Host "[$pluginName] not found in official JSON repository and not installed locally." -ForegroundColor Red
        }
        continue
    }

    $folderName = $repoEntry."folder-name"
    $downloadUrl = $repoEntry."repository"
    $targetDir = Join-Path $nppPluginsDir $folderName

    # Check if already installed
    if (Test-Path $targetDir) {
        Write-Host "[$pluginName] is already installed at $targetDir. Skipping." -ForegroundColor Yellow
        continue
    }

    # 4. Download and Extract
    Write-Host "Downloading $pluginName..."
    $tempZip = Join-Path $env:TEMP "$folderName.zip"
    
    try {
        Invoke-RestMethod -Uri $downloadUrl -OutFile $tempZip
        
        Write-Host "Extracting..."
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        
        # Extract the zip. 
        # Note: We extract to a temporary subfolder first to prevent "double-nesting" 
        # if the author put a root folder inside their zip file.
        $extractTemp = Join-Path $env:TEMP "${folderName}_extracted"
        Expand-Archive -Path $tempZip -DestinationPath $extractTemp -Force
        
        # Move contents exactly where Notepad++ expects them
        $extractedItems = Get-ChildItem -Path $extractTemp
        if ($extractedItems.Count -eq 1 -and $extractedItems[0].PSIsContainer) {
            # The author put everything in a single root folder inside the zip
            Copy-Item -Path "$($extractedItems[0].FullName)\*" -Destination $targetDir -Recurse -Force
        } else {
            # The author just zipped the files directly
            Copy-Item -Path "$extractTemp\*" -Destination $targetDir -Recurse -Force
        }

        # Cleanup
        Remove-Item -Path $tempZip -Force
        Remove-Item -Path $extractTemp -Recurse -Force

        Write-Host "SUCCESS: [$pluginName] installed." -ForegroundColor Green
    } catch {
        Write-Host "Failed to download or extract [$pluginName]. Check URL: $downloadUrl" -ForegroundColor Red
    }
}