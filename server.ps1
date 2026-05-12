param(
  [int]$Port = 8787,
  [int]$CheckIntervalSeconds = 30,
  [int]$Attempts = 3,
  [int]$TimeoutMs = 900
)

$ErrorActionPreference = "Stop"

$Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$PublicDir = Join-Path $Root "public"
$DataFile = Join-Path $Root "data\store.json"
$BackupDir = Join-Path $Root "backups"
$script:LoginAttempts = @{}

function Get-DefaultSettings {
  return [pscustomobject][ordered]@{
    app_name = "Sword"
    security_mode = "hardened-local"
    session_hours = 8
    login_rate_limit_window_minutes = 15
    login_rate_limit_max_attempts = 5
    audit_retention_days = 180
    event_retention_days = 365
    backup_retention_days = 30
    check_interval_seconds = $CheckIntervalSeconds
    check_attempts = $Attempts
    check_timeout_ms = $TimeoutMs
    require_csrf = $true
    allow_viewer_export = $false
    critical_sound_enabled = $true
    critical_sound_minutes = 5
    ui_theme = "system"
    updated_at = Get-NowIso
  }
}

function Get-NowIso {
  return (Get-Date).ToString("o")
}

function Get-CleanArray($Items) {
  if ($null -eq $Items) {
    return
  }

  foreach ($item in @($Items)) {
    if ($null -ne $item) {
      $item
    }
  }
}

function Get-RandomBytes([int]$Length) {
  $bytes = New-Object byte[] $Length
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($bytes)
  } finally {
    $rng.Dispose()
  }
  return $bytes
}

function ConvertTo-Base64Url([byte[]]$Bytes) {
  return [Convert]::ToBase64String($Bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function New-EntityId([string]$Prefix) {
  $stamp = (Get-Date).ToString("yyyyMMddHHmmssfff")
  $suffix = -join ((48..57) + (97..102) | Get-Random -Count 6 | ForEach-Object {[char]$_})
  return "${Prefix}_${stamp}_${suffix}"
}

function Read-Store {
  if (-not (Test-Path -LiteralPath $DataFile)) {
    throw "Arquivo de dados nao encontrado: $DataFile"
  }

  $json = Get-Content -LiteralPath $DataFile -Raw
  $store = $json | ConvertFrom-Json
  $store.devices = @(Get-CleanArray $store.devices)
  $store.status_events = @(Get-CleanArray $store.status_events)
  $store.alerts = @(Get-CleanArray $store.alerts)
  $store | Add-Member -NotePropertyName users -NotePropertyValue @(Get-CleanArray $store.users) -Force
  $store | Add-Member -NotePropertyName sessions -NotePropertyValue @(Get-CleanArray $store.sessions) -Force
  $store | Add-Member -NotePropertyName audit_logs -NotePropertyValue @(Get-CleanArray $store.audit_logs) -Force
  $store | Add-Member -NotePropertyName integrations -NotePropertyValue @(Get-CleanArray $store.integrations) -Force
  $store | Add-Member -NotePropertyName integration_deliveries -NotePropertyValue @(Get-CleanArray $store.integration_deliveries) -Force
  $store | Add-Member -NotePropertyName report_snapshots -NotePropertyValue @(Get-CleanArray $store.report_snapshots) -Force
  if ($null -eq $store.settings) {
    $store | Add-Member -NotePropertyName settings -NotePropertyValue (Get-DefaultSettings) -Force
  }
  $defaultSettings = Get-DefaultSettings
  foreach ($settingName in $defaultSettings.PSObject.Properties.Name) {
    if ($null -eq $store.settings.$settingName) {
      $store.settings | Add-Member -NotePropertyName $settingName -NotePropertyValue $defaultSettings.$settingName -Force
    }
  }
  foreach ($device in @(Get-CleanArray $store.devices)) {
    if ($null -eq $device.check_method) { $device | Add-Member -NotePropertyName check_method -NotePropertyValue "ping" -Force }
    if ($null -eq $device.port) { $device | Add-Member -NotePropertyName port -NotePropertyValue $null -Force }
    if ($null -eq $device.url_path) { $device | Add-Member -NotePropertyName url_path -NotePropertyValue "/" -Force }
    if ($null -eq $device.expected_status) { $device | Add-Member -NotePropertyName expected_status -NotePropertyValue 200 -Force }
    if ($null -eq $device.owner) { $device | Add-Member -NotePropertyName owner -NotePropertyValue "" -Force }
    if ($null -eq $device.tags) { $device | Add-Member -NotePropertyName tags -NotePropertyValue "" -Force }
    if ($null -eq $device.notes) { $device | Add-Member -NotePropertyName notes -NotePropertyValue "" -Force }
    if ($null -eq $device.serial_number) { $device | Add-Member -NotePropertyName serial_number -NotePropertyValue "" -Force }
    if ($null -eq $device.asset_tag) { $device | Add-Member -NotePropertyName asset_tag -NotePropertyValue "" -Force }
    if ($null -eq $device.model) { $device | Add-Member -NotePropertyName model -NotePropertyValue "" -Force }
    if ($null -eq $device.maintenance_until) { $device | Add-Member -NotePropertyName maintenance_until -NotePropertyValue $null -Force }
  }
  foreach ($user in @(Get-CleanArray $store.users)) {
    if ($null -eq $user.avatar_data_url) { $user | Add-Member -NotePropertyName avatar_data_url -NotePropertyValue "" -Force }
  }
  return $store
}

function Save-Store($Store) {
  $Store.devices = @(Get-CleanArray $Store.devices)
  $Store.status_events = @(Get-CleanArray $Store.status_events)
  $Store.alerts = @(Get-CleanArray $Store.alerts)
  $Store | Add-Member -NotePropertyName users -NotePropertyValue @(Get-CleanArray $Store.users) -Force
  $Store | Add-Member -NotePropertyName sessions -NotePropertyValue @(Get-CleanArray $Store.sessions) -Force
  $Store | Add-Member -NotePropertyName audit_logs -NotePropertyValue @(Get-CleanArray $Store.audit_logs) -Force
  $Store | Add-Member -NotePropertyName integrations -NotePropertyValue @(Get-CleanArray $Store.integrations) -Force
  $Store | Add-Member -NotePropertyName integration_deliveries -NotePropertyValue @(Get-CleanArray $Store.integration_deliveries) -Force
  $Store | Add-Member -NotePropertyName report_snapshots -NotePropertyValue @(Get-CleanArray $Store.report_snapshots) -Force
  if ($null -eq $Store.settings) {
    $Store | Add-Member -NotePropertyName settings -NotePropertyValue (Get-DefaultSettings) -Force
  }
  ConvertTo-Json -InputObject $Store -Depth 20 -Compress | Set-Content -LiteralPath $DataFile -Encoding UTF8
}

function Read-RequestJson($Request) {
  if ($Request.HasEntityBody -ne $true -and [string]::IsNullOrWhiteSpace($Request.ContentBody)) {
    return $null
  }

  if ($null -ne $Request.ContentBody) {
    if ([string]::IsNullOrWhiteSpace($Request.ContentBody)) {
      return $null
    }
    return $Request.ContentBody | ConvertFrom-Json
  }

  $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
  $body = $reader.ReadToEnd()
  $reader.Close()

  if ([string]::IsNullOrWhiteSpace($body)) {
    return $null
  }

  return $body | ConvertFrom-Json
}

function Send-Raw($Context, [byte[]]$Bytes, [string]$ContentType, [int]$StatusCode = 200, [string[]]$ExtraHeaders = @()) {
  $reason = switch ($StatusCode) {
    200 { "OK" }
    201 { "Created" }
    400 { "Bad Request" }
    401 { "Unauthorized" }
    403 { "Forbidden" }
    404 { "Not Found" }
    429 { "Too Many Requests" }
    500 { "Internal Server Error" }
    default { "OK" }
  }

  $extra = ""
  $securityHeaders = @(
    "X-Content-Type-Options: nosniff",
    "X-Frame-Options: DENY",
    "Referrer-Policy: no-referrer",
    "Permissions-Policy: geolocation=(), microphone=(), camera=()",
    "Content-Security-Policy: default-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
  )
  foreach ($line in $securityHeaders) {
    $extra += "$line`r`n"
  }
  foreach ($line in $ExtraHeaders) {
    if (-not [string]::IsNullOrWhiteSpace($line)) {
      $extra += "$line`r`n"
    }
  }

  $header = "HTTP/1.1 $StatusCode $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Bytes.Length)`r`nConnection: close`r`nCache-Control: no-store`r`n$extra`r`n"
  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
  $Context.Stream.Write($headerBytes, 0, $headerBytes.Length)
  $Context.Stream.Write($Bytes, 0, $Bytes.Length)
  $Context.Stream.Flush()
  $Context.Client.Close()
}

function Send-Json($Context, $Data, [int]$StatusCode = 200, [string[]]$ExtraHeaders = @()) {
  $json = ConvertTo-Json -InputObject $Data -Depth 20 -Compress
  if ([string]::IsNullOrWhiteSpace($json)) {
    $json = "null"
  }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  Send-Raw $Context $bytes "application/json; charset=utf-8" $StatusCode $ExtraHeaders
}

function Send-JsonArray($Context, $Items, [int]$StatusCode = 200, [string[]]$ExtraHeaders = @()) {
  $array = @(Get-CleanArray $Items)
  if ($array.Count -eq 0) {
    $json = "[]"
  } else {
    $json = ConvertTo-Json -InputObject $array -Depth 20 -Compress
  }

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  Send-Raw $Context $bytes "application/json; charset=utf-8" $StatusCode $ExtraHeaders
}

function Send-DownloadText($Context, [string]$Text, [string]$ContentType, [string]$FileName) {
  $safeName = "$FileName" -replace '[^A-Za-z0-9_.-]', "_"
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  Send-Raw $Context $bytes $ContentType 200 @("Content-Disposition: attachment; filename=""$safeName""")
}

function Send-Text($Context, [string]$Text, [int]$StatusCode = 200) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  Send-Raw $Context $bytes "text/plain; charset=utf-8" $StatusCode
}

function Send-File($Context, [string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Send-Text $Context "Arquivo nao encontrado" 404
    return
  }

  $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  $contentType = switch ($extension) {
    ".html" { "text/html; charset=utf-8" }
    ".css" { "text/css; charset=utf-8" }
    ".js" { "application/javascript; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    ".svg" { "image/svg+xml" }
    ".png" { "image/png" }
    ".jpg" { "image/jpeg" }
    ".jpeg" { "image/jpeg" }
    default { "application/octet-stream" }
  }

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Send-Raw $Context $bytes $contentType 200
}

function Test-HostOnline([string]$HostName, [int]$AttemptCount, [int]$PingTimeoutMs) {
  if ([string]::IsNullOrWhiteSpace($HostName)) {
    return $false
  }

  $ping = [System.Net.NetworkInformation.Ping]::new()
  try {
    for ($i = 0; $i -lt $AttemptCount; $i++) {
      try {
        $reply = $ping.Send($HostName, $PingTimeoutMs)
        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
          return $true
        }
      } catch {
        Start-Sleep -Milliseconds 120
      }
    }
  } finally {
    $ping.Dispose()
  }

  return $false
}

function Test-TcpOnline([string]$HostName, [int]$Port, [int]$AttemptCount, [int]$TimeoutMs) {
  if ([string]::IsNullOrWhiteSpace($HostName) -or $Port -lt 1 -or $Port -gt 65535) {
    return $false
  }

  for ($i = 0; $i -lt $AttemptCount; $i++) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
      $task = $client.ConnectAsync($HostName, $Port)
      if ($task.Wait($TimeoutMs) -and $client.Connected) {
        return $true
      }
    } catch {
      Start-Sleep -Milliseconds 120
    } finally {
      $client.Close()
    }
  }

  return $false
}

