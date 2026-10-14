# sync-sniper.ps1 — مزامنة نتائج Gold Sniper مع موقع The Sniper
# ---------------------------------------------------------------
# يقرأ سجل صفقات الروبوت (قراءة فقط)، ويحسب الأرقام، ويكتب assets/data.js
# في مجلد الموقع، ثم يرفع التغيير إلى GitHub إذا تغيّر شيء.
# لا يلمس كود الروبوت ولا ملفات ذاكرته.
#
# التشغيل اليدوي:
#   powershell -ExecutionPolicy Bypass -File C:\TheSniper\sync\sync-sniper.ps1

param(
    [string]$Journal  = "$env:APPDATA\MetaQuotes\Terminal\Common\Files\GoldSniperV97_Journal.csv",
    [string]$SiteRepo = "C:\TheSniper",
    [string]$Stage    = "حساب تجريبي",
    [string]$Version  = "Gold Sniper V9.8.1",
    [int]$MinTrades   = 100,
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"
$cols = "closeTime","positionId","engine","direction","candle","htf","move","location","session","hour","score",
        "profit","R","memP","memEV","memLCB","treeEV","modelEV","analogEV","newsNode","known",
        "openTime","holdMin","exit","addType","Rp","mfeR","maeR","spreadPts","slipPts",
        "riskPts","stealth","regime","dow","trend24","targetR","rrIdx"

if (-not (Test-Path $Journal)) { Write-Error "لم أجد سجل الصفقات: $Journal" }

# نسخة مؤقتة حتى لا نتعارض مع الروبوت وهو يكتب في الملف
$tmp = Join-Path $env:TEMP "gs_journal_copy.csv"
Copy-Item $Journal $tmp -Force

$inv = [Globalization.CultureInfo]::InvariantCulture
$rows = Import-Csv $tmp -Header $cols -Encoding Unicode |
        Where-Object { $_.closeTime -match '^\d{4}\.\d{2}\.\d{2}' }

$days   = [ordered]@{}
$tradesR = New-Object System.Collections.Generic.List[string]

foreach ($r in $rows) {
    $d = $r.closeTime.Substring(0,10).Replace('.','-')
    $p = [double]::Parse($r.profit, $inv)
    $R = [double]::Parse($r.R, $inv)
    if (-not $days.Contains($d)) { $days[$d] = @{ trades = 0; wins = 0; r = 0.0; pnl = 0.0 } }
    $days[$d].trades++
    if ($p -gt 0) { $days[$d].wins++ }
    $days[$d].r   += $R
    $days[$d].pnl += $p
    $tradesR.Add([Math]::Round($R, 3).ToString($inv))
}

$dayLines = foreach ($k in $days.Keys) {
    $v = $days[$k]
    '    {d: "' + $k + '", trades: ' + $v.trades + ', wins: ' + $v.wins +
    ', r: ' + [Math]::Round($v.r, 2).ToString($inv) + ', pnl: ' + [Math]::Round($v.pnl, 2).ToString($inv) + '}'
}

$now = Get-Date -Format "yyyy-MM-dd HH:mm"
$js = @"
/*
  يُولَّد تلقائياً بسكربت sync-sniper.ps1 من سجل صفقات الروبوت. لا تعدّله يدوياً.
  المنشورات في assets/posts.js.
  R = الربح أو الخسارة مقسوماً على مخاطرة الصفقة.
*/
window.SNIPER_DATA = {
  stage: "$Stage",
  updated: "$now",
  minTrades: $MinTrades,
  account: { name: "$Version", symbol: "XAUUSD" },
  days: [
$($dayLines -join ",`n")
  ],
  tradesR: [$($tradesR -join ', ')]
};
"@

$out = Join-Path $SiteRepo "assets\data.js"
$old = if (Test-Path $out) { Get-Content $out -Raw -Encoding UTF8 } else { "" }
# المقارنة بدون سطر الوقت حتى لا نرفع تغييراً كل 5 دقائق بلا صفقات جديدة
$strip = { param($s) ($s -split "`n" | Where-Object { $_ -notmatch '^\s*updated:' }) -join "`n" }
if ((& $strip $old).Trim() -eq (& $strip $js).Trim()) {
    Write-Host "لا صفقات جديدة ($($rows.Count) صفقة)."
    exit 0
}

[IO.File]::WriteAllText($out, $js, (New-Object Text.UTF8Encoding($false)))
Write-Host "تم تحديث data.js: $($rows.Count) صفقة."

if ($NoPush) { exit 0 }
Push-Location $SiteRepo
try {
    git add assets/data.js
    git commit -m "تحديث النتائج $now ($($rows.Count) صفقة)" | Out-Null
    git push --quiet
    Write-Host "تم الرفع إلى GitHub."
} finally { Pop-Location }
