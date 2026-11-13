# Serve-WebGL.ps1
# Web server lokal sederhana untuk build WebGL Beres Rumah.
# Tanpa dependensi (tidak butuh Python/Node), cukup Windows PowerShell.
#
# Kenapa perlu server:
#   Browser memblokir fetch file:// sehingga .data/.wasm gagal dimuat.
#   Game harus disajikan lewat http://localhost.

[CmdletBinding()]
param(
    [int]$Port = 8080,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\')

if (-not (Test-Path -LiteralPath (Join-Path $rootFull 'index.html'))) {
    Write-Host ""
    Write-Host "  index.html tidak ditemukan di folder ini." -ForegroundColor Red
    Write-Host "  Jalankan launcher dari dalam folder hasil build WebGL."
    Write-Host ""
    exit 1
}

$mime = @{
    '.html'  = 'text/html; charset=utf-8'
    '.htm'   = 'text/html; charset=utf-8'
    '.js'    = 'text/javascript; charset=utf-8'
    '.mjs'   = 'text/javascript; charset=utf-8'
    '.css'   = 'text/css; charset=utf-8'
    '.json'  = 'application/json; charset=utf-8'
    '.wasm'  = 'application/wasm'
    '.data'  = 'application/octet-stream'
    '.unityweb' = 'application/octet-stream'
    '.mem'   = 'application/octet-stream'
    '.png'   = 'image/png'
    '.jpg'   = 'image/jpeg'
    '.jpeg'  = 'image/jpeg'
    '.gif'   = 'image/gif'
    '.ico'   = 'image/x-icon'
    '.svg'   = 'image/svg+xml'
    '.mp3'   = 'audio/mpeg'
    '.wav'   = 'audio/wav'
    '.ogg'   = 'audio/ogg'
    '.txt'   = 'text/plain; charset=utf-8'
    '.xml'   = 'application/xml'
    '.webmanifest' = 'application/manifest+json'
}

# Cari port yang bebas (8080, 8081, ...).
$listener = $null
$chosenPort = $Port

for ($p = $Port; $p -lt ($Port + 20); $p++) {
    try {
        $candidate = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $p)
        $candidate.Start()
        $listener = $candidate
        $chosenPort = $p
        break
    }
    catch {
        $listener = $null
    }
}

if ($null -eq $listener) {
    Write-Host ""
    Write-Host "  Tidak ada port bebas di rentang $Port-$($Port + 19)." -ForegroundColor Red
    Write-Host ""
    exit 1
}

$url = "http://localhost:$chosenPort/"

Write-Host ""
Write-Host "  Beres Rumah - WebGL" -ForegroundColor Green
Write-Host "  -------------------"
Write-Host "  Folder : $rootFull"
Write-Host "  Alamat : $url" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Biarkan jendela ini terbuka selama bermain."
Write-Host "  Tekan Ctrl+C untuk menghentikan server."
Write-Host ""

if (-not $NoBrowser) {
    try {
        Start-Process $url
    }
    catch {
        Write-Host "  Buka manual di browser: $url"
    }
}

function Send-Response {
    param(
        [System.IO.Stream]$Stream,
        [string]$Status,
        [string]$ContentType,
        [byte[]]$Body,
        [bool]$HeadOnly
    )

    $header = "HTTP/1.1 $Status`r`n" +
              "Content-Type: $ContentType`r`n" +
              "Content-Length: $($Body.Length)`r`n" +
              "Cache-Control: no-store`r`n" +
              "Connection: close`r`n`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)

    if (-not $HeadOnly -and $Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }

    $Stream.Flush()
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $client.ReceiveTimeout = 20000
        $client.SendTimeout = 20000

        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader(
                $stream, [System.Text.Encoding]::ASCII, $false, 8192, $true)

            $requestLine = $reader.ReadLine()

            if ([string]::IsNullOrWhiteSpace($requestLine)) {
                $client.Close()
                continue
            }

            # Baca sisa header sampai baris kosong.
            while ($true) {
                $line = $reader.ReadLine()

                if ($null -eq $line -or $line -eq '') {
                    break
                }
            }

            $parts = $requestLine.Split(' ')

            if ($parts.Length -lt 2) {
                $client.Close()
                continue
            }

            $method = $parts[0].ToUpperInvariant()
            $target = $parts[1]
            $path = $target.Split('?')[0]
            $path = [System.Uri]::UnescapeDataString($path)

            if ([string]::IsNullOrEmpty($path) -or $path -eq '/') {
                $path = '/index.html'
            }

            $relative = $path.TrimStart('/').Replace('/', '\')
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $rootFull $relative))

            $headOnly = $method -eq 'HEAD'

            if (-not $fullPath.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                $body = [System.Text.Encoding]::UTF8.GetBytes('403 Forbidden')
                Send-Response -Stream $stream -Status '403 Forbidden' `
                    -ContentType 'text/plain; charset=utf-8' -Body $body -HeadOnly $headOnly
                continue
            }

            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                $body = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
                Send-Response -Stream $stream -Status '404 Not Found' `
                    -ContentType 'text/plain; charset=utf-8' -Body $body -HeadOnly $headOnly
                Write-Host "  404 $path" -ForegroundColor DarkYellow
                continue
            }

            $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
            $contentType = if ($mime.ContainsKey($extension)) {
                $mime[$extension]
            } else {
                'application/octet-stream'
            }

            $bytes = [System.IO.File]::ReadAllBytes($fullPath)
            Send-Response -Stream $stream -Status '200 OK' `
                -ContentType $contentType -Body $bytes -HeadOnly $headOnly

            if ($path -ne '/favicon.ico') {
                Write-Host "  200 $path" -ForegroundColor DarkGray
            }
        }
        catch {
            # Koneksi diputus browser (normal saat pindah halaman).
        }
        finally {
            try { $client.Close() } catch { }
        }
    }
}
finally {
    if ($null -ne $listener) {
        try { $listener.Stop() } catch { }
    }

    Write-Host ""
    Write-Host "  Server dihentikan." -ForegroundColor Yellow
}