function Test-HttpOnline($Device, [int]$AttemptCount, [int]$TimeoutMs, [string]$DefaultScheme = "http") {
  $hostValue = "$($Device.host)".Trim()
  if ([string]::IsNullOrWhiteSpace($hostValue)) {
    return $false
  }

  $path = if ([string]::IsNullOrWhiteSpace($Device.url_path)) { "/" } else { "$($Device.url_path)" }
  if (-not $path.StartsWith("/")) { $path = "/$path" }
  $expected = if ($null -eq $Device.expected_status) { 200 } else { [int]$Device.expected_status }
  $scheme = if ($DefaultScheme -eq "https") { "https" } else { "http" }
  $url = if ($hostValue -match "^https?://") { $hostValue } else { "${scheme}://$hostValue" }
  if ($null -ne $Device.port -and [int]$Device.port -gt 0 -and $url -notmatch ":\d+(/|$)") {
    $url = "$url`:$($Device.port)"
  }
  if ($url -notmatch "/$" -and $path -ne "/") { $url = "$url$path" }

  for ($i = 0; $i -lt $AttemptCount; $i++) {
    try {
      $request = [System.Net.HttpWebRequest]::Create($url)
      $request.Method = "GET"
      $request.Timeout = $TimeoutMs
      $request.ReadWriteTimeout = $TimeoutMs
      $request.AllowAutoRedirect = $false
      $response = $request.GetResponse()
      try {
        $statusCode = [int]$response.StatusCode
        if ($statusCode -eq $expected) {
          return $true
        }
      } finally {
        $response.Close()
      }
    } catch [System.Net.WebException] {
      if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
        $_.Exception.Response.Close()
        if ($statusCode -eq $expected) {
          return $true
        }
      }
      Start-Sleep -Milliseconds 120
    } catch {
      Start-Sleep -Milliseconds 120
    }
  }

  return $false
}

function Test-DeviceOnline($Device, [int]$AttemptCount, [int]$TimeoutMs) {
  $method = if ([string]::IsNullOrWhiteSpace($Device.check_method)) { "ping" } else { "$($Device.check_method)".ToLowerInvariant() }
  switch ($method) {
    "tcp" { return Test-TcpOnline "$($Device.host)" ([int]$Device.port) $AttemptCount $TimeoutMs }
    "http" { return Test-HttpOnline $Device $AttemptCount $TimeoutMs "http" }
    "https" { return Test-HttpOnline $Device $AttemptCount $TimeoutMs "https" }
    default { return Test-HostOnline "$($Device.host)" $AttemptCount $TimeoutMs }
  }
}

function Get-OpenEvent($Store, [string]$DeviceId) {
  return @(Get-CleanArray $Store.status_events) |
    Where-Object { $_.device_id -eq $DeviceId -and $_.status -eq "open" } |
    Select-Object -First 1
}

function Get-DeviceById($Store, [string]$DeviceId) {
  return @(Get-CleanArray $Store.devices) | Where-Object { $_.id -eq $DeviceId } | Select-Object -First 1
}

function Test-AllowedValue([string]$Value, [string[]]$Allowed) {
  return $Allowed -contains "$Value".ToLowerInvariant()
}

function Get-PasswordHash([string]$Password) {
  $iterations = 120000
  $salt = Get-RandomBytes 16
  $derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($Password, $salt, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
  try {
    $hash = $derive.GetBytes(32)
  } finally {
    $derive.Dispose()
  }

  return "pbkdf2-sha256:${iterations}:$([Convert]::ToBase64String($salt)):$([Convert]::ToBase64String($hash))"
}

function Test-PasswordHash([string]$Password, [string]$StoredHash) {
  if ([string]::IsNullOrWhiteSpace($Password) -or [string]::IsNullOrWhiteSpace($StoredHash)) {
    return $false
  }

  $parts = @($StoredHash -split ":")
  if ($parts.Count -ne 4 -or $parts[0] -ne "pbkdf2-sha256") {
    return $false
  }

  try {
    $iterations = [int]$parts[1]
    $salt = [Convert]::FromBase64String($parts[2])
    $expected = [Convert]::FromBase64String($parts[3])
    $derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($Password, $salt, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
      $actual = $derive.GetBytes($expected.Length)
    } finally {
      $derive.Dispose()
    }
    if ($actual.Length -ne $expected.Length) {
      return $false
    }

    $diff = 0
    for ($i = 0; $i -lt $actual.Length; $i++) {
      $diff = $diff -bor ($actual[$i] -bxor $expected[$i])
    }
    return $diff -eq 0
  } catch {
    return $false
  }
}

function Get-TokenHash([string]$Token) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Token)
    return [Convert]::ToBase64String($sha.ComputeHash($bytes))
  } finally {
    $sha.Dispose()
  }
}

function New-SessionToken {
  return ConvertTo-Base64Url (Get-RandomBytes 32)
}

function New-CsrfToken {
  return ConvertTo-Base64Url (Get-RandomBytes 24)
}

function Get-CookieValue($Request, [string]$Name) {
  if ($null -eq $Request.Headers -or -not $Request.Headers.ContainsKey("cookie")) {
    return $null
  }

  foreach ($part in @($Request.Headers["cookie"] -split ";")) {
    $pair = @($part.Trim() -split "=", 2)
    if ($pair.Count -eq 2 -and $pair[0] -eq $Name) {
      return $pair[1]
    }
  }

  return $null
}

function Get-PublicUser($User) {
  if ($null -eq $User) {
    return $null
  }

  return [pscustomobject][ordered]@{
    id = $User.id
    name = $User.name
    email = $User.email
    role = $User.role
    status = $User.status
    avatar_data_url = if ($null -eq $User.avatar_data_url) { "" } else { $User.avatar_data_url }
    created_at = $User.created_at
    updated_at = $User.updated_at
    last_login_at = $User.last_login_at
  }
}

function Get-PublicSettings($Settings) {
  if ($null -eq $Settings) {
    $Settings = Get-DefaultSettings
  }

  return [pscustomobject][ordered]@{
    app_name = $Settings.app_name
    security_mode = $Settings.security_mode
    session_hours = [int]$Settings.session_hours
    login_rate_limit_window_minutes = [int]$Settings.login_rate_limit_window_minutes
    login_rate_limit_max_attempts = [int]$Settings.login_rate_limit_max_attempts
    audit_retention_days = [int]$Settings.audit_retention_days
    event_retention_days = [int]$Settings.event_retention_days
    backup_retention_days = [int]$Settings.backup_retention_days
    check_interval_seconds = [int]$Settings.check_interval_seconds
    check_attempts = [int]$Settings.check_attempts
    check_timeout_ms = [int]$Settings.check_timeout_ms
    require_csrf = [bool]$Settings.require_csrf
    allow_viewer_export = [bool]$Settings.allow_viewer_export
    critical_sound_enabled = [bool]$Settings.critical_sound_enabled
    critical_sound_minutes = [int]$Settings.critical_sound_minutes
    ui_theme = if ([string]::IsNullOrWhiteSpace($Settings.ui_theme)) { "system" } else { $Settings.ui_theme }
    updated_at = $Settings.updated_at
  }
}

function Get-RoleLabel([string]$Role) {
  switch ("$Role".ToLowerInvariant()) {
    "admin" { "Administrador" }
    "operator" { "Operador" }
    "viewer" { "Visualizador" }
    default { $Role }
  }
}

function Test-RoleAllowed([string]$Role, [string[]]$AllowedRoles) {
  return $AllowedRoles -contains "$Role".ToLowerInvariant()
}

function Get-CurrentUser($Store, $Request) {
  $token = Get-CookieValue $Request "sword_session"
  if ([string]::IsNullOrWhiteSpace($token)) {
    return $null
  }

  $tokenHash = Get-TokenHash $token
  $now = Get-Date
  $session = @(Get-CleanArray $Store.sessions) |
    Where-Object { $_.token_hash -eq $tokenHash -and $_.status -eq "active" } |
    Select-Object -First 1

  if ($null -eq $session) {
    return $null
  }

  if ([datetime]::Parse($session.expires_at) -lt $now) {
    $session.status = "expired"
    return $null
  }

  $user = @(Get-CleanArray $Store.users) |
    Where-Object { $_.id -eq $session.user_id -and $_.status -eq "active" } |
    Select-Object -First 1

  return $user
}

function Get-CurrentSession($Store, $Request) {
  $token = Get-CookieValue $Request "sword_session"
  if ([string]::IsNullOrWhiteSpace($token)) {
    return $null
  }

  $tokenHash = Get-TokenHash $token
  $now = Get-Date
  return @(Get-CleanArray $Store.sessions) |
    Where-Object { $_.token_hash -eq $tokenHash -and $_.status -eq "active" -and [datetime]::Parse($_.expires_at) -gt $now } |
    Select-Object -First 1
}

function Test-Csrf($Store, $Request) {
  if ($Store.settings.require_csrf -ne $true) {
    return $true
  }

  $method = "$($Request.HttpMethod)".ToUpperInvariant()
  if ($method -notin @("POST", "PUT", "DELETE", "PATCH")) {
    return $true
  }

  $path = $Request.Url.AbsolutePath.TrimEnd("/")
  if ($path -in @("/api/auth/setup", "/api/auth/login", "/api/auth/logout")) {
    return $true
  }

  $session = Get-CurrentSession $Store $Request
  if ($null -eq $session -or [string]::IsNullOrWhiteSpace($session.csrf_token)) {
    return $false
  }

  if ($null -eq $Request.Headers -or -not $Request.Headers.ContainsKey("x-csrf-token")) {
    return $false
  }

  return "$($Request.Headers["x-csrf-token"])" -eq "$($session.csrf_token)"
}

function Get-UserByEmail($Store, [string]$Email) {
  $normalized = "$Email".Trim().ToLowerInvariant()
  return @(Get-CleanArray $Store.users) |
    Where-Object { "$($_.email)".ToLowerInvariant() -eq $normalized } |
    Select-Object -First 1
}

function Get-UserById($Store, [string]$UserId) {
  return @(Get-CleanArray $Store.users) |
    Where-Object { $_.id -eq $UserId } |
    Select-Object -First 1
}

function Add-AuditLog($Store, $User, [string]$Action, [string]$EntityType, [string]$EntityId, $Metadata = $null) {
  $entry = [pscustomobject][ordered]@{
    id = New-EntityId "aud"
    user_id = if ($null -eq $User) { $null } else { $User.id }
    action = $Action
    entity_type = $EntityType
    entity_id = $EntityId
    created_at = Get-NowIso
    metadata = $Metadata
  }
  $Store.audit_logs = @(Get-CleanArray $Store.audit_logs) + $entry
}

function Get-AuditRows($Store) {
  return @(Get-CleanArray $Store.audit_logs) |
    Sort-Object { [datetime]::Parse($_.created_at) } -Descending |
    Select-Object -First 500 |
    ForEach-Object {
      $user = Get-UserById $Store $_.user_id
      [pscustomobject][ordered]@{
        id = $_.id
        user_id = $_.user_id
        user_name = if ($null -eq $user) { "Sistema" } else { $user.name }
        action = $_.action
        entity_type = $_.entity_type
        entity_id = $_.entity_id
        created_at = $_.created_at
        metadata = $_.metadata
      }
    }
}

