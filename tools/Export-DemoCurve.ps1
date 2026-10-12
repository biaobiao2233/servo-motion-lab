param([Parameter(Mandatory=$true)][string]$CsvPath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms.DataVisualization
Add-Type -AssemblyName System.Drawing
$rows=@(Import-Csv -LiteralPath $CsvPath)
if($rows.Count -lt 2){throw 'At least two actual observations are required.'}
$start=[datetimeoffset]$rows[0].ObservedAt
$elapsed=@($rows|ForEach-Object{(([datetimeoffset]$_.ObservedAt)-$start).TotalSeconds})
$intervals=@(for($i=1;$i -lt $elapsed.Count;$i++){$elapsed[$i]-$elapsed[$i-1]})
$intervals=@($intervals|Sort-Object)
$median=$intervals[[int][Math]::Floor($intervals.Count/2)]
$blue=[Drawing.ColorTranslator]::FromHtml('#2a78d6')
$orange=[Drawing.ColorTranslator]::FromHtml('#eb6834')
function New-Chart([string]$Title,[string]$YTitle,[int]$Height){
    $chart=[Windows.Forms.DataVisualization.Charting.Chart]::new()
    $chart.Width=1600;$chart.Height=$Height;$chart.BackColor=[Drawing.ColorTranslator]::FromHtml('#fcfcfb')
    $chart.Font=[Drawing.Font]::new('Microsoft YaHei',12)
    $area=[Windows.Forms.DataVisualization.Charting.ChartArea]::new('Data')
    $area.BackColor=$chart.BackColor
    $area.AxisX.Title='观测时间 / s';$area.AxisY.Title=$YTitle
    $area.AxisX.Minimum=0;$area.AxisX.Maximum=[Math]::Ceiling($elapsed[-1]/5)*5
    foreach($axis in @($area.AxisX,$area.AxisY)){
        $axis.MajorGrid.LineColor=[Drawing.ColorTranslator]::FromHtml('#e5e5e2')
        $axis.LineColor=[Drawing.ColorTranslator]::FromHtml('#b0b0aa')
        $axis.LabelStyle.ForeColor=[Drawing.ColorTranslator]::FromHtml('#52514e')
        $axis.TitleForeColor=[Drawing.ColorTranslator]::FromHtml('#0b0b0b')
        $axis.TitleFont=[Drawing.Font]::new('Microsoft YaHei',13)
    }
    $chart.ChartAreas.Add($area)
    [void]$chart.Titles.Add($Title)
    $chart.Titles[0].Font=[Drawing.Font]::new('Microsoft YaHei',17,[Drawing.FontStyle]::Bold)
    return $chart
}
function Add-Line($Chart,[string]$Name,[string]$Column,$Color,[switch]$Target){
    $series=[Windows.Forms.DataVisualization.Charting.Series]::new($Name)
    $series.Color=$Color;$series.BorderWidth=2
    $series.ChartType=if($Target){[Windows.Forms.DataVisualization.Charting.SeriesChartType]::StepLine}else{[Windows.Forms.DataVisualization.Charting.SeriesChartType]::Line}
    if($Target){$series.BorderDashStyle=[Windows.Forms.DataVisualization.Charting.ChartDashStyle]::Dash}
    else{$series.MarkerStyle=[Windows.Forms.DataVisualization.Charting.MarkerStyle]::Circle;$series.MarkerSize=8;$series.MarkerBorderColor=$Chart.BackColor;$series.MarkerBorderWidth=2}
    for($i=0;$i -lt $rows.Count;$i++){[void]$series.Points.AddXY($elapsed[$i],[double]$rows[$i].$Column)}
    $Chart.Series.Add($series)
}
$position=New-Chart 'NC/PTP 单轴仿真：位置与已接受目标' '位置 / mm' 550
$velocity=New-Chart 'NC 仿真轴实际速度' '速度 / (mm/s)' 450
$canvas=[Drawing.Bitmap]::new(1600,1120)
$graphics=[Drawing.Graphics]::FromImage($canvas)
$images=[Collections.Generic.List[Drawing.Image]]::new()
try{
    $position.ChartAreas[0].AxisY.Minimum=0;$position.ChartAreas[0].AxisY.Maximum=100
    Add-Line $position '已接受目标（阶梯虚线）' 'TargetPosition' $orange -Target
    Add-Line $position '实际 NC 位置（圆点为采样）' 'ActualPosition' $blue
    for($i=0;$i -lt $rows.Count;$i++){
        if($rows[$i].StopHeld -eq 'True' -and $rows[$i].StopDone -eq 'True'){
            $position.Series[1].Points[$i].Label='停止保持 '+([double]$rows[$i].ActualPosition).ToString('0.00')+' mm'
            $position.Series[1].Points[$i].LabelForeColor=[Drawing.Color]::Black
            $position.Series[0].Points[$i].Label='已接受目标 80 mm'
            $position.Series[0].Points[$i].LabelForeColor=[Drawing.Color]::Black
            break
        }
    }
    $legend=[Windows.Forms.DataVisualization.Charting.Legend]::new('Series')
    $legend.Docking=[Windows.Forms.DataVisualization.Charting.Docking]::Top
    $legend.Font=[Drawing.Font]::new('Microsoft YaHei',12);$legend.ForeColor=[Drawing.ColorTranslator]::FromHtml('#0b0b0b')
    $position.Legends.Add($legend)
    Add-Line $velocity 'Actual NC velocity' 'ActualVelocity' $blue
    $velocity.Series[0].IsVisibleInLegend=$false
    $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#fcfcfb'))
    foreach($entry in @(@($position,0),@($velocity,550))){
        $stream=[IO.MemoryStream]::new()
        try{
            $entry[0].SaveImage($stream,[Windows.Forms.DataVisualization.Charting.ChartImageFormat]::Png)
            $stream.Position=0
            $plot=[Drawing.Image]::FromStream($stream)
            try{$graphics.DrawImage($plot,0,[int]$entry[1],1600,$entry[0].Height)}finally{$plot.Dispose()}
        }finally{$stream.Dispose()}
    }
    $caption='来源：TwinCAT Usermode Runtime / NC 仿真反馈；'+$rows.Count+' 点，实际采样间隔中位数 '+$median.ToString('0.00')+' s。'
    $caption2='折线仅连接实际采样点；顺序 ADS 读取，非同周期原子快照；不代表物理电机或硬实时测量。'
    $font=[Drawing.Font]::new('Microsoft YaHei',13)
    try{
        $graphics.DrawString($caption,$font,[Drawing.Brushes]::Black,55,1010)
        $graphics.DrawString($caption2,$font,[Drawing.Brushes]::Black,55,1050)
    }finally{$font.Dispose()}
    $canvas.Save([IO.Path]::GetFullPath($OutputPath),[Drawing.Imaging.ImageFormat]::Png)
    [pscustomobject]@{OutputPath=$OutputPath;SampleCount=$rows.Count;MedianIntervalSeconds=$median}|ConvertTo-Json
}finally{$graphics.Dispose();$canvas.Dispose();$position.Dispose();$velocity.Dispose()}
