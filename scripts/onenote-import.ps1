# Convierte un .one (seccion de OneNote) a markdown + imagenes, usando la API
# COM de OneNote de escritorio. Prueba de concepto: convierte las primeras N
# paginas a $OutputDir.
param(
  [Parameter(Mandatory=$true)][string]$InputOne,
  [Parameter(Mandatory=$true)][string]$OutputDir,
  [int]$MaxPages = 0
)
$ErrorActionPreference = 'Stop'
$NS = 'http://schemas.microsoft.com/office/onenote/2013/onenote'

function Convert-Inline([string]$html) {
  if ([string]::IsNullOrEmpty($html)) { return '' }
  $t = $html
  $t = [regex]::Replace($t, '(?s)<a\b[^>]*?\bhref=(?:"([^"]*)"|''([^'']*)'')[^>]*>(.*?)</a>', {
    param($m)
    $url = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
    $text = $m.Groups[3].Value
    if ([string]::IsNullOrWhiteSpace($text)) { $text = $url }
    '[' + $text + '](' + $url + ')'
  })
  $t = [regex]::Replace($t, '(?s)<span\b[^>]*font-weight:\s*bold[^>]*>(.*?)</span>', '**$1**')
  $t = [regex]::Replace($t, '(?s)<span\b[^>]*font-style:\s*italic[^>]*>(.*?)</span>', '_$1_')
  $t = [regex]::Replace($t, '<br\s*/?>', "`n")
  $t = [regex]::Replace($t, '<[^>]+>', '')
  return [System.Net.WebUtility]::HtmlDecode($t)
}

function Get-ImageExt([byte[]]$bytes) {
  if ($bytes.Length -ge 4 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50) { return 'png' }
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) { return 'jpg' }
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0x47 -and $bytes[1] -eq 0x49 -and $bytes[2] -eq 0x46) { return 'gif' }
  if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4D) { return 'bmp' }
  return 'bin'
}

$script:imageCount = 0

function Convert-OEChildren($node, [int]$depth, [string]$slug, [string]$imagesDir, $out) {
  foreach ($child in $node.ChildNodes) {
    if ($child.LocalName -eq 'OE') { Convert-OE $child $depth $slug $imagesDir $out }
    elseif ($child.LocalName -eq 'Table') { Convert-Table $child $depth $slug $imagesDir $out }
  }
}

function Convert-OE($oe, [int]$depth, [string]$slug, [string]$imagesDir, $out) {
  $indent = '  ' * $depth
  $list = $oe.GetAttribute('list')
  $text = ''
  foreach ($t in $oe.SelectNodes('./*[local-name()="T"]')) { $text += Convert-Inline $t.InnerText }
  $text = $text.Trim()
  if ($text.Length -gt 0) {
    if ($list -eq 'bullet') { $out.Add("$indent- $text") }
    elseif ($list -eq 'number') { $out.Add("$indent1. $text") }
    else { $out.Add("$indent$text") }
  }
  foreach ($img in $oe.SelectNodes('./*[local-name()="Image"]')) {
    $data = $img.SelectSingleNode('./*[local-name()="Data"]')
    if ($null -ne $data -and $data.InnerText.Length -gt 0) {
      $bytes = [Convert]::FromBase64String($data.InnerText)
      $ext = Get-ImageExt $bytes
      $script:imageCount++
      $name = "$slug-$($script:imageCount).$ext"
      [System.IO.File]::WriteAllBytes((Join-Path $imagesDir $name), $bytes)
      $out.Add("$indent![](imagenes/$name)")
    }
  }
  # La tabla es hija directa del OE (no de OEChildren).
  foreach ($tbl in $oe.SelectNodes('./*[local-name()="Table"]')) {
    Convert-Table $tbl $depth $slug $imagesDir $out
  }
  foreach ($kids in $oe.SelectNodes('./*[local-name()="OEChildren"]')) {
    Convert-OEChildren $kids ($depth + 1) $slug $imagesDir $out
  }
}

function Convert-Table($table, [int]$depth, [string]$slug, [string]$imagesDir, $out) {
  $rows = $table.SelectNodes('./*[local-name()="Row"]')
  $first = $true
  foreach ($row in $rows) {
    $cells = @()
    foreach ($cell in $row.SelectNodes('./*[local-name()="Cell"]')) {
      $cellLines = New-Object System.Collections.Generic.List[string]
      foreach ($kids in $cell.SelectNodes('./*[local-name()="OEChildren"]')) {
        Convert-OEChildren $kids 0 $slug $imagesDir $cellLines
      }
      $cells += ($cellLines -join ' ').Trim()
    }
    $out.Add('| ' + ($cells -join ' | ') + ' |')
    if ($first) { $out.Add('| ' + (($cells | ForEach-Object { '---' }) -join ' | ') + ' |'); $first = $false }
  }
}

# --- abrir la seccion --------------------------------------------------------
$onenote = New-Object -ComObject OneNote.Application
$sectionId = ''
$onenote.OpenHierarchy($InputOne, '', [ref]$sectionId, [Microsoft.Office.Interop.OneNote.CreateFileType]::cftNone) | Out-Null
$hier = ''
$onenote.GetHierarchy($sectionId, [Microsoft.Office.Interop.OneNote.HierarchyScope]::hsPages, [ref]$hier) | Out-Null
$pageIds = [regex]::Matches($hier, '<one:Page ID="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
if ($MaxPages -gt 0) { $pageIds = $pageIds | Select-Object -First $MaxPages }
Write-Output "Paginas a convertir: $($pageIds.Count)"

$imagesDir = Join-Path $OutputDir 'imagenes'
New-Item -ItemType Directory -Force -Path $OutputDir, $imagesDir | Out-Null
$usedSlugs = @{}

foreach ($pageId in $pageIds) {
  $content = ''
  $onenote.GetPageContent($pageId, [ref]$content, [Microsoft.Office.Interop.OneNote.PageInfo]::piAll) | Out-Null
  $doc = New-Object System.Xml.XmlDocument
  $doc.LoadXml($content)
  $page = $doc.DocumentElement
  $name = $page.GetAttribute('name')
  $date = $page.GetAttribute('dateTime')
  $slug = ($name -replace '[^\w\-]+', '-').Trim('-').ToLower()
  if ($slug.Length -eq 0) { $slug = 'pagina' }
  # Un titulo largo no puede pasarse del limite de ruta de Windows.
  if ($slug.Length -gt 80) { $slug = $slug.Substring(0, 80).Trim('-') }
  # Dos paginas pueden llamarse igual: se desambigua para no pisarse.
  $base = $slug
  $n = 2
  while ($usedSlugs.ContainsKey($slug)) { $slug = "$base-$n"; $n++ }
  $usedSlugs[$slug] = $true

  $out = New-Object System.Collections.Generic.List[string]
  $out.Add("# $name")
  $out.Add('')
  foreach ($outline in $page.SelectNodes('./*[local-name()="Outline"]')) {
    foreach ($kids in $outline.SelectNodes('./*[local-name()="OEChildren"]')) {
      Convert-OEChildren $kids 0 $slug $imagesDir $out
    }
    $out.Add('')
  }
  $file = Join-Path $OutputDir "$slug.md"
  [System.IO.File]::WriteAllText($file, ($out -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
  Write-Output "  -> $slug.md ($($out.Count) lineas)"
}
Write-Output "Imagenes extraidas: $($script:imageCount)"