function Invoke-RetentionCleanup($Store) {
  $settings = Get-PublicSettings $Store.settings
  $now = Get-Date
  $auditCutoff = $now.AddDays(-[int]$settings.audit_retention_days)
  $eventCutoff = $now.AddDays(-[int]$settings.event_retention_days)

  $Store.audit_logs = @(Get-CleanArray $Store.audit_logs | Where-Object { [datetime]::Parse($_.created_at) -ge $auditCutoff })
  $Store.status_events = @(Get-CleanArray $Store.status_events | Where-Object { $_.status -eq "open" -or [datetime]::Parse($_.created_at) -ge $eventCutoff })
}

function New-Backup($Store, $User) {
  if (-not (Test-Path -LiteralPath $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
  }

  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $fileName = "sword-backup-$stamp.json"
  $path = Join-Path $BackupDir $fileName
  ConvertTo-Json -InputObject $Store -Depth 20 -Compress | Set-Content -LiteralPath $path -Encoding UTF8
  Add-AuditLog $Store $User "backup.create" "backup" $fileName $null
  return [pscustomobject][ordered]@{
    file = $fileName
    path = $path
    created_at = Get-NowIso
  }
}

function Get-Backups {
  if (-not (Test-Path -LiteralPath $BackupDir)) {
    return @()
  }

  return @(Get-ChildItem -LiteralPath $BackupDir -Filter "sword-backup-*.json" -File | Sort-Object LastWriteTime -Descending | ForEach-Object {
    [pscustomobject][ordered]@{
      file = $_.Name
      size = $_.Length
      created_at = $_.LastWriteTime.ToString("o")
    }
  })
}

function Test-LoginRateLimit($Store, [string]$Email, [string]$RemoteKey) {
  $settings = Get-PublicSettings $Store.settings
  $key = ("$Email|$RemoteKey").ToLowerInvariant()
  $now = Get-Date
  $windowStart = $now.AddMinutes(-[int]$settings.login_rate_limit_window_minutes)

  if (-not $script:LoginAttempts.ContainsKey($key)) {
    $script:LoginAttempts[$key] = @()
  }

  $script:LoginAttempts[$key] = @($script:LoginAttempts[$key] | Where-Object { $_ -gt $windowStart })
  return @($script:LoginAttempts[$key]).Count -lt [int]$settings.login_rate_limit_max_attempts
}

function Add-LoginFailure($Store, [string]$Email, [string]$RemoteKey) {
  $key = ("$Email|$RemoteKey").ToLowerInvariant()
  if (-not $script:LoginAttempts.ContainsKey($key)) {
    $script:LoginAttempts[$key] = @()
  }
  $script:LoginAttempts[$key] = @($script:LoginAttempts[$key]) + (Get-Date)
}

function Clear-LoginFailures([string]$Email, [string]$RemoteKey) {
  $key = ("$Email|$RemoteKey").ToLowerInvariant()
  if ($script:LoginAttempts.ContainsKey($key)) {
    $script:LoginAttempts.Remove($key)
  }
}

function Get-UserBodyError($Body, [bool]$IsCreate) {
  if ($null -eq $Body) {
    return "Corpo da requisicao invalido."
  }

  if ($IsCreate -or $null -ne $Body.name) {
    if ([string]::IsNullOrWhiteSpace($Body.name) -or "$($Body.name)".Trim().Length -gt 80) {
      return "Nome e obrigatorio e deve ter ate 80 caracteres."
    }
  }

  if ($IsCreate -or $null -ne $Body.email) {
    if ([string]::IsNullOrWhiteSpace($Body.email) -or "$($Body.email)" -notmatch "^[^@\s]+@[^@\s]+\.[^@\s]+$") {
      return "Email invalido."
    }
  }

  if ($IsCreate -or $null -ne $Body.role) {
    if (-not (Test-AllowedValue "$($Body.role)" @("admin", "operator", "viewer"))) {
      return "Cargo invalido."
    }
  }

  if ($IsCreate -or $null -ne $Body.password) {
    if ([string]::IsNullOrWhiteSpace($Body.password) -or "$($Body.password)".Length -lt 6) {
      return "Senha deve ter pelo menos 6 caracteres."
    }
  }

  if ($null -ne $Body.status -and -not (Test-AllowedValue "$($Body.status)" @("active", "inactive"))) {
    return "Status de usuario invalido."
  }

  if ($null -ne $Body.avatar_data_url -and "$($Body.avatar_data_url)".Length -gt 250000) {
    return "Foto do usuario deve ter ate 250 KB."
  }

  if ($null -ne $Body.avatar_data_url -and -not [string]::IsNullOrWhiteSpace($Body.avatar_data_url) -and "$($Body.avatar_data_url)" -notmatch "^data:image/(png|jpeg|jpg|webp);base64,") {
    return "Foto do usuario deve ser PNG, JPG ou WEBP."
  }

  return $null
}

function Get-SettingsBodyError($Body) {
  if ($null -eq $Body) {
    return "Corpo da requisicao invalido."
  }

  foreach ($field in @("session_hours", "login_rate_limit_window_minutes", "login_rate_limit_max_attempts", "audit_retention_days", "event_retention_days", "backup_retention_days", "check_interval_seconds", "check_attempts", "check_timeout_ms", "critical_sound_minutes")) {
    if ($null -ne $Body.$field) {
      $value = [int]$Body.$field
      if ($value -lt 1 -or $value -gt 100000) {
        return "Valor invalido para $field."
      }
    }
  }

  if ($null -ne $Body.app_name -and ("$($Body.app_name)".Trim().Length -lt 1 -or "$($Body.app_name)".Trim().Length -gt 40)) {
    return "Nome da aplicacao deve ter ate 40 caracteres."
  }

  if ($null -ne $Body.ui_theme -and -not (Test-AllowedValue "$($Body.ui_theme)" @("system", "light", "dark", "blackout", "steel", "contrast"))) {
    return "Tema invalido."
  }

  return $null
}

function New-UserFromBody($Body, [string]$Now) {
  return [pscustomobject][ordered]@{
    id = New-EntityId "usr"
    name = "$($Body.name)".Trim()
    email = "$($Body.email)".Trim().ToLowerInvariant()
    password_hash = Get-PasswordHash "$($Body.password)"
    role = "$($Body.role)".Trim().ToLowerInvariant()
    status = "active"
    avatar_data_url = if ([string]::IsNullOrWhiteSpace($Body.avatar_data_url)) { "" } else { "$($Body.avatar_data_url)".Trim() }
    created_at = $Now
    updated_at = $Now
    last_login_at = $null
  }
}

function New-Session($Store, $User, $Request) {
  $token = New-SessionToken
  $csrfToken = New-CsrfToken
  $now = Get-Date
  $settings = Get-PublicSettings $Store.settings
  $session = [pscustomobject][ordered]@{
    id = New-EntityId "ses"
    user_id = $User.id
    token_hash = Get-TokenHash $token
    csrf_token = $csrfToken
    status = "active"
    created_at = $now.ToString("o")
    expires_at = $now.AddHours([int]$settings.session_hours).ToString("o")
    ip_address = if ($null -eq $Request.RemoteEndPoint) { $null } else { "$($Request.RemoteEndPoint)" }
    user_agent = if ($Request.Headers.ContainsKey("user-agent")) { $Request.Headers["user-agent"] } else { $null }
  }
  $Store.sessions = @(Get-CleanArray $Store.sessions | Where-Object { $_.status -eq "active" -and [datetime]::Parse($_.expires_at) -gt $now }) + $session
  return [pscustomobject]@{ token = $token; csrf_token = $csrfToken; session = $session }
}

function Get-SessionCookieHeader([string]$Token, [int]$Hours = 8) {
  $maxAge = [math]::Max(60, $Hours * 3600)
  return "Set-Cookie: sword_session=$Token; HttpOnly; SameSite=Strict; Path=/; Max-Age=$maxAge"
}

function Get-ClearSessionCookieHeader {
  return "Set-Cookie: sword_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0"
}

function Get-QueryValue($Request, [string]$Name, [string]$Default = "") {
  $query = "$($Request.Url.Query)"
  if ([string]::IsNullOrWhiteSpace($query)) {
    return $Default
  }

  foreach ($part in @($query.TrimStart("?").Split("&", [System.StringSplitOptions]::RemoveEmptyEntries))) {
    $pair = @($part -split "=", 2)
    $key = [uri]::UnescapeDataString($pair[0])
    if ($key -eq $Name) {
      if ($pair.Count -eq 1) { return "" }
      return [uri]::UnescapeDataString($pair[1].Replace("+", " "))
    }
  }

  return $Default
}

function Get-ReportRange($Request) {
  $now = Get-Date
  $fromText = Get-QueryValue $Request "from" ""
  $toText = Get-QueryValue $Request "to" ""
  $from = if ([string]::IsNullOrWhiteSpace($fromText)) { $now.AddHours(-24) } else { [datetime]::Parse($fromText) }
  $to = if ([string]::IsNullOrWhiteSpace($toText)) { $now } else { [datetime]::Parse($toText) }
  if ($to -lt $from) {
    $tmp = $from
    $from = $to
    $to = $tmp
  }
  return [pscustomobject]@{ From = $from; To = $to }
}

function ConvertTo-CsvText($Rows) {
  $items = @(Get-CleanArray $Rows)
  if ($items.Count -eq 0) {
    return ""
  }
  return (@($items | ConvertTo-Csv -NoTypeInformation) -join "`r`n")
}

function New-ReportSnapshot($Store, $User, [string]$Kind, $Filters, [int]$RowCount) {
  $snapshot = [pscustomobject][ordered]@{
    id = New-EntityId "rpt"
    kind = $Kind
    filters = $Filters
    row_count = $RowCount
    created_by = if ($null -eq $User) { $null } else { $User.id }
    created_at = Get-NowIso
  }
  $Store.report_snapshots = @(@(Get-CleanArray $Store.report_snapshots) + $snapshot | Select-Object -Last 100)
  return $snapshot
}

function Get-DeviceBodyError($Body, [bool]$IsCreate) {
  if ($null -eq $Body) {
    return "Corpo da requisicao invalido."
  }

  if ($IsCreate -or $null -ne $Body.name) {
    if ([string]::IsNullOrWhiteSpace($Body.name) -or "$($Body.name)".Length -gt 80) {
      return "Nome e obrigatorio e deve ter ate 80 caracteres."
    }
  }

  if ($IsCreate -or $null -ne $Body.host) {
    if ([string]::IsNullOrWhiteSpace($Body.host) -or "$($Body.host)".Length -gt 120) {
      return "IP ou hostname e obrigatorio e deve ter ate 120 caracteres."
    }
    if ("$($Body.host)" -notmatch "^[A-Za-z0-9_.:-]+$") {
      return "IP ou hostname deve conter apenas letras, numeros, ponto, hifen, underline ou dois-pontos."
    }
  }

  if ($IsCreate -or $null -ne $Body.criticality) {
    if (-not (Test-AllowedValue "$($Body.criticality)" @("baixa", "media", "alta", "critica"))) {
      return "Criticidade invalida."
    }
  }

  if ($null -ne $Body.current_status -and -not (Test-AllowedValue "$($Body.current_status)" @("online", "offline"))) {
    return "Status atual invalido."
  }

  if ($null -ne $Body.check_method -and -not (Test-AllowedValue "$($Body.check_method)" @("ping", "tcp", "http", "https"))) {
    return "Metodo de verificacao invalido."
  }

  $method = if ([string]::IsNullOrWhiteSpace($Body.check_method)) { "ping" } else { "$($Body.check_method)".Trim().ToLowerInvariant() }
  if ($method -eq "tcp" -and ($null -eq $Body.port -or "$($Body.port)" -eq "")) {
    return "Porta e obrigatoria para verificacao TCP."
  }

  if ($null -ne $Body.port -and "$($Body.port)" -ne "") {
    try {
      $port = [int]$Body.port
    } catch {
      return "Porta deve ser numerica."
    }
    if ($port -lt 1 -or $port -gt 65535) {
      return "Porta deve estar entre 1 e 65535."
    }
  }

  if ($null -ne $Body.expected_status -and "$($Body.expected_status)" -ne "") {
    try {
      $status = [int]$Body.expected_status
    } catch {
      return "Status HTTP esperado deve ser numerico."
    }
    if ($status -lt 100 -or $status -gt 599) {
      return "Status HTTP esperado deve estar entre 100 e 599."
    }
  }

  foreach ($field in @("type", "location", "owner", "tags", "serial_number", "asset_tag", "model")) {
    if ($null -ne $Body.$field -and "$($Body.$field)".Length -gt 120) {
      return "Campo $field deve ter ate 120 caracteres."
    }
  }

  if ($null -ne $Body.url_path -and "$($Body.url_path)".Length -gt 160) {
    return "Caminho HTTP deve ter ate 160 caracteres."
  }

  if ($null -ne $Body.maintenance_until -and -not [string]::IsNullOrWhiteSpace($Body.maintenance_until)) {
    try {
      [datetime]::Parse("$($Body.maintenance_until)") | Out-Null
    } catch {
      return "Data de manutencao invalida."
    }
  }

  if ($null -ne $Body.notes -and "$($Body.notes)".Length -gt 500) {
    return "Observacoes devem ter ate 500 caracteres."
  }

  return $null
}

function New-StatusEvent($Store, $Device, [string]$Now) {
  $event = [pscustomobject][ordered]@{
    id = New-EntityId "evt"
    device_id = $Device.id
    down_at = $Now
    up_at = $null
    duration_seconds = $null
    status = "open"
    criticality = $Device.criticality
    created_at = $Now
    updated_at = $Now
  }

  $Store.status_events = @(Get-CleanArray $Store.status_events) + $event
  return $event
}

function New-CriticalAlert($Store, $Device, $Event, [string]$Now) {
  $criticality = "$($Device.criticality)".ToLowerInvariant()
  if ($criticality -notin @("alta", "critica")) {
    return
  }

  $priority = if ($criticality -eq "critica") { "critical" } else { "high" }
  $label = if ($criticality -eq "critica") { "CRITICO" } else { "ALTA" }
  $alert = [pscustomobject][ordered]@{
    id = New-EntityId "alt"
    device_id = $Device.id
    status_event_id = $Event.id
    title = "[$label] $($Device.name) offline"
    message = "$($Device.name) esta offline em $($Device.location)."
    priority = $priority
    status = "open"
    created_at = $Now
    resolved_at = $null
  }

  $Store.alerts = @(Get-CleanArray $Store.alerts) + $alert
  Invoke-AlertIntegrations $Store $Device $Event $alert
}

function Invoke-AlertIntegrations($Store, $Device, $Event, $Alert) {
  foreach ($integration in @(Get-CleanArray $Store.integrations | Where-Object { $_.enabled -eq $true -and $_.type -eq "webhook" })) {
    $delivery = [pscustomobject][ordered]@{
      id = New-EntityId "del"
      integration_id = $integration.id
      alert_id = $Alert.id
      status = "pending"
      status_code = $null
      error = $null
      created_at = Get-NowIso
    }

    try {
      $payload = [pscustomobject][ordered]@{
        source = "Sword"
        event = "alert.created"
        alert = $Alert
        device = $Device
        status_event = $Event
        sent_at = Get-NowIso
      } | ConvertTo-Json -Depth 12 -Compress
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
      $request = [System.Net.HttpWebRequest]::Create("$($integration.url)")
      $request.Method = "POST"
      $request.ContentType = "application/json"
      $request.Timeout = 2500
      $request.ReadWriteTimeout = 2500
      if (-not [string]::IsNullOrWhiteSpace($integration.secret)) {
        $request.Headers.Add("X-Sword-Secret", "$($integration.secret)")
      }
      $request.ContentLength = $bytes.Length
      $stream = $request.GetRequestStream()
      $stream.Write($bytes, 0, $bytes.Length)
      $stream.Close()
      $response = $request.GetResponse()
      try {
        $delivery.status = "delivered"
        $delivery.status_code = [int]$response.StatusCode
      } finally {
        $response.Close()
      }
    } catch {
      $delivery.status = "failed"
      $delivery.error = $_.Exception.Message
    }

    $Store.integration_deliveries = @(Get-CleanArray $Store.integration_deliveries) + $delivery
  }
}

function Resolve-EventAndAlerts($Store, $Device, [string]$Now) {
  $openEvent = Get-OpenEvent $Store $Device.id
  if ($null -eq $openEvent) {
    return
  }

  $downAt = [datetime]::Parse($openEvent.down_at)
  $upAt = [datetime]::Parse($Now)
  $openEvent.up_at = $Now
  $openEvent.duration_seconds = [int][math]::Max(0, ($upAt - $downAt).TotalSeconds)
  $openEvent.status = "resolved"
  $openEvent.updated_at = $Now

  foreach ($alert in @(Get-CleanArray $Store.alerts)) {
    if ($alert.status_event_id -eq $openEvent.id -and $alert.status -eq "open") {
      $alert.status = "resolved"
      $alert.resolved_at = $Now
    }
  }
}

function Apply-DeviceStatus($Store, $Device, [bool]$IsOnline, [string]$Now) {
  $nextStatus = if ($IsOnline) { "online" } else { "offline" }
  $previousStatus = "$($Device.current_status)".ToLowerInvariant()

  if ($nextStatus -eq "offline") {
    $openEvent = Get-OpenEvent $Store $Device.id
    if ($null -eq $openEvent) {
      $event = New-StatusEvent $Store $Device $Now
      New-CriticalAlert $Store $Device $event $Now
    }
  } elseif ($previousStatus -ne $nextStatus) {
      Resolve-EventAndAlerts $Store $Device $Now
  }

  $Device.current_status = $nextStatus
  $Device.last_check_at = $Now
  $Device.updated_at = $Now
}

function Invoke-DeviceCheck($Store, $Device) {
  if ($Device.is_active -ne $true) {
    return [pscustomobject]@{
      device_id = $Device.id
      checked = $false
      reason = "inactive"
      status = $Device.current_status
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($Device.maintenance_until)) {
    try {
      if ([datetime]::Parse($Device.maintenance_until) -gt (Get-Date)) {
        return [pscustomobject]@{
          device_id = $Device.id
          checked = $false
          reason = "maintenance"
          status = $Device.current_status
          maintenance_until = $Device.maintenance_until
        }
      }
    } catch {}
  }

  $now = Get-NowIso
  $settings = Get-PublicSettings $Store.settings
  $isOnline = Test-DeviceOnline $Device ([int]$settings.check_attempts) ([int]$settings.check_timeout_ms)
  Apply-DeviceStatus $Store $Device $isOnline $now

  return [pscustomobject]@{
    device_id = $Device.id
    checked = $true
    status = $Device.current_status
    method = if ([string]::IsNullOrWhiteSpace($Device.check_method)) { "ping" } else { "$($Device.check_method)" }
    checked_at = $now
  }
}

function Invoke-MonitorCycle {
  $store = Read-Store
  $results = @()

  foreach ($device in @(Get-CleanArray $store.devices)) {
    if ($device.is_active -eq $true) {
      $results += Invoke-DeviceCheck $store $device
    }
  }

  Save-Store $store
  return $results
}

function Get-Summary($Store) {
  $activeDevices = @(Get-CleanArray $Store.devices) | Where-Object { $_.is_active -eq $true }
  $online = @($activeDevices | Where-Object { $_.current_status -eq "online" })
  $offline = @($activeDevices | Where-Object { $_.current_status -eq "offline" })
  $criticalOffline = @($offline | Where-Object { "$($_.criticality)".ToLowerInvariant() -in @("alta", "critica") })
  $openAlerts = @(Get-CleanArray $Store.alerts | Where-Object { $_.status -eq "open" })

  return [pscustomobject]@{
    total = @($activeDevices).Count
    online = $online.Count
    offline = $offline.Count
    critical_offline = $criticalOffline.Count
    open_alerts = $openAlerts.Count
    generated_at = Get-NowIso
  }
}

function Get-ReportDevices($Store, [string]$DeviceId) {
  $devices = @(Get-CleanArray $Store.devices)
  if (-not [string]::IsNullOrWhiteSpace($DeviceId) -and $DeviceId -ne "all") {
    $devices = @($devices | Where-Object { $_.id -eq $DeviceId })
  }
  return $devices
}

function Get-EventsInRange($Store, [datetime]$From, [datetime]$To, [string]$DeviceId = "") {
  return @(Get-CleanArray $Store.status_events) | Where-Object {
    if ([string]::IsNullOrWhiteSpace($_.down_at)) {
      $false
    } else {
      $downAt = [datetime]::Parse($_.down_at)
      $upAt = if ([string]::IsNullOrWhiteSpace($_.up_at)) { $To } else { [datetime]::Parse($_.up_at) }
      $matchesDevice = [string]::IsNullOrWhiteSpace($DeviceId) -or $DeviceId -eq "all" -or $_.device_id -eq $DeviceId
      $matchesDevice -and $downAt -le $To -and $upAt -ge $From
    }
  }
}

function Get-AttentionAssessment($Device, [double]$Availability, [int]$DownSeconds, [bool]$OpenIncident) {
  $criticality = "$($Device.criticality)".ToLowerInvariant()
  if ($OpenIncident -and $criticality -in @("alta", "critica")) {
    return [pscustomobject]@{ level = "critica"; label = "Atencao imediata"; reason = "Ativo critico offline agora." }
  }
  if ($Availability -lt 95) {
    return [pscustomobject]@{ level = "alta"; label = "Investigar"; reason = "Disponibilidade abaixo de 95% no periodo." }
  }
  if ($Availability -lt 99 -or $DownSeconds -gt 0) {
    return [pscustomobject]@{ level = "media"; label = "Acompanhar"; reason = "Houve indisponibilidade no periodo." }
  }
  return [pscustomobject]@{ level = "baixa"; label = "Normal"; reason = "Sem queda relevante no periodo." }
}

function Get-AvailabilityReport($Store, $Request = $null) {
  $range = if ($null -eq $Request) { [pscustomobject]@{ From = (Get-Date).AddHours(-24); To = Get-Date } } else { Get-ReportRange $Request }
  $deviceId = if ($null -eq $Request) { "" } else { Get-QueryValue $Request "device_id" "" }
  $devices = @(Get-ReportDevices $Store $deviceId)
  $periodSeconds = [math]::Max(1, ($range.To - $range.From).TotalSeconds)
  $rows = @()

  foreach ($device in $devices) {
    $events = @(Get-EventsInRange $Store $range.From $range.To $device.id)
    $downSeconds = 0
    $resolvedDurations = @()

    foreach ($event in $events) {
      $downAt = [datetime]::Parse($event.down_at)
      $upAt = if ([string]::IsNullOrWhiteSpace($event.up_at)) { $range.To } else { [datetime]::Parse($event.up_at) }
      $start = if ($downAt -lt $range.From) { $range.From } else { $downAt }
      $end = if ($upAt -gt $range.To) { $range.To } else { $upAt }
      $duration = [int][math]::Max(0, ($end - $start).TotalSeconds)
      $downSeconds += $duration
      if (-not [string]::IsNullOrWhiteSpace($event.up_at)) {
        $resolvedDurations += [int][math]::Max(0, ([datetime]::Parse($event.up_at) - [datetime]::Parse($event.down_at)).TotalSeconds)
      }
    }

    $upSeconds = [int][math]::Max(0, $periodSeconds - $downSeconds)
    $availability = [math]::Round([math]::Max(0, (1 - ($downSeconds / $periodSeconds)) * 100), 2)
    $openIncident = $null -ne (Get-OpenEvent $Store $device.id)
    $assessment = Get-AttentionAssessment $device $availability ([int]$downSeconds) $openIncident
    $mttr = if (@($resolvedDurations).Count -gt 0) { [int]([math]::Round((@($resolvedDurations) | Measure-Object -Average).Average, 0)) } else { 0 }

    $rows += [pscustomobject][ordered]@{
      device_id = $device.id
      name = $device.name
      host = $device.host
      type = $device.type
      location = $device.location
      criticality = $device.criticality
      current_status = $device.current_status
      check_method = if ([string]::IsNullOrWhiteSpace($device.check_method)) { "ping" } else { $device.check_method }
      serial_number = if ($null -eq $device.serial_number) { "" } else { $device.serial_number }
      asset_tag = if ($null -eq $device.asset_tag) { "" } else { $device.asset_tag }
      model = if ($null -eq $device.model) { "" } else { $device.model }
      last_check_at = $device.last_check_at
      events_count = @($events).Count
      down_count = @($events | Where-Object { $_.down_at }).Count
      up_count = @($events | Where-Object { -not [string]::IsNullOrWhiteSpace($_.up_at) }).Count
      down_seconds = [int]$downSeconds
      up_seconds = $upSeconds
      mttr_seconds = $mttr
      availability_percent = $availability
      open_incident = $openIncident
      attention_level = $assessment.level
      attention_label = $assessment.label
      attention_reason = $assessment.reason
      down_seconds_24h = [int]$downSeconds
      availability_24h = $availability
    }
  }

  $totalDown = [int](@($rows | Measure-Object -Property down_seconds -Sum).Sum)
  $totalUp = [int](@($rows | Measure-Object -Property up_seconds -Sum).Sum)
  $totalPeriod = [math]::Max(1, ($periodSeconds * [math]::Max(1, @($rows).Count)))
  $overallAvailability = [math]::Round([math]::Max(0, (1 - ($totalDown / $totalPeriod)) * 100), 2)

  return [pscustomobject][ordered]@{
    generated_at = Get-NowIso
    from = $range.From.ToString("o")
    to = $range.To.ToString("o")
    device_id = $deviceId
    summary = [pscustomobject][ordered]@{
      devices = @($rows).Count
      total_down_seconds = $totalDown
      total_up_seconds = $totalUp
      availability_percent = $overallAvailability
      events = [int](@($rows | Measure-Object -Property events_count -Sum).Sum)
      open_incidents = @($rows | Where-Object { $_.open_incident }).Count
      attention = @($rows | Where-Object { $_.attention_level -in @("critica", "alta", "media") }).Count
    }
    rows = @($rows | Sort-Object availability_percent, name)
  }
}

function Get-AvailabilityExportRows($Report) {
  return @($Report.rows) | ForEach-Object {
    [pscustomobject][ordered]@{
      Dispositivo = $_.name
      Host = $_.host
      Tipo = $_.type
      Localizacao = $_.location
      Serial = $_.serial_number
      Patrimonio = $_.asset_tag
      Modelo = $_.model
      Criticidade = $_.criticality
      StatusAtual = $_.current_status
      Metodo = $_.check_method
      UltimaVerificacao = $_.last_check_at
      Eventos = $_.events_count
      Quedas = $_.down_count
      Retornos = $_.up_count
      TempoOfflineSeg = $_.down_seconds
      TempoOnlineSeg = $_.up_seconds
      MTTRSeg = $_.mttr_seconds
      DisponibilidadePercentual = $_.availability_percent
      IncidenteAberto = $_.open_incident
      Atencao = $_.attention_label
      Motivo = $_.attention_reason
    }
  }
}

function Get-HistoryReport($Store, $Request) {
  $range = Get-ReportRange $Request
  $deviceId = Get-QueryValue $Request "device_id" ""
  $events = @(Get-EventsInRange $Store $range.From $range.To $deviceId)
  $rows = @($events | Sort-Object { [datetime]::Parse($_.down_at) } -Descending | ForEach-Object {
    $device = Get-DeviceById $Store $_.device_id
    [pscustomobject][ordered]@{
      event_id = $_.id
      device_id = $_.device_id
      device_name = if ($null -eq $device) { $_.device_id } else { $device.name }
      host = if ($null -eq $device) { "" } else { $device.host }
      type = if ($null -eq $device) { "" } else { $device.type }
      location = if ($null -eq $device) { "" } else { $device.location }
      criticality = $_.criticality
      down_at = $_.down_at
      up_at = $_.up_at
      duration_seconds = if ($null -eq $_.duration_seconds) { [int][math]::Max(0, ($range.To - [datetime]::Parse($_.down_at)).TotalSeconds) } else { $_.duration_seconds }
      status = $_.status
      event_type = if ($_.status -eq "open") { "down_aberto" } else { "down_up_resolvido" }
    }
  })

  return [pscustomobject][ordered]@{
    generated_at = Get-NowIso
    from = $range.From.ToString("o")
    to = $range.To.ToString("o")
    device_id = $deviceId
    summary = [pscustomobject][ordered]@{
      events = @($rows).Count
      open_events = @($rows | Where-Object { $_.status -eq "open" }).Count
      resolved_events = @($rows | Where-Object { $_.status -eq "resolved" }).Count
      total_duration_seconds = [int](@($rows | Measure-Object -Property duration_seconds -Sum).Sum)
    }
    rows = $rows
  }
}

function Get-HistoryExportRows($Report) {
  return @($Report.rows) | ForEach-Object {
    [pscustomobject][ordered]@{
      Dispositivo = $_.device_name
      Host = $_.host
      Tipo = $_.type
      Localizacao = $_.location
      Criticidade = $_.criticality
      Evento = $_.event_type
      DownAt = $_.down_at
      UpAt = $_.up_at
      DuracaoSeg = $_.duration_seconds
      Status = $_.status
    }
  }
}

function Get-AuditReport($Store, $Request) {
  $range = Get-ReportRange $Request
  $action = Get-QueryValue $Request "action" ""
  $userId = Get-QueryValue $Request "user_id" ""
  $rows = @(Get-CleanArray $Store.audit_logs) | Where-Object {
    $created = [datetime]::Parse($_.created_at)
    $matchesAction = [string]::IsNullOrWhiteSpace($action) -or "$($_.action)" -like "*$action*"
    $matchesUser = [string]::IsNullOrWhiteSpace($userId) -or $userId -eq "all" -or $_.user_id -eq $userId
    $created -ge $range.From -and $created -le $range.To -and $matchesAction -and $matchesUser
  } | Sort-Object { [datetime]::Parse($_.created_at) } -Descending | ForEach-Object {
    $user = Get-UserById $Store $_.user_id
    [pscustomobject][ordered]@{
      id = $_.id
      user_id = $_.user_id
      user_name = if ($null -eq $user) { "Sistema" } else { $user.name }
      action = $_.action
      entity_type = $_.entity_type
      entity_id = $_.entity_id
      created_at = $_.created_at
      metadata = if ($null -eq $_.metadata) { "" } else { ($_.metadata | ConvertTo-Json -Compress -Depth 8) }
    }
  }

  return [pscustomobject][ordered]@{
    generated_at = Get-NowIso
    from = $range.From.ToString("o")
    to = $range.To.ToString("o")
    action = $action
    user_id = $userId
    summary = [pscustomobject][ordered]@{
      entries = @($rows).Count
      users = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.user_id) } | Select-Object -ExpandProperty user_id -Unique).Count
      blocked_csrf = @($rows | Where-Object { $_.action -eq "security.csrf.blocked" }).Count
      failed_logins = @($rows | Where-Object { $_.action -eq "auth.login.failed" }).Count
    }
    rows = $rows
  }
}

