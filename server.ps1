param(
  [int]$Port = 8787
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$rooms = @{}

function Get-ContentType([string]$path) {
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    ".html" { "text/html; charset=utf-8" }
    ".css" { "text/css; charset=utf-8" }
    ".js" { "application/javascript; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    default { "application/octet-stream" }
  }
}

function Read-Request($stream) {
  $buffer = New-Object byte[] 65536
  $read = $stream.Read($buffer, 0, $buffer.Length)
  if ($read -le 0) { return $null }
  $text = [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
  $parts = $text -split "`r`n`r`n", 2
  $head = $parts[0]
  $body = if ($parts.Count -gt 1) { $parts[1] } else { "" }
  $lines = $head -split "`r`n"
  $first = $lines[0] -split " "
  $headers = @{}
  foreach ($line in $lines | Select-Object -Skip 1) {
    $i = $line.IndexOf(":")
    if ($i -gt 0) { $headers[$line.Substring(0,$i).ToLowerInvariant()] = $line.Substring($i+1).Trim() }
  }
  $length = if ($headers.ContainsKey("content-length")) { [int]$headers["content-length"] } else { 0 }
  $bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
  while ($bodyBytes.Length -lt $length) {
    $more = $stream.Read($buffer, 0, [Math]::Min($buffer.Length, $length - $bodyBytes.Length))
    if ($more -le 0) { break }
    $body += [Text.Encoding]::UTF8.GetString($buffer, 0, $more)
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
  }
  [pscustomobject]@{ Method=$first[0]; Url=$first[1]; Headers=$headers; Body=$body }
}

function Send-Bytes($stream, [int]$status, [string]$type, [byte[]]$bytes) {
  $reason = if ($status -eq 200) { "OK" } elseif ($status -eq 404) { "Not Found" } else { "Error" }
  $head = "HTTP/1.1 $status $reason`r`nContent-Type: $type`r`nContent-Length: $($bytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nConnection: close`r`n`r`n"
  $headBytes = [Text.Encoding]::UTF8.GetBytes($head)
  $stream.Write($headBytes, 0, $headBytes.Length)
  $stream.Write($bytes, 0, $bytes.Length)
}

function Send-Json($stream, $obj) {
  $json = $obj | ConvertTo-Json -Depth 100 -Compress
  Send-Bytes $stream 200 "application/json; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes($json))
}

function Get-Query([string]$url) {
  $q = @{}
  $idx = $url.IndexOf("?")
  if ($idx -lt 0) { return $q }
  foreach ($part in $url.Substring($idx + 1).Split("&")) {
    if ($part.Trim() -eq "") { continue }
    $kv = $part.Split("=", 2)
    $key = [Uri]::UnescapeDataString($kv[0])
    $val = if ($kv.Length -gt 1) { [Uri]::UnescapeDataString($kv[1]) } else { "" }
    $q[$key] = $val
  }
  $q
}

function Get-Path([string]$url) {
  $idx = $url.IndexOf("?")
  if ($idx -ge 0) { return $url.Substring(0, $idx) }
  $url
}

function Ensure-Room([string]$room) {
  if ([string]::IsNullOrWhiteSpace($room)) { $room = "BRUMA" }
  $room = $room.ToUpperInvariant()
  if (-not $rooms.ContainsKey($room)) {
    $rooms[$room] = [pscustomobject]@{ State=$null; Players=@{}; Chat=@() }
  }
  $room
}

function Room-Snapshot([string]$room) {
  $r = $rooms[$room]
  $now = Get-Date
  foreach ($k in @($r.Players.Keys)) {
    if (($now - $r.Players[$k].LastSeen).TotalSeconds -gt 20) { $r.Players.Remove($k) }
  }
  [pscustomobject]@{
    state = $r.State
    players = @($r.Players.Values | Sort-Object Joined | ForEach-Object { [pscustomobject]@{ id=$_.Id; name=$_.Name } })
    chat = $r.Chat
  }
}

try {
  $listener.Start()
  $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -notlike '169.*' -and $_.IPAddress -ne '127.0.0.1'} | Select-Object -First 1 -ExpandProperty IPAddress)
  Write-Host "Juego listo en http://localhost:$Port/"
  if ($ip) { Write-Host "En LAN: http://$ip`:$Port/" }
  Write-Host "Ctrl+C para parar."

  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $req = Read-Request $stream
      if ($null -eq $req) { continue }
      $path = Get-Path $req.Url
      $query = Get-Query $req.Url

      if ($path -eq "/api/join") {
        $room = Ensure-Room $query["room"]
        $id = $query["id"]
        if ([string]::IsNullOrWhiteSpace($id)) { $id = [Guid]::NewGuid().ToString("N") }
        $name = if ([string]::IsNullOrWhiteSpace($query["name"])) { "Jugador" } else { $query["name"] }
        $rooms[$room].Players[$id] = [pscustomobject]@{ Id=$id; Name=$name; LastSeen=Get-Date; Joined=Get-Date }
        Send-Json $stream ([pscustomobject]@{ clientId=$id; room=$room; snapshot=(Room-Snapshot $room) })
      } elseif ($path -eq "/api/poll") {
        $room = Ensure-Room $query["room"]
        $id = $query["id"]
        if ($id -and $rooms[$room].Players.ContainsKey($id)) { $rooms[$room].Players[$id].LastSeen = Get-Date }
        Send-Json $stream (Room-Snapshot $room)
      } elseif ($path -eq "/api/state" -and $req.Method -eq "POST") {
        $room = Ensure-Room $query["room"]
        $rooms[$room].State = $req.Body | ConvertFrom-Json
        Send-Json $stream ([pscustomobject]@{ ok=$true })
      } elseif ($path -eq "/api/chat" -and $req.Method -eq "POST") {
        $room = Ensure-Room $query["room"]
        $msg = $req.Body | ConvertFrom-Json
        $rooms[$room].Chat += [pscustomobject]@{ name=$msg.name; text=$msg.text; at=(Get-Date).ToString("HH:mm:ss") }
        if ($rooms[$room].Chat.Count -gt 60) { $rooms[$room].Chat = @($rooms[$room].Chat | Select-Object -Last 60) }
        Send-Json $stream ([pscustomobject]@{ ok=$true })
      } else {
        $rel = $path.TrimStart("/")
        if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "index.html" }
        $file = Join-Path $root $rel
        $full = [IO.Path]::GetFullPath($file)
        if (-not $full.StartsWith([IO.Path]::GetFullPath($root)) -or -not (Test-Path $full -PathType Leaf)) {
          Send-Bytes $stream 404 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes("No encontrado"))
        } else {
          Send-Bytes $stream 200 (Get-ContentType $full) ([IO.File]::ReadAllBytes($full))
        }
      }
    } catch {
      try { Send-Bytes $stream 500 "text/plain; charset=utf-8" ([Text.Encoding]::UTF8.GetBytes($_.Exception.Message)) } catch {}
    } finally {
      $client.Close()
    }
  }
} finally {
  $listener.Stop()
}
