Option Explicit

Dim fso, shell, scriptDir, scriptPath, command, i

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(scriptDir, "technician-companion.ps1")

If Not fso.FileExists(scriptPath) Then
  MsgBox "technician-companion.ps1 was not found next to this installer.", vbCritical, "Exantas RustDesk Companion"
  WScript.Quit 1
End If

command = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Quote(scriptPath) & " -InstallStartup"
For i = 0 To WScript.Arguments.Count - 1
  command = command & " " & Quote(WScript.Arguments(i))
Next

shell.Run command, 0, False

Function Quote(value)
  Quote = """" & Replace(CStr(value), """", """""") & """"
End Function