function Get-AuditExportRows($Report) {
  return @($Report.rows) | ForEach-Object {
    [pscustomobject][ordered]@{
      DataHora = $_.created_at
      Usuario = $_.user_name
      Acao = $_.action
      Entidade = $_.entity_type
      EntidadeId = $_.entity_id
      Metadados = $_.metadata
    }
  }
}

function New-IntegrationFromBody($Body, [string]$Now) {
  return [pscustomobject][ordered]@{
    id = New-EntityId "int"
    name = "$($Body.name)".Trim()
    type = if ([string]::IsNullOrWhiteSpace($Body.type)) { "webhook" } else { "$($Body.type)".Trim().ToLowerInvariant() }
    url = "$($Body.url)".Trim()
    secret = if ([string]::IsNullOrWhiteSpace($Body.secret)) { "" } else { "$($Body.secret)".Trim() }
    enabled = if ($null -eq $Body.enabled) { $true } else { [bool]$Body.enabled }
    created_at = $Now
    updated_at = $Now
  }
}

function Get-PublicIntegration($Integration) {
  return [pscustomobject][ordered]@{
    id = $Integration.id
    name = $Integration.name
    type = $Integration.type
    url = $Integration.url
    secret_configured = -not [string]::IsNullOrWhiteSpace($Integration.secret)
    enabled = $Integration.enabled
    created_at = $Integration.created_at
    updated_at = $Integration.updated_at
  }
}

