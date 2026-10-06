<#
.SINOPSIS
    Instalador de StreamDock ES para Windows 10/11.

.DESCRIPCION
    Descarga el ultimo plugin de GitHub Releases, lo descomprime en la carpeta de
    plugins de OpenDeck y comprueba que el ejecutable esta en su sitio.

.PARAMETROS
    -Zip       Ruta a un .plugin.zip local (si no, se descarga el ultimo release).
    -Version   Etiqueta concreta a descargar, por ejemplo v0.12.0.
    -NoLanzar  No arranca OpenDeck al terminar.

.EJEMPLOS
    powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
    powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Version v0.12.0
#>

[CmdletBinding()]
param(
    [string]$Zip,
    [string]$Version,
    [switch]$NoLanzar
)

$ErrorActionPreference = 'Stop'

$Repo       = 'pilahito/streamdock-es'
$PluginId   = 'st.lynx.plugins.opendeck-akp153.sdPlugin'
$Destino    = Join-Path $env:APPDATA "opendeck\plugins"
$Exe        = 'opendeck-akp153-win.exe'

function Ok($t)    { Write-Host "  [OK] $t"   -ForegroundColor Green }
function Info($t)  { Write-Host "  [..] $t"   -ForegroundColor Cyan }
function Aviso($t) { Write-Host "  [!!] $t"   -ForegroundColor Yellow }
function Fallo($t) { Write-Host "  [XX] $t"   -ForegroundColor Red }

Write-Host ""
Write-Host "StreamDock ES - instalador para Windows" -ForegroundColor White
Write-Host "=======================================" -ForegroundColor White
Write-Host ""

# -- 1. OpenDeck ------------------------------------------------------------
Write-Host "[1/4] OpenDeck"

$opendeck = Get-Command opendeck -ErrorAction SilentlyContinue
if ($opendeck) {
    Ok "encontrado en $($opendeck.Source)"
} else {
    $candidatos = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\opendeck\opendeck.exe'),
        (Join-Path $env:ProgramFiles 'opendeck\opendeck.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'opendeck\opendeck.exe')
    ) | Where-Object { $_ -and (Test-Path $_) }

    if ($candidatos) {
        Ok "encontrado en $($candidatos[0])"
    } else {
        Aviso "no encuentro OpenDeck instalado."
        Aviso "Descargalo de https://github.com/nekename/OpenDeck/releases/latest"
        $seguir = Read-Host "  Continuar de todas formas? (s/N)"
        if ($seguir -notmatch '^[sSyY]') { exit 1 }
    }
}

# -- 2. descargar el plugin -------------------------------------------------
Write-Host ""
Write-Host "[2/4] Plugin"

$temp = Join-Path $env:TEMP ("streamdock-es-" + [guid]::NewGuid().ToString('N'))

if (-not $Zip) {
    if ($Version) {
        $url = "https://github.com/$Repo/releases/download/$Version/opendeck-akp153.plugin.zip"
    } else {
        Info "buscando el ultimo release..."
        $api = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
            -Headers @{ 'User-Agent' = 'streamdock-es-installer' }
        $asset = $api.assets | Where-Object { $_.name -eq 'opendeck-akp153.plugin.zip' } | Select-Object -First 1
        if (-not $asset) { Fallo "el release $($api.tag_name) no trae opendeck-akp153.plugin.zip"; exit 1 }
        $url = $asset.browser_download_url
        Info "release $($api.tag_name)"
    }

    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $Zip = Join-Path $temp 'plugin.zip'
    Info "descargando $url"
    Invoke-WebRequest -Uri $url -OutFile $Zip -UseBasicParsing
    Ok "descargado ($([math]::Round((Get-Item $Zip).Length / 1MB, 2)) MB)"
} else {
    if (-not (Test-Path $Zip)) { Fallo "no existe $Zip"; exit 1 }
    Ok "usando el zip local $Zip"
}

# -- 3. descomprimir --------------------------------------------------------
Write-Host ""
Write-Host "[3/4] Instalando en OpenDeck"

New-Item -ItemType Directory -Force -Path $Destino | Out-Null

# Si ya habia una version, la quitamos para no dejar binarios viejos mezclados
$anterior = Join-Path $Destino $PluginId
if (Test-Path $anterior) {
    Info "quitando la version anterior"
    Remove-Item -Recurse -Force $anterior
}

Expand-Archive -Path $Zip -DestinationPath $Destino -Force
Ok "descomprimido en $Destino"

$destinoExe = Join-Path $Destino "$PluginId\$Exe"
if (-not (Test-Path $destinoExe)) {
    Fallo "no encuentro $destinoExe dentro del paquete"
    exit 1
}
Ok "ejecutable en su sitio"

# Quitar la marca de "descargado de internet" para que Windows no lo bloquee
Unblock-File -Path $destinoExe -ErrorAction SilentlyContinue

# -- 4. limpieza ------------------------------------------------------------
Write-Host ""
Write-Host "[4/4] Limpieza"

if ($temp -and (Test-Path $temp)) {
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
    Ok "temporales borrados"
}

Write-Host ""
Write-Host "Listo. Desenchufa y vuelve a enchufar el aparato y reinicia OpenDeck." -ForegroundColor Green

if (-not $NoLanzar) {
    $exe = if ($opendeck) { $opendeck.Source } else { $candidatos[0] }
    if ($exe) {
        Info "arrancando OpenDeck..."
        Start-Process -FilePath $exe | Out-Null
    }
}

Write-Host ""