function Get-IntegrationBodyError($Body) {
  if ($null -eq $Body -or [string]::IsNullOrWhiteSpace($Body.name) -or [string]::IsNullOrWhiteSpace($Body.url)) {
    return "Nome e URL sao obrigatorios."
  }
  if ("$($Body.name)".Trim().Length -gt 80) {
    return "Nome da integracao deve ter ate 80 caracteres."
  }
  if ("$($Body.url)".Trim().Length -gt 300) {
    return "URL da integracao deve ter ate 300 caracteres."
  }
  if ("$($Body.url)" -notmatch "^https?://") {
    return "Webhook deve iniciar com http:// ou https://."
  }
  if ($null -ne $Body.type -and "$($Body.type)".Trim().ToLowerInvariant() -ne "webhook") {
    return "Tipo de integracao invalido."
  }
  if ($null -ne $Body.secret -and "$($Body.secret)".Length -gt 160) {
    return "Segredo da integracao deve ter ate 160 caracteres."
  }
  return $null
}

function New-DeviceFromBody($Body, [string]$Now) {
  $isActive = if ($null -eq $Body.is_active) { $true } else { [bool]$Body.is_active }
  return [pscustomobject][ordered]@{
    id = New-EntityId "dev"
    name = "$($Body.name)".Trim()
    host = "$($Body.host)".Trim()
    type = if ([string]::IsNullOrWhiteSpace($Body.type)) { "Servidor" } else { "$($Body.type)".Trim() }
    location = if ([string]::IsNullOrWhiteSpace($Body.location)) { "Nao informado" } else { "$($Body.location)".Trim() }
    criticality = if ([string]::IsNullOrWhiteSpace($Body.criticality)) { "media" } else { "$($Body.criticality)".Trim().ToLowerInvariant() }
    current_status = if ($Body.current_status) { "$($Body.current_status)".ToLowerInvariant() } else { "offline" }
    check_method = if ([string]::IsNullOrWhiteSpace($Body.check_method)) { "ping" } else { "$($Body.check_method)".Trim().ToLowerInvariant() }
    port = if ($null -eq $Body.port -or "$($Body.port)" -eq "") { $null } else { [int]$Body.port }
    url_path = if ([string]::IsNullOrWhiteSpace($Body.url_path)) { "/" } else { "$($Body.url_path)".Trim() }
    expected_status = if ($null -eq $Body.expected_status -or "$($Body.expected_status)" -eq "") { 200 } else { [int]$Body.expected_status }
    owner = if ([string]::IsNullOrWhiteSpace($Body.owner)) { "" } else { "$($Body.owner)".Trim() }
    tags = if ([string]::IsNullOrWhiteSpace($Body.tags)) { "" } else { "$($Body.tags)".Trim() }
    notes = if ([string]::IsNullOrWhiteSpace($Body.notes)) { "" } else { "$($Body.notes)".Trim() }
    serial_number = if ([string]::IsNullOrWhiteSpace($Body.serial_number)) { "" } else { "$($Body.serial_number)".Trim() }
    asset_tag = if ([string]::IsNullOrWhiteSpace($Body.asset_tag)) { "" } else { "$($Body.asset_tag)".Trim() }
    model = if ([string]::IsNullOrWhiteSpace($Body.model)) { "" } else { "$($Body.model)".Trim() }
    maintenance_until = if ([string]::IsNullOrWhiteSpace($Body.maintenance_until)) { $null } else { "$($Body.maintenance_until)".Trim() }
    is_active = $isActive
    last_check_at = $null
    created_at = $Now
    updated_at = $Now
  }
}

function Update-DeviceFromBody($Device, $Body, [string]$Now) {
  foreach ($field in @("name", "host", "type", "location", "criticality", "current_status", "check_method", "url_path", "owner", "tags", "notes", "serial_number", "asset_tag", "model", "maintenance_until")) {
    if ($null -ne $Body.$field) {
      $value = "$($Body.$field)".Trim()
      if ($field -in @("criticality", "current_status", "check_method")) {
        $value = $value.ToLowerInvariant()
      }
      if ($field -eq "maintenance_until" -and [string]::IsNullOrWhiteSpace($value)) {
        $value = $null
      }
      $Device.$field = $value
    }
  }

  foreach ($field in @("port", "expected_status")) {
    if ($null -ne $Body.$field) {
      $Device.$field = if ("$($Body.$field)" -eq "") { $null } else { [int]$Body.$field }
    }
  }

  if ($null -ne $Body.is_active) {
    $Device.is_active = [bool]$Body.is_active
  }

  $Device.updated_at = $Now
}

function Handle-ApiRequest($Context) {
  $request = $Context.Request
  $method = $request.HttpMethod.ToUpperInvariant()
  $path = $request.Url.AbsolutePath.TrimEnd("/")
  if ($path -eq "") { $path = "/" }
  $segments = @($path.Trim("/").Split("/", [System.StringSplitOptions]::RemoveEmptyEntries))

  try {
    $store = Read-Store

    if ($method -eq "GET" -and $path -eq "/api/health") {
      Send-Json $Context ([pscustomobject]@{ ok = $true; now = Get-NowIso })
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/auth/status") {
      $currentUser = Get-CurrentUser $store $request
      $currentSession = Get-CurrentSession $store $request
      Save-Store $store
      Send-Json $Context ([pscustomobject]@{
        setup_required = @(Get-CleanArray $store.users).Count -eq 0
        authenticated = $null -ne $currentUser
        user = Get-PublicUser $currentUser
        csrf_token = if ($null -eq $currentSession) { $null } else { $currentSession.csrf_token }
        settings = Get-PublicSettings $store.settings
        roles = @(
          [pscustomobject]@{ value = "admin"; label = "Administrador" },
          [pscustomobject]@{ value = "operator"; label = "Operador" },
          [pscustomobject]@{ value = "viewer"; label = "Visualizador" }
        )
      })
      return
    }

    if ($method -eq "POST" -and $path -eq "/api/auth/setup") {
      if (@(Get-CleanArray $store.users).Count -gt 0) {
        Send-Json $Context ([pscustomobject]@{ error = "Administrador inicial ja foi criado." }) 403
        return
      }

      $body = Read-RequestJson $request
      if ($null -eq $body) {
        Send-Json $Context ([pscustomobject]@{ error = "Corpo da requisicao invalido." }) 400
        return
      }
      $body | Add-Member -NotePropertyName role -NotePropertyValue "admin" -Force
      $bodyError = Get-UserBodyError $body $true
      if ($null -ne $bodyError) {
        Send-Json $Context ([pscustomobject]@{ error = $bodyError }) 400
        return
      }

      $now = Get-NowIso
      $user = New-UserFromBody $body $now
      $store.users = @(Get-CleanArray $store.users) + $user
      $sessionResult = New-Session $store $user $request
      $user.last_login_at = $now
      Add-AuditLog $store $user "auth.setup" "user" $user.id ([pscustomobject]@{ role = $user.role })
      Save-Store $store
      Send-Json $Context ([pscustomobject]@{ ok = $true; user = Get-PublicUser $user; csrf_token = $sessionResult.csrf_token }) 201 @((Get-SessionCookieHeader $sessionResult.token ([int]$store.settings.session_hours)))
      return
    }

    if ($method -eq "POST" -and $path -eq "/api/auth/login") {
      $body = Read-RequestJson $request
      if ($null -eq $body -or [string]::IsNullOrWhiteSpace($body.email) -or [string]::IsNullOrWhiteSpace($body.password)) {
        Send-Json $Context ([pscustomobject]@{ error = "Informe email e senha." }) 400
        return
      }

      $remoteKey = if ($null -eq $request.RemoteEndPoint) { "local" } else { "$($request.RemoteEndPoint)" }
      if (-not (Test-LoginRateLimit $store "$($body.email)" $remoteKey)) {
        Add-AuditLog $store $null "auth.login.rate_limited" "user" "$($body.email)" ([pscustomobject]@{ remote = $remoteKey })
        Save-Store $store
        Send-Json $Context ([pscustomobject]@{ error = "Muitas tentativas. Aguarde antes de tentar novamente." }) 429
        return
      }

      $user = Get-UserByEmail $store "$($body.email)"
      if ($null -eq $user -or $user.status -ne "active" -or -not (Test-PasswordHash "$($body.password)" "$($user.password_hash)")) {
        Add-LoginFailure $store "$($body.email)" $remoteKey
        Add-AuditLog $store $null "auth.login.failed" "user" "$($body.email)" ([pscustomobject]@{ remote = $remoteKey })
        Save-Store $store
        Send-Json $Context ([pscustomobject]@{ error = "Email ou senha invalidos." }) 401
        return
      }

      Clear-LoginFailures "$($body.email)" $remoteKey
      $sessionResult = New-Session $store $user $request
      $user.last_login_at = Get-NowIso
      $user.updated_at = Get-NowIso
      Add-AuditLog $store $user "auth.login" "user" $user.id $null
      Save-Store $store
      Send-Json $Context ([pscustomobject]@{ ok = $true; user = Get-PublicUser $user; csrf_token = $sessionResult.csrf_token }) 200 @((Get-SessionCookieHeader $sessionResult.token ([int]$store.settings.session_hours)))
      return
    }

    if ($method -eq "POST" -and $path -eq "/api/auth/logout") {
      $token = Get-CookieValue $request "sword_session"
      if (-not [string]::IsNullOrWhiteSpace($token)) {
        $tokenHash = Get-TokenHash $token
        foreach ($session in @(Get-CleanArray $store.sessions)) {
          if ($session.token_hash -eq $tokenHash) {
            $session.status = "revoked"
          }
        }
        Save-Store $store
      }
      Send-Json $Context ([pscustomobject]@{ ok = $true }) 200 @((Get-ClearSessionCookieHeader))
      return
    }

    $currentUser = Get-CurrentUser $store $request
    if ($null -eq $currentUser) {
      Save-Store $store
      Send-Json $Context ([pscustomobject]@{ error = "Login necessario." }) 401 @((Get-ClearSessionCookieHeader))
      return
    }

    if (-not (Test-Csrf $store $request)) {
      Add-AuditLog $store $currentUser "security.csrf.blocked" "request" $path ([pscustomobject]@{ method = $method })
      Save-Store $store
      Send-Json $Context ([pscustomobject]@{ error = "Token de seguranca invalido. Atualize a pagina e tente novamente." }) 403
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/auth/me") {
      $currentSession = Get-CurrentSession $store $request
      Send-Json $Context ([pscustomobject]@{ user = Get-PublicUser $currentUser; csrf_token = if ($null -eq $currentSession) { $null } else { $currentSession.csrf_token } })
      return
    }

    if ($method -eq "PUT" -and $path -eq "/api/auth/password") {
      $body = Read-RequestJson $request
      if ($null -eq $body -or [string]::IsNullOrWhiteSpace($body.current_password) -or [string]::IsNullOrWhiteSpace($body.new_password)) {
        Send-Json $Context ([pscustomobject]@{ error = "Informe senha atual e nova senha." }) 400
        return
      }
      if ("$($body.new_password)".Length -lt 6) {
        Send-Json $Context ([pscustomobject]@{ error = "A nova senha deve ter pelo menos 6 caracteres." }) 400
        return
      }
      if (-not (Test-PasswordHash "$($body.current_password)" "$($currentUser.password_hash)")) {
        Send-Json $Context ([pscustomobject]@{ error = "Senha atual invalida." }) 401
        return
      }

      $currentUser.password_hash = Get-PasswordHash "$($body.new_password)"
      $currentUser.updated_at = Get-NowIso
      Add-AuditLog $store $currentUser "auth.password.change" "user" $currentUser.id $null
      Save-Store $store
      Send-Json $Context ([pscustomobject]@{ ok = $true })
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/settings") {
      Send-Json $Context (Get-PublicSettings $store.settings)
      return
    }

    if ($method -eq "PUT" -and $path -eq "/api/settings") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem alterar configuracoes." }) 403
        return
      }

      $body = Read-RequestJson $request
      $settingsError = Get-SettingsBodyError $body
      if ($null -ne $settingsError) {
        Send-Json $Context ([pscustomobject]@{ error = $settingsError }) 400
        return
      }

      foreach ($field in @("app_name", "session_hours", "login_rate_limit_window_minutes", "login_rate_limit_max_attempts", "audit_retention_days", "event_retention_days", "backup_retention_days", "check_interval_seconds", "check_attempts", "check_timeout_ms", "require_csrf", "allow_viewer_export", "critical_sound_enabled", "critical_sound_minutes", "ui_theme")) {
        if ($null -ne $body.$field) {
          $store.settings.$field = $body.$field
        }
      }
      $store.settings.security_mode = "hardened-local"
      $store.settings.updated_at = Get-NowIso
      Invoke-RetentionCleanup $store
      Add-AuditLog $store $currentUser "settings.update" "settings" "system" (Get-PublicSettings $store.settings)
      Save-Store $store
      Send-Json $Context (Get-PublicSettings $store.settings)
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/audit") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem ver auditoria." }) 403
        return
      }
      Send-JsonArray $Context (Get-AuditRows $store)
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/audit/report") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem gerar relatorio de auditoria." }) 403
        return
      }
      Send-Json $Context (Get-AuditReport $store $request)
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/audit/export") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem exportar auditoria." }) 403
        return
      }
      $report = Get-AuditReport $store $request
      New-ReportSnapshot $store $currentUser "audit" ([pscustomobject]@{ from = $report.from; to = $report.to; action = $report.action; user_id = $report.user_id }) @($report.rows).Count | Out-Null
      Add-AuditLog $store $currentUser "audit.export" "audit" "csv" ([pscustomobject]@{ rows = @($report.rows).Count })
      Save-Store $store
      Send-DownloadText $Context (ConvertTo-CsvText (Get-AuditExportRows $report)) "text/csv; charset=utf-8" ("sword-auditoria-{0}.csv" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/backups") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem listar backups." }) 403
        return
      }
      Send-JsonArray $Context (Get-Backups)
      return
    }

    if ($method -eq "POST" -and $path -eq "/api/backups") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem criar backups." }) 403
        return
      }
      $backup = New-Backup $store $currentUser
      Save-Store $store
      Send-Json $Context $backup 201
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/export") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin", "operator")) -and $store.settings.allow_viewer_export -ne $true) {
        Send-Json $Context ([pscustomobject]@{ error = "Seu cargo nao permite exportar dados." }) 403
        return
      }
      Add-AuditLog $store $currentUser "data.export" "store" "json" $null
      Save-Store $store
      Send-Json $Context ([pscustomobject]@{
        exported_at = Get-NowIso
        exported_by = Get-PublicUser $currentUser
        devices = $store.devices
        status_events = $store.status_events
        alerts = $store.alerts
      })
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/reports/availability") {
      Send-Json $Context (Get-AvailabilityReport $store $request)
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/reports/availability/export") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin", "operator")) -and $store.settings.allow_viewer_export -ne $true) {
        Send-Json $Context ([pscustomobject]@{ error = "Seu cargo nao permite exportar relatorios." }) 403
        return
      }
      $report = Get-AvailabilityReport $store $request
      New-ReportSnapshot $store $currentUser "availability" ([pscustomobject]@{ from = $report.from; to = $report.to; device_id = $report.device_id }) @($report.rows).Count | Out-Null
      Add-AuditLog $store $currentUser "reports.availability.export" "report" "csv" ([pscustomobject]@{ rows = @($report.rows).Count })
      Save-Store $store
      Send-DownloadText $Context (ConvertTo-CsvText (Get-AvailabilityExportRows $report)) "text/csv; charset=utf-8" ("sword-disponibilidade-{0}.csv" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/history/report") {
      Send-Json $Context (Get-HistoryReport $store $request)
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/history/export") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin", "operator")) -and $store.settings.allow_viewer_export -ne $true) {
        Send-Json $Context ([pscustomobject]@{ error = "Seu cargo nao permite exportar historico." }) 403
        return
      }
      $report = Get-HistoryReport $store $request
      New-ReportSnapshot $store $currentUser "history" ([pscustomobject]@{ from = $report.from; to = $report.to; device_id = $report.device_id }) @($report.rows).Count | Out-Null
      Add-AuditLog $store $currentUser "history.export" "history" "csv" ([pscustomobject]@{ rows = @($report.rows).Count })
      Save-Store $store
      Send-DownloadText $Context (ConvertTo-CsvText (Get-HistoryExportRows $report)) "text/csv; charset=utf-8" ("sword-historico-{0}.csv" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/report-snapshots") {
      Send-JsonArray $Context (@(Get-CleanArray $store.report_snapshots) | Sort-Object { [datetime]::Parse($_.created_at) } -Descending)
      return
    }

    if ($method -eq "DELETE" -and $path -eq "/api/report-snapshots") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem limpar relatorios." }) 403
        return
      }
      $count = @(Get-CleanArray $store.report_snapshots).Count
      $store.report_snapshots = @()
      Add-AuditLog $store $currentUser "reports.clear" "report" "snapshots" ([pscustomobject]@{ count = $count })
      Save-Store $store
      Send-Json $Context ([pscustomobject]@{ ok = $true; removed = $count })
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/integrations") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem listar integracoes." }) 403
        return
      }
      $items = @(Get-CleanArray $store.integrations) | ForEach-Object { Get-PublicIntegration $_ }
      Send-JsonArray $Context $items
      return
    }

    if ($method -eq "POST" -and $path -eq "/api/integrations") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem criar integracoes." }) 403
        return
      }
      $body = Read-RequestJson $request
      $bodyError = Get-IntegrationBodyError $body
      if ($null -ne $bodyError) {
        Send-Json $Context ([pscustomobject]@{ error = $bodyError }) 400
        return
      }
      $integration = New-IntegrationFromBody $body (Get-NowIso)
      $store.integrations = @(Get-CleanArray $store.integrations) + $integration
      Add-AuditLog $store $currentUser "integrations.create" "integration" $integration.id ([pscustomobject]@{ type = $integration.type })
      Save-Store $store
      Send-Json $Context (Get-PublicIntegration $integration) 201
      return
    }

    if ($segments.Count -ge 3 -and $segments[0] -eq "api" -and $segments[1] -eq "integrations") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem gerenciar integracoes." }) 403
        return
      }

      $integrationId = $segments[2]
      $integration = @(Get-CleanArray $store.integrations) | Where-Object { $_.id -eq $integrationId } | Select-Object -First 1
      if ($null -eq $integration) {
        Send-Json $Context ([pscustomobject]@{ error = "Integracao nao encontrada." }) 404
        return
      }

      if ($method -eq "PUT" -and $segments.Count -eq 3) {
        $body = Read-RequestJson $request
        $bodyError = Get-IntegrationBodyError $body
        if ($null -ne $bodyError) {
          Send-Json $Context ([pscustomobject]@{ error = $bodyError }) 400
          return
        }
        foreach ($field in @("name", "type", "url")) {
          if ($null -ne $body.$field) {
            $value = "$($body.$field)".Trim()
            if ($field -eq "type") { $value = $value.ToLowerInvariant() }
            $integration.$field = $value
          }
        }
        if ($null -ne $body.secret -and -not [string]::IsNullOrWhiteSpace($body.secret)) {
          $integration.secret = "$($body.secret)".Trim()
        }
        if ($null -ne $body.enabled) { $integration.enabled = [bool]$body.enabled }
        $integration.updated_at = Get-NowIso
        Add-AuditLog $store $currentUser "integrations.update" "integration" $integration.id $null
        Save-Store $store
        Send-Json $Context (Get-PublicIntegration $integration)
        return
      }

      if ($method -eq "DELETE" -and $segments.Count -eq 3) {
        $store.integrations = @(Get-CleanArray $store.integrations | Where-Object { $_.id -ne $integrationId })
        Add-AuditLog $store $currentUser "integrations.delete" "integration" $integrationId $null
        Save-Store $store
        Send-Json $Context ([pscustomobject]@{ ok = $true })
        return
      }
    }

    if ($method -eq "GET" -and $path -eq "/api/users") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem listar usuarios." }) 403
        return
      }

      $users = @(Get-CleanArray $store.users) | ForEach-Object { Get-PublicUser $_ }
      Send-JsonArray $Context $users
      return
    }

    if ($method -eq "POST" -and $path -eq "/api/users") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem criar usuarios." }) 403
        return
      }

      $body = Read-RequestJson $request
      $bodyError = Get-UserBodyError $body $true
      if ($null -ne $bodyError) {
        Send-Json $Context ([pscustomobject]@{ error = $bodyError }) 400
        return
      }

      if ($null -ne (Get-UserByEmail $store "$($body.email)")) {
        Send-Json $Context ([pscustomobject]@{ error = "Ja existe usuario com este email." }) 400
        return
      }

      $now = Get-NowIso
      $newUser = New-UserFromBody $body $now
      $store.users = @(Get-CleanArray $store.users) + $newUser
      Add-AuditLog $store $currentUser "users.create" "user" $newUser.id ([pscustomobject]@{ role = $newUser.role })
      Save-Store $store
      Send-Json $Context (Get-PublicUser $newUser) 201
      return
    }

    if ($segments.Count -ge 3 -and $segments[0] -eq "api" -and $segments[1] -eq "users") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem gerenciar usuarios." }) 403
        return
      }

      $userId = $segments[2]
      $targetUser = Get-UserById $store $userId
      if ($null -eq $targetUser) {
        Send-Json $Context ([pscustomobject]@{ error = "Usuario nao encontrado." }) 404
        return
      }

      if ($method -eq "PUT" -and $segments.Count -eq 3) {
        $body = Read-RequestJson $request
        $bodyError = Get-UserBodyError $body $false
        if ($null -ne $bodyError) {
          Send-Json $Context ([pscustomobject]@{ error = $bodyError }) 400
          return
        }

        if ($null -ne $body.email) {
          $sameEmail = Get-UserByEmail $store "$($body.email)"
          if ($null -ne $sameEmail -and $sameEmail.id -ne $targetUser.id) {
            Send-Json $Context ([pscustomobject]@{ error = "Ja existe usuario com este email." }) 400
            return
          }
          $targetUser.email = "$($body.email)".Trim().ToLowerInvariant()
        }
        if ($null -ne $body.name) { $targetUser.name = "$($body.name)".Trim() }
        if ($null -ne $body.role) { $targetUser.role = "$($body.role)".Trim().ToLowerInvariant() }
        if ($null -ne $body.status) { $targetUser.status = "$($body.status)".Trim().ToLowerInvariant() }
        if ($null -ne $body.avatar_data_url) { $targetUser.avatar_data_url = "$($body.avatar_data_url)".Trim() }
        if ($null -ne $body.password -and -not [string]::IsNullOrWhiteSpace($body.password)) {
          $targetUser.password_hash = Get-PasswordHash "$($body.password)"
        }

        $activeAdmins = @(Get-CleanArray $store.users | Where-Object { $_.role -eq "admin" -and $_.status -eq "active" })
        if ($activeAdmins.Count -eq 0) {
          Send-Json $Context ([pscustomobject]@{ error = "Deve existir pelo menos um administrador ativo." }) 400
          return
        }

        $targetUser.updated_at = Get-NowIso
        Add-AuditLog $store $currentUser "users.update" "user" $targetUser.id ([pscustomobject]@{ role = $targetUser.role; status = $targetUser.status })
        Save-Store $store
        Send-Json $Context (Get-PublicUser $targetUser)
        return
      }

      if ($method -eq "DELETE" -and $segments.Count -eq 3) {
        if ($targetUser.id -eq $currentUser.id) {
          Send-Json $Context ([pscustomobject]@{ error = "Voce nao pode excluir seu proprio usuario." }) 400
          return
        }

        $remainingAdmins = @(Get-CleanArray $store.users | Where-Object { $_.id -ne $targetUser.id -and $_.role -eq "admin" -and $_.status -eq "active" })
        if ($targetUser.role -eq "admin" -and $remainingAdmins.Count -eq 0) {
          Send-Json $Context ([pscustomobject]@{ error = "Deve existir pelo menos um administrador ativo." }) 400
          return
        }

        $store.users = @(Get-CleanArray $store.users | Where-Object { $_.id -ne $targetUser.id })
        $store.sessions = @(Get-CleanArray $store.sessions | Where-Object { $_.user_id -ne $targetUser.id })
        Add-AuditLog $store $currentUser "users.delete" "user" $targetUser.id $null
        Save-Store $store
        Send-Json $Context ([pscustomobject]@{ ok = $true })
        return
      }
    }

    if ($method -eq "GET" -and $path -eq "/api/summary") {
      Send-Json $Context (Get-Summary $store)
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/devices") {
      Send-JsonArray $Context $store.devices
      return
    }

    if ($method -eq "POST" -and $path -eq "/api/devices") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin", "operator"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Seu cargo nao permite cadastrar dispositivos." }) 403
        return
      }

      $body = Read-RequestJson $request
      $bodyError = Get-DeviceBodyError $body $true
      if ($null -ne $bodyError) {
        Send-Json $Context ([pscustomobject]@{ error = $bodyError }) 400
        return
      }

      $now = Get-NowIso
      $device = New-DeviceFromBody $body $now
      $store.devices = @(Get-CleanArray $store.devices) + $device
      Add-AuditLog $store $currentUser "devices.create" "device" $device.id ([pscustomobject]@{ host = $device.host; criticality = $device.criticality })
      Save-Store $store
      Send-Json $Context $device 201
      return
    }

    if ($segments.Count -ge 3 -and $segments[0] -eq "api" -and $segments[1] -eq "devices") {
      $deviceId = $segments[2]
      $device = Get-DeviceById $store $deviceId
      if ($null -eq $device) {
        Send-Json $Context ([pscustomobject]@{ error = "Dispositivo nao encontrado." }) 404
        return
      }

      if ($method -eq "PUT" -and $segments.Count -eq 3) {
        if (-not (Test-RoleAllowed $currentUser.role @("admin", "operator"))) {
          Send-Json $Context ([pscustomobject]@{ error = "Seu cargo nao permite editar dispositivos." }) 403
          return
        }

        $body = Read-RequestJson $request
        $bodyError = Get-DeviceBodyError $body $false
        if ($null -ne $bodyError) {
          Send-Json $Context ([pscustomobject]@{ error = $bodyError }) 400
          return
        }
        Update-DeviceFromBody $device $body (Get-NowIso)
        Add-AuditLog $store $currentUser "devices.update" "device" $device.id $null
        Save-Store $store
        Send-Json $Context $device
        return
      }

      if ($method -eq "DELETE" -and $segments.Count -eq 3) {
        if (-not (Test-RoleAllowed $currentUser.role @("admin", "operator"))) {
          Send-Json $Context ([pscustomobject]@{ error = "Seu cargo nao permite excluir dispositivos." }) 403
          return
        }

        $eventIds = @(Get-CleanArray $store.status_events | Where-Object { $_.device_id -eq $deviceId } | ForEach-Object { $_.id })
        $store.devices = @(Get-CleanArray $store.devices | Where-Object { $_.id -ne $deviceId })
        $store.status_events = @(Get-CleanArray $store.status_events | Where-Object { $_.device_id -ne $deviceId })
        $store.alerts = @(Get-CleanArray $store.alerts | Where-Object { $_.device_id -ne $deviceId -and $eventIds -notcontains $_.status_event_id })
        Add-AuditLog $store $currentUser "devices.delete" "device" $deviceId $null
        Save-Store $store
        Send-Json $Context ([pscustomobject]@{ ok = $true })
        return
      }

      if ($method -eq "POST" -and $segments.Count -eq 4 -and $segments[3] -eq "check") {
        if (-not (Test-RoleAllowed $currentUser.role @("admin", "operator"))) {
          Send-Json $Context ([pscustomobject]@{ error = "Seu cargo nao permite executar verificacoes." }) 403
          return
        }

        $result = Invoke-DeviceCheck $store $device
        Add-AuditLog $store $currentUser "devices.check" "device" $device.id ([pscustomobject]@{ status = $result.status })
        Save-Store $store
        Send-Json $Context $result
        return
      }
    }

    if ($method -eq "POST" -and $path -eq "/api/monitor/run") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin", "operator"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Seu cargo nao permite executar monitoramento." }) 403
        return
      }

      $results = Invoke-MonitorCycle
      $store = Read-Store
      Add-AuditLog $store $currentUser "monitor.run" "monitor" "cycle" ([pscustomobject]@{ count = @($results).Count })
      Save-Store $store
      Send-Json $Context ([pscustomobject]@{ ok = $true; results = $results })
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/events") {
      Send-JsonArray $Context $store.status_events
      return
    }

    if ($method -eq "DELETE" -and $path -eq "/api/events") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Apenas administradores podem limpar historico." }) 403
        return
      }
      $scope = Get-QueryValue $request "scope" "resolved"
      $beforeEvents = @(Get-CleanArray $store.status_events).Count
      $beforeAlerts = @(Get-CleanArray $store.alerts).Count
      if ($scope -eq "all") {
        $store.status_events = @(Get-CleanArray $store.status_events | Where-Object { $_.status -eq "open" })
        $openEventIds = @(Get-CleanArray $store.status_events | ForEach-Object { $_.id })
        $store.alerts = @(Get-CleanArray $store.alerts | Where-Object { $_.status -eq "open" -and $openEventIds -contains $_.status_event_id })
      } else {
        $store.status_events = @(Get-CleanArray $store.status_events | Where-Object { $_.status -eq "open" })
        $store.alerts = @(Get-CleanArray $store.alerts | Where-Object { $_.status -eq "open" })
      }
      $removedEvents = $beforeEvents - (@(Get-CleanArray $store.status_events).Count)
      $removedAlerts = $beforeAlerts - (@(Get-CleanArray $store.alerts).Count)
      Add-AuditLog $store $currentUser "history.clear" "history" $scope ([pscustomobject]@{ events = $removedEvents; alerts = $removedAlerts })
      Save-Store $store
      Send-Json $Context ([pscustomobject]@{ ok = $true; removed_events = $removedEvents; removed_alerts = $removedAlerts })
      return
    }

    if ($method -eq "GET" -and $path -eq "/api/alerts") {
      Send-JsonArray $Context $store.alerts
      return
    }

    if ($segments.Count -eq 4 -and $method -eq "POST" -and $segments[0] -eq "api" -and $segments[1] -eq "alerts" -and $segments[3] -eq "resolve") {
      if (-not (Test-RoleAllowed $currentUser.role @("admin", "operator"))) {
        Send-Json $Context ([pscustomobject]@{ error = "Seu cargo nao permite resolver alertas." }) 403
        return
      }

      $alertId = $segments[2]
      $alert = @(Get-CleanArray $store.alerts) | Where-Object { $_.id -eq $alertId } | Select-Object -First 1
      if ($null -eq $alert) {
        Send-Json $Context ([pscustomobject]@{ error = "Alerta nao encontrado." }) 404
        return
      }

      $alert.status = "resolved"
      $alert.resolved_at = Get-NowIso
      Add-AuditLog $store $currentUser "alerts.resolve" "alert" $alert.id $null
      Save-Store $store
      Send-Json $Context $alert
      return
    }

    Send-Json $Context ([pscustomobject]@{ error = "Rota nao encontrada." }) 404
  } catch {
    Send-Json $Context ([pscustomobject]@{ error = $_.Exception.Message }) 500
  }
}

function Handle-StaticRequest($Context) {
  $path = $Context.Request.Url.AbsolutePath
  if ($path -eq "/" -or [string]::IsNullOrWhiteSpace($path)) {
    Send-File $Context (Join-Path $PublicDir "index.html")
    return
  }

  $relative = $path.TrimStart("/").Replace("/", [System.IO.Path]::DirectorySeparatorChar)
  $filePath = Join-Path $PublicDir $relative
  $resolvedPublic = [System.IO.Path]::GetFullPath($PublicDir)
  $resolvedFile = [System.IO.Path]::GetFullPath($filePath)

  if (-not $resolvedFile.StartsWith($resolvedPublic, [System.StringComparison]::OrdinalIgnoreCase)) {
    Send-Text $Context "Acesso negado" 403
    return
  }

  if (Test-Path -LiteralPath $resolvedFile -PathType Leaf) {
    Send-File $Context $resolvedFile
  } else {
    Send-File $Context (Join-Path $PublicDir "index.html")
  }
}

function Read-TcpHttpContext($Client) {
  $stream = $Client.GetStream()
  $buffer = New-Object byte[] 8192
  $memory = [System.IO.MemoryStream]::new()
  $headerEnd = -1

  while ($headerEnd -lt 0) {
    $read = $stream.Read($buffer, 0, $buffer.Length)
    if ($read -le 0) {
      throw "Requisicao vazia."
    }

    $memory.Write($buffer, 0, $read)
    $text = [System.Text.Encoding]::ASCII.GetString($memory.ToArray())
    $headerEnd = $text.IndexOf("`r`n`r`n")
  }

  $data = $memory.ToArray()
  $headerText = [System.Text.Encoding]::ASCII.GetString($data, 0, $headerEnd)
  $headerLines = @($headerText -split "`r`n")
  $requestParts = @($headerLines[0] -split " ")
  if ($requestParts.Count -lt 2) {
    throw "Linha de requisicao invalida."
  }

  $headers = @{}
  if ($headerLines.Count -gt 1) {
    foreach ($line in $headerLines[1..($headerLines.Count - 1)]) {
      $separator = $line.IndexOf(":")
      if ($separator -gt 0) {
        $key = $line.Substring(0, $separator).Trim().ToLowerInvariant()
        $value = $line.Substring($separator + 1).Trim()
        $headers[$key] = $value
      }
    }
  }

  $contentLength = 0
  if ($headers.ContainsKey("content-length")) {
    [int]::TryParse($headers["content-length"], [ref]$contentLength) | Out-Null
  }
  if ($contentLength -gt 1048576) {
    throw "Corpo da requisicao excede 1 MB."
  }

  $bodyStart = $headerEnd + 4
  while (($data.Length - $bodyStart) -lt $contentLength) {
    $read = $stream.Read($buffer, 0, $buffer.Length)
    if ($read -le 0) {
      break
    }
    $memory.Write($buffer, 0, $read)
    $data = $memory.ToArray()
  }

  $body = ""
  if ($contentLength -gt 0 -and $data.Length -ge ($bodyStart + $contentLength)) {
    $body = [System.Text.Encoding]::UTF8.GetString($data, $bodyStart, $contentLength)
  }

  $target = $requestParts[1]
  if ($target.StartsWith("http", [System.StringComparison]::OrdinalIgnoreCase)) {
    $uri = [uri]$target
  } else {
    $uri = [uri]"http://localhost:$Port$target"
  }

  $request = [pscustomobject]@{
    HttpMethod = $requestParts[0]
    Url = $uri
    HasEntityBody = $contentLength -gt 0
    ContentBody = $body
    Headers = $headers
    RemoteEndPoint = $Client.Client.RemoteEndPoint
  }

  return [pscustomobject]@{
    Client = $Client
    Stream = $stream
    Request = $request
  }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), $Port)
$listener.Start()
$prefix = "http://localhost:$Port/"

Write-Host "Infra Monitor MVP rodando em $prefix"
Write-Host "Monitoramento: intervalo=${CheckIntervalSeconds}s, tentativas=$Attempts, timeout=${TimeoutMs}ms"
Write-Host "Pressione Ctrl+C para parar."

$nextCheck = (Get-Date).AddSeconds(2)

try {
  while ($true) {
    if ((Get-Date) -ge $nextCheck) {
      try {
        $checked = Invoke-MonitorCycle
        Write-Host ("Monitoramento executado: {0} dispositivo(s)." -f @($checked).Count)
      } catch {
        Write-Warning "Falha no ciclo de monitoramento: $($_.Exception.Message)"
      }
      $cycleSettings = Get-PublicSettings (Read-Store).settings
      $nextCheck = (Get-Date).AddSeconds([int]$cycleSettings.check_interval_seconds)
    }

    $clientTask = $listener.AcceptTcpClientAsync()
    while (-not $clientTask.IsCompleted) {
      Start-Sleep -Milliseconds 150
      if ((Get-Date) -ge $nextCheck) {
        try {
          $checked = Invoke-MonitorCycle
          Write-Host ("Monitoramento executado: {0} dispositivo(s)." -f @($checked).Count)
        } catch {
          Write-Warning "Falha no ciclo de monitoramento: $($_.Exception.Message)"
        }
        $cycleSettings = Get-PublicSettings (Read-Store).settings
        $nextCheck = (Get-Date).AddSeconds([int]$cycleSettings.check_interval_seconds)
      }
    }

    $client = $clientTask.Result
    try {
      $context = Read-TcpHttpContext $client
      if ($context.Request.Url.AbsolutePath.StartsWith("/api/")) {
        Handle-ApiRequest $context
      } else {
        Handle-StaticRequest $context
      }
    } catch {
      try {
        $fallbackContext = [pscustomobject]@{ Client = $client; Stream = $client.GetStream() }
        Send-Json $fallbackContext ([pscustomobject]@{ error = $_.Exception.Message }) 500
      } catch {
        $client.Close()
      }
    }
  }
} finally {
  $listener.Stop()
}
